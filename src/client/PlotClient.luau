--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local FormexFolder = ReplicatedStorage:WaitForChild("Formex")
local Formex = require(FormexFolder:WaitForChild("Formex"))
local NetworkFunction: RemoteFunction = FormexFolder:WaitForChild("RemoteFunction") :: RemoteFunction

if not Players.LocalPlayer then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
end
local localPlayer = Players.LocalPlayer

local PlotClient = {}

local plots = {} :: {[number]: Formex.Plot} -- [plotId]
local currentPlot: Formex.Plot? = nil

local function attachAttribute(instance: Instance, attributeName: string, onUpdate: (any) -> ())
	instance:GetAttributeChangedSignal(attributeName):Connect(function()
		local value = instance:GetAttribute(attributeName)
		onUpdate(value)
	end)
	local initialValue = instance:GetAttribute(attributeName)
	onUpdate(initialValue)
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

function PlotClient.RegisterPlot(plotPart: Part)
	local plot = {} :: Formex.Plot
	local plotId = plotPart:GetAttribute("PlotId")
	if type(plotId) ~= "number" then
		error("PlotId attribute missing on plot")
	end
	plots[plotId] = plot

	plot.Part = plotPart
	plot.PlotId = plotId
	plot.Id = plotId
	plot.Name = ""
	plot.OwnerUserId = nil
	plot.OwnerName = nil
	plot.MyPermission = Formex.Permission.Guest
	plot.SegmentsUnlocked = 0
	plot.LevelsUnlocked = 0
	plot.Segments = {}
	plot.Levels = {}
	plot.Players = {}
	plot.CanUndo = false
	plot.CanRedo = false
	plot.DesignMode = Formex.DesignMode.Play
	plot.SelectedPart = nil
	plot.OnPlotChanged = Instance.new("BindableEvent")
	plot.OnPartChanged = Instance.new("BindableEvent")
	plot.OnSelectionChanged = Instance.new("BindableEvent")

	local function notifyPlotChanged()
		plot.OnPlotChanged:Fire()
	end

	local function notifyPartChanged(part: Formex.Wall | Formex.Floor | Formex.Object)
		plot.OnPartChanged:Fire(part)
	end

	local function notifySelectionChanged()
		plot.OnSelectionChanged:Fire()
	end

	local function updateSelectedPart(part: Formex.Wall | Formex.Floor | Formex.Object, isSelected: boolean)
		if isSelected then
			if plot.SelectedPart ~= part then
				plot.SelectedPart = part
				notifySelectionChanged()
			end
		elseif plot.SelectedPart == part then
			plot.SelectedPart = nil
			notifySelectionChanged()
		end
	end

	local function updateSegmentsFromCount()
		for index, segment in ipairs(plot.Segments) do
			local isUnlocked = index <= plot.SegmentsUnlocked
			segment.IsUnlocked = isUnlocked
			segment.CanUnlock = not isUnlocked and index == plot.SegmentsUnlocked + 1
		end
		notifyPlotChanged()
	end

	function plot:SetName(newName: string)
		plot.Name = newName
		plotPart:SetAttribute("Name", newName)
		NetworkFunction:InvokeServer(plotId, "SetName", newName)
	end

	function plot:SetPermission(userId: number, permission: Formex.Permission)
		NetworkFunction:InvokeServer(plotId, "SetPermission", userId, permission)
	end

	function plot:SetDesignMode(mode: Formex.DesignMode, levelIndex: number)
		plot.DesignMode = mode
		plotPart:SetAttribute("DesignMode", mode)
		NetworkFunction:InvokeServer(plotId, "SetDesignMode", mode, levelIndex)
	end

	function plot:SelectPart(part: Formex.Wall | Formex.Floor | Formex.Object)
		plot.SelectedPart = part
		notifySelectionChanged()
		NetworkFunction:InvokeServer(plotId, "SelectPart", part.Level.Id, part.Id)
	end

	function plot:DeselectAll()
		if plot.SelectedPart ~= nil then
			plot.SelectedPart = nil
			notifySelectionChanged()
		end
		NetworkFunction:InvokeServer(plotId, "DeselectAll")
	end

	function plot:Undo()
		NetworkFunction:InvokeServer(plotId, "Undo")
	end

	function plot:Redo()
		NetworkFunction:InvokeServer(plotId, "Redo")
	end

	function plot:IsPointValid(point: Vector2 | Vector2int16): boolean
		return NetworkFunction:InvokeServer(plotId, "IsPointValid", point)
	end

	function plot:IsLineValid(lineStart: Vector2 | Vector2int16, lineEnd: Vector2 | Vector2int16): boolean
		return NetworkFunction:InvokeServer(plotId, "IsLineValid", lineStart, lineEnd)
	end

	function plot:IsPolygonValid(points: {Vector2 | Vector2int16}): boolean
		return NetworkFunction:InvokeServer(plotId, "IsPolygonValid", points)
	end

	function plot:IsPointNearBoundary(point: Vector3, threshold: number): boolean
		return NetworkFunction:InvokeServer(plotId, "IsPointNearBoundary", point, threshold)
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
		wall.Start = Vector2int16.new(0, 0)
		wall.End = Vector2int16.new(0, 0)
		wall.Height = 0
		wall.FrontMaterial = Formex.DefaultWallMaterial
		wall.BackMaterial = Formex.DefaultWallMaterial
		wall.IsGhost = false
		wall.IsSelected = false

		function wall:UpdatePoints(newStart: Vector2int16, newEnd: Vector2int16)
			wall.Start = newStart
			wall.End = newEnd
			wallPart:SetAttribute("Start", newStart)
			wallPart:SetAttribute("End", newEnd)
			NetworkFunction:InvokeServer(plotId, "UpdatePoints", level.Id, wall.Id, newStart, newEnd)
		end

		function wall:SetHeight(newHeight: number)
			wall.Height = newHeight
			wallPart:SetAttribute("Height", newHeight)
			NetworkFunction:InvokeServer(plotId, "SetHeight", level.Id, wall.Id, newHeight)
		end

		function wall:SetFrontMaterial(materialId: number)
			wall.FrontMaterial = materialId
			wallPart:SetAttribute("FrontMaterial", materialId)
			NetworkFunction:InvokeServer(plotId, "SetFrontMaterial", level.Id, wall.Id, materialId)
		end

		function wall:SetBackMaterial(materialId: number)
			wall.BackMaterial = materialId
			wallPart:SetAttribute("BackMaterial", materialId)
			NetworkFunction:InvokeServer(plotId, "SetBackMaterial", level.Id, wall.Id, materialId)
		end

		function wall:Select()
			plot:SelectPart(wall)
		end

		function wall:Finish()
			NetworkFunction:InvokeServer(plotId, "Finish", level.Id, wall.Id)
		end

		function wall:Delete()
			NetworkFunction:InvokeServer(plotId, "Delete", level.Id, wall.Id)
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
			wall.Height = value or 0
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
			updateSelectedPart(wall, wall.IsSelected)
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
		floor.Points = {}
		floor.IsGhost = false
		floor.IsSelected = false

		function floor:UpdatePoints(newPoints: {Vector2int16})
			floor.Points = newPoints
			NetworkFunction:InvokeServer(plotId, "UpdatePoints", level.Id, floor.Id, newPoints)
		end

		function floor:SetHeight(newHeight: number)
			floorPart:SetAttribute("Height", newHeight)
			NetworkFunction:InvokeServer(plotId, "SetHeight", level.Id, floor.Id, newHeight)
		end

		function floor:SetFloorMaterial(materialId: number)
			floorPart:SetAttribute("FloorMaterial", materialId)
			NetworkFunction:InvokeServer(plotId, "SetFloorMaterial", level.Id, floor.Id, materialId)
		end

		function floor:SetCeilingMaterial(materialId: number)
			floorPart:SetAttribute("CeilingMaterial", materialId)
			NetworkFunction:InvokeServer(plotId, "SetCeilingMaterial", level.Id, floor.Id, materialId)
		end

		function floor:SetFoundationMaterial(materialId: number)
			floorPart:SetAttribute("FoundationMaterial", materialId)
			NetworkFunction:InvokeServer(plotId, "SetFoundationMaterial", level.Id, floor.Id, materialId)
		end

		function floor:Select()
			plot:SelectPart(floor)
		end

		function floor:Finish()
			NetworkFunction:InvokeServer(plotId, "Finish", level.Id, floor.Id)
		end

		function floor:Delete()
			NetworkFunction:InvokeServer(plotId, "Delete", level.Id, floor.Id)
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
			updateSelectedPart(floor, floor.IsSelected)
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
		object.ModelId = 0
		object.Position = Vector3.new(0, 0, 0)
		object.Orientation = Vector3.new(0, 0, 0)
		object.IsGhost = false
		object.IsSelected = false

		function object:SetPosition(newPosition: Vector3)
			object.Position = newPosition
			objectPart:SetAttribute("Position", newPosition)
			NetworkFunction:InvokeServer(plotId, "SetPosition", level.Id, object.Id, newPosition)
		end

		function object:SetOrientation(newOrientation: Vector3)
			object.Orientation = newOrientation
			objectPart:SetAttribute("Orientation", newOrientation)
			NetworkFunction:InvokeServer(plotId, "SetOrientation", level.Id, object.Id, newOrientation)
		end

		function object:Select()
			plot:SelectPart(object)
		end

		function object:Finish()
			NetworkFunction:InvokeServer(plotId, "Finish", level.Id, object.Id)
		end

		function object:Delete()
			NetworkFunction:InvokeServer(plotId, "Delete", level.Id, object.Id)
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
			updateSelectedPart(object, object.IsSelected)
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
		level.IsUnlocked = false
		level.IsActive = false
		level.CanUnlock = false
		level.Walls = {}
		level.Floors = {}
		level.Objects = {}

		function level:Unlock()
			NetworkFunction:InvokeServer(plotId, "UnlockLevel", level.Id)
		end

		function level:AddWall(start: Vector2int16): Formex.Wall
			local result = NetworkFunction:InvokeServer(plotId, "AddWall", level.Id, start)
			if type(result) == "number" then
				return level.Walls[result]
			end
			return result
		end

		function level:AddFloor(start: Vector2int16): Formex.Floor
			local result = NetworkFunction:InvokeServer(plotId, "AddFloor", level.Id, start)
			if type(result) == "number" then
				return level.Floors[result]
			end
			return result
		end

		function level:AddObject(start: Vector2int16, modelId: number): Formex.Object
			local result = NetworkFunction:InvokeServer(plotId, "AddObject", level.Id, start, modelId)
			if type(result) == "number" then
				return level.Objects[result]
			end
			return result
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

		local wallFolder = levelPart:WaitForChild("Walls") :: Folder
		local floorFolder = levelPart:WaitForChild("Floors") :: Folder
		local objectFolder = levelPart:WaitForChild("Objects") :: Folder

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
					plot.SelectedPart = nil
					notifySelectionChanged()
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
					plot.SelectedPart = nil
					notifySelectionChanged()
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
					plot.SelectedPart = nil
					notifySelectionChanged()
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

	local permissionOrder = {
		[Formex.Permission.Owner] = 1,
		[Formex.Permission.Manager] = 2,
		[Formex.Permission.VIP] = 3,
		[Formex.Permission.Guest] = 4,
		[Formex.Permission.Banned] = 5,
	}

	local playersByInstance = {} :: {[Instance]: Formex.PlotPlayer}

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
		plotPlayer.SortOrder = playerInstance:GetAttribute("SortOrder") or permissionOrder[plotPlayer.Permission] or 0

		playersByInstance[playerInstance] = plotPlayer
		plot.Players[userId] = plotPlayer

		if userId == localPlayer.UserId then
			plot.MyPermission = plotPlayer.Permission
			notifyPlotChanged()
		end

		attachAttribute(playerInstance, "UserName", function(value)
			plotPlayer.UserName = value or ""
			notifyPlotChanged()
		end)

		attachAttribute(playerInstance, "Permission", function(value)
			plotPlayer.Permission = value or Formex.Permission.Guest
			plotPlayer.SortOrder = permissionOrder[plotPlayer.Permission] or plotPlayer.SortOrder
			if userId == localPlayer.UserId then
				plot.MyPermission = plotPlayer.Permission
			end
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

	local permissionAttribute = "U_" .. tostring(localPlayer.UserId)
	local function updateMyPermission(value: any)
		plot.MyPermission = value or Formex.Permission.Guest
		notifyPlotChanged()
	end
	attachAttribute(plotPart, permissionAttribute, updateMyPermission)
	attachAttribute(plotPart, "MyPermission", updateMyPermission)

	for index = 1, Formex.Segments.Count do
		local segment = {} :: Formex.Segment
		local row = math.floor((index - 1) / Formex.Segments.GridWidth)
		local column = (index - 1) % Formex.Segments.GridWidth
		segment.Position = Vector2int16.new(column + 1, row + 1)
		segment.IsUnlocked = false
		segment.CanUnlock = false

		function segment:Unlock()
			NetworkFunction:InvokeServer(plotId, "UnlockSegment", index)
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
			notifyPlotChanged()
		elseif child.Name == "Players" then
			plot.Players = {}
			playersByInstance = {}
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

return PlotClient
