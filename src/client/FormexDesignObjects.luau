--!strict
--[[
FormexDesignObjects
Handles object design interactions (placement, handles, paint/dropper).
Exports:
- Init(): ()
- GetSelectedObjectData(): Formex.ObjectData?
- ApplySelectedDesign(design, colors): boolean
- ApplyPaintToTarget(input): boolean
- CopyPaintFromTarget(input): boolean
- HandleUpdate(input): ()
- HandlePrimaryClick(input): ()
- HandlePrimaryRelease(input): ()
- CancelAction(): ()
]]
local Context = require(script.Parent:WaitForChild("FormexDesignContext"))

local Objects = {}

type ObjectHandleType = "Move" | "Rotate" | "Delete"

local FormexClient: any
local Formex: any
local Handles: any
local OverlayFolder: Folder
local Enums: any
local Constants: any

local getActionType: () -> string
local setActionType: (string) -> ()
local getDesignMode: () -> string
local getSelectionType: () -> string
local getSelectionData: () -> any?
local getSelectionSnapshot: () -> any?
local getCurrentLevel: () -> number
local getLastInputInfo: () -> any?
local getObjectPaintSettings: () -> Context.ObjectPaintSettings
local getObjectPrefabName: () -> string?
local updateDesignState: (any) -> ()
local notifyDesignModeChange: () -> ()
local clearSelection: () -> ()
local select: (any) -> boolean
local selectPlotModelByIdAsync: (any, string, number, number, number?) -> ()

local ghostModel: Model? = nil
local ghostHighlight: Highlight? = nil
local ghostPrefabName: string? = nil
local ghostValid = false
local ghostData: Formex.ObjectData? = nil

local handleMove: BasePart? = nil
local handleRotate: BasePart? = nil
local handleDelete: BasePart? = nil
local moveOriginal: Formex.ObjectData? = nil
local movePreview: Formex.ObjectData? = nil
local previewHighlight: Highlight? = nil
local previewValid = true
local moveSnapshot: {[number]: Formex.ObjectData}? = nil
local moveSnapshotMoved: {[number]: boolean}? = nil

local lastHandleObjectId: number? = nil
local SURFACE_UP_DOT = 0.65
local ROTATE_STEP_DEGREES = 22.5

local function snapRotationDegrees(value: number): number
	return math.round(value / ROTATE_STEP_DEGREES) * ROTATE_STEP_DEGREES
end

local function getResultObjectId(result: any): number | string?
	local resultType = type(result)
	if resultType == "number" or resultType == "string" then return result end
	if resultType == "table" then
		if result.ObjectId then
			return result.ObjectId
		end
		if #result >= 1 then
			return result[1]
		end
	end
	return nil
end

local function setHandlesBusy(active: boolean)
	if Handles and Handles.SetBusy then
		Handles.SetBusy(active)
	end
end

local function runBuildTransaction(changes: {Formex.BuildChange}, selection: Formex.SelectionSnapshot?): {Formex.BuildChangeResult}?
	setHandlesBusy(true)
	local results = FormexClient.BuildTransaction(changes, selection)
	setHandlesBusy(false)
	return results
end

local function buildObject(objectData: any, action: any, selection: Formex.SelectionSnapshot?): any
	local results = runBuildTransaction({
		{
			PartType = Formex.PartType.Object,
			Action = action,
			Data = objectData,
		},
	}, selection)
	if not results then return nil end
	local changeResult = results[1]
	return changeResult and changeResult.Result or nil
end

local function setGhostHighlight(valid: boolean)
	ghostValid = valid
	if ghostHighlight then
		ghostHighlight.OutlineColor = valid and Constants.GhostValidColor or Constants.GhostInvalidColor
		ghostHighlight.FillColor = ghostHighlight.OutlineColor
	end
end

local function setPreviewHighlight(valid: boolean)
	previewValid = valid
	if previewHighlight then
		previewHighlight.OutlineColor = valid and Constants.GhostValidColor or Constants.GhostInvalidColor
	end
end

local function applyGhostAppearance(model: Model)
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			child.Anchored = true
			child.CanCollide = false
			child.CanTouch = false
			child.CanQuery = false
			child.CastShadow = false
			child.Transparency = 0.5
		end
	end
end

local function syncPrimaryPartFromTemplate(model: Model, template: Model)
	if template.PrimaryPart then
		local name = template.PrimaryPart.Name
		local found = model:FindFirstChild(name, true)
		if found and found:IsA("BasePart") then
			model.PrimaryPart = found
			return
		end
	end
	model.PrimaryPart = nil
end


local function ensureGhost(prefab: Formex.ObjectPrefab)
	if ghostPrefabName ~= prefab.PrefabName then
		if ghostModel then
			ghostModel:Destroy()
		end
		if ghostHighlight then
			ghostHighlight:Destroy()
		end
		ghostModel = nil
		ghostHighlight = nil
		ghostData = nil
	end

	if ghostModel then return end
	ghostPrefabName = prefab.PrefabName

	local sourceModel, _ = Formex.Objects.ResolvePrefabModels(prefab)
	if not sourceModel and prefab.PrefabName then
		local resolved = Formex.Objects.GetPrefab(prefab.PrefabName)
		if resolved then
			sourceModel = (Formex.Objects.ResolvePrefabModels(resolved))
		end
	end
	if not sourceModel then return end
	ghostModel = sourceModel:Clone()
	ghostModel.Name = "ObjectGhost"
	ghostModel.Parent = OverlayFolder
	syncPrimaryPartFromTemplate(ghostModel, sourceModel)
	applyGhostAppearance(ghostModel)

	ghostHighlight = Instance.new("Highlight")
	ghostHighlight.FillTransparency = 1
	ghostHighlight.OutlineTransparency = 0
	ghostHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	ghostHighlight.Adornee = ghostModel
	ghostHighlight.Parent = ghostModel
	setGhostHighlight(true)
end

local function clearGhost()
	if ghostModel then
		ghostModel:Destroy()
		ghostModel = nil
	end
	if ghostHighlight then
		ghostHighlight:Destroy()
		ghostHighlight = nil
	end
	ghostPrefabName = nil
	ghostData = nil
	ghostValid = false
end

local function getLevelFolder(plotInfo: any, levelIndex: number): BasePart?
	local plotPart = plotInfo and plotInfo.PlotPart
	if not plotPart then return nil end
	local levelPart = plotPart:FindFirstChild(tostring(levelIndex))
	if levelPart and levelPart:IsA("BasePart") then return levelPart end
	return nil
end

local function getLevelFolderChild(plotInfo: any, levelIndex: number, name: string): Folder?
	local levelPart = getLevelFolder(plotInfo, levelIndex)
	if not levelPart then return nil end
	local folder = levelPart:FindFirstChild(name)
	if folder and folder:IsA("Folder") then return folder end
	return nil
end

local function snapToGrid(value: number): number
	local grid = Formex.ObjectGridSize
	if grid <= 0 then return value end
	return math.round(value / grid) * grid
end

local function getFloorSurfaceHeightsFromData(floorData: Formex.FloorData): (number, number)
	local levelIndex = floorData.LevelIndex
	local raiseHeight = floorData.RaiseHeight or 0
	local levelTop = Formex.LevelHeight * (levelIndex - 1)
	if raiseHeight > 0 then
		return levelTop + raiseHeight, levelTop
	end
	local thickness = levelIndex == 1 and Formex.FoundationHeight or Formex.InterfloorHeight
	return levelTop, levelTop - thickness
end

type Obb2D = {
	Center: Vector2,
	CenterY: number,
	HalfX: number,
	HalfY: number,
	HalfZ: number,
	Cos: number,
	Sin: number,
}

local function buildObb(localCFrame: CFrame, size: Vector3): Obb2D
	local _, yaw, _ = localCFrame:ToOrientation()
	local center = localCFrame.Position
	return {
		Center = Vector2.new(center.X, center.Z),
		CenterY = center.Y,
		HalfX = size.X / 2,
		HalfY = size.Y / 2,
		HalfZ = size.Z / 2,
		Cos = math.cos(yaw),
		Sin = math.sin(yaw),
	}
end

local function getObbAxis(cosYaw: number, sinYaw: number, index: number): Vector2
	if index == 1 then
		return Vector2.new(cosYaw, sinYaw)
	end
	return Vector2.new(-sinYaw, cosYaw)
end

local function getObbRadius(obb: Obb2D, axis: Vector2): number
	local axisX = obb.Cos
	local axisZ = obb.Sin
	local perpX = -obb.Sin
	local perpZ = obb.Cos
	local projectionX = math.abs(axis.X * axisX + axis.Y * axisZ)
	local projectionZ = math.abs(axis.X * perpX + axis.Y * perpZ)
	return (obb.HalfX * projectionX) + (obb.HalfZ * projectionZ)
end

local function obbOverlap2D(a: Obb2D, b: Obb2D): boolean
	if math.abs(a.CenterY - b.CenterY) >= (a.HalfY + b.HalfY - Constants.Epsilon) then return false end
	local delta = b.Center - a.Center
	for _, axis in ipairs({
		getObbAxis(a.Cos, a.Sin, 1),
		getObbAxis(a.Cos, a.Sin, 2),
		getObbAxis(b.Cos, b.Sin, 1),
		getObbAxis(b.Cos, b.Sin, 2),
	}) do
		local distance = math.abs(delta:Dot(axis))
		local radius = getObbRadius(a, axis) + getObbRadius(b, axis)
		if distance > radius - Constants.Epsilon then return false end
	end

	return true
end

local function getObjectWorldCFrame(plotInfo: any, objectData: Formex.ObjectData, prefab: Formex.ObjectPrefab): CFrame?
	local plotPart = plotInfo and plotInfo.PlotPart
	if not plotPart then return nil end
	if Formex.Objects.GetObjectCFrame then
		return Formex.Objects.GetObjectCFrame(objectData, prefab, plotPart, plotInfo.PlotData)
	end
	return nil
end

local function getObjectLocalCFrame(
	plotInfo: any,
	objectData: Formex.ObjectData,
	prefab: Formex.ObjectPrefab,
	_wallOverride: Formex.WallData?
): CFrame?
	local plotPart = plotInfo and plotInfo.PlotPart
	if not plotPart then return nil end
	local worldCFrame = getObjectWorldCFrame(plotInfo, objectData, prefab)
	if not worldCFrame then return nil end
	return plotPart.CFrame:ToObjectSpace(worldCFrame)
end

local function getObjectBoundsSize(prefab: Formex.ObjectPrefab, objectData: Formex.ObjectData?): Vector3
	local _, boundsSize = Formex.Objects.GetPrefabBounds(prefab, objectData and objectData.ObjectModel or nil)
	return boundsSize
end

local function getLevelObjects(
	plotInfo: any,
	levelIndex: number,
	snapshot: {[number]: Formex.ObjectData}?
): {[number]: Formex.ObjectData}?
	if snapshot then return snapshot end
	local plotData = plotInfo and plotInfo.PlotData
	local levelData = plotData and plotData.Levels and plotData.Levels[levelIndex]
	return levelData and levelData.Objects or nil
end

local function isPlacementClear(
	plotInfo: any,
	objectData: Formex.ObjectData,
	prefab: Formex.ObjectPrefab,
	ignoreObjectId: number?,
	wallOverride: Formex.WallData?,
	snapshot: {[number]: Formex.ObjectData}?,
	movedIds: {[number]: boolean}?
): boolean
	if not plotInfo or not plotInfo.PlotData then return true end
	local localCFrame = getObjectLocalCFrame(plotInfo, objectData, prefab, wallOverride)
	if not localCFrame then return true end
	local levelIndex = objectData.Level or getCurrentLevel()
	local levelObjects = getLevelObjects(plotInfo, levelIndex, snapshot)
	if not levelObjects then return true end
	local size = getObjectBoundsSize(prefab, objectData)
	local sourceObb = buildObb(localCFrame, size)
	for _, other in pairs(levelObjects) do
		if ignoreObjectId and other.ObjectId == ignoreObjectId then
			continue
		end
		if objectData.ObjectId ~= 0 and other.ObjectId == objectData.ObjectId then
			continue
		end
		if movedIds and other.ObjectId and movedIds[other.ObjectId] then
			continue
		end
		local otherPrefab = other.Prefab
		if not otherPrefab and other.PrefabName then
			otherPrefab = Formex.Objects.GetPrefab(other.PrefabName)
			other.Prefab = otherPrefab
		end
		if otherPrefab then
			local otherCFrame = getObjectLocalCFrame(plotInfo, other, otherPrefab, nil)
			if otherCFrame then
				local otherSize = getObjectBoundsSize(otherPrefab, other)
				local otherObb = buildObb(otherCFrame, otherSize)
				if obbOverlap2D(sourceObb, otherObb) then return false end
			end
		end
	end
	return true
end

local function buildObjectSnapshot(plotInfo: any, levelIndex: number): {[number]: Formex.ObjectData}
	local snapshot = {} :: {[number]: Formex.ObjectData}
	local plotData = plotInfo and plotInfo.PlotData
	local levelData = plotData and plotData.Levels and plotData.Levels[levelIndex]
	if not levelData or not levelData.Objects then return snapshot end
	for _, objectData in pairs(levelData.Objects) do
		if objectData.ObjectId then
			snapshot[objectData.ObjectId] = {
				ObjectId = objectData.ObjectId,
				Level = objectData.Level,
				Position = objectData.Position,
				Rotation = objectData.Rotation,
				Side = objectData.Side,
				WallId = objectData.WallId,
				PrefabName = objectData.PrefabName,
				Prefab = objectData.Prefab,
				ObjectModel = objectData.ObjectModel,
			} :: Formex.ObjectData
		end
	end

	return snapshot
end

local function clearMoveSnapshot()
	moveSnapshot = nil
	moveSnapshotMoved = nil
end

local function startMoveSnapshot(input: any, objectData: Formex.ObjectData)
	if not input or not input.PlotInfo or not objectData.ObjectId then return end
	local levelIndex = objectData.Level or getCurrentLevel()
	moveSnapshot = buildObjectSnapshot(input.PlotInfo, levelIndex)
	moveSnapshotMoved = { [objectData.ObjectId] = true }
end

local function resolvePrefab(): Formex.ObjectPrefab?
	local prefabName = getObjectPrefabName()
	if prefabName then
		local prefab = Formex.Objects.GetPrefab(prefabName)
		if prefab then return prefab end
	end

	local prefabs = Formex.Objects.GetPrefabs()
	if #prefabs > 0 then
		return prefabs[1]
	end
	return nil
end

local function applyDesignToGhost(prefab: Formex.ObjectPrefab)
	if not ghostModel then return end
	local paintSettings = getObjectPaintSettings()
	ghostData = {
		ObjectId = 0,
		Level = getCurrentLevel(),
		Position = Vector3.new(0, 0, 0),
		Rotation = Vector3.new(0, 0, 0),
		Side = Formex.ObjectSide.Front,
		WallId = nil,
		Design = table.clone(paintSettings.Design),
		DesignColors = table.clone(paintSettings.DesignColors),
		IsPortal = false,
		Prefab = prefab,
		PrefabName = prefab.PrefabName,
		Part = ghostModel,
		ObjectModel = ghostModel,
		DesignParts = Formex.Objects.BuildDesignParts(ghostModel),
	} :: Formex.ObjectData
	Formex.Objects.EnsureDesignDefaults(ghostData, prefab)
	Formex.Objects.ApplyDesign(ghostData, ghostModel)
end

local function getWallPlacement(input: any, prefab: Formex.ObjectPrefab, wallData: Formex.WallData, _rotationOverride: Vector3?): (Formex.ObjectData, boolean)
	local plotPart = input.PlotInfo.PlotPart
	local hitPosition = input.HitPosition
	if not plotPart or not hitPosition then
		return {} :: Formex.ObjectData, false
	end

	local localHit = plotPart.CFrame:PointToObjectSpace(hitPosition)
	local dir, right, startLocal, length = Formex.Objects.GetWallBasis(wallData)
	if length <= Constants.Epsilon then
		return {} :: Formex.ObjectData, false
	end
	local offset = Vector2.new(localHit.X - startLocal.X, localHit.Z - startLocal.Z)
	local dir2 = Vector2.new(dir.X, dir.Z)
	local distance = offset:Dot(dir2)
	local sideValue = offset:Dot(Vector2.new(right.X, right.Z))
	local side = sideValue >= 0 and Formex.ObjectSide.Back or Formex.ObjectSide.Front

	local _, boundsSize = Formex.Objects.GetPrefabBounds(prefab, ghostModel)
	local levelIndex = wallData.Level or getCurrentLevel()
	local levelOffset = Formex.Plot.GetLevelOffset(levelIndex)
	local anchor2 = Vector2.new(startLocal.X + dir.X * distance, startLocal.Z + dir.Z * distance)
	local floorData = Formex.Objects.GetFloorAtPosition(input.PlotInfo.PlotData, levelIndex, anchor2)
	local floorHeight = floorData and Formex.Objects.GetFloorSurfaceY(floorData) or levelOffset
	local wallHeight = wallData.Height or Formex.LevelHeight
	local wallTop = levelOffset + wallHeight

	local positionX = snapToGrid(distance)
	local positionY = snapToGrid(localHit.Y - floorHeight)
	if prefab.ObjectMount == Formex.MountType.Door then
		positionY = 0
	end
	local minX = boundsSize.X / 2
	local maxX = length - (boundsSize.X / 2)
	local insideWidth = positionX >= minX - Constants.Epsilon and positionX <= maxX + Constants.Epsilon
	if prefab.ObjectMount == Formex.MountType.Door then
		positionX = math.clamp(positionX, minX, maxX)
		insideWidth = true
	end

	local bottomY = floorHeight + positionY
	local topY = bottomY + boundsSize.Y
	local insideHeight = positionY >= -Constants.Epsilon and topY <= wallTop + Constants.Epsilon

	local position = Vector3.new(positionX, positionY, 0)
	local valid = insideWidth and insideHeight

	return {
		ObjectId = 0,
		Level = levelIndex,
		Position = position,
		Rotation = Vector3.new(0, 0, 0),
		Side = side,
		WallId = wallData.WallId,
		PrefabName = prefab.PrefabName,
		Prefab = prefab,
	} :: Formex.ObjectData, valid
end

local function getSurfacePlacementWithMount(
	input: any,
	prefab: Formex.ObjectPrefab,
	rotationOverride: Vector3?,
	mountOverride: Formex.ObjectMount?
): (Formex.ObjectData, boolean)
	local plotPart = input.PlotInfo.PlotPart
	local hitPosition = input.HitPosition
	if not plotPart or not hitPosition then
		return {} :: Formex.ObjectData, false
	end
	local localHit = plotPart.CFrame:PointToObjectSpace(hitPosition)
	local normal = input.HitNormal or Vector3.new(0, 1, 0)
	local mount = mountOverride or prefab.ObjectMount
	local levelIndex = input.LevelIndex
	local validSurface = true
	local rotationY = rotationOverride and rotationOverride.Y or 0
	local _, boundsSize = Formex.Objects.GetPrefabBounds(prefab, nil)
	local floorTopY = 0
	local ceilingBottomY = 0

	if mount == Formex.MountType.Floor or mount == Formex.MountType.Ceiling then
		if not input.FloorData or not input.FloorSide then
			return {} :: Formex.ObjectData, false
		end
		levelIndex = input.FloorData.LevelIndex
		floorTopY, ceilingBottomY = getFloorSurfaceHeightsFromData(input.FloorData)
		if mount == Formex.MountType.Floor then
			if input.FloorSide ~= "Floor" or normal.Y < SURFACE_UP_DOT then
				validSurface = false
			end
		else
			if input.FloorSide ~= "Ceiling" or math.abs(normal.Y) < SURFACE_UP_DOT then
				validSurface = false
			end
		end
	elseif mount == Formex.MountType.Surface then
		if normal.Y < SURFACE_UP_DOT then
			validSurface = false
		end
	end

	local positionX = snapToGrid(localHit.X)
	local positionZ = snapToGrid(localHit.Z)
	local positionY = localHit.Y
	if mount == Formex.MountType.Floor then
		positionY = floorTopY + (boundsSize.Y / 2)
	elseif mount == Formex.MountType.Ceiling then
		positionY = ceilingBottomY - (boundsSize.Y / 2)
	elseif mount == Formex.MountType.Surface then
		positionY = localHit.Y + (boundsSize.Y / 2)
	end
	local position = Vector3.new(positionX, positionY, positionZ)
	local rotation = Vector3.new(0, rotationY, 0)
	local valid = validSurface
		and Formex.Plot.IsPointInUnlockedSegments(Vector2.new(position.X, position.Z), input.PlotInfo.SegmentsUnlocked)
	return {
		ObjectId = 0,
		Level = levelIndex,
		Position = position,
		Rotation = rotation,
		Side = Formex.ObjectSide.Front,
		WallId = nil,
		PrefabName = prefab.PrefabName,
		Prefab = prefab,
	} :: Formex.ObjectData, valid
end

local function getSurfacePlacement(input: any, prefab: Formex.ObjectPrefab, rotationOverride: Vector3?): (Formex.ObjectData, boolean)
	return getSurfacePlacementWithMount(input, prefab, rotationOverride, nil)
end

local function getPlacement(
	input: any,
	prefab: Formex.ObjectPrefab,
	rotationOverride: Vector3?,
	wallOverride: Formex.WallData?,
	ignoreObjectId: number?,
	snapshot: {[number]: Formex.ObjectData}?,
	movedIds: {[number]: boolean}?
): (Formex.ObjectData, boolean)
	local objectMount = prefab.ObjectMount
	if objectMount == Formex.MountType.Wall or objectMount == Formex.MountType.Door or objectMount == Formex.MountType.Window then
		local wallData = wallOverride or (input and input.WallData)
		if not wallData then
			return {} :: Formex.ObjectData, false
		end
		local data, valid = getWallPlacement(input, prefab, wallData, rotationOverride)
		if valid then
			valid = isPlacementClear(input.PlotInfo, data, prefab, ignoreObjectId, wallData, snapshot, movedIds)
		end
		return data, valid
	end

	local data, valid = getSurfacePlacement(input, prefab, rotationOverride)
	if valid then
		valid = isPlacementClear(input.PlotInfo, data, prefab, ignoreObjectId, nil, snapshot, movedIds)
	end
	return data, valid
end

local function isObjectTransactionValid(plotInfo: any, objectData: Formex.ObjectData, action: Formex.BuildAction): boolean
	if not plotInfo or not plotInfo.PlotData then return false end
	local validation = Formex.IsTransactionValid(plotInfo.PlotData, {
		{
			PartType = Formex.PartType.Object,
			Action = action,
			Data = objectData,
		},
	})
	return validation ~= nil and validation.IsValid == true
end

local function getSelectedObjectModel(): Model?
	if getSelectionType() ~= Enums.SelectionType.Object then return nil end
	local selectionData = getSelectionData()
	if not selectionData or not selectionData.Part then return nil end
	return selectionData.Part
end

local function cloneObjectData(objectData: Formex.ObjectData): Formex.ObjectData
	local clone = table.clone(objectData)
	clone.Design = objectData.Design and table.clone(objectData.Design) or {}
	clone.DesignColors = objectData.DesignColors and table.clone(objectData.DesignColors) or {}
	return clone
end

function Objects.GetSelectedObjectData(): Formex.ObjectData?
	if getSelectionType() ~= Enums.SelectionType.Object then return nil end
	local selectionData = getSelectionData()
	if not selectionData then return nil end
	return cloneObjectData(selectionData)
end

local function ensurePreviewHighlight(model: Model)
	if previewHighlight and previewHighlight.Parent then return end
	previewHighlight = Instance.new("Highlight")
	previewHighlight.FillTransparency = 1
	previewHighlight.OutlineTransparency = 0
	previewHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	previewHighlight.Adornee = model
	previewHighlight.Parent = model
	setPreviewHighlight(true)
end

local function clearPreviewHighlight()
	if previewHighlight then
		previewHighlight:Destroy()
		previewHighlight = nil
	end
	previewValid = true
end

local function clearHandles()
	Handles.ClearHandleHover()
	Handles.Clear()
	handleMove = nil
	handleRotate = nil
	handleDelete = nil
	lastHandleObjectId = nil
end

local function setHandlesVisible(visible: boolean)
	for _, handle in ipairs({ handleMove, handleRotate, handleDelete }) do
		Handles.SetHandleVisible(handle, visible)
	end
end

local function updateHandlePositions(plotInfo: any, objectData: Formex.ObjectData, prefab: Formex.ObjectPrefab)
	local model = objectData.Part
	if not model then return end
	local boxCFrame, boxSize = model:GetBoundingBox()
	local center = boxCFrame.Position
	local anchorY = center.Y
	if prefab.ObjectMount == Formex.MountType.Floor
		or prefab.ObjectMount == Formex.MountType.Surface
		or prefab.ObjectMount == Formex.MountType.Door then
		anchorY = anchorY - (boxSize.Y / 2)
	elseif prefab.ObjectMount == Formex.MountType.Ceiling then
		anchorY = anchorY + (boxSize.Y / 2)
	end

	local basePosition = Vector3.new(center.X, anchorY, center.Z)
	local offset = math.max(boxSize.X, boxSize.Z) / 2 + Constants.HandleOffset

	if handleMove then
		handleMove.Position = basePosition
	end
	if handleRotate then
		handleRotate.Position = basePosition + Vector3.new(offset, 0, 0)
	end
	if handleDelete then
		handleDelete.Position = basePosition + Vector3.new(-offset, 0, 0)
	end
end

local function onHandleClick(handleType: ObjectHandleType)
	local input = getLastInputInfo()
	local selectedData = Objects.GetSelectedObjectData()
	if not input or not selectedData or not selectedData.Part then return end
	local prefab = selectedData.Prefab
	if not prefab and selectedData.PrefabName then
		prefab = Formex.Objects.GetPrefab(selectedData.PrefabName)
	end
	if not prefab then return end
	if handleType == "Delete" then
		buildObject({
			ObjectId = selectedData.ObjectId,
			Level = selectedData.Level,
			Position = selectedData.Position,
			Rotation = selectedData.Rotation,
			Side = selectedData.Side,
			WallId = selectedData.WallId,
			PrefabName = selectedData.PrefabName,
			Design = selectedData.Design,
			DesignColors = selectedData.DesignColors,
		}, Formex.BuildAction.Delete, getSelectionSnapshot())
		clearSelection()
		return
	end

	if handleType == "Rotate" and (prefab.ObjectMount == Formex.MountType.Wall
		or prefab.ObjectMount == Formex.MountType.Door
		or prefab.ObjectMount == Formex.MountType.Window) then
		local nextSide = selectedData.Side == Formex.ObjectSide.Back
			and Formex.ObjectSide.Front
			or Formex.ObjectSide.Back
		selectedData.Side = nextSide
		buildObject({
			ObjectId = selectedData.ObjectId,
			Level = selectedData.Level,
			Position = selectedData.Position,
			Rotation = selectedData.Rotation,
			Side = selectedData.Side,
			WallId = selectedData.WallId,
			PrefabName = selectedData.PrefabName,
			Design = selectedData.Design,
			DesignColors = selectedData.DesignColors,
		}, Formex.BuildAction.Edit, getSelectionSnapshot())
		return
	end

	moveOriginal = selectedData
	movePreview = table.clone(selectedData)
	startMoveSnapshot(input, moveOriginal)
	setActionType(handleType == "Rotate" and Enums.ActionType.Rotate or Enums.ActionType.Move)
	setHandlesVisible(false)
	ensurePreviewHighlight(selectedData.Part)
end

local function updateObjectHandles(plotInfo: any)
	if getSelectionType() ~= Enums.SelectionType.Object then
		clearHandles()
		clearPreviewHighlight()
		return
	end

	local objectData = Objects.GetSelectedObjectData()
	if not objectData or not plotInfo or not plotInfo.PlotPart then
		clearHandles()
		clearPreviewHighlight()
		return
	end

	local prefab = objectData.Prefab
	if not prefab and objectData.PrefabName then
		prefab = Formex.Objects.GetPrefab(objectData.PrefabName)
	end
	if not prefab then
		clearHandles()
		return
	end

	if objectData.ObjectId ~= lastHandleObjectId then
		clearHandles()
		handleMove = Handles.CreateHandle("ObjectMove", Constants.HandleMoveColor, Formex.Icons.MoveItem, onHandleClick, "Move")
		local rotateIcon = Formex.Icons.RotateItem
		if prefab.ObjectMount == Formex.MountType.Wall
			or prefab.ObjectMount == Formex.MountType.Door
			or prefab.ObjectMount == Formex.MountType.Window then
			rotateIcon = Formex.Icons.DirectionIndicator
		end
		handleRotate = Handles.CreateHandle("ObjectRotate", Constants.HandleFlipColor, rotateIcon, onHandleClick, "Rotate")
		handleDelete = Handles.CreateHandle("ObjectDelete", Constants.HandleDeleteColor, Formex.Icons.DeleteItem, onHandleClick, "Delete")
		lastHandleObjectId = objectData.ObjectId
	end

	updateHandlePositions(plotInfo, objectData, prefab)
	setHandlesVisible(true)
end

function Objects.ApplySelectedDesign(design: {[number]: number}, colors: {[number]: Color3}): boolean
	local selectedData = Objects.GetSelectedObjectData()
	if not selectedData then return false end
	selectedData.Design = table.clone(design)
	selectedData.DesignColors = table.clone(colors)
	buildObject({
		ObjectId = selectedData.ObjectId,
		Level = selectedData.Level,
		Position = selectedData.Position,
		Rotation = selectedData.Rotation,
		Side = selectedData.Side,
		WallId = selectedData.WallId,
		PrefabName = selectedData.PrefabName,
		Design = selectedData.Design,
		DesignColors = selectedData.DesignColors,
	}, Formex.BuildAction.Edit, getSelectionSnapshot())
	return true
end

function Objects.ApplyPaintToTarget(input: any): boolean
	if not input or not input.ObjectData or not input.ObjectDesignIndex then return false end
	local objectData = input.ObjectData
	local designIndex = input.ObjectDesignIndex
	local paintSettings = getObjectPaintSettings()
	local materialId = paintSettings.Design[designIndex]
	local color = paintSettings.DesignColors[designIndex]
	if not materialId and not color then return false end
	local updatedDesign = table.clone(objectData.Design)
	local updatedColors = table.clone(objectData.DesignColors)
	if materialId then
		updatedDesign[designIndex] = materialId
	end
	if color then
		updatedColors[designIndex] = color
	end
	buildObject({
		ObjectId = objectData.ObjectId,
		Level = objectData.Level,
		Position = objectData.Position,
		Rotation = objectData.Rotation,
		Side = objectData.Side,
		WallId = objectData.WallId,
		PrefabName = objectData.PrefabName,
		Design = updatedDesign,
		DesignColors = updatedColors,
	}, Formex.BuildAction.Edit, getSelectionSnapshot())
	return true
end

function Objects.CopyPaintFromTarget(input: any): boolean
	if not input or not input.ObjectData or not input.ObjectDesignIndex then return false end
	local objectData = input.ObjectData
	local designIndex = input.ObjectDesignIndex
	local materialId = objectData.Design[designIndex]
	local color = objectData.DesignColors[designIndex]
	if not materialId and not color then return false end
	updateDesignState({
		Object = {
			DesignIndex = designIndex,
			Material = materialId,
			Color = color,
		},
	})
	return true
end

local function updateGhostPlacement(input: any)
	local prefab = resolvePrefab()
	if not prefab then
		clearGhost()
		return
	end
	ensureGhost(prefab)
	if not ghostModel then return end
	applyDesignToGhost(prefab)

	local data, valid = getPlacement(input, prefab, nil, nil, nil, nil, nil)
	if valid then
		valid = isObjectTransactionValid(input.PlotInfo, data, Formex.BuildAction.Add)
	end
	setGhostHighlight(valid)
	if data.Position and data.Rotation then
		data.ObjectModel = ghostModel
		local cframe = getObjectWorldCFrame(input.PlotInfo, data, prefab)
		if cframe then
			ghostModel:PivotTo(cframe)
		end
	end
	ghostValid = valid
end

local function finalizePlacement(input: any)
	if not ghostValid then return end
	local prefab = resolvePrefab()
	if not prefab then return end
	local data, valid = getPlacement(input, prefab, nil, nil, nil, nil, nil)
	if valid then
		valid = isObjectTransactionValid(input.PlotInfo, data, Formex.BuildAction.Add)
	end
	if not valid then
		setGhostHighlight(false)
		return
	end

	local paintSettings = getObjectPaintSettings()
	local design = table.clone(paintSettings.Design)
	local colors = table.clone(paintSettings.DesignColors)
	local objectEntry: Formex.ObjectData = {
		ObjectId = 0,
		Level = data.Level,
		Position = data.Position,
		Rotation = data.Rotation,
		Side = data.Side,
		WallId = data.WallId,
		PrefabName = prefab.PrefabName,
		Design = design,
		DesignColors = colors,
	}
	Formex.Objects.EnsureDesignDefaults(objectEntry, prefab)

local result = buildObject(objectEntry, Formex.BuildAction.Add, getSelectionSnapshot())
	clearGhost()
	setActionType(Enums.ActionType.Select)
	local resultObjectId = getResultObjectId(result)
	if resultObjectId then
		selectPlotModelByIdAsync(input.PlotInfo, Enums.SelectionType.Object, data.Level, resultObjectId)
	end
	notifyDesignModeChange()
end

local function updateMovePreview(input: any)
	if not moveOriginal or not moveOriginal.Part then return end
	if not input or not input.PlotInfo or not input.PlotInfo.PlotPart then return end
	local prefab = moveOriginal.Prefab
	if not prefab and moveOriginal.PrefabName then
		prefab = Formex.Objects.GetPrefab(moveOriginal.PrefabName)
	end
	if not prefab then return end
	local wallData = nil
	if prefab.ObjectMount == Formex.MountType.Wall
		or prefab.ObjectMount == Formex.MountType.Door
		or prefab.ObjectMount == Formex.MountType.Window then
		wallData = input.WallData
	end

	local data, valid = getPlacement(
		input,
		prefab,
		moveOriginal.Rotation,
		wallData,
		moveOriginal.ObjectId,
		moveSnapshot,
		moveSnapshotMoved
	)
	if data.Level ~= moveOriginal.Level then
		data.Level = moveOriginal.Level
		valid = false
	end
	if not data.Position or not data.Rotation then return end
	movePreview = table.clone(moveOriginal)
	movePreview.Level = moveOriginal.Level
	movePreview.Position = data.Position
	movePreview.Rotation = data.Rotation
	movePreview.Side = data.Side
	movePreview.WallId = data.WallId
	if valid then
		valid = isObjectTransactionValid(input.PlotInfo, movePreview, Formex.BuildAction.Edit)
	end
	setPreviewHighlight(valid)

	movePreview.ObjectModel = moveOriginal.ObjectModel
	local targetCFrame = getObjectWorldCFrame(input.PlotInfo, movePreview, prefab)
	if targetCFrame then
		moveOriginal.Part:PivotTo(targetCFrame)
	end
end

local function updateRotatePreview(input: any)
	if not moveOriginal or not moveOriginal.Part then return end
	if not input or not input.PlotInfo or not input.PlotInfo.PlotPart or not input.HitPosition then return end
	local prefab = moveOriginal.Prefab
	if not prefab and moveOriginal.PrefabName then
		prefab = Formex.Objects.GetPrefab(moveOriginal.PrefabName)
	end
	if not prefab then return end
	local plotPart = input.PlotInfo.PlotPart
	local localHit = plotPart.CFrame:PointToObjectSpace(input.HitPosition)
	local boxCFrame = moveOriginal.Part:GetBoundingBox()
	local objectLocal = plotPart.CFrame:PointToObjectSpace(boxCFrame.Position)
	local delta = Vector2.new(localHit.X - objectLocal.X, localHit.Z - objectLocal.Z)
	if delta.Magnitude <= Constants.Epsilon then return end
	local angle = math.deg(math.atan2(delta.X, delta.Y))
	if prefab.ObjectMount == Formex.MountType.Floor
		or prefab.ObjectMount == Formex.MountType.Ceiling
		or prefab.ObjectMount == Formex.MountType.Surface then
		angle = snapRotationDegrees(angle)
	end
	local newRotation = Vector3.new(0, angle, 0)
	movePreview = table.clone(moveOriginal)
	movePreview.Rotation = newRotation
	movePreview.ObjectModel = moveOriginal.ObjectModel
	local valid = isPlacementClear(
		input.PlotInfo,
		movePreview,
		prefab,
		moveOriginal.ObjectId,
		nil,
		moveSnapshot,
		moveSnapshotMoved
	)
	if valid then
		valid = isObjectTransactionValid(input.PlotInfo, movePreview, Formex.BuildAction.Edit)
	end
	setPreviewHighlight(valid)

	local cframe = getObjectWorldCFrame(input.PlotInfo, movePreview, prefab)
	if cframe then
		moveOriginal.Part:PivotTo(cframe)
	end
end

local function finalizeMove(input: any)
	if not moveOriginal or not movePreview then return end
	local plotPart = input and input.PlotInfo and input.PlotInfo.PlotPart
	if not previewValid then
		if moveOriginal.Part then
			if plotPart then
				local prefab = moveOriginal.Prefab or (moveOriginal.PrefabName and Formex.Objects.GetPrefab(moveOriginal.PrefabName))
				if prefab then
					local cframe = getObjectWorldCFrame(input.PlotInfo, moveOriginal, prefab)
					if cframe then
						moveOriginal.Part:PivotTo(cframe)
					end
				end
			end
		end
		moveOriginal = nil
		movePreview = nil
		clearPreviewHighlight()
		clearMoveSnapshot()
		setActionType(Enums.ActionType.Select)
		notifyDesignModeChange()
		return
	end

	buildObject({
		ObjectId = moveOriginal.ObjectId,
		Level = movePreview.Level or moveOriginal.Level,
		Position = movePreview.Position,
		Rotation = movePreview.Rotation,
		Side = movePreview.Side,
		WallId = movePreview.WallId,
		PrefabName = moveOriginal.PrefabName,
		Design = moveOriginal.Design,
		DesignColors = moveOriginal.DesignColors,
	}, Formex.BuildAction.Edit, getSelectionSnapshot())

	moveOriginal = nil
	movePreview = nil
	clearPreviewHighlight()
	clearMoveSnapshot()
	setActionType(Enums.ActionType.Select)
	notifyDesignModeChange()
end

function Objects.Init()
	local ctx = Context.Get()
	FormexClient = ctx.FormexClient
	Formex = ctx.Formex
	Handles = ctx.Handles
	OverlayFolder = ctx.OverlayFolder
	Enums = ctx.Enums
	Constants = ctx.Constants

	getActionType = ctx.GetActionType
	setActionType = ctx.SetActionType
	getDesignMode = ctx.GetDesignMode
	getSelectionType = ctx.GetSelectionType
	getSelectionData = ctx.GetSelectionData
	getSelectionSnapshot = ctx.GetSelectionSnapshot
	getCurrentLevel = ctx.GetCurrentLevel
	getLastInputInfo = ctx.GetLastInputInfo
	getObjectPaintSettings = ctx.GetObjectPaintSettings
	getObjectPrefabName = ctx.GetObjectPrefabName
	updateDesignState = ctx.UpdateDesignState
	notifyDesignModeChange = ctx.NotifyDesignModeChange
	clearSelection = ctx.ClearSelection
	select = ctx.Select
	selectPlotModelByIdAsync = ctx.SelectPlotModelByIdAsync
end

function Objects.UpdateHandles(plotInfo: any)
	updateObjectHandles(plotInfo)
end

function Objects.ClearSelection()
	clearHandles()
	clearPreviewHighlight()
end

function Objects.GetRaycastIgnoreInstances(): {Instance}
	if moveOriginal and moveOriginal.Part then
		return { moveOriginal.Part }
	end
	return {}
end

local function resolveRaycastPrefab(): Formex.ObjectPrefab?
	local actionType = getActionType()
	if (actionType == Enums.ActionType.Move or actionType == Enums.ActionType.Rotate) and moveOriginal then
		return moveOriginal.Prefab or (moveOriginal.PrefabName and Formex.Objects.GetPrefab(moveOriginal.PrefabName))
	end
	return resolvePrefab()
end

function Objects.GetRaycastInfo(plotInfo: any, levelIndex: number): {FilterType: Enum.RaycastFilterType, Instances: {Instance}}?
	local prefab = resolveRaycastPrefab()
	if not prefab then return nil end
	local mount = prefab.ObjectMount
	if mount == Formex.MountType.Floor or mount == Formex.MountType.Ceiling then
		local floors = getLevelFolderChild(plotInfo, levelIndex, "Floors")
		if floors then
			return { FilterType = Enum.RaycastFilterType.Include, Instances = { floors } }
		end
		return { FilterType = Enum.RaycastFilterType.Include, Instances = {} }
	end

	if mount == Formex.MountType.Wall or mount == Formex.MountType.Door or mount == Formex.MountType.Window then
		local instances = {}
		local walls = getLevelFolderChild(plotInfo, levelIndex, "Walls")
		if walls then
			table.insert(instances, walls)
		end
		local floors = getLevelFolderChild(plotInfo, levelIndex, "Floors")
		if floors then
			table.insert(instances, floors)
		end
		return { FilterType = Enum.RaycastFilterType.Include, Instances = instances }
	end

	if mount == Formex.MountType.Surface then
		return { FilterType = Enum.RaycastFilterType.Exclude, Instances = {} }
	end

	return nil
end

function Objects.CancelAction()
	clearGhost()
	clearPreviewHighlight()
	if moveOriginal and moveOriginal.Part then
		local input = getLastInputInfo()
		if input and input.PlotInfo and input.PlotInfo.PlotPart then
			local plotPart = input.PlotInfo.PlotPart
			local prefab = moveOriginal.Prefab or (moveOriginal.PrefabName and Formex.Objects.GetPrefab(moveOriginal.PrefabName))
			if prefab then
				local cframe = getObjectWorldCFrame(input.PlotInfo, moveOriginal, prefab)
				if cframe then
					moveOriginal.Part:PivotTo(cframe)
				end
			end
		end
	end
	moveOriginal = nil
	movePreview = nil
	clearMoveSnapshot()
	setActionType(Enums.ActionType.Select)
end

function Objects.HandleUpdate(input: any)
	if getDesignMode() ~= Enums.DesignMode.Object then return end
	local actionType = getActionType()
	if actionType == Enums.ActionType.Select then
		updateObjectHandles(input.PlotInfo)
		Handles.CheckHover(input.Ray)
		return
	end

	if actionType == Enums.ActionType.Start then
		updateGhostPlacement(input)
		return
	end

	if actionType == Enums.ActionType.Move then
		updateMovePreview(input)
		return
	end

	if actionType == Enums.ActionType.Rotate then
		updateRotatePreview(input)
		return
	end
end

function Objects.HandlePrimaryRelease(input: any)
	local actionType = getActionType()
	if actionType == Enums.ActionType.Move or actionType == Enums.ActionType.Rotate then
		finalizeMove(input)
	end
end

function Objects.HandlePrimaryClick(input: any)
	local actionType = getActionType()
	if actionType == Enums.ActionType.Select then
		local selectionType = getSelectionType()
		local selectionData = getSelectionData()
		local hadSelection = selectionType ~= Enums.SelectionType.None
		if hadSelection
			and selectionType == Enums.SelectionType.Object
			and input.ObjectData
			and selectionData
			and input.ObjectData == selectionData then
			return
		end

		local selected = select(input)
		if selected then return end
		if hadSelection then
			clearSelection()
			return
		end

		setActionType(Enums.ActionType.Start)
		clearGhost()
		notifyDesignModeChange()
		return
	end

	if actionType == Enums.ActionType.Start then
		finalizePlacement(input)
	end
end

return Objects
