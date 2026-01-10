--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Formex = require(script.Parent:FindFirstChild("Formex"))
Formex.Util = require(script.Parent:FindFirstChild("FormexUtil"))

Formex.Objects = {}

local PREFAB_FOLDER_NAME = "FormexPrefabs"
local prefabFolder = ReplicatedStorage:FindFirstChild(PREFAB_FOLDER_NAME)

local function splitPath(path: string): {string}
	local parts = {}
	for segment in string.gmatch(path, "[^/]+") do
		table.insert(parts, segment)
	end
	return parts
end

local function findPrefabModel(prefabName: string): Model?
	if not prefabName or prefabName == "" or not prefabFolder then
		return nil
	end

	local current: Instance = prefabFolder
	for _, segment in ipairs(splitPath(prefabName)) do
		local child = current:FindFirstChild(segment)
		if not child then
			return nil
		end
		current = child
	end

	if current:IsA("Model") then
		return current
	end
	return nil
end

local function resolveObjectMount(value: any): Formex.ObjectMount
	if value == Formex.MountType.Ceiling then
		return Formex.MountType.Ceiling
	elseif value == Formex.MountType.Floor then
		return Formex.MountType.Floor
	elseif value == Formex.MountType.Wall then
		return Formex.MountType.Wall
	elseif value == Formex.MountType.Window then
		return Formex.MountType.Window
	elseif value == Formex.MountType.Door then
		return Formex.MountType.Door
	elseif value == Formex.MountType.Surface then
		return Formex.MountType.Surface
	end
	return Formex.MountType.Floor
end

local function parseNumberList(value: any): {number}
	if type(value) ~= "string" then
		return {}
	end
	local result = {}
	for entry in string.gmatch(value, "([^,]+)") do
		local numberValue = tonumber(entry)
		if numberValue then
			table.insert(result, numberValue)
		end
	end
	return result
end

local function parseStringList(value: any): {string}
	if type(value) ~= "string" then
		return {}
	end
	local result = {}
	for entry in string.gmatch(value, "([^,]+)") do
		local trimmed = string.gsub(entry, "^%s*(.-)%s*$", "%1")
		if trimmed ~= "" then
			table.insert(result, trimmed)
		end
	end
	return result
end

local function collectDesignIndices(model: Model): {number}
	local indices = {}
	local seen = {}
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			local index = tonumber(child.Name)
			if index and not seen[index] then
				seen[index] = true
				table.insert(indices, index)
			end
		end
	end
	table.sort(indices)
	return indices
end

local function ensureDefaultDesign(prefab: Formex.ObjectPrefab, model: Model?)
	if prefab.DefaultDesign and #prefab.DefaultDesign > 0 then
		return
	end
	if not model then
		prefab.DefaultDesign = {}
		return
	end
	prefab.DefaultDesign = collectDesignIndices(model)
end

local cachedPrefabs: {Formex.ObjectPrefab}? = nil
local prefabByName: {[string]: Formex.ObjectPrefab}? = nil

local function buildPrefabFromModel(model: Model, pathName: string): Formex.ObjectPrefab
	local size = model:GetAttribute("Size")
	if typeof(size) ~= "Vector3" then
		size = model:GetExtentsSize()
	end

	local prefab: Formex.ObjectPrefab = {
		Name = model:GetAttribute("DisplayName") or model.Name,
		IconAssetId = model:GetAttribute("IconAssetId") or 0,
		PrefabName = pathName,
		ObjectMount = resolveObjectMount(model:GetAttribute("ObjectMount")),
		Size = size,
		Categories = parseStringList(model:GetAttribute("Categories")),
		DefaultDesign = parseNumberList(model:GetAttribute("DefaultDesign")),
		Attributes = model:GetAttributes(),
		Model = model,
	}

	ensureDefaultDesign(prefab, model)
	return prefab
end

local function collectPrefabModels(root: Instance, prefix: string, list: {Formex.ObjectPrefab})
	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("Model") then
			local pathName = prefix ~= "" and (prefix .. "/" .. child.Name) or child.Name
			table.insert(list, buildPrefabFromModel(child, pathName))
		elseif child:IsA("Folder") then
			local folderPrefix = prefix ~= "" and (prefix .. "/" .. child.Name) or child.Name
			collectPrefabModels(child, folderPrefix, list)
		end
	end
end

local function buildPrefabCache(): ({Formex.ObjectPrefab}, {[string]: Formex.ObjectPrefab})
	local list = table.clone(Formex.Furniture or {})
	local byName = {} :: {[string]: Formex.ObjectPrefab}

	for _, prefab in ipairs(list) do
		if prefab.PrefabName then
			prefab.Model = findPrefabModel(prefab.PrefabName)
			ensureDefaultDesign(prefab, prefab.Model)
			prefab.ObjectMount = resolveObjectMount(prefab.ObjectMount)
			byName[prefab.PrefabName] = prefab
		end
	end

	if prefabFolder then
		local discovered = {} :: {Formex.ObjectPrefab}
		collectPrefabModels(prefabFolder, "", discovered)
		for _, prefab in ipairs(discovered) do
			if not byName[prefab.PrefabName] then
				table.insert(list, prefab)
				byName[prefab.PrefabName] = prefab
			end
		end
	end

	return list, byName
end

function Formex.Objects.GetPrefabs(): {Formex.ObjectPrefab}
	if not cachedPrefabs or not prefabByName then
		local list, byName = buildPrefabCache()
		cachedPrefabs = list
		prefabByName = byName
	end
	return cachedPrefabs
end

function Formex.Objects.GetPrefab(prefabName: string?): Formex.ObjectPrefab?
	if not prefabName or prefabName == "" then
		return nil
	end
	if not cachedPrefabs or not prefabByName then
		Formex.Objects.GetPrefabs()
	end
	return prefabByName and prefabByName[prefabName] or nil
end

local function resolvePrefabModels(prefab: Formex.ObjectPrefab): (Model?, Model?)
	local prefabModel = prefab.Model or findPrefabModel(prefab.PrefabName)
	if not prefabModel then
		return nil, nil
	end

	if prefab.ObjectMount == Formex.MountType.Door or prefab.ObjectMount == Formex.MountType.Window then
		local objectModel = prefabModel:FindFirstChild("Model")
		local subtractModel = prefabModel:FindFirstChild("Subtract")
		if objectModel and objectModel:IsA("Model") then
			return objectModel, subtractModel and subtractModel:IsA("Model") and subtractModel or nil
		end
	end

	return prefabModel, nil
end

local function ensurePrimaryPart(model: Model): BasePart?
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			model.PrimaryPart = child
			return child
		end
	end
	return nil
end

local function applyObjectPartsSetup(model: Model, collisionGroup: string, isSubtract: boolean)
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			child.Anchored = true
			child.CollisionGroup = collisionGroup
			if isSubtract then
				child.Transparency = 1
				child.CanCollide = false
				child.CanTouch = false
				child.CanQuery = false
				child.CastShadow = false
			end
		end
	end
end

function Formex.Objects.BuildDesignParts(model: Model): {[number]: {BasePart}}
	local grouped = {} :: {[number]: {BasePart}}
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			local index = tonumber(child.Name)
			if index then
				local list = grouped[index]
				if not list then
					list = {}
					grouped[index] = list
				end
				table.insert(list, child)
			end
		end
	end
	return grouped
end

local function resolveDesignColor(designColors: {[number]: Color3}?, index: number, fallback: Color3): Color3
	if designColors then
		local color = designColors[index]
		if color then
			return color
		end
	end
	return fallback
end

function Formex.Objects.ApplyDesign(objectData: Formex.ObjectData, objectModel: Model?)
	if not objectData or not objectModel then
		return
	end
	if not objectData.DesignParts then
		objectData.DesignParts = Formex.Objects.BuildDesignParts(objectModel)
	end
	local design = objectData.Design or {}
	local designColors = objectData.DesignColors or {}
	for index, parts in pairs(objectData.DesignParts) do
		local materialId = design[index]
		local colorFallback = parts[1] and parts[1].Color or Color3.new(1, 1, 1)
		local color = resolveDesignColor(designColors, index, colorFallback)
		for _, part in ipairs(parts) do
			Formex.Util.ApplyWallMaterial(part, materialId, color)
		end
	end
end

local function getEncodedColor(color: Color3?): (number, number, number)
	local resolved = color or Color3.new(1, 1, 1)
	return math.round(resolved.R * 255), math.round(resolved.G * 255), math.round(resolved.B * 255)
end

function Formex.Objects.EncodeDesign(design: {[number]: number}?, designColors: {[number]: Color3}?): string
	local entries = {}
	if design then
		for index, materialId in pairs(design) do
			if type(index) == "number" and type(materialId) == "number" then
				local r, g, b = getEncodedColor(designColors and designColors[index])
				table.insert(entries, string.format("%d,%d,%d,%d,%d", index, materialId, r, g, b))
			end
		end
	end
	table.sort(entries)
	return table.concat(entries, ";")
end

function Formex.Objects.DecodeDesign(value: string?): ({[number]: number}, {[number]: Color3})
	local design = {}
	local colors = {}
	if not value or value == "" then
		return design, colors
	end

	for entry in string.gmatch(value, "([^;]+)") do
		local i1, i2, i3, i4, i5 = string.match(entry, "([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")
		if i1 and i2 and i3 and i4 and i5 then
			local index = tonumber(i1)
			local materialId = tonumber(i2)
			local r = tonumber(i3)
			local g = tonumber(i4)
			local b = tonumber(i5)
			if index and materialId then
				design[index] = materialId
				if r and g and b then
					colors[index] = Color3.fromRGB(r, g, b)
				end
			end
		else
			local simpleIndex, simpleMaterial = string.match(entry, "([^,]+),([^,]+)")
			if simpleIndex and simpleMaterial then
				local index = tonumber(simpleIndex)
				local materialId = tonumber(simpleMaterial)
				if index and materialId then
					design[index] = materialId
				end
			else
				local legacyIndex, legacyMaterial = string.match(entry, "([^:]+):([^:]+)")
				local index = tonumber(legacyIndex)
				local materialId = tonumber(legacyMaterial)
				if index and materialId then
					design[index] = materialId
				end
			end
		end
	end

	return design, colors
end

function Formex.Objects.EnsureDesignDefaults(objectData: Formex.ObjectData, prefab: Formex.ObjectPrefab)
	objectData.Design = objectData.Design or {}
	objectData.DesignColors = objectData.DesignColors or {}
	for index, defaultMaterial in ipairs(prefab.DefaultDesign or {}) do
		if objectData.Design[index] == nil then
			objectData.Design[index] = defaultMaterial
		end
	end
end

local function snapToGrid(value: number, grid: number): number
	if grid <= 0 then
		return value
	end
	return math.round(value / grid) * grid
end

function Formex.Objects.SnapVector(position: Vector3): Vector3
	local grid = Formex.ObjectGridSize
	return Vector3.new(
		snapToGrid(position.X, grid),
		snapToGrid(position.Y, grid),
		snapToGrid(position.Z, grid)
	)
end

function Formex.Objects.GetWallBasis(wall: Formex.WallData): (Vector3, Vector3, Vector3, number)
	local startPoint = wall.Start
	local endPoint = wall.End
	local dir = Vector3.new(endPoint.X - startPoint.X, 0, endPoint.Y - startPoint.Y)
	local length = dir.Magnitude
	if length <= Formex.EPSILON then
		dir = Vector3.new(0, 0, 1)
		length = 0
	else
		dir = dir / length
	end
	local right = Vector3.new(-dir.Z, 0, dir.X)
	return dir, right, Vector3.new(startPoint.X, 0, startPoint.Y), length
end

function Formex.Objects.GetWallCFrame(plotPart: BasePart, wall: Formex.WallData, localPosition: Vector3, rotation: Vector3): CFrame
	local dir, right, startLocal, _ = Formex.Objects.GetWallBasis(wall)
	local levelOffset = Formex.Plot.GetLevelOffset(wall.Level or 1)
	local base = Vector3.new(startLocal.X, levelOffset, startLocal.Z)
	local localPos = base + (dir * localPosition.X) + Vector3.new(0, localPosition.Y, 0) + (right * localPosition.Z)
	local yaw = math.atan2(dir.X, dir.Z)
	local radians = Vector3.new(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
	local localCFrame = CFrame.new(localPos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(radians.X, radians.Y, radians.Z)
	return plotPart.CFrame * localCFrame
end

function Formex.Objects.GetWorldCFrame(plotPart: BasePart, position: Vector3, rotation: Vector3): CFrame
	local radians = Vector3.new(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
	local localCFrame = CFrame.new(position) * CFrame.Angles(radians.X, radians.Y, radians.Z)
	return plotPart.CFrame * localCFrame
end

local function shouldCarve(prefab: Formex.ObjectPrefab?): boolean
	if not prefab then
		return false
	end
	return prefab.ObjectMount == Formex.MountType.Door or prefab.ObjectMount == Formex.MountType.Window
end

function Formex.Objects.CarveWallObjects(plotData: Formex.PlotData, wallData: Formex.WallData)
	if not plotData or not wallData or not wallData.Part then
		return
	end
	local levelData = plotData.Levels and plotData.Levels[wallData.Level or 1]
	if not levelData or not levelData.Objects then
		return
	end

	local subtractParts = {}
	for _, objectData in pairs(levelData.Objects) do
		if objectData.WallId == wallData.WallId then
			local prefab = objectData.Prefab
			if not prefab and objectData.PrefabName then
				prefab = Formex.Objects.GetPrefab(objectData.PrefabName)
				objectData.Prefab = prefab
			end
			if shouldCarve(prefab) then
				local subtractModel = objectData.SubtractModel
				if not subtractModel and objectData.Part then
					local found = objectData.Part:FindFirstChild("Subtract")
					if found and found:IsA("Model") then
						subtractModel = found
						objectData.SubtractModel = subtractModel
					end
				end
				if subtractModel then
					for _, child in ipairs(subtractModel:GetChildren()) do
						if child:IsA("BasePart") then
							table.insert(subtractParts, child)
						end
					end
				end
			end
		end
	end

	if #subtractParts == 0 then
		return
	end

	local wallModel = wallData.Part
	local partNames = {
		Formex.Walls and Formex.Walls.FrontPartName or "Front",
		Formex.Walls and Formex.Walls.BackPartName or "BackSide",
		"FrontTop",
		"BackTop",
	}

	for _, name in ipairs(partNames) do
		local wallPart = wallModel:FindFirstChild(name)
		if wallPart and wallPart:IsA("BasePart") then
			local carved = wallPart:SubtractAsync(subtractParts)
			if carved then
				carved.Name = wallPart.Name
				carved.Anchored = wallPart.Anchored
				carved.Material = wallPart.Material
				carved.MaterialVariant = wallPart.MaterialVariant
				carved.Color = wallPart.Color
				carved.Transparency = wallPart.Transparency
				carved.CollisionGroup = wallPart.CollisionGroup
				carved.CanCollide = wallPart.CanCollide
				carved.CanTouch = wallPart.CanTouch
				carved.CanQuery = wallPart.CanQuery
				carved.CastShadow = wallPart.CastShadow
				carved.Parent = wallPart.Parent
				wallPart:Destroy()
			end
		end
	end
end

function Formex.Objects.CreateObject(parent: Instance, objectData: Formex.ObjectData, plotPart: BasePart?, plotData: Formex.PlotData?): Model?
	if not objectData or not parent then
		return nil
	end

	local prefab = objectData.Prefab
	if not prefab and objectData.PrefabName then
		prefab = Formex.Objects.GetPrefab(objectData.PrefabName)
	end
	if not prefab then
		return nil
	end

	local objectModelTemplate, subtractTemplate = resolvePrefabModels(prefab)
	if not objectModelTemplate then
		return nil
	end

	local container = Instance.new("Model")
	container.Name = tostring(objectData.ObjectId)
	container.Parent = parent
	objectData.Part = container
	objectData.Prefab = prefab
	objectData.PrefabName = prefab.PrefabName

	local objectModel = objectModelTemplate:Clone()
	objectModel.Name = "Object"
	objectModel.Parent = container
	applyObjectPartsSetup(objectModel, Formex.CollisionGroup.Object, false)
	ensurePrimaryPart(objectModel)

	local subtractModel: Model? = nil
	if subtractTemplate and subtractTemplate:IsA("Model") then
		subtractModel = subtractTemplate:Clone()
		subtractModel.Name = "Subtract"
		subtractModel.Parent = container
		applyObjectPartsSetup(subtractModel, Formex.CollisionGroup.Object, true)
	end

	container.PrimaryPart = objectModel.PrimaryPart or ensurePrimaryPart(objectModel)
	objectData.ObjectModel = objectModel
	objectData.SubtractModel = subtractModel
	objectData.DesignParts = Formex.Objects.BuildDesignParts(objectModel)
	Formex.Objects.EnsureDesignDefaults(objectData, prefab)
	Formex.Objects.ApplyDesign(objectData, objectModel)

	if plotPart then
		Formex.Objects.EditObject(objectData, plotPart, plotData)
	end

	return container
end

function Formex.Objects.EditObject(objectData: Formex.ObjectData, plotPart: BasePart?, plotData: Formex.PlotData?)
	local container = objectData.Part
	if not container or not plotPart then
		return
	end

	local prefab = objectData.Prefab
	if not prefab and objectData.PrefabName then
		prefab = Formex.Objects.GetPrefab(objectData.PrefabName)
		objectData.Prefab = prefab
	end

	if prefab then
		Formex.Objects.EnsureDesignDefaults(objectData, prefab)
	end

	local objectModel = objectData.ObjectModel
	if not objectModel then
		local found = container:FindFirstChild("Object")
		if found and found:IsA("Model") then
			objectModel = found
			objectData.ObjectModel = objectModel
		end
	end

	if objectModel then
		objectData.DesignParts = objectData.DesignParts or Formex.Objects.BuildDesignParts(objectModel)
		Formex.Objects.ApplyDesign(objectData, objectModel)
	end

	local rotation = objectData.Rotation or Vector3.new(0, 0, 0)
	local position = objectData.Position or Vector3.new(0, 0, 0)
	local objectMount = prefab and prefab.ObjectMount or Formex.MountType.Floor
	local targetCFrame: CFrame? = nil

	if objectMount == Formex.MountType.Wall or objectMount == Formex.MountType.Door or objectMount == Formex.MountType.Window then
		local wall = nil
		if objectData.WallId and objectData.Level and plotData and plotData.Levels and plotData.Levels[objectData.Level] then
			wall = plotData.Levels[objectData.Level].Walls[objectData.WallId]
		end
		if wall then
			targetCFrame = Formex.Objects.GetWallCFrame(plotPart, wall, position, rotation)
		end
	else
		targetCFrame = Formex.Objects.GetWorldCFrame(plotPart, position, rotation)
	end

	if targetCFrame then
		container:PivotTo(targetCFrame)
	end

	container:SetAttribute("Position", position)
	container:SetAttribute("Rotation", rotation)
	container:SetAttribute("WallId", objectData.WallId)
	container:SetAttribute("PrefabName", objectData.PrefabName or (prefab and prefab.PrefabName) or "")
	container:SetAttribute("Design", Formex.Objects.EncodeDesign(objectData.Design, objectData.DesignColors))
	container:SetAttribute("IsPortal", objectData.IsPortal == true)
end

Formex.CreateObject = Formex.Objects.CreateObject
Formex.EditObject = Formex.Objects.EditObject

return Formex.Objects
