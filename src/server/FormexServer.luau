--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FormexFolder = ReplicatedStorage:WaitForChild("Formex")
local Formex = require(FormexFolder:WaitForChild("Formex"))

local function getRemoteFunction(): RemoteFunction
	local existing = FormexFolder:FindFirstChild("RemoteFunction")
	if existing then
		if not existing:IsA("RemoteFunction") then
			error("Formex RemoteFunction must be a RemoteFunction")
		end
		return existing
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = "RemoteFunction"
	remote.Parent = FormexFolder
	return remote
end

local NetworkFunction: RemoteFunction = getRemoteFunction()

local PlotServer = {}

local plots = {} :: {[number]: Formex.Plot} -- [plotId]
local plotsByPlayer = {} :: {[number]: Formex.Plot} -- [player.UserId]

PlotServer.Plots = plots
PlotServer.PlotsByPlayer = plotsByPlayer

local function attachAttribute(instance: Instance, attributeName: string, onUpdate: (any) -> ())
	instance:GetAttributeChangedSignal(attributeName):Connect(function()
		local value = instance:GetAttribute(attributeName)
		onUpdate(value)
	end)
	local initialValue = instance:GetAttribute(attributeName)
	onUpdate(initialValue)
end

local function setAttributeIfChanged(instance: Instance, attributeName: string, value: any)
	if instance:GetAttribute(attributeName) ~= value then
		instance:SetAttribute(attributeName, value)
	end
end

local function toVector2int16(value: any, fallback: Vector2int16): Vector2int16
	if typeof(value) == "Vector2int16" then
		return value
	end
	if typeof(value) == "Vector2" then
		return Vector2int16.new(value.X, value.Y)
	end
	if typeof(value) == "Vector3int16" then
		return Vector2int16.new(value.X, value.Z)
	end
	if typeof(value) == "Vector3" then
		return Vector2int16.new(value.X, value.Z)
	end
	return fallback
end

local function decodePoints(value: any): {Vector2int16}
	if type(value) == "table" then
		return value :: {Vector2int16}
	end
	if typeof(value) ~= "string" then
		return {}
	end

	local points = {} :: {Vector2int16}
	for xText, yText in string.gmatch(value, "(-?%d+)%s*,%s*(-?%d+)") do
		local x = tonumber(xText)
		local y = tonumber(yText)
		if x and y then
			table.insert(points, Vector2int16.new(x, y))
		end
	end
	return points
end

local function encodePoints(points: {Vector2int16}): string
	if #points == 0 then
		return ""
	end
	local chunks = table.create(#points)
	for index, point in ipairs(points) do
		chunks[index] = tostring(point.X) .. "," .. tostring(point.Y)
	end
	return table.concat(chunks, ";")
end

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local folder = parent:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder :: Folder
end

local function getNextId(folder: Folder): number
	local maxId = 0
	for _, child in ipairs(folder:GetChildren()) do
		local id = tonumber(child.Name)
		if id and id > maxId then
			maxId = id
		end
	end
	return maxId + 1
end

local permissionLevels = {
	[Formex.Permission.Owner] = 4,
	[Formex.Permission.Manager] = 3,
	[Formex.Permission.VIP] = 2,
	[Formex.Permission.Guest] = 1,
	[Formex.Permission.Banned] = 0,
}

local function requirePermission(plot: Formex.Plot, required: Formex.Permission)
	if permissionLevels[plot.MyPermission] < permissionLevels[required] then
		error("Player does not have required permission")
	end
end

local function getLevel(plot: Formex.Plot, levelId: number): Formex.Level
	local level = plot.Levels[levelId]
	if not level then
		error("Level not found: " .. tostring(levelId))
	end
	return level
end

local function getWall(level: Formex.Level, wallId: number): Formex.Wall
	local wall = level.Walls[wallId]
	if not wall then
		error("Wall not found: " .. tostring(wallId))
	end
	return wall
end

local function getFloor(level: Formex.Level, floorId: number): Formex.Floor
	local floor = level.Floors[floorId]
	if not floor then
		error("Floor not found: " .. tostring(floorId))
	end
	return floor
end

local function getObject(level: Formex.Level, objectId: number): Formex.Object
	local object = level.Objects[objectId]
	if not object then
		error("Object not found: " .. tostring(objectId))
	end
	return object
end

function PlotServer.GetPlot(plotId: number): Formex.Plot
	return plots[plotId] or error("Plot not found: " .. tostring(plotId))
end

function PlotServer.SetPlayerCurrentPlot(player: Player, plotId: number)
	plotsByPlayer[player.UserId] = PlotServer.GetPlot(plotId)
end

function PlotServer.GetPlayerCurrentPlot(player: Player): Formex.Plot?
	return plotsByPlayer[player.UserId]
end

function PlotServer.RegisterPlot(plotPart: BasePart)
	local plot = {} :: Formex.Plot
	local plotId = plotPart:GetAttribute("PlotId")
	if type(plotId) ~= "number" then
		error("PlotId attribute missing on plot")
	end

	plots[plotId] = plot

	plot.Part = plotPart :: Part
	plot.PlotId = plotId
	plot.Id = plotId
	plot.Name = plotPart:GetAttribute("Name") or ""
	local ownerUserId = plotPart:GetAttribute("OwnerUserId")
	if ownerUserId == 0 then
		ownerUserId = nil
	end
	plot.OwnerUserId = ownerUserId
	plot.OwnerName = plotPart:GetAttribute("OwnerName")
	plot.MyPermission = Formex.Permission.Guest
	plot.SegmentsUnlocked = plotPart:GetAttribute("SegmentsUnlocked") or 0
	plot.LevelsUnlocked = plotPart:GetAttribute("LevelsUnlocked") or 0
	plot.Segments = {}
	plot.Levels = {}
	plot.Players = {}
	plot.CanUndo = plotPart:GetAttribute("CanUndo") or false
	plot.CanRedo = plotPart:GetAttribute("CanRedo") or false
	plot.DesignMode = plotPart:GetAttribute("DesignMode") or Formex.DesignMode.Play
	plot.SelectedPart = nil
	plot.OnPlotChanged = Instance.new("BindableEvent")
	plot.OnPartChanged = Instance.new("BindableEvent")
	plot.OnSelectionChanged = Instance.new("BindableEvent")

	local levelFolders = {} :: {[number]: {Walls: Folder, Floors: Folder, Objects: Folder}}
	local playersByInstance = {} :: {[Instance]: Formex.PlotPlayer}
	local playersByUserId = {} :: {[number]: Instance}

	local function notifyPlotChanged()
		plot.OnPlotChanged:Fire()
	end

	local function notifyPartChanged(part: Formex.Wall | Formex.Floor | Formex.Object)
		plot.OnPartChanged:Fire(part)
	end

	local function notifySelectionChanged()
		plot.OnSelectionChanged:Fire()
	end

	local function setSelectedPart(part: Formex.Wall | Formex.Floor | Formex.Object | nil)
		if plot.SelectedPart == part then
			return
		end

		local previous = plot.SelectedPart
		plot.SelectedPart = part

		if previous then
			previous.IsSelected = false
			setAttributeIfChanged(previous.Part, "IsSelected", false)
		end

		if part then
			part.IsSelected = true
			setAttributeIfChanged(part.Part, "IsSelected", true)
		end

		notifySelectionChanged()
	end

	local function updateSegmentsFromCount()
		for index, segment in ipairs(plot.Segments) do
			local isUnlocked = index <= plot.SegmentsUnlocked
			segment.IsUnlocked = isUnlocked
			segment.CanUnlock = not isUnlocked and index == plot.SegmentsUnlocked + 1
		end
		setAttributeIfChanged(plotPart, "SegmentsUnlocked", plot.SegmentsUnlocked)
		notifyPlotChanged()
	end

	function plot:SetName(newName: string)
		plot.Name = newName
		setAttributeIfChanged(plotPart, "Name", newName)
	end

	function plot:SetPermission(userId: number, permission: Formex.Permission)
		local attributeName = "U_" .. tostring(userId)
		setAttributeIfChanged(plotPart, attributeName, permission)

		local plotPlayer = plot.Players[userId]
		if plotPlayer then
			plotPlayer.Permission = permission
			local playerInstance = playersByUserId[userId]
			if playerInstance then
				setAttributeIfChanged(playerInstance, "Permission", permission)
			end
		end
		notifyPlotChanged()
	end

	function plot:SetDesignMode(mode: Formex.DesignMode, levelIndex: number)
		plot.DesignMode = mode
		setAttributeIfChanged(plotPart, "DesignMode", mode)

		if plot.Levels[levelIndex] then
			for id, level in pairs(plot.Levels) do
				local isActive = id == levelIndex
				if level.IsActive ~= isActive then
					level.IsActive = isActive
					setAttributeIfChanged(level.Part, "IsActive", isActive)
				end
			end
		end

		notifyPlotChanged()
	end

	function plot:SelectPart(part: Formex.Wall | Formex.Floor | Formex.Object)
		setSelectedPart(part)
	end

	function plot:DeselectAll()
		setSelectedPart(nil)
	end

	function plot:Undo()
		notifyPlotChanged()
	end

	function plot:Redo()
		notifyPlotChanged()
	end

	function plot:IsPointValid(point: Vector2 | Vector2int16): boolean
		local x = point.X
		local y = point.Y
		return x >= 1 and y >= 1 and x <= Formex.LayoutGrid.Columns and y <= Formex.LayoutGrid.Rows
	end

	function plot:IsLineValid(lineStart: Vector2 | Vector2int16, lineEnd: Vector2 | Vector2int16): boolean
		return plot:IsPointValid(lineStart) and plot:IsPointValid(lineEnd)
	end

	function plot:IsPolygonValid(points: {Vector2 | Vector2int16}): boolean
		for _, point in ipairs(points) do
			if not plot:IsPointValid(point) then
				return false
			end
		end
		return true
	end

	function plot:IsPointNearBoundary(point: Vector3, threshold: number): boolean
		local localPoint = plotPart.CFrame:PointToObjectSpace(point)
		local halfSize = plotPart.Size * 0.5
		local nearX = math.abs(halfSize.X - math.abs(localPoint.X)) <= threshold
		local nearZ = math.abs(halfSize.Z - math.abs(localPoint.Z)) <= threshold
		return nearX or nearZ
	end

	local function registerWall(level: Formex.Level, wallPart: BasePart)
		local id = tonumber(wallPart.Name)
		if not id or level.Walls[id] then
			return
		end

		local wall = {} :: Formex.Wall
		wall.Id = id
		wall.Part = wallPart :: Part
		wall.Level = level
		wall.Start = toVector2int16(wallPart:GetAttribute("Start"), Vector2int16.new(0, 0))
		wall.End = toVector2int16(wallPart:GetAttribute("End"), Vector2int16.new(0, 0))
		wall.Height = wallPart:GetAttribute("Height") or Formex.LevelHeight
		wall.FrontMaterial = wallPart:GetAttribute("FrontMaterial") or Formex.DefaultWallMaterial
		wall.BackMaterial = wallPart:GetAttribute("BackMaterial") or Formex.DefaultWallMaterial
		wall.IsGhost = wallPart:GetAttribute("IsGhost") or false
		wall.IsSelected = wallPart:GetAttribute("IsSelected") or false

		function wall:UpdatePoints(newStart: Vector2int16, newEnd: Vector2int16)
			wall.Start = newStart
			wall.End = newEnd
			setAttributeIfChanged(wallPart, "Start", newStart)
			setAttributeIfChanged(wallPart, "End", newEnd)
			notifyPartChanged(wall)
		end

		function wall:SetHeight(newHeight: number)
			wall.Height = newHeight
			setAttributeIfChanged(wallPart, "Height", newHeight)
			notifyPartChanged(wall)
		end

		function wall:SetFrontMaterial(materialId: number)
			wall.FrontMaterial = materialId
			setAttributeIfChanged(wallPart, "FrontMaterial", materialId)
			notifyPartChanged(wall)
		end

		function wall:SetBackMaterial(materialId: number)
			wall.BackMaterial = materialId
			setAttributeIfChanged(wallPart, "BackMaterial", materialId)
			notifyPartChanged(wall)
		end

		function wall:Select()
			plot:SelectPart(wall)
		end

		function wall:Finish()
			wall.IsGhost = false
			setAttributeIfChanged(wallPart, "IsGhost", false)
			notifyPartChanged(wall)
		end

		function wall:Delete()
			level.Walls[id] = nil
			if plot.SelectedPart == wall then
				setSelectedPart(nil)
			end
			wallPart:Destroy()
			notifyPartChanged(wall)
		end

		attachAttribute(wallPart, "Start", function(value)
			wall.Start = toVector2int16(value, wall.Start)
			notifyPartChanged(wall)
		end)

		attachAttribute(wallPart, "End", function(value)
			wall.End = toVector2int16(value, wall.End)
			notifyPartChanged(wall)
		end)

		attachAttribute(wallPart, "Height", function(value)
			wall.Height = value or Formex.LevelHeight
			notifyPartChanged(wall)
		end)

		attachAttribute(wallPart, "FrontMaterial", function(value)
			wall.FrontMaterial = value or Formex.DefaultWallMaterial
			notifyPartChanged(wall)
		end)

		attachAttribute(wallPart, "BackMaterial", function(value)
			wall.BackMaterial = value or Formex.DefaultWallMaterial
			notifyPartChanged(wall)
		end)

		attachAttribute(wallPart, "IsGhost", function(value)
			wall.IsGhost = value or false
			notifyPartChanged(wall)
		end)

		attachAttribute(wallPart, "IsSelected", function(value)
			wall.IsSelected = value or false
			if wall.IsSelected then
				setSelectedPart(wall)
			elseif plot.SelectedPart == wall then
				setSelectedPart(nil)
			end
			notifyPartChanged(wall)
		end)

		level.Walls[id] = wall
		notifyPartChanged(wall)
	end

	local function registerFloor(level: Formex.Level, floorPart: BasePart)
		local id = tonumber(floorPart.Name)
		if not id or level.Floors[id] then
			return
		end

		local floor = {} :: Formex.Floor
		floor.Id = id
		floor.Part = floorPart :: Part
		floor.Level = level
		floor.Points = decodePoints(floorPart:GetAttribute("Points"))
		floor.IsGhost = floorPart:GetAttribute("IsGhost") or false
		floor.IsSelected = floorPart:GetAttribute("IsSelected") or false

		function floor:UpdatePoints(newPoints: {Vector2int16})
			floor.Points = newPoints
			setAttributeIfChanged(floorPart, "Points", encodePoints(newPoints))
			notifyPartChanged(floor)
		end

		function floor:SetHeight(newHeight: number)
			setAttributeIfChanged(floorPart, "Height", newHeight)
			notifyPartChanged(floor)
		end

		function floor:SetFloorMaterial(materialId: number)
			setAttributeIfChanged(floorPart, "FloorMaterial", materialId)
			notifyPartChanged(floor)
		end

		function floor:SetCeilingMaterial(materialId: number)
			setAttributeIfChanged(floorPart, "CeilingMaterial", materialId)
			notifyPartChanged(floor)
		end

		function floor:SetFoundationMaterial(materialId: number)
			setAttributeIfChanged(floorPart, "FoundationMaterial", materialId)
			notifyPartChanged(floor)
		end

		function floor:Select()
			plot:SelectPart(floor)
		end

		function floor:Finish()
			floor.IsGhost = false
			setAttributeIfChanged(floorPart, "IsGhost", false)
			notifyPartChanged(floor)
		end

		function floor:Delete()
			level.Floors[id] = nil
			if plot.SelectedPart == floor then
				setSelectedPart(nil)
			end
			floorPart:Destroy()
			notifyPartChanged(floor)
		end

		attachAttribute(floorPart, "Points", function(value)
			floor.Points = decodePoints(value)
			notifyPartChanged(floor)
		end)

		attachAttribute(floorPart, "IsGhost", function(value)
			floor.IsGhost = value or false
			notifyPartChanged(floor)
		end)

		attachAttribute(floorPart, "IsSelected", function(value)
			floor.IsSelected = value or false
			if floor.IsSelected then
				setSelectedPart(floor)
			elseif plot.SelectedPart == floor then
				setSelectedPart(nil)
			end
			notifyPartChanged(floor)
		end)

		level.Floors[id] = floor
		notifyPartChanged(floor)
	end

	local function registerObject(level: Formex.Level, objectPart: BasePart)
		local id = tonumber(objectPart.Name)
		if not id or level.Objects[id] then
			return
		end

		local object = {} :: Formex.Object
		object.Id = id
		object.Part = objectPart :: Part
		object.Level = level
		object.ModelId = objectPart:GetAttribute("ModelId") or 0
		object.Position = objectPart:GetAttribute("Position") or Vector3.new(0, 0, 0)
		object.Orientation = objectPart:GetAttribute("Orientation") or Vector3.new(0, 0, 0)
		object.IsGhost = objectPart:GetAttribute("IsGhost") or false
		object.IsSelected = objectPart:GetAttribute("IsSelected") or false

		function object:SetPosition(newPosition: Vector3)
			object.Position = newPosition
			setAttributeIfChanged(objectPart, "Position", newPosition)
			notifyPartChanged(object)
		end

		function object:SetOrientation(newOrientation: Vector3)
			object.Orientation = newOrientation
			setAttributeIfChanged(objectPart, "Orientation", newOrientation)
			notifyPartChanged(object)
		end

		function object:Select()
			plot:SelectPart(object)
		end

		function object:Finish()
			object.IsGhost = false
			setAttributeIfChanged(objectPart, "IsGhost", false)
			notifyPartChanged(object)
		end

		function object:Delete()
			level.Objects[id] = nil
			if plot.SelectedPart == object then
				setSelectedPart(nil)
			end
			objectPart:Destroy()
			notifyPartChanged(object)
		end

		attachAttribute(objectPart, "ModelId", function(value)
			object.ModelId = value or 0
			notifyPartChanged(object)
		end)

		attachAttribute(objectPart, "Position", function(value)
			object.Position = typeof(value) == "Vector3" and value or Vector3.new(0, 0, 0)
			notifyPartChanged(object)
		end)

		attachAttribute(objectPart, "Orientation", function(value)
			object.Orientation = typeof(value) == "Vector3" and value or Vector3.new(0, 0, 0)
			notifyPartChanged(object)
		end)

		attachAttribute(objectPart, "IsGhost", function(value)
			object.IsGhost = value or false
			notifyPartChanged(object)
		end)

		attachAttribute(objectPart, "IsSelected", function(value)
			object.IsSelected = value or false
			if object.IsSelected then
				setSelectedPart(object)
			elseif plot.SelectedPart == object then
				setSelectedPart(nil)
			end
			notifyPartChanged(object)
		end)

		level.Objects[id] = object
		notifyPartChanged(object)
	end

	local function registerLevel(levelPart: Instance)
		if not levelPart:IsA("BasePart") then
			return
		end

		local levelId = tonumber(levelPart.Name)
		if not levelId or plot.Levels[levelId] then
			return
		end

		local level = {} :: Formex.Level
		level.Id = levelId
		level.Plot = plot
		level.Part = levelPart :: Part
		level.IsUnlocked = levelPart:GetAttribute("IsUnlocked") or false
		level.IsActive = levelPart:GetAttribute("IsActive") or false
		level.CanUnlock = levelPart:GetAttribute("CanUnlock") or false
		level.Walls = {}
		level.Floors = {}
		level.Objects = {}

		local wallFolder = getOrCreateFolder(levelPart, "Walls")
		local floorFolder = getOrCreateFolder(levelPart, "Floors")
		local objectFolder = getOrCreateFolder(levelPart, "Objects")

		levelFolders[levelId] = {
			Walls = wallFolder,
			Floors = floorFolder,
			Objects = objectFolder,
		}

		function level:Unlock()
			level.IsUnlocked = true
			level.CanUnlock = false
			setAttributeIfChanged(levelPart, "IsUnlocked", true)
			setAttributeIfChanged(levelPart, "CanUnlock", false)
			plot.LevelsUnlocked = math.max(plot.LevelsUnlocked, levelId)
			setAttributeIfChanged(plotPart, "LevelsUnlocked", plot.LevelsUnlocked)
			notifyPlotChanged()
		end

		function level:AddWall(start: Vector2int16): Formex.Wall
			local folders = levelFolders[levelId]
			local wallPart = Instance.new("Part")
			wallPart.Name = tostring(getNextId(folders.Walls))
			wallPart.Parent = folders.Walls
			wallPart.Anchored = true
			wallPart.CanCollide = false
			wallPart:SetAttribute("Start", start)
			wallPart:SetAttribute("End", start)
			wallPart:SetAttribute("Height", Formex.LevelHeight)
			wallPart:SetAttribute("FrontMaterial", Formex.DefaultWallMaterial)
			wallPart:SetAttribute("BackMaterial", Formex.DefaultWallMaterial)
			wallPart:SetAttribute("IsGhost", false)
			wallPart:SetAttribute("IsSelected", false)
			registerWall(level, wallPart)
			return getWall(level, tonumber(wallPart.Name) :: number)
		end

		function level:AddFloor(start: Vector2int16): Formex.Floor
			local folders = levelFolders[levelId]
			local floorPart = Instance.new("Part")
			floorPart.Name = tostring(getNextId(folders.Floors))
			floorPart.Parent = folders.Floors
			floorPart.Anchored = true
			floorPart.CanCollide = false
			floorPart:SetAttribute("Points", encodePoints({start}))
			floorPart:SetAttribute("FloorMaterial", Formex.DefaultFloorMaterial)
			floorPart:SetAttribute("CeilingMaterial", Formex.DefaultCeilingMaterial)
			floorPart:SetAttribute("FoundationMaterial", Formex.DefaultFoundationMaterial)
			floorPart:SetAttribute("IsGhost", false)
			floorPart:SetAttribute("IsSelected", false)
			registerFloor(level, floorPart)
			return getFloor(level, tonumber(floorPart.Name) :: number)
		end

		function level:AddObject(start: Vector2int16, modelId: number): Formex.Object
			local folders = levelFolders[levelId]
			local objectPart = Instance.new("Part")
			objectPart.Name = tostring(getNextId(folders.Objects))
			objectPart.Parent = folders.Objects
			objectPart.Anchored = true
			objectPart.CanCollide = false
			objectPart:SetAttribute("ModelId", modelId)
			objectPart:SetAttribute("Position", Vector3.new(start.X, 0, start.Y))
			objectPart:SetAttribute("Orientation", Vector3.new(0, 0, 0))
			objectPart:SetAttribute("IsGhost", false)
			objectPart:SetAttribute("IsSelected", false)
			registerObject(level, objectPart)
			return getObject(level, tonumber(objectPart.Name) :: number)
		end

		attachAttribute(levelPart, "IsUnlocked", function(value)
			level.IsUnlocked = value or false
			notifyPlotChanged()
		end)

		attachAttribute(levelPart, "IsActive", function(value)
			level.IsActive = value or false
			notifyPlotChanged()
		end)

		attachAttribute(levelPart, "CanUnlock", function(value)
			level.CanUnlock = value or false
			notifyPlotChanged()
		end)

		plot.Levels[levelId] = level
		notifyPlotChanged()

		wallFolder.ChildAdded:Connect(function(child)
			if child:IsA("BasePart") then
				registerWall(level, child)
			end
		end)
		wallFolder.ChildRemoved:Connect(function(child)
			local id = tonumber(child.Name)
			local wall = id and level.Walls[id]
			if wall then
				level.Walls[id] = nil
				if plot.SelectedPart == wall then
					setSelectedPart(nil)
				end
				notifyPartChanged(wall)
			end
		end)
		for _, wallPart in ipairs(wallFolder:GetChildren()) do
			if wallPart:IsA("BasePart") then
				registerWall(level, wallPart)
			end
		end

		floorFolder.ChildAdded:Connect(function(child)
			if child:IsA("BasePart") then
				registerFloor(level, child)
			end
		end)
		floorFolder.ChildRemoved:Connect(function(child)
			local id = tonumber(child.Name)
			local floor = id and level.Floors[id]
			if floor then
				level.Floors[id] = nil
				if plot.SelectedPart == floor then
					setSelectedPart(nil)
				end
				notifyPartChanged(floor)
			end
		end)
		for _, floorPart in ipairs(floorFolder:GetChildren()) do
			if floorPart:IsA("BasePart") then
				registerFloor(level, floorPart)
			end
		end

		objectFolder.ChildAdded:Connect(function(child)
			if child:IsA("BasePart") then
				registerObject(level, child)
			end
		end)
		objectFolder.ChildRemoved:Connect(function(child)
			local id = tonumber(child.Name)
			local object = id and level.Objects[id]
			if object then
				level.Objects[id] = nil
				if plot.SelectedPart == object then
					setSelectedPart(nil)
				end
				notifyPartChanged(object)
			end
		end)
		for _, objectPart in ipairs(objectFolder:GetChildren()) do
			if objectPart:IsA("BasePart") then
				registerObject(level, objectPart)
			end
		end
	end

	local function registerPlayer(playerInstance: Instance)
		local userId = playerInstance:GetAttribute("UserId") or tonumber(playerInstance.Name)
		if type(userId) ~= "number" then
			return
		end
		if playersByInstance[playerInstance] then
			return
		end

		local plotPlayer = {} :: Formex.PlotPlayer
		plotPlayer.UserId = userId
		plotPlayer.UserName = playerInstance:GetAttribute("UserName") or ""
		plotPlayer.Permission = playerInstance:GetAttribute("Permission") or Formex.Permission.Guest
		plotPlayer.Color = playerInstance:GetAttribute("Color") or Color3.new(1, 1, 1)
		plotPlayer.IsPresent = playerInstance:GetAttribute("IsPresent") or false
		plotPlayer.DesignMode = playerInstance:GetAttribute("DesignMode") or Formex.DesignMode.Play
		plotPlayer.SortOrder = playerInstance:GetAttribute("SortOrder") or 0

		playersByInstance[playerInstance] = plotPlayer
		playersByUserId[userId] = playerInstance
		plot.Players[userId] = plotPlayer

		attachAttribute(playerInstance, "UserName", function(value)
			plotPlayer.UserName = value or ""
			notifyPlotChanged()
		end)

		attachAttribute(playerInstance, "Permission", function(value)
			plotPlayer.Permission = value or Formex.Permission.Guest
			notifyPlotChanged()
		end)

		attachAttribute(playerInstance, "Color", function(value)
			plotPlayer.Color = typeof(value) == "Color3" and value or Color3.new(1, 1, 1)
			notifyPlotChanged()
		end)

		attachAttribute(playerInstance, "IsPresent", function(value)
			plotPlayer.IsPresent = value or false
			notifyPlotChanged()
		end)

		attachAttribute(playerInstance, "DesignMode", function(value)
			plotPlayer.DesignMode = value or Formex.DesignMode.Play
			notifyPlotChanged()
		end)

		attachAttribute(playerInstance, "SortOrder", function(value)
			plotPlayer.SortOrder = value or plotPlayer.SortOrder
			notifyPlotChanged()
		end)

		notifyPlotChanged()
	end

	local function unregisterPlayer(playerInstance: Instance)
		local plotPlayer = playersByInstance[playerInstance]
		if not plotPlayer then
			return
		end

		playersByInstance[playerInstance] = nil
		playersByUserId[plotPlayer.UserId] = nil
		plot.Players[plotPlayer.UserId] = nil
		notifyPlotChanged()
	end

	local function bindPlayersFolder(playersFolder: Instance)
		if not playersFolder:IsA("Folder") then
			return
		end

		for _, child in ipairs(playersFolder:GetChildren()) do
			registerPlayer(child)
		end
		playersFolder.ChildAdded:Connect(registerPlayer)
		playersFolder.ChildRemoved:Connect(unregisterPlayer)
	end

	attachAttribute(plotPart, "Name", function(value)
		plot.Name = value or ""
		notifyPlotChanged()
	end)

	attachAttribute(plotPart, "OwnerUserId", function(value)
		if value == nil or value == 0 then
			plot.OwnerUserId = nil
		else
			plot.OwnerUserId = value
		end
		notifyPlotChanged()
	end)

	attachAttribute(plotPart, "OwnerName", function(value)
		plot.OwnerName = value
		notifyPlotChanged()
	end)

	attachAttribute(plotPart, "SegmentsUnlocked", function(value)
		plot.SegmentsUnlocked = value or 0
		updateSegmentsFromCount()
	end)

	attachAttribute(plotPart, "LevelsUnlocked", function(value)
		plot.LevelsUnlocked = value or 0
		notifyPlotChanged()
	end)

	attachAttribute(plotPart, "CanUndo", function(value)
		plot.CanUndo = value or false
		notifyPlotChanged()
	end)

	attachAttribute(plotPart, "CanRedo", function(value)
		plot.CanRedo = value or false
		notifyPlotChanged()
	end)

	attachAttribute(plotPart, "DesignMode", function(value)
		plot.DesignMode = value or Formex.DesignMode.Play
		notifyPlotChanged()
	end)

	for index = 1, Formex.Segments.Count do
		local segment = {} :: Formex.Segment
		local row = math.floor((index - 1) / Formex.Segments.GridWidth)
		local column = (index - 1) % Formex.Segments.GridWidth
		segment.Position = Vector2int16.new(column + 1, row + 1)
		segment.IsUnlocked = false
		segment.CanUnlock = false

		function segment:Unlock()
			plot.SegmentsUnlocked = math.max(plot.SegmentsUnlocked, index)
			updateSegmentsFromCount()
		end

		plot.Segments[index] = segment
	end
	updateSegmentsFromCount()

	plotPart.ChildAdded:Connect(function(child)
		if child:IsA("BasePart") then
			registerLevel(child)
		elseif child.Name == "Players" then
			bindPlayersFolder(child)
		end
	end)
	plotPart.ChildRemoved:Connect(function(child)
		local levelIndex = tonumber(child.Name)
		if levelIndex then
			plot.Levels[levelIndex] = nil
			levelFolders[levelIndex] = nil
			notifyPlotChanged()
		elseif child.Name == "Players" then
			plot.Players = {}
			playersByInstance = {}
			playersByUserId = {}
			notifyPlotChanged()
		end
	end)

	for _, child in ipairs(plotPart:GetChildren()) do
		if child:IsA("BasePart") then
			registerLevel(child)
		elseif child.Name == "Players" then
			bindPlayersFolder(child)
		end
	end

	return plot
end

local networkFunctions = {
	SetName = function(player: Player, plot: Formex.Plot, newName: string)
		requirePermission(plot, Formex.Permission.Manager)
		plot:SetName(newName)
	end,
	SetPermission = function(player: Player, plot: Formex.Plot, userId: number, permission: Formex.Permission)
		requirePermission(plot, Formex.Permission.Owner)
		plot:SetPermission(userId, permission)
	end,
	SetDesignMode = function(player: Player, plot: Formex.Plot, mode: Formex.DesignMode, levelIndex: number)
		requirePermission(plot, Formex.Permission.Guest)
		plot:SetDesignMode(mode, levelIndex)
	end,
	SelectPart = function(player: Player, plot: Formex.Plot, levelId: number, partId: number)
		requirePermission(plot, Formex.Permission.Guest)
		local level = getLevel(plot, levelId)
		local part = level.Walls[partId] or level.Floors[partId] or level.Objects[partId]
		if not part then
			error("Part not found: " .. tostring(partId))
		end
		plot:SelectPart(part)
	end,
	DeselectAll = function(player: Player, plot: Formex.Plot)
		requirePermission(plot, Formex.Permission.Guest)
		plot:DeselectAll()
	end,
	Undo = function(player: Player, plot: Formex.Plot)
		requirePermission(plot, Formex.Permission.Guest)
		plot:Undo()
	end,
	Redo = function(player: Player, plot: Formex.Plot)
		requirePermission(plot, Formex.Permission.Guest)
		plot:Redo()
	end,
	IsPointValid = function(player: Player, plot: Formex.Plot, point: Vector2 | Vector2int16): boolean
		return plot:IsPointValid(point)
	end,
	IsLineValid = function(player: Player, plot: Formex.Plot, lineStart: Vector2 | Vector2int16, lineEnd: Vector2 | Vector2int16): boolean
		return plot:IsLineValid(lineStart, lineEnd)
	end,
	IsPolygonValid = function(player: Player, plot: Formex.Plot, points: {Vector2 | Vector2int16}): boolean
		return plot:IsPolygonValid(points)
	end,
	IsPointNearBoundary = function(player: Player, plot: Formex.Plot, point: Vector3, threshold: number): boolean
		return plot:IsPointNearBoundary(point, threshold)
	end,
	UpdatePoints = function(player: Player, plot: Formex.Plot, levelId: number, partId: number, ...)
		requirePermission(plot, Formex.Permission.Guest)
		local level = getLevel(plot, levelId)
		local args = { ... }
		if #args == 1 and type(args[1]) == "table" then
			local floor = getFloor(level, partId)
			floor:UpdatePoints(args[1])
			return
		end
		if #args >= 2 then
			local wall = getWall(level, partId)
			wall:UpdatePoints(args[1], args[2])
			return
		end
		error("Invalid UpdatePoints arguments")
	end,
	SetHeight = function(player: Player, plot: Formex.Plot, levelId: number, partId: number, newHeight: number)
		requirePermission(plot, Formex.Permission.Guest)
		local level = getLevel(plot, levelId)
		if level.Walls[partId] then
			local wall = getWall(level, partId)
			wall:SetHeight(newHeight)
			return
		end
		if level.Floors[partId] then
			local floor = getFloor(level, partId)
			floor:SetHeight(newHeight)
			return
		end
		error("Part not found: " .. tostring(partId))
	end,
	SetFrontMaterial = function(player: Player, plot: Formex.Plot, levelId: number, partId: number, materialId: number)
		requirePermission(plot, Formex.Permission.Guest)
		local wall = getWall(getLevel(plot, levelId), partId)
		wall:SetFrontMaterial(materialId)
	end,
	SetBackMaterial = function(player: Player, plot: Formex.Plot, levelId: number, partId: number, materialId: number)
		requirePermission(plot, Formex.Permission.Guest)
		local wall = getWall(getLevel(plot, levelId), partId)
		wall:SetBackMaterial(materialId)
	end,
	SetFloorMaterial = function(player: Player, plot: Formex.Plot, levelId: number, partId: number, materialId: number)
		requirePermission(plot, Formex.Permission.Guest)
		local floor = getFloor(getLevel(plot, levelId), partId)
		floor:SetFloorMaterial(materialId)
	end,
	SetCeilingMaterial = function(player: Player, plot: Formex.Plot, levelId: number, partId: number, materialId: number)
		requirePermission(plot, Formex.Permission.Guest)
		local floor = getFloor(getLevel(plot, levelId), partId)
		floor:SetCeilingMaterial(materialId)
	end,
	SetFoundationMaterial = function(player: Player, plot: Formex.Plot, levelId: number, partId: number, materialId: number)
		requirePermission(plot, Formex.Permission.Guest)
		local floor = getFloor(getLevel(plot, levelId), partId)
		floor:SetFoundationMaterial(materialId)
	end,
	SetPosition = function(player: Player, plot: Formex.Plot, levelId: number, partId: number, newPosition: Vector3)
		requirePermission(plot, Formex.Permission.Guest)
		local object = getObject(getLevel(plot, levelId), partId)
		object:SetPosition(newPosition)
	end,
	SetOrientation = function(player: Player, plot: Formex.Plot, levelId: number, partId: number, newOrientation: Vector3)
		requirePermission(plot, Formex.Permission.Guest)
		local object = getObject(getLevel(plot, levelId), partId)
		object:SetOrientation(newOrientation)
	end,
	Finish = function(player: Player, plot: Formex.Plot, levelId: number, partId: number)
		requirePermission(plot, Formex.Permission.Guest)
		local level = getLevel(plot, levelId)
		if level.Walls[partId] then
			getWall(level, partId):Finish()
			return
		end
		if level.Floors[partId] then
			getFloor(level, partId):Finish()
			return
		end
		if level.Objects[partId] then
			getObject(level, partId):Finish()
			return
		end
		error("Part not found: " .. tostring(partId))
	end,
	Delete = function(player: Player, plot: Formex.Plot, levelId: number, partId: number)
		requirePermission(plot, Formex.Permission.Guest)
		local level = getLevel(plot, levelId)
		if level.Walls[partId] then
			getWall(level, partId):Delete()
			return
		end
		if level.Floors[partId] then
			getFloor(level, partId):Delete()
			return
		end
		if level.Objects[partId] then
			getObject(level, partId):Delete()
			return
		end
		error("Part not found: " .. tostring(partId))
	end,
	UnlockLevel = function(player: Player, plot: Formex.Plot, levelId: number)
		requirePermission(plot, Formex.Permission.Owner)
		local level = getLevel(plot, levelId)
		level:Unlock()
	end,
	AddWall = function(player: Player, plot: Formex.Plot, levelId: number, start: Vector2int16): number
		requirePermission(plot, Formex.Permission.Guest)
		local level = getLevel(plot, levelId)
		local wall = level:AddWall(start)
		return wall.Id
	end,
	AddFloor = function(player: Player, plot: Formex.Plot, levelId: number, start: Vector2int16): number
		requirePermission(plot, Formex.Permission.Guest)
		local level = getLevel(plot, levelId)
		local floor = level:AddFloor(start)
		return floor.Id
	end,
	AddObject = function(player: Player, plot: Formex.Plot, levelId: number, start: Vector2int16, modelId: number): number
		requirePermission(plot, Formex.Permission.Guest)
		local level = getLevel(plot, levelId)
		local object = level:AddObject(start, modelId)
		return object.Id
	end,
	UnlockSegment = function(player: Player, plot: Formex.Plot, segmentIndex: number)
		requirePermission(plot, Formex.Permission.Owner)
		local segment = plot.Segments[segmentIndex]
		if not segment then
			error("Segment not found: " .. tostring(segmentIndex))
		end
		segment:Unlock()
	end,
}

NetworkFunction.OnServerInvoke = function(player, plotId, functionName, ...)
	local plot = PlotServer.GetPlot(plotId)
	local permissionAttribute = "U_" .. tostring(player.UserId)
	local permission = plot.Part:GetAttribute(permissionAttribute)
	local plotPlayer = plot.Players[player.UserId]
	if permission == nil and plotPlayer then
		permission = plotPlayer.Permission
	end
	if permission == nil then
		permission = Formex.Permission.Guest
	end
	plot.MyPermission = permission
	local handler = networkFunctions[functionName]
	if not handler then
		error("Unknown function: " .. tostring(functionName))
	end
	return handler(player, plot, ...)
end

return PlotServer
