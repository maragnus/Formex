--!strict
--[[
FormexDesignObjects
Handles object design interactions (placement, handles, paint/dropper).
Exports:
- Init(): ()
- GetSelectedObjectData(): Formex.ObjectData?
- ApplySelectedDesign(design, colors): boolean
- ApplyPaintToTarget(target): boolean
- CopyPaintFromTarget(target): boolean
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
local getSelectionPart: () -> Instance?
local getSelectionSnapshot: () -> any?
local getCurrentLevel: () -> number
local getLastInputInfo: () -> any?
local getObjectPaintSettings: () -> Context.ObjectPaintSettings
local getObjectPrefabName: () -> string?
local updateDesignState: (any) -> ()
local notifyDesignModeChange: () -> ()
local clearSelection: () -> ()
local select: (Instance) -> boolean
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

local lastHandleObjectId: number? = nil
local SURFACE_UP_DOT = 0.65

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

	if ghostModel then
		return
	end

	ghostPrefabName = prefab.PrefabName

	local sourceModel, _ = Formex.Objects.ResolvePrefabModels(prefab)
	if not sourceModel and prefab.PrefabName then
		local resolved = Formex.Objects.GetPrefab(prefab.PrefabName)
		if resolved then
			sourceModel = (Formex.Objects.ResolvePrefabModels(resolved))
		end
	end
	if not sourceModel then
		return
	end

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

local function getObjectModelFromTarget(target: Instance?): Model?
	if not target then
		return nil
	end
	local model = target:IsA("Model") and target or target:FindFirstAncestorOfClass("Model")
	while model and model.Parent do
		if model.Parent:IsA("Folder") and model.Parent.Name == "Objects" then
			return model
		end
		if not model.Parent:IsA("Model") then
			break
		end
		model = model.Parent
	end
	return nil
end

local function getObjectDesignIndexFromTarget(target: Instance?): number?
	if not target then
		return nil
	end
	if target:IsA("BasePart") then
		return tonumber(target.Name)
	end
	return nil
end

local function getWallModelFromTarget(target: Instance?): Model?
	if not target then
		return nil
	end
	if target:IsA("Model") and target.Parent and target.Parent:IsA("Folder") and target.Parent.Name == "Walls" then
		return target
	end
	local model = target:FindFirstAncestorOfClass("Model")
	if model and model.Parent and model.Parent:IsA("Folder") and model.Parent.Name == "Walls" then
		return model
	end
	return nil
end

local function getWallDataFromModel(model: Model): Formex.WallData?
	local level = tonumber(model.Parent.Parent.Name) or getCurrentLevel()
	local wallId = tonumber(model.Name) or 0
	local startValue = model:GetAttribute("Start") or Vector2.new(0, 0)
	local endValue = model:GetAttribute("End") or Vector2.new(0, 0)
	local height = model:GetAttribute("WallHeight") or Formex.LevelHeight
	return {
		WallId = wallId,
		Level = level,
		Start = Vector2int16.new(math.round(startValue.X), math.round(startValue.Y)),
		End = Vector2int16.new(math.round(endValue.X), math.round(endValue.Y)),
		Height = height,
		Part = model,
	} :: Formex.WallData
end

local function getFloorModelFromTarget(target: Instance?): Model?
	if not target then
		return nil
	end
	local model = target:IsA("Model") and target or target:FindFirstAncestorOfClass("Model")
	if model and model.Parent and model.Parent:IsA("Folder") and model.Parent.Name == "Floors" then
		return model
	end
	return nil
end

local function snapToGrid(value: number): number
	local grid = Formex.ObjectGridSize
	if grid <= 0 then
		return value
	end
	return math.round(value / grid) * grid
end

local function getLevelIndexFromModel(model: Model): number
	local parent = model.Parent
	if parent and parent.Parent and parent.Parent:IsA("BasePart") then
		return tonumber(parent.Parent.Name) or getCurrentLevel()
	end
	return getCurrentLevel()
end

local function getFloorSurfaceHeights(floorModel: Model): (number, number)
	local levelIndex = getLevelIndexFromModel(floorModel)
	local raiseHeight = floorModel:GetAttribute("RaiseHeight") or 0
	local levelTop = Formex.LevelHeight * (levelIndex - 1)
	if raiseHeight > 0 then
		return levelTop + raiseHeight, levelTop
	end
	local thickness = levelIndex == 1 and Formex.FoundationHeight or Formex.InterfloorHeight
	return levelTop, levelTop - thickness
end

local function getLevelFromTarget(target: Instance?): number
	local floorModel = getFloorModelFromTarget(target)
	if floorModel then
		return getLevelIndexFromModel(floorModel)
	end
	local objectModel = getObjectModelFromTarget(target)
	if objectModel then
		return getLevelIndexFromModel(objectModel)
	end
	return getCurrentLevel()
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
	if math.abs(a.CenterY - b.CenterY) >= (a.HalfY + b.HalfY - Constants.Epsilon) then
		return false
	end

	local delta = b.Center - a.Center
	for _, axis in ipairs({
		getObbAxis(a.Cos, a.Sin, 1),
		getObbAxis(a.Cos, a.Sin, 2),
		getObbAxis(b.Cos, b.Sin, 1),
		getObbAxis(b.Cos, b.Sin, 2),
	}) do
		local distance = math.abs(delta:Dot(axis))
		local radius = getObbRadius(a, axis) + getObbRadius(b, axis)
		if distance > radius - Constants.Epsilon then
			return false
		end
	end

	return true
end

local function getObjectWorldCFrame(plotInfo: any, objectData: Formex.ObjectData, prefab: Formex.ObjectPrefab): CFrame?
	local plotPart = plotInfo and plotInfo.PlotPart
	if not plotPart then
		return nil
	end
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
	if not plotPart then
		return nil
	end
	local worldCFrame = getObjectWorldCFrame(plotInfo, objectData, prefab)
	if not worldCFrame then
		return nil
	end
	return plotPart.CFrame:ToObjectSpace(worldCFrame)
end

local function isPlacementClear(
	plotInfo: any,
	objectData: Formex.ObjectData,
	prefab: Formex.ObjectPrefab,
	ignoreObjectId: number?,
	wallOverride: Formex.WallData?
): boolean
	if not plotInfo or not plotInfo.PlotData then
		return true
	end
	local localCFrame = getObjectLocalCFrame(plotInfo, objectData, prefab, wallOverride)
	if not localCFrame then
		return true
	end
	local size = prefab.Size or Vector3.new(1, 1, 1)
	local sourceObb = buildObb(localCFrame, size)
	for _, levelData in pairs(plotInfo.PlotData.Levels or {}) do
		for _, other in pairs(levelData.Objects or {}) do
			if ignoreObjectId and other.ObjectId == ignoreObjectId then
				continue
			end
			if objectData.ObjectId ~= 0 and other.ObjectId == objectData.ObjectId then
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
					local otherSize = otherPrefab.Size or Vector3.new(1, 1, 1)
					local otherObb = buildObb(otherCFrame, otherSize)
					if obbOverlap2D(sourceObb, otherObb) then
						return false
					end
				end
			end
		end
	end
	return true
end

local function resolvePrefab(): Formex.ObjectPrefab?
	local prefabName = getObjectPrefabName()
	if prefabName then
		local prefab = Formex.Objects.GetPrefab(prefabName)
		if prefab then
			return prefab
		end
	end

	local prefabs = Formex.Objects.GetPrefabs()
	if #prefabs > 0 then
		return prefabs[1]
	end
	return nil
end

local function applyDesignToGhost(prefab: Formex.ObjectPrefab)
	if not ghostModel then
		return
	end
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

local function getSurfacePlacement(input: any, prefab: Formex.ObjectPrefab, rotationOverride: Vector3?): (Formex.ObjectData, boolean)
	local plotPart = input.PlotInfo.PlotPart
	local hitPosition = input.HitPosition
	if not plotPart or not hitPosition then
		return {} :: Formex.ObjectData, false
	end
	local localHit = plotPart.CFrame:PointToObjectSpace(hitPosition)
	local normal = input.HitNormal or Vector3.new(0, 1, 0)
	local mount = prefab.ObjectMount
	local levelIndex = getLevelFromTarget(input.Target)
	local validSurface = true
	local rotationY = rotationOverride and rotationOverride.Y or 0
	local _, boundsSize = Formex.Objects.GetPrefabBounds(prefab, nil)
	local floorTopY = 0
	local ceilingBottomY = 0

	if mount == Formex.MountType.Floor or mount == Formex.MountType.Ceiling then
		local floorModel = getFloorModelFromTarget(input.Target)
		if not floorModel then
			return {} :: Formex.ObjectData, false
		end
		levelIndex = getLevelIndexFromModel(floorModel)
		floorTopY, ceilingBottomY = getFloorSurfaceHeights(floorModel)
		if mount == Formex.MountType.Floor then
			if normal.Y < SURFACE_UP_DOT then
				validSurface = false
			end
		else
			if math.abs(normal.Y) < SURFACE_UP_DOT then
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

local function getPlacement(
	input: any,
	prefab: Formex.ObjectPrefab,
	rotationOverride: Vector3?,
	wallOverride: Formex.WallData?,
	ignoreObjectId: number?
): (Formex.ObjectData, boolean)
	local objectMount = prefab.ObjectMount
	if objectMount == Formex.MountType.Wall or objectMount == Formex.MountType.Door or objectMount == Formex.MountType.Window then
		local wallData = wallOverride
		if not wallData then
			local wallModel = getWallModelFromTarget(input.Target)
			if wallModel then
				wallData = getWallDataFromModel(wallModel)
			end
		end
		if not wallData then
			return {} :: Formex.ObjectData, false
		end
		local data, valid = getWallPlacement(input, prefab, wallData, rotationOverride)
		if valid then
			valid = isPlacementClear(input.PlotInfo, data, prefab, ignoreObjectId, wallData)
		end
		return data, valid
	end

	local data, valid = getSurfacePlacement(input, prefab, rotationOverride)
	if valid then
		valid = isPlacementClear(input.PlotInfo, data, prefab, ignoreObjectId, nil)
	end
	return data, valid
end

local function getSelectedObjectModel(): Model?
	local selectionPart = getSelectionPart()
	if not selectionPart then
		return nil
	end
	return getObjectModelFromTarget(selectionPart)
end

local function getObjectDataFromModel(model: Model): Formex.ObjectData
	local level = tonumber(model.Parent.Parent.Name) or getCurrentLevel()
	local objectId = tonumber(model.Name) or 0
	local position = model:GetAttribute("Position") or Vector3.new(0, 0, 0)
	local rotation = model:GetAttribute("Rotation") or Vector3.new(0, 0, 0)
	local side = model:GetAttribute("Side") or Formex.ObjectSide.Front
	local wallId = model:GetAttribute("WallId")
	local prefabName = model:GetAttribute("PrefabName")
	local design, colors = Formex.Objects.DecodeDesign(model:GetAttribute("Design"))
	local prefab = prefabName and Formex.Objects.GetPrefab(prefabName) or nil
	local objectModel = model:FindFirstChild("Object")
	return {
		ObjectId = objectId,
		Level = level,
		Position = position,
		Rotation = rotation,
		Side = side,
		WallId = wallId,
		PrefabName = prefabName,
		Prefab = prefab,
		Design = design,
		DesignColors = colors,
		IsPortal = model:GetAttribute("IsPortal") == true,
		Part = model,
		ObjectModel = objectModel and objectModel:IsA("Model") and objectModel or nil,
		DesignParts = {},
	} :: Formex.ObjectData
end

function Objects.GetSelectedObjectData(): Formex.ObjectData?
	local model = getSelectedObjectModel()
	if not model then
		return nil
	end
	return getObjectDataFromModel(model)
end

local function ensurePreviewHighlight(model: Model)
	if previewHighlight and previewHighlight.Parent then
		return
	end
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
	if not model then
		return
	end
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
	if not input or not selectedData or not selectedData.Part then
		return
	end

	local prefab = selectedData.Prefab
	if not prefab and selectedData.PrefabName then
		prefab = Formex.Objects.GetPrefab(selectedData.PrefabName)
	end
	if not prefab then
		return
	end

	if handleType == "Delete" then
		FormexClient.BuildObject({
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
		FormexClient.BuildObject({
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
		handleRotate = Handles.CreateHandle("ObjectRotate", Constants.HandleFlipColor, Formex.Icons.RotateItem, onHandleClick, "Rotate")
		handleDelete = Handles.CreateHandle("ObjectDelete", Constants.HandleDeleteColor, Formex.Icons.DeleteItem, onHandleClick, "Delete")
		lastHandleObjectId = objectData.ObjectId
	end

	updateHandlePositions(plotInfo, objectData, prefab)
	setHandlesVisible(true)
end

function Objects.ApplySelectedDesign(design: {[number]: number}, colors: {[number]: Color3}): boolean
	local selectedData = Objects.GetSelectedObjectData()
	if not selectedData then
		return false
	end
	selectedData.Design = table.clone(design)
	selectedData.DesignColors = table.clone(colors)
	FormexClient.BuildObject({
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

function Objects.ApplyPaintToTarget(target: Instance): boolean
	local model = getObjectModelFromTarget(target)
	if not model then
		return false
	end
	local designIndex = getObjectDesignIndexFromTarget(target)
	if not designIndex then
		return false
	end
	local objectData = getObjectDataFromModel(model)
	local paintSettings = getObjectPaintSettings()
	local materialId = paintSettings.Design[designIndex]
	local color = paintSettings.DesignColors[designIndex]
	if not materialId and not color then
		return false
	end
	local updatedDesign = table.clone(objectData.Design)
	local updatedColors = table.clone(objectData.DesignColors)
	if materialId then
		updatedDesign[designIndex] = materialId
	end
	if color then
		updatedColors[designIndex] = color
	end
	FormexClient.BuildObject({
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

function Objects.CopyPaintFromTarget(target: Instance): boolean
	local model = getObjectModelFromTarget(target)
	if not model then
		return false
	end
	local designIndex = getObjectDesignIndexFromTarget(target)
	if not designIndex then
		return false
	end
	local objectData = getObjectDataFromModel(model)
	local materialId = objectData.Design[designIndex]
	local color = objectData.DesignColors[designIndex]
	if not materialId and not color then
		return false
	end
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
	if not ghostModel then
		return
	end
	applyDesignToGhost(prefab)

	local data, valid = getPlacement(input, prefab, nil, nil, nil)
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
	if not ghostValid then
		return
	end
	local prefab = resolvePrefab()
	if not prefab then
		return
	end
	local data, valid = getPlacement(input, prefab, nil, nil, nil)
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

	local result = FormexClient.BuildObject(objectEntry, Formex.BuildAction.Add, getSelectionSnapshot())
	clearGhost()
	setActionType(Enums.ActionType.Select)
	if result and result.ObjectId then
		selectPlotModelByIdAsync(input.PlotInfo, Enums.SelectionType.Object, data.Level, result.ObjectId)
	end
	notifyDesignModeChange()
end

local function updateMovePreview(input: any)
	if not moveOriginal or not moveOriginal.Part then
		return
	end
	if not input or not input.PlotInfo or not input.PlotInfo.PlotPart then
		return
	end
	local prefab = moveOriginal.Prefab
	if not prefab and moveOriginal.PrefabName then
		prefab = Formex.Objects.GetPrefab(moveOriginal.PrefabName)
	end
	if not prefab then
		return
	end

	local wallData = nil
	if prefab.ObjectMount == Formex.MountType.Wall
		or prefab.ObjectMount == Formex.MountType.Door
		or prefab.ObjectMount == Formex.MountType.Window then
		local targetWall = input.Target and getWallModelFromTarget(input.Target)
		if targetWall then
			wallData = getWallDataFromModel(targetWall)
		elseif moveOriginal.WallId then
			local plotData = input.PlotInfo.PlotData
			local levelData = plotData.Levels and plotData.Levels[moveOriginal.Level]
			if levelData then
				wallData = levelData.Walls[moveOriginal.WallId]
			end
		end
	end

	local data, valid = getPlacement(input, prefab, moveOriginal.Rotation, wallData, moveOriginal.ObjectId)
	if data.Level ~= moveOriginal.Level then
		data.Level = moveOriginal.Level
		valid = false
	end
	setPreviewHighlight(valid)
	if not data.Position or not data.Rotation then
		return
	end

	movePreview = table.clone(moveOriginal)
	movePreview.Level = moveOriginal.Level
	movePreview.Position = data.Position
	movePreview.Rotation = data.Rotation
	movePreview.Side = data.Side
	movePreview.WallId = data.WallId

	movePreview.ObjectModel = moveOriginal.ObjectModel
	local targetCFrame = getObjectWorldCFrame(input.PlotInfo, movePreview, prefab)
	if targetCFrame then
		moveOriginal.Part:PivotTo(targetCFrame)
	end
end

local function updateRotatePreview(input: any)
	if not moveOriginal or not moveOriginal.Part then
		return
	end
	if not input or not input.PlotInfo or not input.PlotInfo.PlotPart or not input.HitPosition then
		return
	end
	local prefab = moveOriginal.Prefab
	if not prefab and moveOriginal.PrefabName then
		prefab = Formex.Objects.GetPrefab(moveOriginal.PrefabName)
	end
	if not prefab then
		return
	end
	local plotPart = input.PlotInfo.PlotPart
	local localHit = plotPart.CFrame:PointToObjectSpace(input.HitPosition)
	local boxCFrame = moveOriginal.Part:GetBoundingBox()
	local objectLocal = plotPart.CFrame:PointToObjectSpace(boxCFrame.Position)
	local delta = Vector2.new(localHit.X - objectLocal.X, localHit.Z - objectLocal.Z)
	if delta.Magnitude <= Constants.Epsilon then
		return
	end

	local angle = math.deg(math.atan2(delta.X, delta.Y))
	local newRotation = Vector3.new(0, angle, 0)
	movePreview = table.clone(moveOriginal)
	movePreview.Rotation = newRotation
	movePreview.ObjectModel = moveOriginal.ObjectModel
	setPreviewHighlight(true)

	local cframe = getObjectWorldCFrame(input.PlotInfo, movePreview, prefab)
	if cframe then
		moveOriginal.Part:PivotTo(cframe)
	end
end

local function finalizeMove(input: any)
	if not moveOriginal or not movePreview then
		return
	end
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
		setActionType(Enums.ActionType.Select)
		notifyDesignModeChange()
		return
	end

	FormexClient.BuildObject({
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
	getSelectionPart = ctx.GetSelectionPart
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
	setActionType(Enums.ActionType.Select)
end

function Objects.HandleUpdate(input: any)
	if getDesignMode() ~= Enums.DesignMode.Object then
		return
	end
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
		local currentSelection = getSelectionPart()
		local hadSelection = getSelectionType() ~= Enums.SelectionType.None or currentSelection ~= nil
		if hadSelection and input.Target and currentSelection then
			if input.Target == currentSelection
				or input.Target:IsDescendantOf(currentSelection)
				or currentSelection:IsDescendantOf(input.Target) then
				return
			end
		end

		local selected = input.Target and select(input.Target) or false
		if selected then
			return
		end

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
