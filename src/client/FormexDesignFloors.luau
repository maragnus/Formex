--!strict
--[[
FormexDesignFloors
Handles floor design actions (placement, handles, paint/dropper).
Exports:
- Init(): load shared dependencies
- ApplyPaintToTarget(target): boolean
- CopyPaintFromTarget(target): boolean
- ApplySelectedAppearance(overrides): boolean
- GetSelectedFloorModel(): Model?
- GetSelectedFloorData(): Formex.FloorData?
- GetFloorDataFromModel(model): Formex.FloorData
- UpdateHandles(plotInfo): ()
- StartFloor(): ()
- CancelAction(): ()
- ClearSelection(): ()
- HandleUpdate(input): ()
- HandlePrimaryRelease(input): ()
- HandlePrimaryClick(input): ()
- HandleSecondaryClick(input): boolean
]]
local Context = require(script.Parent:WaitForChild("FormexDesignContext"))
local ManualFloors = require(script.Parent:WaitForChild("FormexDesignFloorsManual"))

local Floors = {}

type FloorHandleType = "Point" | "Midpoint" | "Delete" | "Side" | "Height"

type FloorHandle = {
	Kind: FloorHandleType,
	Index: number,
	NextIndex: number?,
	Handle: BasePart,
}

type ActiveFloorHandle = {
	Kind: FloorHandleType,
	Index: number,
	NextIndex: number?,
	Handle: BasePart,
	OriginKey: string?,
	OriginKey2: string?,
}

type SharedFloorPoint = {
	FloorId: number,
	LevelIndex: number,
	Points: {Vector2int16},
	PointIndex: number,
	OriginKey: string,
	RaiseHeight: number,
	FloorMaterial: number,
	CeilingMaterial: number,
	FoundationMaterial: number,
	FloorColor: Color3,
	CeilingColor: Color3,
	FoundationColor: Color3,
}

local FormexClient: any
local Formex: any
local Handles: any
local Highlight: any
local Enums: any
local Constants: any

local getActionType: () -> string
local setActionType: (string) -> ()
local getDesignMode: () -> string
local getCurrentLevel: () -> number
local getSelectionType: () -> string
local getSelectionPart: () -> Instance?
local getSelectionSnapshot: () -> any?
local getFloorMaterialId: () -> number
local getCeilingMaterialId: () -> number
local getFloorRaiseHeight: () -> number
local getFloorColor: () -> Color3
local getCeilingColor: () -> Color3
local getFoundationMaterialId: () -> number
local getFoundationColor: () -> Color3
local getFloorMode: () -> string
local updateGhostValidity: (boolean) -> ()
local ensureFloorGhost: (BasePart, number, Vector2int16, any) -> ()
local clearGhost: () -> ()
local isGhostActive: () -> boolean
local getGhostType: () -> any?
local updateDesignState: (any) -> ()
local select: (Instance) -> boolean
local clearSelection: () -> ()
local getSelectionInfoFromInstance: (Instance?) -> (string?, number?, number?)
local notifyDesignModeChange: () -> ()
local cancelAction: () -> ()

local floorHandles = {} :: {FloorHandle}
local activeHandle: ActiveFloorHandle? = nil
local moveOriginalPoints: {Vector2int16}? = nil
local moveSharedPoints: {SharedFloorPoint} = {}
local moveFloorId: number? = nil
local moveLevelIndex: number? = nil
local moveRaiseHeight: number = 0
local moveRaiseHeightOriginal: number? = nil
local movePreviewPoints: {Vector2int16}? = nil
local lastHandleFloorId: number? = nil
local lastHandleLevelIndex: number? = nil
local lastHandlePointsKey: string? = nil
local lastHandleRaiseHeight: number = 0
local lastHandleAltHeld: boolean? = nil
local lastPreviewTile: Vector2int16? = nil
local lastAltHeld: boolean = false

function Floors.Init()
	local ctx = Context.Get()
	FormexClient = ctx.FormexClient
	Formex = ctx.Formex
	Handles = ctx.Handles
	Highlight = ctx.Highlight
	Enums = ctx.Enums
	Constants = ctx.Constants

	getActionType = ctx.GetActionType
	setActionType = ctx.SetActionType
	getDesignMode = ctx.GetDesignMode
	getCurrentLevel = ctx.GetCurrentLevel
	getSelectionType = ctx.GetSelectionType
	getSelectionPart = ctx.GetSelectionPart
	getSelectionSnapshot = ctx.GetSelectionSnapshot
	getFloorMaterialId = ctx.GetFloorMaterialId
	getCeilingMaterialId = ctx.GetCeilingMaterialId
	getFloorRaiseHeight = ctx.GetFloorRaiseHeight
	getFloorColor = ctx.GetFloorColor
	getCeilingColor = ctx.GetCeilingColor
	getFoundationMaterialId = ctx.GetFoundationMaterialId
	getFoundationColor = ctx.GetFoundationColor
	getFloorMode = ctx.GetFloorMode
	updateGhostValidity = ctx.UpdateGhostValidity
	ensureFloorGhost = ctx.EnsureFloorGhost
	clearGhost = ctx.ClearGhost
	isGhostActive = ctx.IsGhostActive
	getGhostType = ctx.GetGhostType
	updateDesignState = ctx.UpdateDesignState
	select = ctx.Select
	clearSelection = ctx.ClearSelection
	getSelectionInfoFromInstance = ctx.GetSelectionInfoFromInstance
	notifyDesignModeChange = ctx.NotifyDesignModeChange
	cancelAction = ctx.CancelAction

	ManualFloors.Init()
end

local function pointsEqual(a: Vector2int16, b: Vector2int16): boolean
	return a.X == b.X and a.Y == b.Y
end

local function getPointKey(point: Vector2int16): string
	return tostring(point.X) .. "," .. tostring(point.Y)
end

local function buildFloorDataFromTile(tile: Vector2int16): Formex.FloorData
	local tileSize = Formex.LayoutGridSize
	local x0 = tile.X * tileSize - (Formex.Dimensions.Width / 2)
	local z0 = tile.Y * tileSize - (Formex.Dimensions.Depth / 2)
	local materialId = getFloorMaterialId()
	local ceilingMaterial = getCeilingMaterialId()
	local raiseHeight = getFloorRaiseHeight()
	local floorColor = getFloorColor()
	local ceilingColor = getCeilingColor()
	local foundationMaterial = getFoundationMaterialId()
	local foundationColor = getFoundationColor()
	return {
		FloorId = 0,
		LevelIndex = getCurrentLevel(),
		Points = {
			Vector2int16.new(x0, z0),
			Vector2int16.new(x0 + tileSize, z0),
			Vector2int16.new(x0 + tileSize, z0 + tileSize),
			Vector2int16.new(x0, z0 + tileSize),
		},
		RaiseHeight = raiseHeight,
		FloorMaterial = materialId,
		CeilingMaterial = ceilingMaterial,
		FoundationMaterial = foundationMaterial,
		FloorColor = floorColor,
		CeilingColor = ceilingColor,
		FoundationColor = foundationColor,
		Model = nil,
	}
end

local function getFloorModelFromSelection(): Model?
	local selectionPart = getSelectionPart()
	if not selectionPart then
		return nil
	end

	if selectionPart:IsA("Model") then
		local parent = selectionPart.Parent
		if parent and parent:IsA("Folder") and parent.Name == "Floors" then
			return selectionPart
		end
	end

	local selectionKind, floorId, level = getSelectionInfoFromInstance(selectionPart)
	if selectionKind ~= Enums.SelectionType.Floor or not floorId or not level then
		return nil
	end

	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.PlotPart then
		return nil
	end

	local levelPart = plotInfo.PlotPart:FindFirstChild(tostring(level))
	if not levelPart then
		return nil
	end
	local floorsFolder = levelPart:FindFirstChild("Floors")
	if not floorsFolder then
		return nil
	end

	local floorModel = floorsFolder:FindFirstChild(tostring(floorId))
	if floorModel and floorModel:IsA("Model") then
		return floorModel
	end
	return nil
end

local function getFloorDataFromModel(model: Model): Formex.FloorData
	local points = Formex.DecodeFloorPoints(model:GetAttribute("Points"))
	local floorMaterial = model:GetAttribute("FloorMaterial") or Formex.DefaultFloorMaterial
	local ceilingMaterial = model:GetAttribute("CeilingMaterial") or floorMaterial
	local foundationMaterial = model:GetAttribute("FoundationMaterial") or Formex.DefaultFoundationMaterial
	local floorColor = model:GetAttribute("FloorColor") or Color3.new(1, 1, 1)
	local ceilingColor = model:GetAttribute("CeilingColor") or floorColor
	local foundationColor = model:GetAttribute("FoundationColor") or floorColor
	local raiseHeight = model:GetAttribute("RaiseHeight") or 0
	local levelIndex = tonumber(model.Parent.Parent.Name) or getCurrentLevel()
	local floorId = tonumber(model.Name) or 0

	return {
		FloorId = floorId,
		LevelIndex = levelIndex,
		Points = points,
		RaiseHeight = raiseHeight,
		FloorMaterial = floorMaterial,
		CeilingMaterial = ceilingMaterial,
		FoundationMaterial = foundationMaterial,
		FloorColor = floorColor,
		CeilingColor = ceilingColor,
		FoundationColor = foundationColor,
		Model = model,
	}
end

function Floors.GetSelectedFloorModel(): Model?
	return getFloorModelFromSelection()
end

function Floors.GetSelectedFloorData(): Formex.FloorData?
	local model = getFloorModelFromSelection()
	if not model then
		return nil
	end
	return getFloorDataFromModel(model)
end

function Floors.GetFloorDataFromModel(model: Model): Formex.FloorData
	return getFloorDataFromModel(model)
end

local function getFloorModelFromTarget(target: Instance?): Model?
	if not target then
		return nil
	end
	if target:IsA("Model") and target.Parent and target.Parent:IsA("Folder") and target.Parent.Name == "Floors" then
		return target
	end
	local model = target:FindFirstAncestorOfClass("Model")
	if model and model.Parent and model.Parent:IsA("Folder") and model.Parent.Name == "Floors" then
		return model
	end
	return nil
end

function Floors.ApplyPaintToTarget(target: Instance): boolean
	local model = getFloorModelFromTarget(target)
	if not model then
		return false
	end

	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid then
		return false
	end

	local current = getFloorDataFromModel(model)
	if not current.Points or #current.Points < 3 then
		return false
	end

	local updated = {
		FloorId = current.FloorId,
		LevelIndex = current.LevelIndex,
		Points = current.Points,
		RaiseHeight = getFloorRaiseHeight(),
		FloorMaterial = getFloorMaterialId(),
		CeilingMaterial = getCeilingMaterialId(),
		FoundationMaterial = getFoundationMaterialId(),
		FloorColor = getFloorColor(),
		CeilingColor = getCeilingColor(),
		FoundationColor = getFoundationColor(),
		Model = model,
	}

	FormexClient.BuildFloor(updated, Formex.BuildAction.Edit, getSelectionSnapshot())
	return true
end

function Floors.ApplySelectedAppearance(overrides: {[string]: any}): boolean
	local model = getFloorModelFromSelection()
	if not model then
		return false
	end

	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid then
		return false
	end

	local current = getFloorDataFromModel(model)
	if #current.Points < 3 then
		return false
	end
	local raiseHeight = overrides.RaiseHeight ~= nil and overrides.RaiseHeight or current.RaiseHeight
	local updated = {
		FloorId = current.FloorId,
		LevelIndex = current.LevelIndex,
		Points = current.Points,
		RaiseHeight = raiseHeight,
		FloorMaterial = overrides.FloorMaterial or current.FloorMaterial,
		CeilingMaterial = overrides.CeilingMaterial or current.CeilingMaterial,
		FoundationMaterial = overrides.FoundationMaterial or current.FoundationMaterial,
		FloorColor = overrides.FloorColor or current.FloorColor,
		CeilingColor = overrides.CeilingColor or current.CeilingColor,
		FoundationColor = overrides.FoundationColor or current.FoundationColor,
		Model = model,
	}

	FormexClient.BuildFloor(updated, Formex.BuildAction.Edit, getSelectionSnapshot())
	return true
end

function Floors.CopyPaintFromTarget(target: Instance): boolean
	local model = getFloorModelFromTarget(target)
	if not model then
		return false
	end

	local current = getFloorDataFromModel(model)
	updateDesignState({
		Floor = {
			RaiseHeight = current.RaiseHeight,
			FloorMaterial = current.FloorMaterial,
			CeilingMaterial = current.CeilingMaterial,
			FoundationMaterial = current.FoundationMaterial,
			FloorColor = current.FloorColor,
			CeilingColor = current.CeilingColor,
			FoundationColor = current.FoundationColor,
		},
	})
	return true
end

local function getHandleY(levelIndex: number): number
	return Formex.LevelHeight * (levelIndex - 1)
end

local function setHandlesVisible(visible: boolean)
	for _, handle in ipairs(floorHandles) do
		Handles.SetHandleVisible(handle.Handle, visible)
	end
end

local function clearFloorHandles()
	Handles.ClearHandleHover()
	Handles.Clear()
	floorHandles = {}
	activeHandle = nil
	lastHandleFloorId = nil
	lastHandleLevelIndex = nil
	lastHandlePointsKey = nil
	lastHandleRaiseHeight = 0
	lastHandleAltHeld = nil
end

local function updateFloorEdgePreview(plotInfo: any, levelIndex: number, points: {Vector2int16})
	local isValid = Formex.Floors.IsValid(plotInfo :: any, { Points = points } :: any)
	Highlight.UpdateFloorEdgePreview(plotInfo, levelIndex, points, isValid, nil)
end

local function addFloorHandle(name: string, color: Color3, iconAsset: string, onClick: (any) -> (), argument: any): BasePart
	local handle = Handles.CreateHandle(name, color, iconAsset, onClick, argument)
	Handles.SetHandleVisible(handle, true)
	return handle
end

local function getSnappedMidpoint(points: {Vector2int16}, index: number): Vector2int16?
	local nextIndex = (index % #points) + 1
	local startPoint = points[index]
	local endPoint = points[nextIndex]
	local dx = endPoint.X - startPoint.X
	local dy = endPoint.Y - startPoint.Y
	local distance = math.sqrt(dx * dx + dy * dy)
	local minHandleLength = Formex.LayoutGridSize * 2
	if distance < minHandleLength then
		return nil
	end

	local grid = Formex.LayoutGridSize
	local midX = math.round(((startPoint.X + endPoint.X) / 2) / grid) * grid
	local midY = math.round(((startPoint.Y + endPoint.Y) / 2) / grid) * grid
	return Vector2int16.new(midX, midY)
end

local function getFloorBounds(points: {Vector2int16}): (number, Vector2)
	local maxX = -math.huge
	local sumX = 0
	local sumY = 0
	for _, point in ipairs(points) do
		maxX = math.max(maxX, point.X)
		sumX += point.X
		sumY += point.Y
	end
	local count = math.max(#points, 1)
	local centroid = Vector2.new(sumX / count, sumY / count)
	return maxX, centroid
end

local function updateHandlePositions(plotPart: BasePart, floorData: Formex.FloorData, handlePoints: {Vector2int16})
	local y = getHandleY(floorData.LevelIndex)
	local raisedY = y + (floorData.RaiseHeight or 0)
	local maxX, centroid = getFloorBounds(handlePoints)
	for index, handle in ipairs(floorHandles) do
		if handle.Kind == "Point" then
			local point = handlePoints[handle.Index]
			if point then
				local worldPos = plotPart.CFrame * Vector3.new(point.X, y, point.Y)
				handle.Handle.CFrame = CFrame.new(worldPos)
			end
		elseif handle.Kind == "Side" then
			local midpoint = getSnappedMidpoint(handlePoints, handle.Index)
			if midpoint then
				local worldPos = plotPart.CFrame * Vector3.new(midpoint.X, y, midpoint.Y)
				handle.Handle.CFrame = CFrame.new(worldPos)
			end
		elseif handle.Kind == "Height" then
			local offsetX = maxX + (Constants.HandleOffset * 2)
			local worldPos = plotPart.CFrame * Vector3.new(offsetX, raisedY, centroid.Y)
			handle.Handle.CFrame = CFrame.new(worldPos)
		end
	end
end

local function getPolygonArea2(points: {Vector2int16}): number
	local area = 0
	for i = 1, #points do
		local nextIndex = (i % #points) + 1
		local a = points[i]
		local b = points[nextIndex]
		area += (a.X * b.Y) - (b.X * a.Y)
	end
	return area
end

local function getMidpointOffset(points: {Vector2int16}, index: number, handleOffset: number): Vector2int16
	local nextIndex = (index % #points) + 1
	local startPoint = points[index]
	local endPoint = points[nextIndex]
	local dx = endPoint.X - startPoint.X
	local dy = endPoint.Y - startPoint.Y
	local length = math.sqrt(dx * dx + dy * dy)
	if length <= Constants.Epsilon then
		return Vector2int16.new(0, 0)
	end

	local area2 = getPolygonArea2(points)
	local normalX, normalY
	if area2 >= 0 then
		normalX = dy
		normalY = -dx
	else
		normalX = -dy
		normalY = dx
	end

	local scale = handleOffset / length
	local offsetX = math.round(normalX * scale)
	local offsetY = math.round(normalY * scale)
	return Vector2int16.new(offsetX, offsetY)
end

local function collectSharedFloors(plotPart: BasePart, levelIndex: number, originPoint: Vector2int16, originKey: string, ignoreFloorId: number): {SharedFloorPoint}
	local shared = {}
	local levelPart = plotPart:FindFirstChild(tostring(levelIndex))
	if not levelPart then
		return shared
	end

	local floorsFolder = levelPart:FindFirstChild("Floors")
	if not floorsFolder then
		return shared
	end

	for _, child in ipairs(floorsFolder:GetChildren()) do
		if child:IsA("Model") then
			local floorId = tonumber(child.Name)
			if floorId and floorId ~= ignoreFloorId then
				local floorData = getFloorDataFromModel(child)
				for index, point in ipairs(floorData.Points) do
						if pointsEqual(point, originPoint) then
							table.insert(shared, {
								FloorId = floorId,
								LevelIndex = levelIndex,
								Points = floorData.Points,
								PointIndex = index,
								OriginKey = originKey,
								RaiseHeight = floorData.RaiseHeight,
								FloorMaterial = floorData.FloorMaterial,
								CeilingMaterial = floorData.CeilingMaterial,
								FoundationMaterial = floorData.FoundationMaterial or Formex.DefaultFoundationMaterial,
								FloorColor = floorData.FloorColor or Color3.new(1, 1, 1),
								CeilingColor = floorData.CeilingColor or Color3.new(1, 1, 1),
								FoundationColor = floorData.FoundationColor or Color3.new(1, 1, 1),
							})
						end
					end
				end
		end
	end

	return shared
end

local function mergeDuplicatePoints(points: {Vector2int16}): {Vector2int16}
	local unique = {}
	local seen = {}
	for _, point in ipairs(points) do
		local key = tostring(point.X) .. "," .. tostring(point.Y)
		if not seen[key] then
			seen[key] = true
			table.insert(unique, point)
		end
	end
	return unique
end

local function finalizeMove(plotInfo: any)
	if not movePreviewPoints or not moveFloorId or not moveLevelIndex then
		return
	end

	local updates = {}
	local floorModel = getFloorModelFromSelection()
	if floorModel then
		local current = getFloorDataFromModel(floorModel)
		current.Points = mergeDuplicatePoints(movePreviewPoints)
		current.LevelIndex = moveLevelIndex
		current.FloorId = moveFloorId
		current.RaiseHeight = moveRaiseHeight
		table.insert(updates, current)
	end

	for _, shared in ipairs(moveSharedPoints) do
		shared.Points = mergeDuplicatePoints(shared.Points)
		local modelData = {
			FloorId = shared.FloorId,
			LevelIndex = shared.LevelIndex,
			Points = shared.Points,
			RaiseHeight = shared.RaiseHeight,
			FloorMaterial = shared.FloorMaterial,
			CeilingMaterial = shared.CeilingMaterial,
			FoundationMaterial = shared.FoundationMaterial,
			FloorColor = shared.FloorColor,
			CeilingColor = shared.CeilingColor,
			FoundationColor = shared.FoundationColor,
			Model = nil,
		}
		table.insert(updates, modelData)
	end

	if #updates > 0 then
		FormexClient.BuildFloor(updates, Formex.BuildAction.Edit, getSelectionSnapshot())
	end

	movePreviewPoints = nil
	moveOriginalPoints = nil
	moveSharedPoints = {}
	moveFloorId = nil
	moveLevelIndex = nil
	moveRaiseHeight = 0
	moveRaiseHeightOriginal = nil
	activeHandle = nil
end

local function handlePointMove(plotInfo: any, input: any)
	if not activeHandle or activeHandle.Kind == "Delete" then
		return
	end
	if activeHandle.Kind == "Height" then
		if not input.HitPosition or not plotInfo or not plotInfo.PlotPart or not moveLevelIndex then
			return
		end
		local localPosition = plotInfo.PlotPart.CFrame:PointToObjectSpace(input.HitPosition)
		local baseY = getHandleY(moveLevelIndex)
		local newHeight = localPosition.Y - baseY
		updateDesignState({
			Floor = {
				RaiseHeight = newHeight,
			},
		})
		moveRaiseHeight = getFloorRaiseHeight()
		if movePreviewPoints then
			updateHandlePositions(plotInfo.PlotPart, {
				FloorId = moveFloorId or 0,
				LevelIndex = moveLevelIndex,
				Points = movePreviewPoints,
				RaiseHeight = moveRaiseHeight,
				FloorMaterial = Formex.DefaultFloorMaterial,
				CeilingMaterial = Formex.DefaultFloorMaterial,
			}, movePreviewPoints)
		end
		return
	end
	if not input.SnapPoint then
		return
	end

	if not movePreviewPoints then
		return
	end

	local newPoint = input.SnapPoint
	if activeHandle.Kind == "Side" then
		local nextIndex = activeHandle.NextIndex or ((activeHandle.Index % #movePreviewPoints) + 1)
		local midpoint = getSnappedMidpoint(movePreviewPoints, activeHandle.Index)
		if not midpoint then
			return
		end
		local deltaX = newPoint.X - midpoint.X
		local deltaY = newPoint.Y - midpoint.Y
		local startPoint = movePreviewPoints[activeHandle.Index]
		local endPoint = movePreviewPoints[nextIndex]
		local newStart = Vector2int16.new(math.round(startPoint.X + deltaX), math.round(startPoint.Y + deltaY))
		local newEnd = Vector2int16.new(math.round(endPoint.X + deltaX), math.round(endPoint.Y + deltaY))

		movePreviewPoints[activeHandle.Index] = newStart
		movePreviewPoints[nextIndex] = newEnd
		movePreviewPoints = mergeDuplicatePoints(movePreviewPoints)

		for _, shared in ipairs(moveSharedPoints) do
			if shared.OriginKey == activeHandle.OriginKey then
				shared.Points[shared.PointIndex] = newStart
			elseif shared.OriginKey == activeHandle.OriginKey2 then
				shared.Points[shared.PointIndex] = newEnd
			end
			shared.Points = mergeDuplicatePoints(shared.Points)
		end
	else
		movePreviewPoints[activeHandle.Index] = newPoint
		movePreviewPoints = mergeDuplicatePoints(movePreviewPoints)

		for _, shared in ipairs(moveSharedPoints) do
			if shared.OriginKey == activeHandle.OriginKey then
				shared.Points[shared.PointIndex] = newPoint
				shared.Points = mergeDuplicatePoints(shared.Points)
			end
		end
	end

	local plotPart = plotInfo.PlotPart
	if plotPart then
		updateHandlePositions(plotPart, {
			FloorId = moveFloorId or 0,
			LevelIndex = moveLevelIndex or getCurrentLevel(),
			Points = movePreviewPoints,
			RaiseHeight = moveRaiseHeight,
			FloorMaterial = Formex.DefaultFloorMaterial,
			CeilingMaterial = Formex.DefaultFloorMaterial,
		}, movePreviewPoints)
	end
end

local function createFloorFromTile(tile: Vector2int16, floorData: Formex.FloorData?)
	FormexClient.BuildFloor(floorData or buildFloorDataFromTile(tile), Formex.BuildAction.Add, getSelectionSnapshot())
end

local function updateFloorGhost(plotInfo: any, tile: Vector2int16): (boolean, Formex.FloorData)
	if not plotInfo or not plotInfo.PlotPart then
		return false, buildFloorDataFromTile(tile)
	end

	local floorData = buildFloorDataFromTile(tile)
	ensureFloorGhost(plotInfo.PlotPart, getCurrentLevel(), tile, Formex.PartType.Floor)
	local isValid = Formex.Floors.IsValid(plotInfo :: any, floorData)
	updateGhostValidity(isValid)
	return isValid, floorData
end

local function updateFloorStartGhost(input: any)
	if not input.LayoutTile then
		return
	end

	local tile = input.LayoutTile
	if lastPreviewTile and pointsEqual(tile, lastPreviewTile) then
		return
	end
	lastPreviewTile = tile

	updateFloorGhost(input.PlotInfo, tile)
end

local function finalizeFloorPlacement(plotInfo: any, tile: Vector2int16)
	local isValid, floorData = updateFloorGhost(plotInfo, tile)
	if not isValid then
		return
	end

	createFloorFromTile(tile, floorData)
	lastPreviewTile = nil
	setActionType(Enums.ActionType.Select)
	clearGhost()
	notifyDesignModeChange()
end

local function onFloorHandleClicked(info: any)
	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.PlotPart then
		return
	end

	local floorModel = getFloorModelFromSelection()
	if not floorModel then
		return
	end

	local floorData = getFloorDataFromModel(floorModel)
	if info.Kind == "Delete" then
		FormexClient.BuildFloor({
			FloorId = floorData.FloorId,
			LevelIndex = floorData.LevelIndex,
			Points = floorData.Points,
			RaiseHeight = floorData.RaiseHeight,
			FloorMaterial = floorData.FloorMaterial,
			CeilingMaterial = floorData.CeilingMaterial,
		}, Formex.BuildAction.Delete, getSelectionSnapshot())
		clearSelection()
		return
	end

	local points = table.clone(floorData.Points)
	local handleIndex = info.Index
	if info.Kind == "Midpoint" then
		if #points >= Formex.MaxFloorPoints then
			return
		end
		local midpoint = getSnappedMidpoint(points, handleIndex)
		if not midpoint then
			return
		end
		table.insert(points, handleIndex + 1, midpoint)
		handleIndex = handleIndex + 1
	end

	moveOriginalPoints = table.clone(points)
	movePreviewPoints = points
	moveFloorId = floorData.FloorId
	moveLevelIndex = floorData.LevelIndex
	moveRaiseHeight = floorData.RaiseHeight
	moveRaiseHeightOriginal = floorData.RaiseHeight
	moveSharedPoints = {}

	if info.Kind == "Side" then
		local nextIndex = info.NextIndex or ((handleIndex % #points) + 1)
		local originKey = getPointKey(points[handleIndex])
		local originKey2 = getPointKey(points[nextIndex])
		local sharedStart = collectSharedFloors(plotInfo.PlotPart, floorData.LevelIndex, points[handleIndex], originKey, floorData.FloorId)
		local sharedEnd = collectSharedFloors(plotInfo.PlotPart, floorData.LevelIndex, points[nextIndex], originKey2, floorData.FloorId)
		for _, shared in ipairs(sharedStart) do
			table.insert(moveSharedPoints, shared)
		end
		for _, shared in ipairs(sharedEnd) do
			table.insert(moveSharedPoints, shared)
		end

		activeHandle = {
			Kind = "Side",
			Index = handleIndex,
			NextIndex = nextIndex,
			Handle = info.Handle,
			OriginKey = originKey,
			OriginKey2 = originKey2,
		}
	elseif info.Kind == "Height" then
		activeHandle = {
			Kind = "Height",
			Index = handleIndex,
			Handle = info.Handle,
		}
	else
		local originKey = getPointKey(points[handleIndex])
		moveSharedPoints = collectSharedFloors(plotInfo.PlotPart, floorData.LevelIndex, points[handleIndex], originKey, floorData.FloorId)
		activeHandle = {
			Kind = "Point",
			Index = handleIndex,
			Handle = info.Handle,
			OriginKey = originKey,
		}
	end
	setActionType(Enums.ActionType.Move)
end

local function updateFloorHandles(plotInfo: any)
	if getSelectionType() ~= Enums.SelectionType.Floor then
		clearFloorHandles()
		Highlight.ClearFloorEdgePreview()
		Highlight.UpdateSelectionHighlight()
		return
	end

	local floorModel = getFloorModelFromSelection()
	if not floorModel or not plotInfo or not plotInfo.PlotPart then
		clearFloorHandles()
		Highlight.ClearFloorEdgePreview()
		Highlight.UpdateSelectionHighlight()
		return
	end

	local floorData = getFloorDataFromModel(floorModel)
	local points = movePreviewPoints or floorData.Points
	local altHeld = lastAltHeld
	local pointsKey = Formex.EncodeFloorPoints(points)
	local shouldRebuild = floorData.FloorId ~= lastHandleFloorId
		or floorData.LevelIndex ~= lastHandleLevelIndex
		or pointsKey ~= lastHandlePointsKey
		or floorData.RaiseHeight ~= lastHandleRaiseHeight
		or lastHandleAltHeld ~= altHeld
	if not shouldRebuild then
		return
	end

	clearFloorHandles()
	updateFloorEdgePreview(plotInfo, floorData.LevelIndex, points)
	Highlight.UpdateSelectionHighlight()

	local levelIndex = floorData.LevelIndex
	local y = getHandleY(levelIndex)

	for index, point in ipairs(points) do
		local handle = addFloorHandle("FloorPoint_" .. tostring(index), Constants.HandleMoveColor, Formex.Icons.ResizeItem, onFloorHandleClicked, {
			Kind = "Point",
			Index = index,
			Handle = nil,
		})
		handle.CFrame = plotInfo.PlotPart.CFrame * CFrame.new(point.X, y, point.Y)
		floorHandles[#floorHandles + 1] = {
			Kind = "Point",
			Index = index,
			Handle = handle,
		}
	end

	if altHeld then
		for index = 1, #points do
			local midpoint = getSnappedMidpoint(points, index)
			if midpoint then
				local nextIndex = (index % #points) + 1
				local handle = addFloorHandle("FloorSide_" .. tostring(index), Constants.HandleMoveColor, Formex.Icons.MoveItem, onFloorHandleClicked, {
					Kind = "Side",
					Index = index,
					NextIndex = nextIndex,
					Handle = nil,
				})
				handle.CFrame = plotInfo.PlotPart.CFrame * CFrame.new(midpoint.X, y, midpoint.Y)
				floorHandles[#floorHandles + 1] = {
					Kind = "Side",
					Index = index,
					NextIndex = nextIndex,
					Handle = handle,
				}
			end
		end
	elseif #points < Formex.MaxFloorPoints then
		for index = 1, #points do
			local midpoint = getSnappedMidpoint(points, index)
			if midpoint then
				local offset = getMidpointOffset(points, index, Constants.HandleOffset)
				local handle = addFloorHandle("FloorMid_" .. tostring(index), Constants.HandleAddColor, Formex.Icons.WallExtend, onFloorHandleClicked, {
					Kind = "Midpoint",
					Index = index,
					Handle = nil,
				})
				handle.CFrame = plotInfo.PlotPart.CFrame * CFrame.new(midpoint.X + offset.X, y, midpoint.Y + offset.Y)
				floorHandles[#floorHandles + 1] = {
					Kind = "Midpoint",
					Index = index,
					Handle = handle,
				}
			end
		end
	end

	local maxX, centroid = getFloorBounds(points)
	local deleteHandle = addFloorHandle("FloorDelete", Constants.HandleDeleteColor, Formex.Icons.DeleteItem, onFloorHandleClicked, {
		Kind = "Delete",
		Index = 0,
		Handle = nil,
	})
	deleteHandle.CFrame = plotInfo.PlotPart.CFrame * CFrame.new(centroid.X, y, centroid.Y)
	floorHandles[#floorHandles + 1] = {
		Kind = "Delete",
		Index = 0,
		Handle = deleteHandle,
	}

	local heightHandle = addFloorHandle("FloorRaiseHeight", Constants.HandleHeightColor, Formex.Icons.ElevateItem, onFloorHandleClicked, {
		Kind = "Height",
		Index = 0,
		Handle = nil,
	})
	heightHandle.CFrame = plotInfo.PlotPart.CFrame * CFrame.new(maxX + (Constants.HandleOffset * 2), y + floorData.RaiseHeight, centroid.Y)
	floorHandles[#floorHandles + 1] = {
		Kind = "Height",
		Index = 0,
		Handle = heightHandle,
	}

	lastHandleFloorId = floorData.FloorId
	lastHandleLevelIndex = floorData.LevelIndex
	lastHandlePointsKey = pointsKey
	lastHandleRaiseHeight = floorData.RaiseHeight
	lastHandleAltHeld = altHeld
	setHandlesVisible(true)
end

function Floors.UpdateHandles(plotInfo: any)
	updateFloorHandles(plotInfo)
	Highlight.UpdateSelectionHighlight()
end

function Floors.StartFloor()
	if getActionType() ~= Enums.ActionType.Select then
		cancelAction()
	end

	if getFloorMode() == Enums.FloorMode.Manual then
		ManualFloors.StartFloor()
		return
	end

	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid or not plotInfo.PlotPart then
		return
	end

	setActionType(Enums.ActionType.Start)
	lastPreviewTile = nil
	clearGhost()
	clearSelection()
	notifyDesignModeChange()
end

function Floors.CancelAction()
	if getFloorMode() == Enums.FloorMode.Manual then
		if getActionType() == Enums.ActionType.Start or getActionType() == Enums.ActionType.Step then
			ManualFloors.CancelAction()
			return
		end
	end
	if getActionType() == Enums.ActionType.Move then
		if activeHandle and activeHandle.Kind == "Height" and moveRaiseHeightOriginal ~= nil then
			updateDesignState({
				Floor = {
					RaiseHeight = moveRaiseHeightOriginal,
				},
			})
			moveRaiseHeight = moveRaiseHeightOriginal
		else
			movePreviewPoints = moveOriginalPoints
			local plotInfo = FormexClient.CurrentPlot
			if plotInfo and plotInfo.PlotPart and movePreviewPoints and moveLevelIndex then
				updateFloorEdgePreview(plotInfo, moveLevelIndex, movePreviewPoints)
			end
		end
		moveOriginalPoints = nil
		moveSharedPoints = {}
		moveRaiseHeight = 0
		moveRaiseHeightOriginal = nil
		activeHandle = nil
	end
	lastPreviewTile = nil
	setActionType(Enums.ActionType.Select)
	Highlight.UpdateSelectionHighlight()
end

function Floors.ClearSelection()
	ManualFloors.ClearSelection()
	movePreviewPoints = nil
	moveOriginalPoints = nil
	moveSharedPoints = {}
	moveRaiseHeight = 0
	moveRaiseHeightOriginal = nil
	activeHandle = nil
	lastPreviewTile = nil
	clearFloorHandles()
	Highlight.ClearFloorEdgePreview()
	Highlight.UpdateSelectionHighlight()
end

function Floors.HandleUpdate(input: any)
	local actionType = getActionType()
	if getFloorMode() == Enums.FloorMode.Manual then
		if actionType == Enums.ActionType.Start or actionType == Enums.ActionType.Step then
			ManualFloors.HandleUpdate(input)
			return
		end
	end
	if actionType == Enums.ActionType.Select then
		lastAltHeld = input.AltHeld
		updateFloorHandles(input.PlotInfo)
		Handles.CheckHover(input.Ray)
		if isGhostActive() and getGhostType() == Formex.PartType.Floor then
			clearGhost()
		end
		Highlight.UpdateSelectionHighlight()
		return
	end

	if actionType == Enums.ActionType.Start then
		updateFloorStartGhost(input)
		return
	end

	if actionType == Enums.ActionType.Move then
		handlePointMove(input.PlotInfo, input)
		if movePreviewPoints and moveLevelIndex then
			updateFloorEdgePreview(input.PlotInfo, moveLevelIndex, movePreviewPoints)
		end
		Highlight.UpdateSelectionHighlight()
	end
end

function Floors.HandlePrimaryRelease(input: any)
	if getActionType() == Enums.ActionType.Move then
		if activeHandle and activeHandle.Kind == "Height" then
			activeHandle = nil
			moveRaiseHeightOriginal = nil
			setActionType(Enums.ActionType.Select)
			updateFloorHandles(input.PlotInfo)
		else
			finalizeMove(input.PlotInfo)
			setActionType(Enums.ActionType.Select)
			updateFloorHandles(input.PlotInfo)
		end
	end
end

function Floors.HandlePrimaryClick(input: any)
	local actionType = getActionType()
	if getFloorMode() == Enums.FloorMode.Manual then
		if actionType == Enums.ActionType.Start or actionType == Enums.ActionType.Step then
			ManualFloors.HandlePrimaryClick(input)
			return
		end
	end
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
		if selected then return end

		if hadSelection then
			clearSelection()
			return
		end

		if input.LayoutTile then
			Floors.StartFloor()
		end
		return
	end

	if actionType == Enums.ActionType.Start then
		if input.LayoutTile then
			finalizeFloorPlacement(input.PlotInfo, input.LayoutTile)
		end
	end
end

function Floors.HandleSecondaryClick(input: any): boolean
	if getFloorMode() == Enums.FloorMode.Manual then
		return ManualFloors.HandleSecondaryClick(input)
	end
	return false
end

return Floors
