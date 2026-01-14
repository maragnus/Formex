--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Formex = require(script.Parent:FindFirstChild("Formex"))
Formex.Util = require(script.Parent:FindFirstChild("FormexUtil"))
Formex.Plot = require(script.Parent:FindFirstChild("FormexPlot"))

Formex.Objects = {}

local PREFAB_FOLDER_NAME = "FormexPrefabs"
local WORKSPACE_ROOT_NAME = "Formex"
local WORKSPACE_PREFABS_NAME = "Prefabs"
local WORKSPACE_STAGE_FOLDER_NAME = "Stages"

local prefabFolder = ReplicatedStorage:FindFirstChild(PREFAB_FOLDER_NAME)
local workspacePrefabFolder = nil :: Instance?

local function resolveWorkspacePrefabFolder(): Instance?
	if workspacePrefabFolder then return workspacePrefabFolder end
	local formexFolder = Workspace:FindFirstChild(WORKSPACE_ROOT_NAME)
	if not formexFolder then return nil end
	local prefabsFolder = formexFolder:FindFirstChild(WORKSPACE_PREFABS_NAME)
	if prefabsFolder then
		workspacePrefabFolder = prefabsFolder
	end
	return workspacePrefabFolder
end

local function splitPath(path: string): {string}
	local parts = {}
	for segment in string.gmatch(path, "[^/]+") do
		table.insert(parts, segment)
	end
	return parts
end

local function findPrefabInFolder(root: Instance?, prefabName: string): Model?
	if not prefabName or prefabName == "" or not root then return nil end
	local current: Instance = root
	for _, segment in ipairs(splitPath(prefabName)) do
		local child = current:FindFirstChild(segment)
		if not child then return nil end
		current = child
	end

	if current:IsA("Model") then return current end
	return nil
end

local function findPrefabModel(prefabName: string): Model?
	local found = findPrefabInFolder(prefabFolder, prefabName)
	if found then return found end
	return findPrefabInFolder(resolveWorkspacePrefabFolder(), prefabName)
end

local function ensureDeterministicPrimaryPart(model: Model?)
	if not model or model.PrimaryPart then return end
	local namedBase: BasePart? = nil
	local firstSeat: BasePart? = nil
	local largestPart: BasePart? = nil
	local largestVolume = -math.huge
	local firstPart: BasePart? = nil

	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			if not firstPart then
				firstPart = child
			end
			if child.Name == "BasePart" and not namedBase then
				namedBase = child
			end
			if child:IsA("Seat") and not firstSeat then
				firstSeat = child
			end
			local size = child.Size
			local volume = size.X * size.Y * size.Z
			if volume > largestVolume then
				largestVolume = volume
				largestPart = child
			end
		end
	end

	model.PrimaryPart = namedBase or firstSeat or largestPart or firstPart
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
	if prefab.DefaultDesign and #prefab.DefaultDesign > 0 then return end
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

local function collectPrefabModels(root: Instance, prefix: string, list: {Formex.ObjectPrefab}, skipFolderName: string?)
	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("Model") then
			local pathName = prefix ~= "" and (prefix .. "/" .. child.Name) or child.Name
			table.insert(list, buildPrefabFromModel(child, pathName))
		elseif child:IsA("Folder") then
			if skipFolderName and child.Name == skipFolderName then
				continue
			end
			local folderPrefix = prefix ~= "" and (prefix .. "/" .. child.Name) or child.Name
			collectPrefabModels(child, folderPrefix, list, skipFolderName)
		end
	end
end

local function buildPrefabCache(): ({Formex.ObjectPrefab}, {[string]: Formex.ObjectPrefab})
	if RunService:IsClient() and not game:IsLoaded() then
		game.Loaded:Wait()
	end

	prefabFolder = ReplicatedStorage:FindFirstChild(PREFAB_FOLDER_NAME)
	workspacePrefabFolder = resolveWorkspacePrefabFolder()

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

	local function mergeFromRoot(root: Instance?, skipFolderName: string?)
		if not root then return end
		local discovered = {} :: {Formex.ObjectPrefab}
		collectPrefabModels(root, "", discovered, skipFolderName)
		for _, prefab in ipairs(discovered) do
			if not byName[prefab.PrefabName] then
				table.insert(list, prefab)
				byName[prefab.PrefabName] = prefab
			end
		end
	end

	mergeFromRoot(prefabFolder, nil)
	mergeFromRoot(workspacePrefabFolder, WORKSPACE_STAGE_FOLDER_NAME)

	Formex.Furniture = list

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
	if not prefabName or prefabName == "" then return nil end
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

	local prefabChild = prefabModel:FindFirstChild("Prefab")
	local subtractModel = prefabModel:FindFirstChild("Subtract")
	if prefabChild and prefabChild:IsA("Model") then
		ensureDeterministicPrimaryPart(prefabChild)
		ensureDeterministicPrimaryPart(subtractModel and subtractModel:IsA("Model") and subtractModel or nil)
		if prefab.ObjectMount == Formex.MountType.Door or prefab.ObjectMount == Formex.MountType.Window then
			return prefabChild, subtractModel and subtractModel:IsA("Model") and subtractModel or nil
		end
		return prefabChild, nil
	end

	if prefab.ObjectMount == Formex.MountType.Door or prefab.ObjectMount == Formex.MountType.Window then
		local objectModel = prefabModel:FindFirstChild("Model")
		if objectModel and objectModel:IsA("Model") then
			ensureDeterministicPrimaryPart(objectModel)
			ensureDeterministicPrimaryPart(subtractModel and subtractModel:IsA("Model") and subtractModel or nil)
			return objectModel, subtractModel and subtractModel:IsA("Model") and subtractModel or nil
		end
	end

	ensureDeterministicPrimaryPart(prefabModel)
	ensureDeterministicPrimaryPart(subtractModel and subtractModel:IsA("Model") and subtractModel or nil)
	return prefabModel, nil
end

function Formex.Objects.ResolvePrefabModels(prefab: Formex.ObjectPrefab): (Model?, Model?)
	return resolvePrefabModels(prefab)
end

local function resolveObjectSide(side: Formex.ObjectSide?): Formex.ObjectSide
	if side == Formex.ObjectSide.Back then
		return Formex.ObjectSide.Back
	end
	return Formex.ObjectSide.Front
end

local function getModelBoundsInfo(model: Model?): (CFrame, Vector3)
	if not model then
		return CFrame.new(), Vector3.new(1, 1, 1)
	end
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local pivot = model:GetPivot()
	local offset = pivot:ToObjectSpace(boundsCFrame)
	return offset, boundsSize
end

local function getPrefabBoundsInfo(prefab: Formex.ObjectPrefab?, objectModel: Model?): (CFrame, Vector3)
	local fallbackSize = prefab and prefab.Size or Vector3.new(1, 1, 1)
	if prefab then
		local template = resolvePrefabModels(prefab)
		if template then
			return getModelBoundsInfo(template)
		end
	end
	if objectModel then
		return getModelBoundsInfo(objectModel)
	end
	return CFrame.new(), fallbackSize
end

local function getFloorSurfaceHeights(floor: Formex.FloorData): (number, number)
	local levelIndex = floor.LevelIndex or 1
	local levelTop = Formex.Plot.GetLevelOffset(levelIndex)
	local raiseHeight = floor.RaiseHeight or 0
	local maxRaise = Formex.LevelHeight - Formex.InterfloorHeight
	if maxRaise < 0 then
		maxRaise = 0
	end
	local snappedRaise = math.round(raiseHeight / Formex.GridSize) * Formex.GridSize
	local clampedRaise = math.clamp(snappedRaise, 0, maxRaise)
	if clampedRaise > 0 then
		return levelTop + clampedRaise, levelTop
	end
	local thickness = levelIndex == 1 and Formex.FoundationHeight or Formex.InterfloorHeight
	return levelTop, levelTop - thickness
end

local function isPointOnEdge(point: Vector2, a: Vector2, b: Vector2): boolean
	return Formex.Plot.IsPointOnSegment(point, a, b)
end

local function isPointInsidePolygon(point: Vector2, polygon: {Vector2int16}): boolean
	local count = #polygon
	if count < 3 then return false end
	local inside = false
	local j = count
	for i = 1, count do
		local pi = polygon[i]
		local pj = polygon[j]
		local a = Vector2.new(pi.X, pi.Y)
		local b = Vector2.new(pj.X, pj.Y)
		if isPointOnEdge(point, a, b) then return true end
		local intersects = (pi.Y > point.Y) ~= (pj.Y > point.Y)
			and (point.X < (pj.X - pi.X) * (point.Y - pi.Y) / (pj.Y - pi.Y) + pi.X)
		if intersects then
			inside = not inside
		end
		j = i
	end

	return inside
end

local function getRotationOffset(model: Model?): CFrame
	if not model then
		return CFrame.new()
	end
	local boundsCFrame = model:GetBoundingBox()
	return boundsCFrame - boundsCFrame.Position
end

function Formex.Objects.GetPrefabRotationOffset(prefab: Formex.ObjectPrefab?): CFrame
	if not prefab then
		return CFrame.new()
	end
	local objectModel = resolvePrefabModels(prefab)
	return getRotationOffset(objectModel)
end

local function getPrefabRotationInfo(prefab: Formex.ObjectPrefab?, objectModel: Model?): CFrame
	if prefab then
		local template = resolvePrefabModels(prefab)
		if template then
			return getRotationOffset(template)
		end
	end
	if objectModel then
		return getRotationOffset(objectModel)
	end
	return CFrame.new()
end

function Formex.Objects.ResolveObjectSide(side: Formex.ObjectSide?): Formex.ObjectSide
	return resolveObjectSide(side)
end

function Formex.Objects.GetFloorSurfaceY(floor: Formex.FloorData): number
	local topY = getFloorSurfaceHeights(floor)
	return topY
end

function Formex.Objects.GetCeilingSurfaceY(floor: Formex.FloorData): number
	local _, bottomY = getFloorSurfaceHeights(floor)
	return bottomY
end

function Formex.Objects.GetFloorAtPosition(plotData: Formex.PlotData?, levelIndex: number, position: Vector2): Formex.FloorData?
	if not plotData or not plotData.Levels then return nil end
	local levelData = plotData.Levels[levelIndex]
	if not levelData or not levelData.Floors then return nil end
	local bestFloor = nil
	local bestHeight = -math.huge
	for _, floor in pairs(levelData.Floors) do
		local points = floor.Points
		if points and isPointInsidePolygon(position, points) then
			local topY = Formex.Objects.GetFloorSurfaceY(floor)
			if topY > bestHeight then
				bestHeight = topY
				bestFloor = floor
			end
		end
	end

	return bestFloor
end

function Formex.Objects.GetPrefabBounds(prefab: Formex.ObjectPrefab?, objectModel: Model?): (CFrame, Vector3)
	return getPrefabBoundsInfo(prefab, objectModel)
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
		if color then return color end
	end
	return fallback
end

function Formex.Objects.ApplyDesign(objectData: Formex.ObjectData, objectModel: Model?)
	if not objectData or not objectModel then return end
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
	if grid <= 0 then return value end
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

local function getDefaultFloorSurfaceHeights(levelIndex: number): (number, number)
	local levelTop = Formex.Plot.GetLevelOffset(levelIndex)
	local thickness = levelIndex == 1 and Formex.FoundationHeight or Formex.InterfloorHeight
	return levelTop, levelTop - thickness
end

local function getWallSideNormal(right: Vector3, side: Formex.ObjectSide): Vector3
	if side == Formex.ObjectSide.Back then return right end
	return -right
end

local function getWallYawFromNormal(normal: Vector3): number
	return math.atan2(normal.X, normal.Z)
end

local function getHalfDepthAlongNormal(boundsSize: Vector3, orientation: CFrame, normal: Vector3): number
	local halfX = boundsSize.X / 2
	local halfZ = boundsSize.Z / 2
	local right = orientation.RightVector
	local back = -orientation.LookVector
	return math.abs(normal:Dot(right)) * halfX + math.abs(normal:Dot(back)) * halfZ
end

local function getBoundsPivotCFrame(boundsOffset: CFrame, center: Vector3, yawRadians: number, baseRotation: CFrame): CFrame
	local yawCFrame = CFrame.Angles(0, yawRadians, 0)
	return CFrame.new(center) * yawCFrame * baseRotation * boundsOffset:Inverse()
end

function Formex.Objects.PlaceInWall(
	plotPart: BasePart,
	boundsOffset: CFrame,
	boundsSize: Vector3,
	baseRotation: CFrame,
	floorHeight: number,
	wall: Formex.WallData,
	side: Formex.ObjectSide,
	elevation: number,
	distance: number
): CFrame
	local dir, right, startLocal = Formex.Objects.GetWallBasis(wall)
	local normal = getWallSideNormal(right, side)
	local centerY = floorHeight + elevation + (boundsSize.Y / 2)
	local base = Vector3.new(startLocal.X, centerY, startLocal.Z) + dir * distance
	local center = base + normal * 0
	local yaw = getWallYawFromNormal(normal)
	local localPivot = getBoundsPivotCFrame(boundsOffset, center, yaw, baseRotation)
	return plotPart.CFrame * localPivot
end

function Formex.Objects.PlaceOnWall(
	plotPart: BasePart,
	boundsOffset: CFrame,
	boundsSize: Vector3,
	baseRotation: CFrame,
	floorHeight: number,
	wall: Formex.WallData,
	side: Formex.ObjectSide,
	elevation: number,
	distance: number
): CFrame
	local dir, right, startLocal = Formex.Objects.GetWallBasis(wall)
	local normal = getWallSideNormal(right, side)
	local centerY = floorHeight + elevation + (boundsSize.Y / 2)
	local base = Vector3.new(startLocal.X, centerY, startLocal.Z) + dir * distance
	local yaw = getWallYawFromNormal(normal)
	local orientation = CFrame.Angles(0, yaw, 0) * baseRotation
	local normalOffset = (Formex.WallThickness / 2) + getHalfDepthAlongNormal(boundsSize, orientation, normal)
	local center = base + normal * normalOffset
	local localPivot = getBoundsPivotCFrame(boundsOffset, center, yaw, baseRotation)
	return plotPart.CFrame * localPivot
end

function Formex.Objects.PlaceOnFloor(
	plotPart: BasePart,
	boundsOffset: CFrame,
	boundsSize: Vector3,
	baseRotation: CFrame,
	floorHeight: number,
	positionX: number,
	positionZ: number,
	rotationY: number
): CFrame
	local centerY = floorHeight + (boundsSize.Y / 2)
	local center = Vector3.new(positionX, centerY, positionZ)
	local localPivot = getBoundsPivotCFrame(boundsOffset, center, math.rad(rotationY), baseRotation)
	return plotPart.CFrame * localPivot
end

function Formex.Objects.PlaceOnCeiling(
	plotPart: BasePart,
	boundsOffset: CFrame,
	boundsSize: Vector3,
	baseRotation: CFrame,
	ceilingHeight: number,
	positionX: number,
	positionZ: number,
	rotationY: number
): CFrame
	local centerY = ceilingHeight - (boundsSize.Y / 2)
	local center = Vector3.new(positionX, centerY, positionZ)
	local localPivot = getBoundsPivotCFrame(boundsOffset, center, math.rad(rotationY), baseRotation)
	return plotPart.CFrame * localPivot
end

function Formex.Objects.PlaceOnSurface(
	plotPart: BasePart,
	boundsOffset: CFrame,
	_boundsSize: Vector3,
	baseRotation: CFrame,
	position: Vector3,
	rotationY: number
): CFrame
	local center = position
	local localPivot = getBoundsPivotCFrame(boundsOffset, center, math.rad(rotationY), baseRotation)
	return plotPart.CFrame * localPivot
end

local function getFloorAndCeilingHeights(
	plotData: Formex.PlotData?,
	levelIndex: number,
	position: Vector2
): (number, number, Formex.FloorData?)
	local fallbackTop, fallbackBottom = getDefaultFloorSurfaceHeights(levelIndex)
	if not plotData then
		return fallbackTop, fallbackBottom, nil
	end
	local floor = Formex.Objects.GetFloorAtPosition(plotData, levelIndex, position)
	if not floor then
		return fallbackTop, fallbackBottom, nil
	end
	return Formex.Objects.GetFloorSurfaceY(floor), Formex.Objects.GetCeilingSurfaceY(floor), floor
end

function Formex.Objects.GetWallCFrame(
	plotPart: BasePart,
	wall: Formex.WallData,
	localPosition: Vector3,
	rotation: Vector3,
	rotationOffset: CFrame?
): CFrame
	local dir, right, startLocal, _ = Formex.Objects.GetWallBasis(wall)
	local levelOffset = Formex.Plot.GetLevelOffset(wall.Level or 1)
	local base = Vector3.new(startLocal.X, levelOffset, startLocal.Z)
	local localPos = base + (dir * localPosition.X) + Vector3.new(0, localPosition.Y, 0) + (right * localPosition.Z)
	local yaw = math.atan2(right.X, right.Z)
	local radians = Vector3.new(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
	local rotationCFrame = CFrame.Angles(radians.X, radians.Y, radians.Z)
	if rotationOffset then
		rotationCFrame = rotationCFrame * rotationOffset
	end
	local localCFrame = CFrame.new(localPos) * CFrame.Angles(0, yaw, 0) * rotationCFrame
	return plotPart.CFrame * localCFrame
end

function Formex.Objects.GetWorldCFrame(
	plotPart: BasePart,
	position: Vector3,
	rotation: Vector3,
	rotationOffset: CFrame?
): CFrame
	local radians = Vector3.new(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
	local rotationCFrame = CFrame.Angles(radians.X, radians.Y, radians.Z)
	if rotationOffset then
		rotationCFrame = rotationCFrame * rotationOffset
	end
	local localCFrame = CFrame.new(position) * rotationCFrame
	return plotPart.CFrame * localCFrame
end

function Formex.Objects.GetObjectCFrame(
	objectData: Formex.ObjectData,
	prefab: Formex.ObjectPrefab,
	plotPart: BasePart,
	plotData: Formex.PlotData?
): CFrame?
	if not objectData or not prefab or not plotPart then return nil end
	local position = objectData.Position or Vector3.new(0, 0, 0)
	local rotation = objectData.Rotation or Vector3.new(0, 0, 0)
	local mount = prefab.ObjectMount or Formex.MountType.Floor
	local side = resolveObjectSide(objectData.Side)
	local boundsOffset, boundsSize = getPrefabBoundsInfo(prefab, objectData.ObjectModel)
	local baseRotation = getPrefabRotationInfo(prefab, objectData.ObjectModel)

	if mount == Formex.MountType.Wall
		or mount == Formex.MountType.Door
		or mount == Formex.MountType.Window then
		if not objectData.WallId then return nil end
		local wallData = nil
		local levelIndex = objectData.Level or 1
		if plotData and plotData.Levels and plotData.Levels[levelIndex] then
			wallData = plotData.Levels[levelIndex].Walls[objectData.WallId]
		end
		if not wallData then return nil end
		local dir, _, startLocal = Formex.Objects.GetWallBasis(wallData)
		local anchor2 = Vector2.new(startLocal.X + dir.X * position.X, startLocal.Z + dir.Z * position.X)
		local floorHeight = getFloorAndCeilingHeights(plotData, wallData.Level or levelIndex, anchor2)
		local elevation = position.Y
		if mount == Formex.MountType.Door then
			elevation = 0
		end
		if mount == Formex.MountType.Wall then
			return Formex.Objects.PlaceOnWall(
				plotPart,
				boundsOffset,
				boundsSize,
				baseRotation,
				floorHeight,
				wallData,
				side,
				elevation,
				position.X
			)
		end
		return Formex.Objects.PlaceInWall(
			plotPart,
			boundsOffset,
			boundsSize,
			baseRotation,
			floorHeight,
			wallData,
			side,
			elevation,
			position.X
		)
	end

	local rotationY = rotation.Y
	if mount == Formex.MountType.Floor then
		local levelIndex = objectData.Level or 1
		local floorHeight = getFloorAndCeilingHeights(plotData, levelIndex, Vector2.new(position.X, position.Z))
		return Formex.Objects.PlaceOnFloor(
			plotPart,
			boundsOffset,
			boundsSize,
			baseRotation,
			floorHeight,
			position.X,
			position.Z,
			rotationY
		)
	elseif mount == Formex.MountType.Ceiling then
		local levelIndex = objectData.Level or 1
		local _, ceilingHeight = getFloorAndCeilingHeights(plotData, levelIndex, Vector2.new(position.X, position.Z))
		return Formex.Objects.PlaceOnCeiling(
			plotPart,
			boundsOffset,
			boundsSize,
			baseRotation,
			ceilingHeight,
			position.X,
			position.Z,
			rotationY
		)
	end

	return Formex.Objects.PlaceOnSurface(
		plotPart,
		boundsOffset,
		boundsSize,
		baseRotation,
		position,
		rotationY
	)
end

local function shouldCarve(prefab: Formex.ObjectPrefab?): boolean
	return prefab.ObjectMount == Formex.MountType.Door or prefab.ObjectMount == Formex.MountType.Window
end

function Formex.Objects.CarveWallObjects(plotData: Formex.PlotData, wallData: Formex.WallData, plotPart: BasePart?)
	local levelData = plotData.Levels and plotData.Levels[wallData.Level or 1]
	local subtractParts = {}

	for _, objectData in pairs(levelData.Objects) do
		if objectData.WallId == wallData.WallId then
			local prefab = objectData.Prefab
			if shouldCarve(prefab) then
				local subtractModel = objectData.SubtractModel
				if subtractModel then
					for _, child in ipairs(subtractModel:GetDescendants()) do
						if child:IsA("BasePart") then
							table.insert(subtractParts, child)
						end
					end
				else
					warn("No subtract model found for " .. prefab.PrefabName .. " on object " .. tostring(objectData.ObjectId))
				end
			end
		end
	end

	local wallModel = wallData.Part
	if not wallModel then 
		error("Wall model not found for wall ID: " .. tostring(wallData.WallId))
	end

	local hasCarvedParts = wallModel:FindFirstChildWhichIsA("PartOperation") and true or false

	if #subtractParts > 0 or hasCarvedParts then
		wallModel:ClearAllChildren()
		Formex.Walls.Edit(wallData, plotPart)
	end

	if #subtractParts == 0 then return end
	
	local children = wallModel:GetChildren() :: any
	
	print("Subtract parts for wall", wallData.WallId, ":", subtractParts, children)

	for _, wallPart in children :: {Part} do
		local carved = wallPart:SubtractAsync(subtractParts) :: PartOperation
		if not carved then
			warn("Failed to carve wall", wallData.WallId, "part:", wallPart.Name)
			continue
		end
		carved.Name = wallPart.Name
		carved.Anchored = true
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

function Formex.Objects.CreateObject(parent: Instance, objectData: Formex.ObjectData, plotPart: BasePart?, plotData: Formex.PlotData?): Model?
	if not objectData or not parent then return nil end
	local prefab = objectData.Prefab
	if not prefab and objectData.PrefabName then
		prefab = Formex.Objects.GetPrefab(objectData.PrefabName)
	end
	if not prefab then return nil end
	local objectModelTemplate, subtractTemplate = resolvePrefabModels(prefab)
	if not objectModelTemplate then return nil end
	local container = Instance.new("Model")
	container.Name = tostring(objectData.ObjectId)
	container.Parent = parent
	objectData.Part = container
	objectData.Prefab = prefab
	objectData.PrefabName = prefab.PrefabName
	objectData.Side = resolveObjectSide(objectData.Side)
	objectData.IsPortal = prefab.ObjectMount == Formex.MountType.Door

	local objectModel = objectModelTemplate:Clone()
	objectModel.Name = "Object"
	objectModel.Parent = container
	applyObjectPartsSetup(objectModel, Formex.CollisionGroup.Object, false)

	local subtractModel: Model? = nil
	if subtractTemplate and subtractTemplate:IsA("Model") then
		subtractModel = subtractTemplate:Clone()
		subtractModel.Name = "Subtract"
		subtractModel.Parent = container
		applyObjectPartsSetup(subtractModel, Formex.CollisionGroup.Object, true)
	end

	if objectModel.PrimaryPart then
		container.PrimaryPart = objectModel.PrimaryPart
	else
		container.PrimaryPart = nil
	end
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
	if not container or not plotPart then return end
	local prefab = objectData.Prefab
	if not prefab and objectData.PrefabName then
		prefab = Formex.Objects.GetPrefab(objectData.PrefabName)
		objectData.Prefab = prefab
	end

	if prefab then
		objectData.IsPortal = prefab.ObjectMount == Formex.MountType.Door
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
	if objectModel and objectModel.PrimaryPart then
		container.PrimaryPart = objectModel.PrimaryPart
	else
		container.PrimaryPart = nil
	end

	if objectModel then
		objectData.DesignParts = objectData.DesignParts or Formex.Objects.BuildDesignParts(objectModel)
		Formex.Objects.ApplyDesign(objectData, objectModel)
	end

	local rotation = objectData.Rotation or Vector3.new(0, 0, 0)
	local position = objectData.Position or Vector3.new(0, 0, 0)
	objectData.Side = resolveObjectSide(objectData.Side)
	if prefab and (prefab.ObjectMount == Formex.MountType.Floor or prefab.ObjectMount == Formex.MountType.Ceiling) then
		local _, boundsSize = getPrefabBoundsInfo(prefab, objectData.ObjectModel)
		local levelIndex = objectData.Level or 1
		local floorHeight, ceilingHeight = getFloorAndCeilingHeights(plotData, levelIndex, Vector2.new(position.X, position.Z))
		if prefab.ObjectMount == Formex.MountType.Floor then
			position = Vector3.new(position.X, floorHeight + (boundsSize.Y / 2), position.Z)
		else
			position = Vector3.new(position.X, ceilingHeight - (boundsSize.Y / 2), position.Z)
		end
		objectData.Position = position
	end

	local targetCFrame: CFrame? = nil
	if prefab then
		targetCFrame = Formex.Objects.GetObjectCFrame(objectData, prefab, plotPart, plotData)
	end

	if targetCFrame then
		container:PivotTo(targetCFrame)
	end

	container:SetAttribute("Position", position)
	container:SetAttribute("Rotation", rotation)
	container:SetAttribute("Side", objectData.Side)
	container:SetAttribute("WallId", objectData.WallId)
	container:SetAttribute("PrefabName", objectData.PrefabName or (prefab and prefab.PrefabName) or "")
	container:SetAttribute("Design", Formex.Objects.EncodeDesign(objectData.Design, objectData.DesignColors))
	container:SetAttribute("IsPortal", objectData.IsPortal == true)
end

Formex.CreateObject = Formex.Objects.CreateObject
Formex.EditObject = Formex.Objects.EditObject

return Formex.Objects
