--!strict
--[[
FormexDesignFloorsManual
Manual floor creation uses Start/Step actions to build a polygon on the layout grid.
Ghost balls mark placed points, a cursor ghost follows the mouse, and edge highlights
preview the polygon (closing to the first point once two points exist). A confirm
handle on the first point finishes the polygon, while right-click removes the last
point and returns to Start when all points are gone.
Exports:
- Init(): load shared dependencies
- StartFloor(): ()
- CancelAction(): ()
- ClearSelection(): ()
- HandleUpdate(input): ()
- HandlePrimaryClick(input): ()
- HandleSecondaryClick(input): boolean
]]
local Context = require(script.Parent:WaitForChild("FormexDesignContext"))

local Manual = {}

local FormexClient: any
local Formex: any
local Handles: any
local Highlight: any
local Enums: any
local Constants: any
local OverlayFolder: Folder

local getActionType: () -> string
local setActionType: (string) -> ()
local getCurrentLevel: () -> number
local getSelectionSnapshot: () -> any?
local getFloorMaterialId: () -> number
local getCeilingMaterialId: () -> number
local getFloorRaiseHeight: () -> number
local getFloorColor: () -> Color3
local getCeilingColor: () -> Color3
local getFoundationMaterialId: () -> number
local getFoundationColor: () -> Color3
local buildFloor: (Formex.FloorData, any?) -> any?
local selectAfterFloorBuild: (any, number, {Vector2int16}, any?) -> ()
local updateGhostValidity: (boolean) -> ()
local clearGhost: () -> ()
local clearSelection: () -> ()
local select: (Instance) -> boolean
local notifyDesignModeChange: () -> ()

local ghostPoints = {} :: {BasePart}
local ghostPointHighlights = {} :: {Highlight}
local cursorGhost: BasePart? = nil
local cursorHighlight: Highlight? = nil
local confirmHandle: BasePart? = nil
local points = {} :: {Vector2int16}
local lastCursorPoint: Vector2int16? = nil

local GHOST_POINT_SIZE = 1.4
local GHOST_POINT_TRANSPARENCY = 0.2

function Manual.Init()
	local ctx = Context.Get()
	FormexClient = ctx.FormexClient
	Formex = ctx.Formex
	Handles = ctx.Handles
	Highlight = ctx.Highlight
	Enums = ctx.Enums
	Constants = ctx.Constants
	OverlayFolder = ctx.OverlayFolder

	getActionType = ctx.GetActionType
	setActionType = ctx.SetActionType
	getCurrentLevel = ctx.GetCurrentLevel
	getSelectionSnapshot = ctx.GetSelectionSnapshot
	getFloorMaterialId = ctx.GetFloorMaterialId
	getCeilingMaterialId = ctx.GetCeilingMaterialId
	getFloorRaiseHeight = ctx.GetFloorRaiseHeight
	getFloorColor = ctx.GetFloorColor
	getCeilingColor = ctx.GetCeilingColor
	getFoundationMaterialId = ctx.GetFoundationMaterialId
	getFoundationColor = ctx.GetFoundationColor
	buildFloor = ctx.BuildFloor
	selectAfterFloorBuild = ctx.SelectAfterFloorBuild
	updateGhostValidity = ctx.UpdateGhostValidity
	clearGhost = ctx.ClearGhost
	clearSelection = ctx.ClearSelection
	select = ctx.Select
	notifyDesignModeChange = ctx.NotifyDesignModeChange
end

local function pointsEqual(a: Vector2int16, b: Vector2int16): boolean
	return a.X == b.X and a.Y == b.Y
end

local function toVector2(point: Vector2int16): Vector2
	return Vector2.new(point.X, point.Y)
end

local function cross2(a: Vector2, b: Vector2): number
	return a.X * b.Y - a.Y * b.X
end

local function isPointOnSegment(point: Vector2, a: Vector2, b: Vector2): boolean
	if math.abs(cross2(b - a, point - a)) > Formex.EPSILON then return false end	return math.min(a.X, b.X) - Formex.EPSILON <= point.X and point.X <= math.max(a.X, b.X) + Formex.EPSILON
		and math.min(a.Y, b.Y) - Formex.EPSILON <= point.Y and point.Y <= math.max(a.Y, b.Y) + Formex.EPSILON
end

local function isPointInsidePolygon(point: Vector2, polygon: {Vector2int16}, includeBoundary: boolean?): boolean
	if #polygon < 3 then return false end
	for i = 1, #polygon do
		local a = toVector2(polygon[i])
		local b = toVector2(polygon[(i % #polygon) + 1])
		if isPointOnSegment(point, a, b) then
			return includeBoundary == true
		end
	end

	local inside = false
	local j = #polygon
	for i = 1, #polygon do
		local pi = polygon[i]
		local pj = polygon[j]
		local xi = pi.X
		local yi = pi.Y
		local xj = pj.X
		local yj = pj.Y

		local intersects = ((yi > point.Y) ~= (yj > point.Y))
			and (point.X < (xj - xi) * (point.Y - yi) / ((yj - yi) + 0.0000001) + xi)
		if intersects then
			inside = not inside
		end
		j = i
	end
	return inside
end

local function orientation(a: Vector2, b: Vector2, c: Vector2): number
	local value = (b.Y - a.Y) * (c.X - b.X) - (b.X - a.X) * (c.Y - b.Y)
	if math.abs(value) <= Formex.EPSILON then return 0 end	return value > 0 and 1 or 2
end

local function onSegment(a: Vector2, b: Vector2, c: Vector2): boolean
	return math.min(a.X, c.X) - Formex.EPSILON <= b.X and b.X <= math.max(a.X, c.X) + Formex.EPSILON
		and math.min(a.Y, c.Y) - Formex.EPSILON <= b.Y and b.Y <= math.max(a.Y, c.Y) + Formex.EPSILON
end

local function segmentsIntersect(p1: Vector2, p2: Vector2, q1: Vector2, q2: Vector2): boolean
	local o1 = orientation(p1, p2, q1)
	local o2 = orientation(p1, p2, q2)
	local o3 = orientation(q1, q2, p1)
	local o4 = orientation(q1, q2, p2)

	if o1 ~= o2 and o3 ~= o4 then return true end
	if o1 == 0 and onSegment(p1, q1, p2) then return true end
	if o2 == 0 and onSegment(p1, q2, p2) then return true end
	if o3 == 0 and onSegment(q1, p1, q2) then return true end
	if o4 == 0 and onSegment(q1, p2, q2) then return true end

	return false
end

local function pointsEqualVector2(a: Vector2, b: Vector2): boolean
	return math.abs(a.X - b.X) <= Formex.EPSILON and math.abs(a.Y - b.Y) <= Formex.EPSILON
end

local function segmentsProperlyIntersect(p1: Vector2, p2: Vector2, q1: Vector2, q2: Vector2): boolean
	if not segmentsIntersect(p1, p2, q1, q2) then return false end	if pointsEqualVector2(p1, q1) or pointsEqualVector2(p1, q2)
		or pointsEqualVector2(p2, q1) or pointsEqualVector2(p2, q2) then
		return false
	end

	local collinear = orientation(p1, p2, q1) == 0 and orientation(p1, p2, q2) == 0
	if collinear then return false end
	return true
end

local function polygonsProperlyIntersect(a: {Vector2int16}, b: {Vector2int16}): boolean
	if #a < 2 or #b < 2 then return false end
	for i = 1, #a do
		local a1 = toVector2(a[i])
		local a2 = toVector2(a[(i % #a) + 1])
		for j = 1, #b do
			local b1 = toVector2(b[j])
			local b2 = toVector2(b[(j % #b) + 1])
			if segmentsProperlyIntersect(a1, a2, b1, b2) then return true end		end
	end

	return false
end

local function isPolygonInside(outer: {Vector2int16}, inner: {Vector2int16}): boolean
	if #outer < 3 or #inner < 3 then return false end
	for _, point in ipairs(inner) do
		if not isPointInsidePolygon(Vector2.new(point.X, point.Y), outer, false) then return false end	end

	return true
end

local function isPointOnOrInExistingFloor(plotInfo: any, point: Vector2int16): boolean
	if not plotInfo or not plotInfo.PlotData or not plotInfo.PlotData.Levels then return false end
	local levelIndex = getCurrentLevel()
	local levelData = plotInfo.PlotData.Levels[levelIndex]
	if not levelData or not levelData.Floors then return false end
	local testPoint = Vector2.new(point.X, point.Y)
	for _, floor in pairs(levelData.Floors) do
		if floor.Points and #floor.Points >= 3 then
			local existing = Formex.Floors.CleanPolygon(floor.Points)
			if #existing >= 3 then
				if isPointInsidePolygon(testPoint, existing, true) then return true end			end
		end
	end

	return false
end

local function getFloorModelFromTarget(target: Instance?): Model?
	if not target then return nil end	if target:IsA("Model") and target.Parent and target.Parent:IsA("Folder") and target.Parent.Name == "Floors" then return target end	local model = target:FindFirstAncestorOfClass("Model")
	if model and model.Parent and model.Parent:IsA("Folder") and model.Parent.Name == "Floors" then return model end	return nil
end

local function isOverlappingExistingFloor(plotInfo: any, previewPoints: {Vector2int16}): boolean
	if not plotInfo or not plotInfo.PlotData or not previewPoints or #previewPoints < 3 then return false end
	local levelIndex = getCurrentLevel()
	local levelData = plotInfo.PlotData.Levels and plotInfo.PlotData.Levels[levelIndex]
	if not levelData or not levelData.Floors then return false end
	local preview = Formex.Floors.CleanPolygon(previewPoints)
	if #preview < 3 then return false end
	for _, floor in pairs(levelData.Floors) do
		if floor.Points and #floor.Points >= 3 then
			local existing = Formex.Floors.CleanPolygon(floor.Points)
			if #existing >= 3 then
				if polygonsProperlyIntersect(preview, existing) then return true end				if isPolygonInside(preview, existing) or isPolygonInside(existing, preview) then return true end			end
		end
	end

	return false
end

local function getBaseY(levelIndex: number): number
	return Formex.LevelHeight * (levelIndex - 1) + getFloorRaiseHeight()
end

local function createGhostBall(name: string, color: Color3): BasePart
	local part = Instance.new("Part", OverlayFolder)
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(GHOST_POINT_SIZE, GHOST_POINT_SIZE, GHOST_POINT_SIZE)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Metal
	part.Transparency = 0
	part.Color = color
	part.CollisionGroup = Formex.CollisionGroup.Grid
	return part
end

local function setGhostBallColor(part: BasePart?, color: Color3)
	if not part then return end	part.Color = color
end

local function ensureGhostPoint(index: number, color: Color3): BasePart
	local part = ghostPoints[index]
	if part and part.Parent then
		setGhostBallColor(part, color)
		local highlight = ghostPointHighlights[index]
		if highlight then
			highlight.FillColor = color
			highlight.OutlineColor = color
		end
		return part
	end

	local created = createGhostBall("FloorManualPoint_" .. tostring(index), color)
	ghostPoints[index] = created
	local highlight = Instance.new("Highlight")
	highlight.Name = "FloorManualPointHighlight"
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.OutlineTransparency = 1
	highlight.FillTransparency = 0
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.Adornee = created
	highlight.Parent = created
	ghostPointHighlights[index] = highlight
	return created
end

local function ensureCursorGhost(color: Color3): BasePart
	if cursorGhost and cursorGhost.Parent then
		setGhostBallColor(cursorGhost, color)
		if cursorHighlight then
			cursorHighlight.FillColor = color
			cursorHighlight.OutlineColor = color
		end
		return cursorGhost
	end

	cursorGhost = createGhostBall("FloorManualCursor", color)
	cursorHighlight = Instance.new("Highlight")
	cursorHighlight.Name = "FloorManualCursorHighlight"
	cursorHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	cursorHighlight.OutlineTransparency = 1
	cursorHighlight.FillTransparency = 0
	cursorHighlight.FillColor = color
	cursorHighlight.OutlineColor = color
	cursorHighlight.Adornee = cursorGhost
	cursorHighlight.Parent = cursorGhost
	return cursorGhost
end

local function clearGhostPoints()
	for _, part in ipairs(ghostPoints) do
		if part and part.Parent then
			part:Destroy()
		end
	end
	ghostPoints = {}
	ghostPointHighlights = {}
end

local function clearCursorGhost()
	if cursorGhost and cursorGhost.Parent then
		cursorGhost:Destroy()
	end
	cursorGhost = nil
	cursorHighlight = nil
	lastCursorPoint = nil
end

local function setPointWorldPosition(plotPart: BasePart, levelIndex: number, point: Vector2int16, part: BasePart)
	local y = getBaseY(levelIndex)
	part.CFrame = plotPart.CFrame * CFrame.new(point.X, y, point.Y)
end

local function setCursorWorldPosition(plotPart: BasePart, levelIndex: number, point: Vector2int16, part: BasePart)
	local y = getBaseY(levelIndex)
	part.CFrame = plotPart.CFrame * CFrame.new(point.X, y, point.Y)
end

local function clearConfirmHandle()
	if confirmHandle and confirmHandle.Parent then
		Handles.SetHandleVisible(confirmHandle, false)
	end
end

local function resetManualState()
	clearGhost()
	clearConfirmHandle()
	clearGhostPoints()
	clearCursorGhost()
	points = {}
	Highlight.ClearFloorEdgePreview()
	Handles.ClearHandleHover()
end

local function buildFloorDataFromPoints(pointsList: {Vector2int16}): Formex.FloorData
	return {
		FloorId = 0,
		LevelIndex = getCurrentLevel(),
		Points = table.clone(pointsList),
		RaiseHeight = getFloorRaiseHeight(),
		FloorMaterial = getFloorMaterialId(),
		CeilingMaterial = getCeilingMaterialId(),
		FoundationMaterial = getFoundationMaterialId(),
		FloorColor = getFloorColor(),
		CeilingColor = getCeilingColor(),
		FoundationColor = getFoundationColor(),
		Model = nil,
	}
end

local function updateEdgePreview(plotInfo: any, previewPoints: {Vector2int16}, isValid: boolean)
	Highlight.UpdateFloorEdgePreview(plotInfo, getCurrentLevel(), previewPoints, isValid, getFloorRaiseHeight())
end

local function getPreviewPoints(cursorPoint: Vector2int16?): {Vector2int16}
	local preview = table.clone(points)
	if cursorPoint then
		table.insert(preview, cursorPoint)
	end
	return preview
end

local function isPreviewValid(plotInfo: any, previewPoints: {Vector2int16}): boolean
	if #previewPoints < 3 then
		if #previewPoints >= 1 then
			return not isPointOnOrInExistingFloor(plotInfo, previewPoints[#previewPoints])
		end
		return true
	end
	local previewData = buildFloorDataFromPoints(previewPoints)
	local validation = Formex.IsTransactionValid(plotInfo.PlotData, {
		{
			PartType = Formex.PartType.Floor,
			Action = Formex.BuildAction.Add,
			Data = previewData,
		},
	})
	if not validation or validation.IsValid ~= true then return false end	if isOverlappingExistingFloor(plotInfo, previewPoints) then return false end	return true
end

local function updateGhosts(plotInfo: any, cursorPoint: Vector2int16?)
	if not plotInfo or not plotInfo.PlotPart then return end
	local isValid = isPreviewValid(plotInfo, getPreviewPoints(cursorPoint))
	local color = isValid and Constants.GhostValidColor or Constants.GhostInvalidColor

	for index, point in ipairs(points) do
		local part = ensureGhostPoint(index, color)
		setPointWorldPosition(plotInfo.PlotPart, getCurrentLevel(), point, part)
	end

	for index = #points + 1, #ghostPoints do
		local extra = ghostPoints[index]
		if extra and extra.Parent then
			extra:Destroy()
		end
		ghostPoints[index] = nil
	end

	if cursorPoint then
		local cursor = ensureCursorGhost(color)
		setCursorWorldPosition(plotInfo.PlotPart, getCurrentLevel(), cursorPoint, cursor)
	else
		clearCursorGhost()
	end

	updateGhostValidity(isValid)
end

local function finalizeFloor()
	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid then return end	if #points < 3 then return end
	local floorData = buildFloorDataFromPoints(points)
	local isValid = isPreviewValid(plotInfo, floorData.Points)
	if not isValid then
		updateGhostValidity(false)
		return
	end

	local result = buildFloor(floorData, getSelectionSnapshot())
	selectAfterFloorBuild(plotInfo, floorData.LevelIndex, floorData.Points, result)
	resetManualState()
	setActionType(Enums.ActionType.Select)
	notifyDesignModeChange()
end

local function updateConfirmHandle(plotInfo: any)
	if not plotInfo or not plotInfo.PlotPart or #points < 3 then
		clearConfirmHandle()
		return
	end

	if not confirmHandle or not confirmHandle.Parent then
		confirmHandle = Handles.CreateHandle(
			"FloorManualConfirm",
			Constants.HandleAddColor,
			Formex.Icons.Confirm,
			finalizeFloor,
			nil
		)
	end

	local firstPoint = points[1]
	if firstPoint then
		local y = getBaseY(getCurrentLevel())
		confirmHandle.CFrame = plotInfo.PlotPart.CFrame * CFrame.new(firstPoint.X, y, firstPoint.Y)
		Handles.SetHandleVisible(confirmHandle, true)
	end
end

function Manual.StartFloor()
	resetManualState()
	clearSelection()
	setActionType(Enums.ActionType.Start)
	notifyDesignModeChange()
end

function Manual.CancelAction()
	resetManualState()
	setActionType(Enums.ActionType.Select)
	notifyDesignModeChange()
end

function Manual.ClearSelection()
	resetManualState()
end

function Manual.HandleUpdate(input: any)
	if not input or not input.PlotInfo then return end
	local actionType = getActionType()
	if actionType ~= Enums.ActionType.Start and actionType ~= Enums.ActionType.Step then return end
	local cursorPoint = input.SnapPoint
	if cursorPoint and lastCursorPoint and pointsEqual(cursorPoint, lastCursorPoint) then
		cursorPoint = lastCursorPoint
	end
	lastCursorPoint = cursorPoint

	updateGhosts(input.PlotInfo, cursorPoint)

	if cursorPoint and #points >= 1 then
		local preview = getPreviewPoints(cursorPoint)
		local isValid = isPreviewValid(input.PlotInfo, preview)
		updateEdgePreview(input.PlotInfo, preview, isValid)
	elseif #points >= 2 then
		local isValid = isPreviewValid(input.PlotInfo, points)
		updateEdgePreview(input.PlotInfo, points, isValid)
	else
		Highlight.ClearFloorEdgePreview()
	end

	updateConfirmHandle(input.PlotInfo)
	Handles.CheckHover(input.Ray)
end

function Manual.HandlePrimaryClick(input: any)
	if not input then return end
	local actionType = getActionType()
	local targetFloor = getFloorModelFromTarget(input.Target)
	if targetFloor and select(targetFloor) then
		Manual.CancelAction()
		return
	end
	if not input.SnapPoint then return end	if actionType == Enums.ActionType.Start then
		if isPointOnOrInExistingFloor(FormexClient.CurrentPlot, input.SnapPoint) then
			updateGhostValidity(false)
			return
		end
		points = { input.SnapPoint }
		setActionType(Enums.ActionType.Step)
		notifyDesignModeChange()
		return
	end

	if actionType ~= Enums.ActionType.Step then return end
	if #points >= Formex.MaxFloorPoints then return end
	local nextPoint = input.SnapPoint
	if isPointOnOrInExistingFloor(FormexClient.CurrentPlot, nextPoint) then
		updateGhostValidity(false)
		return
	end
	if points[#points] and pointsEqual(points[#points], nextPoint) then return end
	table.insert(points, nextPoint)
end

function Manual.HandleSecondaryClick(input: any): boolean
	local actionType = getActionType()
	if actionType ~= Enums.ActionType.Start and actionType ~= Enums.ActionType.Step then return false end
	if #points > 0 then
		table.remove(points, #points)
		if #points == 0 then
			setActionType(Enums.ActionType.Start)
			notifyDesignModeChange()
		end
	end

	if input then
		Manual.HandleUpdate(input)
	end
	return true
end

return Manual
