--!strict
--[[
FormexDesignHighlights
Renders selection highlights and edge previews for walls/floors.
Exports:
- Init(): load shared dependencies
- IsHighlightInstance(instance): boolean
- UpdateSelectionHighlight(): ()
- UpdateFloorEdgePreview(plotInfo, levelIndex, points, isValid, raiseHeight): ()
- UpdateFloorHolePreview(plotInfo, levelIndex, points, raiseHeight): ()
- UpdateWallEdgePreview(plotInfo, levelIndex, startPoint, endPoint, isValid): ()
- ClearFloorEdgePreview(): ()
- ClearFloorHolePreview(): ()
]]
local Context = require(script.Parent:WaitForChild("FormexDesignContext"))
local FormexDesignHighlights = {}

local Formex: any
local OverlayFolder: Folder
local Constants: any
local Enums: any
local getDesignMode: () -> string
local getSelectionPart: () -> Instance?
local isGhostActive: () -> boolean
local isGhostValid: () -> boolean
local getGhostInstance: () -> Instance?

local ENABLE_WALL_SELECTION_HIGHLIGHT = false
local ENABLE_FLOOR_SELECTION_HIGHLIGHT = false

local selectionHighlight: Highlight? = nil
local edgeParts = {} :: {BasePart}
local edgeHighlights = {} :: {Highlight}
local holeEdgeParts = {} :: {BasePart}
local holeEdgeHighlights = {} :: {Highlight}

function FormexDesignHighlights.Init()
	local ctx = Context.Get()
	Formex = ctx.Formex
	OverlayFolder = ctx.OverlayFolder
	Constants = ctx.Constants
	Enums = ctx.Enums
	getDesignMode = ctx.GetDesignMode
	getSelectionPart = ctx.GetSelectionPart
	isGhostActive = ctx.IsGhostActive
	isGhostValid = ctx.IsGhostValid
	getGhostInstance = ctx.GetGhostInstance
end

local function ensureSelectionHighlight(): Highlight
	if selectionHighlight and selectionHighlight.Parent then
		return selectionHighlight
	end

	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 0
	highlight.OutlineColor = Constants.SelectionColor
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = OverlayFolder
	selectionHighlight = highlight
	return highlight
end

function FormexDesignHighlights.IsHighlightInstance(instance: Instance?): boolean
	if not instance then
		return false
	end
	return selectionHighlight ~= nil and instance == selectionHighlight
end

function FormexDesignHighlights.UpdateSelectionHighlight()
	if not Formex or not OverlayFolder or not Constants then
		return
	end

	local highlight = ensureSelectionHighlight()
	local highlightEnabled = true
	if getDesignMode and Enums and Enums.DesignMode then
		local designMode = getDesignMode()
		if designMode == Enums.DesignMode.Wall then
			highlightEnabled = ENABLE_WALL_SELECTION_HIGHLIGHT
		elseif designMode == Enums.DesignMode.Floor then
			highlightEnabled = ENABLE_FLOOR_SELECTION_HIGHLIGHT
		end
	end

	if not highlightEnabled then
		highlight.Adornee = nil
		highlight.Enabled = false
		return
	end

	local ghost = getGhostInstance and getGhostInstance() or nil

	if ghost and isGhostActive() then
		highlight.Adornee = ghost
		highlight.OutlineColor = isGhostValid() and Constants.GhostValidColor or Constants.GhostInvalidColor
		highlight.Enabled = true
		return
	end

	local selectionPart = getSelectionPart and getSelectionPart() or nil
	if selectionPart then
		highlight.Adornee = selectionPart
		highlight.OutlineColor = Constants.SelectionColor
		highlight.Enabled = true
		return
	end

	highlight.Adornee = nil
	highlight.Enabled = false
end

local function clearEdgePreviews(edgeList: {BasePart}, highlightList: {Highlight})
	for _, part in ipairs(edgeList) do
		if part and part.Parent then
			part:Destroy()
		end
	end
	for _, highlight in ipairs(highlightList) do
		if highlight and highlight.Parent then
			highlight:Destroy()
		end
	end
	for index = #edgeList, 1, -1 do
		edgeList[index] = nil
	end
	for index = #highlightList, 1, -1 do
		highlightList[index] = nil
	end
end

local function ensureEdgePreview(edgeList: {BasePart}, highlightList: {Highlight}, index: number, nameSuffix: string): (BasePart, Highlight)
	local part = edgeList[index]
	local highlight = highlightList[index]

	if not part or not part.Parent then
		part = Instance.new("Part")
		part.Name = "FloorEdge_" .. nameSuffix .. "_" .. tostring(index)
		part.Shape = Enum.PartType.Block
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Material = Enum.Material.Metal
		part.Parent = OverlayFolder
		edgeList[index] = part
	end

	if not highlight or not highlight.Parent then
		highlight = Instance.new("Highlight")
		highlight.Name = "FloorEdgeHighlight_" .. nameSuffix
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.OutlineTransparency = 0
		highlight.FillTransparency = 0.35
		highlight.Adornee = part
		highlight.Parent = part
		highlightList[index] = highlight
	end

	return part, highlight
end

local function updateEdgePreview(
	plotInfo: any,
	levelIndex: number,
	points: {Vector2int16},
	isValid: boolean,
	closed: boolean,
	heightOffset: number?,
	edgeList: {BasePart},
	highlightList: {Highlight},
	nameSuffix: string
)
	if not plotInfo or not plotInfo.PlotPart or not points or #points < 2 then
		clearEdgePreviews(edgeList, highlightList)
		return
	end

	local edgeCount = closed and #points or (#points - 1)
	if edgeCount <= 0 then
		clearEdgePreviews(edgeList, highlightList)
		return
	end

	local color = isValid and Constants.GhostValidColor or Constants.GhostInvalidColor
	local thickness = 0.15
	local elevation = 0.1
	local y = Formex.LevelHeight * (levelIndex - 1) + elevation
	if heightOffset and heightOffset > 0 then
		y += heightOffset
	end

	for index = 1, edgeCount do
		local nextIndex = index + 1
		if closed and index == #points then
			nextIndex = 1
		end
		local startPoint = points[index]
		local endPoint = points[nextIndex]
		local dir = Vector3.new(endPoint.X - startPoint.X, 0, endPoint.Y - startPoint.Y)
		local part, highlight = ensureEdgePreview(edgeList, highlightList, index, nameSuffix)

		part.Color = color
		highlight.FillColor = color
		highlight.OutlineColor = color

		if dir.Magnitude <= Constants.Epsilon then
			part.Size = Vector3.new(0, 0, 0)
			part.CFrame = plotInfo.PlotPart.CFrame * CFrame.new(0, -10000, 0)
			continue
		end

		local mid = Vector3.new((startPoint.X + endPoint.X) / 2, y, (startPoint.Y + endPoint.Y) / 2)
		local up = dir.Unit
		local right = Vector3.yAxis:Cross(up)
		if right.Magnitude <= Constants.Epsilon then
			right = Vector3.xAxis
		else
			right = right.Unit
		end
		local back = up:Cross(right)

		part.Size = Vector3.new(thickness, dir.Magnitude, thickness)
		part.CFrame = plotInfo.PlotPart.CFrame * CFrame.fromMatrix(mid, right, up, back)
	end

	for index = edgeCount + 1, #edgeList do
		local part = edgeList[index]
		if part and part.Parent then
			part:Destroy()
		end
		local highlight = highlightList[index]
		if highlight and highlight.Parent then
			highlight:Destroy()
		end
		edgeList[index] = nil
		highlightList[index] = nil
	end
end

function FormexDesignHighlights.UpdateFloorEdgePreview(
	plotInfo: any,
	levelIndex: number,
	points: {Vector2int16},
	isValid: boolean,
	raiseHeight: number?
)
	updateEdgePreview(plotInfo, levelIndex, points, isValid, true, raiseHeight, edgeParts, edgeHighlights, "Main")
end

function FormexDesignHighlights.UpdateWallEdgePreview(plotInfo: any, levelIndex: number, startPoint: Vector2int16, endPoint: Vector2int16, isValid: boolean)
	updateEdgePreview(plotInfo, levelIndex, { startPoint, endPoint }, isValid, false, nil, edgeParts, edgeHighlights, "Wall")
end

function FormexDesignHighlights.ClearFloorEdgePreview()
	clearEdgePreviews(edgeParts, edgeHighlights)
end

function FormexDesignHighlights.UpdateFloorHolePreview(
	plotInfo: any,
	levelIndex: number,
	points: {Vector2int16},
	raiseHeight: number?
)
	updateEdgePreview(plotInfo, levelIndex, points, false, true, raiseHeight, holeEdgeParts, holeEdgeHighlights, "Hole")
end

function FormexDesignHighlights.ClearFloorHolePreview()
	clearEdgePreviews(holeEdgeParts, holeEdgeHighlights)
end

return FormexDesignHighlights
