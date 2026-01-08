--!strict
local Context = require(script.Parent:WaitForChild("FormexDesignContext"))

local Floors = {}

type FloorHandleType = "Point" | "Midpoint" | "Delete"

type FloorHandle = {
	Kind: FloorHandleType,
	Index: number,
	Handle: BasePart,
}

type SharedFloorPoint = {
	FloorId: number,
	LevelIndex: number,
	Points: {Vector2int16},
	PointIndex: number,
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
local getFloorMaterialId: () -> number
local getCeilingMaterialId: () -> number
local getFloorRaiseHeight: () -> number
local getFloorColor: () -> Color3
local getCeilingColor: () -> Color3
local getFoundationMaterialId: () -> number
local getFoundationColor: () -> Color3
local select: (Instance) -> boolean
local clearSelection: () -> ()
local getSelectionInfoFromInstance: (Instance?) -> (string?, number?, number?)

local floorHandles = {} :: {FloorHandle}
local activeHandle: FloorHandle? = nil
local moveOriginalPoints: {Vector2int16}? = nil
local moveSharedPoints: {SharedFloorPoint} = {}
local moveFloorId: number? = nil
local moveLevelIndex: number? = nil
local moveRaiseHeight: number = 0
local movePreviewPoints: {Vector2int16}? = nil
local lastHandleFloorId: number? = nil
local lastHandleLevelIndex: number? = nil
local lastHandlePointsKey: string? = nil
local lastHandleRaiseHeight: number = 0

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
	getFloorMaterialId = ctx.GetFloorMaterialId
	getCeilingMaterialId = ctx.GetCeilingMaterialId
	getFloorRaiseHeight = ctx.GetFloorRaiseHeight
	getFloorColor = ctx.GetFloorColor
	getCeilingColor = ctx.GetCeilingColor
	getFoundationMaterialId = ctx.GetFoundationMaterialId
	getFoundationColor = ctx.GetFoundationColor
	select = ctx.Select
	clearSelection = ctx.ClearSelection
	getSelectionInfoFromInstance = ctx.GetSelectionInfoFromInstance
end

local function pointsEqual(a: Vector2int16, b: Vector2int16): boolean
	return a.X == b.X and a.Y == b.Y
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

local function updateHandlePositions(plotPart: BasePart, floorData: Formex.FloorData, handlePoints: {Vector2int16})
	local y = getHandleY(floorData.LevelIndex)
	for index, handle in ipairs(floorHandles) do
		if handle.Kind ~= "Point" then
			continue
		end
		local point = handlePoints[handle.Index]
		if point then
			local worldPos = plotPart.CFrame * Vector3.new(point.X, y, point.Y)
			handle.Handle.CFrame = CFrame.new(worldPos)
		end
	end
end

local function buildMidpoints(points: {Vector2int16}): {Vector2int16}
	local midpoints = {}
	local grid = Formex.LayoutGridSize
	for i = 1, #points do
		local nextIndex = (i % #points) + 1
		local startPoint = points[i]
		local endPoint = points[nextIndex]
		local dx = endPoint.X - startPoint.X
		local dy = endPoint.Y - startPoint.Y
		local distance = math.sqrt(dx * dx + dy * dy)
		if distance >= 4 then
			local midX = math.round(((startPoint.X + endPoint.X) / 2) / grid) * grid
			local midY = math.round(((startPoint.Y + endPoint.Y) / 2) / grid) * grid
			local mid = Vector2int16.new(midX, midY)
			table.insert(midpoints, mid)
		else
			table.insert(midpoints, Vector2int16.new(0, 0))
		end
	end
	return midpoints
end

local function collectSharedFloors(plotPart: BasePart, levelIndex: number, originPoint: Vector2int16, ignoreFloorId: number): {SharedFloorPoint}
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
		FormexClient.BuildFloor(updates, Formex.BuildAction.Edit)
	end

	movePreviewPoints = nil
	moveOriginalPoints = nil
	moveSharedPoints = {}
	moveFloorId = nil
	moveLevelIndex = nil
	moveRaiseHeight = 0
	activeHandle = nil
end

local function handlePointMove(plotInfo: any, input: any)
	if not activeHandle or activeHandle.Kind == "Delete" then
		return
	end
	if not input.SnapPoint then
		return
	end

	if not movePreviewPoints then
		return
	end

	local newPoint = input.SnapPoint
	movePreviewPoints[activeHandle.Index] = newPoint
	movePreviewPoints = mergeDuplicatePoints(movePreviewPoints)

	for _, shared in ipairs(moveSharedPoints) do
		shared.Points[shared.PointIndex] = newPoint
		shared.Points = mergeDuplicatePoints(shared.Points)
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

local function createFloorFromTile(plotInfo: any, tile: Vector2int16)
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
	local floorData = {
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

	FormexClient.BuildFloor(floorData, Formex.BuildAction.Add)
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
		}, Formex.BuildAction.Delete)
		clearSelection()
		return
	end

	local points = table.clone(floorData.Points)
	local handleIndex = info.Index
	if info.Kind == "Midpoint" then
		local midpoints = buildMidpoints(points)
		local midpoint = midpoints[handleIndex]
		if midpoint then
			table.insert(points, handleIndex + 1, midpoint)
			handleIndex = handleIndex + 1
		end
	end

	moveOriginalPoints = table.clone(points)
	movePreviewPoints = points
	moveFloorId = floorData.FloorId
	moveLevelIndex = floorData.LevelIndex
	moveRaiseHeight = floorData.RaiseHeight
	moveSharedPoints = collectSharedFloors(plotInfo.PlotPart, floorData.LevelIndex, points[handleIndex], floorData.FloorId)

	activeHandle = {
		Kind = "Point",
		Index = handleIndex,
		Handle = info.Handle,
	}
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
	local pointsKey = Formex.EncodeFloorPoints(points)
	local shouldRebuild = floorData.FloorId ~= lastHandleFloorId
		or floorData.LevelIndex ~= lastHandleLevelIndex
		or pointsKey ~= lastHandlePointsKey
		or floorData.RaiseHeight ~= lastHandleRaiseHeight
	if not shouldRebuild then
		return
	end

	clearFloorHandles()
	updateFloorEdgePreview(plotInfo, floorData.LevelIndex, points)
	Highlight.UpdateSelectionHighlight()

	local levelIndex = floorData.LevelIndex
	local y = getHandleY(levelIndex)

	for index, point in ipairs(points) do
		local handle = addFloorHandle("FloorPoint_" .. tostring(index), Constants.SelectionColor, Formex.Icons.ResizeItem, onFloorHandleClicked, {
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

	local midpoints = buildMidpoints(points)
	for index, midpoint in ipairs(midpoints) do
		if midpoint.X ~= 0 or midpoint.Y ~= 0 then
			local handle = addFloorHandle("FloorMid_" .. tostring(index), Constants.GhostValidColor, Formex.Icons.WallExtend, onFloorHandleClicked, {
				Kind = "Midpoint",
				Index = index,
				Handle = nil,
			})
			handle.CFrame = plotInfo.PlotPart.CFrame * CFrame.new(midpoint.X, y, midpoint.Y)
			floorHandles[#floorHandles + 1] = {
				Kind = "Midpoint",
				Index = index,
				Handle = handle,
			}
		end
	end

	local centroid = Vector2.new(0, 0)
	for _, point in ipairs(points) do
		centroid += Vector2.new(point.X, point.Y)
	end
	centroid /= math.max(#points, 1)
	local deleteHandle = addFloorHandle("FloorDelete", Constants.GhostInvalidColor, Formex.Icons.DeleteItem, onFloorHandleClicked, {
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

	lastHandleFloorId = floorData.FloorId
	lastHandleLevelIndex = floorData.LevelIndex
	lastHandlePointsKey = pointsKey
	lastHandleRaiseHeight = floorData.RaiseHeight
	setHandlesVisible(true)
end

function Floors.UpdateHandles(plotInfo: any)
	updateFloorHandles(plotInfo)
	Highlight.UpdateSelectionHighlight()
end

function Floors.StartFloor()
	setActionType(Enums.ActionType.Select)
end

function Floors.CancelAction()
	if getActionType() == Enums.ActionType.Move then
		movePreviewPoints = moveOriginalPoints
		moveOriginalPoints = nil
		moveSharedPoints = {}
		moveRaiseHeight = 0
		activeHandle = nil
		local plotInfo = FormexClient.CurrentPlot
		if plotInfo and plotInfo.PlotPart and movePreviewPoints and moveLevelIndex then
			updateFloorEdgePreview(plotInfo, moveLevelIndex, movePreviewPoints)
		end
	end
	setActionType(Enums.ActionType.Select)
	Highlight.UpdateSelectionHighlight()
end

function Floors.ClearSelection()
	movePreviewPoints = nil
	moveOriginalPoints = nil
	moveSharedPoints = {}
	moveRaiseHeight = 0
	activeHandle = nil
	clearFloorHandles()
	Highlight.ClearFloorEdgePreview()
	Highlight.UpdateSelectionHighlight()
end

function Floors.HandleUpdate(input: any)
	if getActionType() == Enums.ActionType.Select then
		updateFloorHandles(input.PlotInfo)
		Handles.CheckHover(input.Ray)
		Highlight.UpdateSelectionHighlight()
		return
	end

	if getActionType() == Enums.ActionType.Move then
		handlePointMove(input.PlotInfo, input)
		if movePreviewPoints and moveLevelIndex then
			updateFloorEdgePreview(input.PlotInfo, moveLevelIndex, movePreviewPoints)
		end
		Highlight.UpdateSelectionHighlight()
	end
end

function Floors.HandlePrimaryRelease(input: any)
	if getActionType() == Enums.ActionType.Move then
		finalizeMove(input.PlotInfo)
		setActionType(Enums.ActionType.Select)
		updateFloorHandles(input.PlotInfo)
	end
end

function Floors.HandlePrimaryClick(input: any)
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
		if selected then return end

		if hadSelection then
			clearSelection()
			return
		end

		if hadSelection then
			clearSelection()
			return
		end

		if input.LayoutTile then
			createFloorFromTile(input.PlotInfo, input.LayoutTile)
		end
	end
end

return Floors
