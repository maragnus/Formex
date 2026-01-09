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
local updateGhostValidity: (boolean) -> ()
local clearGhost: () -> ()
local clearSelection: () -> ()
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
	updateGhostValidity = ctx.UpdateGhostValidity
	clearGhost = ctx.ClearGhost
	clearSelection = ctx.ClearSelection
	notifyDesignModeChange = ctx.NotifyDesignModeChange
end

local function pointsEqual(a: Vector2int16, b: Vector2int16): boolean
	return a.X == b.X and a.Y == b.Y
end

local function getBaseY(levelIndex: number): number
	return Formex.LevelHeight * (levelIndex - 1) + getFloorRaiseHeight()
end

local function createGhostBall(name: string, color: Color3): BasePart
	local part = Instance.new("Part")
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
	part.Parent = OverlayFolder
	return part
end

local function setGhostBallColor(part: BasePart?, color: Color3)
	if not part then
		return
	end
	part.Color = color
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
		return true
	end
	return Formex.Floors.IsValid(plotInfo :: any, { Points = previewPoints } :: any)
end

local function updateGhosts(plotInfo: any, cursorPoint: Vector2int16?)
	if not plotInfo or not plotInfo.PlotPart then
		return
	end

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
	if not plotInfo or not plotInfo.IsValid then
		return
	end
	if #points < 3 then
		return
	end

	local floorData = buildFloorDataFromPoints(points)
	local isValid = Formex.Floors.IsValid(plotInfo :: any, floorData)
	if not isValid then
		updateGhostValidity(false)
		return
	end

	FormexClient.BuildFloor(floorData, Formex.BuildAction.Add, getSelectionSnapshot())
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
	if not input or not input.PlotInfo then
		return
	end

	local actionType = getActionType()
	if actionType ~= Enums.ActionType.Start and actionType ~= Enums.ActionType.Step then
		return
	end

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
	if not input or not input.SnapPoint then
		return
	end

	local actionType = getActionType()
	if actionType == Enums.ActionType.Start then
		points = { input.SnapPoint }
		setActionType(Enums.ActionType.Step)
		notifyDesignModeChange()
		return
	end

	if actionType ~= Enums.ActionType.Step then
		return
	end

	if #points >= Formex.MaxFloorPoints then
		return
	end

	local nextPoint = input.SnapPoint
	if points[#points] and pointsEqual(points[#points], nextPoint) then
		return
	end

	table.insert(points, nextPoint)
end

function Manual.HandleSecondaryClick(input: any): boolean
	local actionType = getActionType()
	if actionType ~= Enums.ActionType.Start and actionType ~= Enums.ActionType.Step then
		return false
	end

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
