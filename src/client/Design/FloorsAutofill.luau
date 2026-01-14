--!strict
--[[
FormexDesignFloorsAutofill
Autofill floor creation traces walls, floor edges, and plot boundaries to build a room polygon.

Algorithm overview (high level):
1) Collect segments (walls, floor perimeters, and the exterior of unlocked plot segments).
   - collectSegments(): gathers wall endpoints and floor edges already placed in the level.
   - addPlotBoundarySegments(): adds edges around the unlocked plot segments so exterior borders
     are treated like walls for tracing.
2) Split and dedupe segments at intersections so the graph is planar.
   - splitSegments(): finds intersections/overlaps, splits segments into atomic edges, and merges
     duplicates so face-walking is stable.
3) Remove dangling walls so interior bits don’t create fake boundaries.
   - pruneWallSegments(): iteratively removes wall segments whose endpoints do not connect to
     at least two other segments, which prevents partial walls from blocking autofill.
4) Build a planar directed-edge graph from segments.
   - buildDirectedEdges(): creates two directed edges per segment, stores adjacency by vertex,
     and computes a Next edge for consistent face-walks.
5) Extract all faces and choose the face containing the cursor.
   - buildFaces(): walks the directed-edge graph to find closed loops.
   - selectFaceForPoint(): picks the smallest face (by area) that contains the cursor.
   - getFaceSamplePoint(): finds an interior point (centroid, bounds center, or ear clip).
6) Validate and reject holes.
   - Any other face fully inside the selected polygon counts as a hole.
   - Faces that enclose the selected polygon (outer boundary) are ignored.
   - findContainedFloorBlocker(): also checks existing floors fully inside the polygon as holes.
7) Validate against Formex rules and expose errors.
   - Formex.IsTransactionValid(): final validation (simple polygon, within plot bounds, etc).
   - Hole previews reuse FormexDesignHighlights edge previews for a red outline.
Debugging:
- When DEBUG is true, HandlePrimaryClick runs a second trace that populates Autofill.DebugOutput
  with structured data to help diagnose failures.

Exports:
- Init(): load shared dependencies
- StartFloor(): ()
- CancelAction(): ()
- ClearSelection(): ()
- HandleUpdate(input): ()
- HandlePrimaryClick(input): ()
- HandleSecondaryClick(input): boolean
]]
local Formex = require(game:GetService("ReplicatedStorage"):WaitForChild("Formex"))
local Context = require(script.Parent:WaitForChild("Context"))

local Autofill = {}

local DEBUG = false
local DEBUG_OUTPUT: {[string]: any}? = nil

type Segment = {
	Start: Vector2int16,
	End: Vector2int16,
	Kind: "Wall" | "Floor",
	IsBoundary: boolean?,
}

type DirectedEdge = {
	Id: number,
	Start: Vector2int16,
	End: Vector2int16,
	StartKey: string,
	EndKey: string,
	Angle: number,
	Kind: "Wall" | "Floor",
	WallId: number?,
	FloorId: number?,
	IsBoundary: boolean?,
	NextId: number?,
	Visited: boolean,
}

type Face = {
	Points: {Vector2int16},
	Edges: {DirectedEdge},
	Area: number,
}

local FormexClient: any
local Formex: any
local Poly: any
local Highlight: any
local Enums: any

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
local setTipMessage: (string?) -> ()
local notifyDesignModeChange: () -> ()
local clearSelection: () -> ()
local clearGhost: () -> ()
local select: (Instance) -> boolean

local cachedPolygon: {Vector2int16}? = nil
local cachedValid = false
local cachedError: string? = nil
local cachedHolePoints: {Vector2int16}? = nil
local cachedPlotId: number? = nil
local cachedLevelIndex: number? = nil

local function setDebugOutput(output: {[string]: any}?)
	DEBUG_OUTPUT = output
	Autofill.DebugOutput = output
end

local function debugWrite(key: string, value: any)
	if not DEBUG_OUTPUT then return end
	DEBUG_OUTPUT[key] = value
end

local function debugMessage(message: string, data: any?)
	if not DEBUG_OUTPUT then return end
	local messages = DEBUG_OUTPUT.Messages
	if not messages then
		messages = {}
		DEBUG_OUTPUT.Messages = messages
	end
	table.insert(messages, {
		Message = message,
		Data = data,
	})
end

local function isArray(value: any): boolean
	if type(value) ~= "table" then return false end
	local count = 0
	for key, _ in pairs(value) do
		if type(key) ~= "number" then return false end
		count += 1
	end
	return count == #value
end

local function serializeValue(value: any, indent: number, visited: {[table]: boolean}): string
	local valueType = type(value)
	if valueType == "string" then
		return string.format("%q", value)
	elseif valueType == "number" or valueType == "boolean" then
		return tostring(value)
	elseif valueType ~= "table" then
		return string.format("<%s>", valueType)
	end

	if visited[value] then
		return "<cycle>"
	end
	visited[value] = true

	local pad = string.rep(" ", indent)
	local childPad = string.rep(" ", indent + 2)
	local lines = {}

	if isArray(value) then
		table.insert(lines, "[")
		for _, item in ipairs(value) do
			table.insert(lines, childPad .. serializeValue(item, indent + 2, visited) .. ",")
		end
		table.insert(lines, pad .. "]")
	else
		table.insert(lines, "{")
		local keys = {}
		for key in pairs(value) do
			table.insert(keys, key)
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		for _, key in ipairs(keys) do
			local renderedKey = type(key) == "string" and key or ("[" .. tostring(key) .. "]")
			table.insert(lines, childPad .. renderedKey .. " = " .. serializeValue(value[key], indent + 2, visited) .. ",")
		end
		table.insert(lines, pad .. "}")
	end

	return table.concat(lines, "\n")
end

local function debugFlush()
	if not DEBUG_OUTPUT then return end
	local output = serializeValue(DEBUG_OUTPUT, 0, {})
	print("[AutofillDebug]\n" .. output)
end

function Autofill.Init()
	local ctx = Context.Get()
	FormexClient = ctx.FormexClient
	Formex = ctx.Formex
	Poly = Formex.Poly
	Highlight = ctx.Highlight
	Enums = ctx.Enums

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
	setTipMessage = ctx.SetTipMessage
	notifyDesignModeChange = ctx.NotifyDesignModeChange
	clearSelection = ctx.ClearSelection
	clearGhost = ctx.ClearGhost
	select = ctx.Select
end

local function toVector2(point: Vector2int16): Vector2
	return Vector2.new(point.X, point.Y)
end

local function pointsEqual(a: Vector2int16, b: Vector2int16): boolean
	return Poly.PointsEqual(a, b)
end

local function cross2(a: Vector2, b: Vector2): number
	return a.X * b.Y - a.Y * b.X
end


local function toPointList(points: {Vector2int16}?): {{number}}
	if not points then
		return {}
	end
	local list = {}
	for _, point in ipairs(points) do
		table.insert(list, { point.X, point.Y })
	end
	return list
end

local function getLevelData(plotInfo: any, levelIndex: number): Formex.LevelData?
	if not plotInfo or not plotInfo.PlotData or not plotInfo.PlotData.Levels then return nil end
	return plotInfo.PlotData.Levels[levelIndex]
end

local function getLevelDebugData(plotInfo: any, levelIndex: number): ({[string]: any}, {[string]: any})
	local walls = {}
	local floors = {}
	local levelData = getLevelData(plotInfo, levelIndex)
	if not levelData then
		return walls, floors
	end

	if levelData.Walls then
		for _, wall in pairs(levelData.Walls) do
			table.insert(walls, {
				WallId = wall.WallId,
				Start = { wall.Start.X, wall.Start.Y },
				End = { wall.End.X, wall.End.Y },
			})
		end
	end

	if levelData.Floors then
		for _, floor in pairs(levelData.Floors) do
			local cleaned = floor.Points and Formex.Floors.CleanPolygon(floor.Points) or nil
			table.insert(floors, {
				FloorId = floor.FloorId,
				Points = toPointList(floor.Points),
				CleanedPoints = toPointList(cleaned),
			})
		end
	end

	return walls, floors
end

local function polygonArea(points: {Vector2int16}): number
	return Poly.PolygonArea(points)
end


local function isPointInsidePolygon(point: Vector2, polygon: {Vector2int16}, includeBoundary: boolean?): boolean
	return Poly.IsPointInsidePolygon(point, polygon, includeBoundary, Formex.EPSILON)
end


local function segmentsIntersect(p1: Vector2, p2: Vector2, q1: Vector2, q2: Vector2): boolean
	return Poly.SegmentsIntersect(p1, p2, q1, q2, Formex.EPSILON)
end

local function polygonsIntersect(a: {Vector2int16}, b: {Vector2int16}): boolean
	return Poly.PolygonsIntersect(a, b, Formex.EPSILON)
end

local function isPolygonInside(outer: {Vector2int16}, inner: {Vector2int16}): boolean
	return Poly.IsPolygonInside(outer, inner, Formex.EPSILON)
end

local function updateHolePreview(plotInfo: any, points: {Vector2int16}?)
	if points and #points >= 3 then
		Highlight.UpdateFloorHolePreview(plotInfo, getCurrentLevel(), points, getFloorRaiseHeight())
	else
		Highlight.ClearFloorHolePreview()
	end
end

local function buildFloorDataFromPoints(points: {Vector2int16}): Formex.FloorData
	return {
		FloorId = 0,
		LevelIndex = getCurrentLevel(),
		Points = table.clone(points),
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

local function isFloorDataValid(plotInfo: any, floorData: Formex.FloorData, action: Formex.BuildAction?): boolean
	if not plotInfo or not plotInfo.PlotData then return false end
	local validation = Formex.IsTransactionValid(plotInfo.PlotData, {
		{
			PartType = Formex.PartType.Floor,
			Action = action or Formex.BuildAction.Edit,
			Data = floorData,
		},
	})
	return validation ~= nil and validation.IsValid == true
end

local function collectSegments(plotInfo: any, levelIndex: number): ({Segment}, number)
	if not plotInfo or not plotInfo.PlotData then
		return {}, 0
	end
	return Poly.CollectSegments(Formex, plotInfo.PlotData, levelIndex, {
		IncludeWalls = true,
		IncludeFloors = true,
		IncludeBoundary = true,
		CleanPolygon = Formex.Floors.CleanPolygon,
	})
end

local function pruneWallSegments(segments: {Segment})
	Poly.PruneSegments(segments, Formex.EPSILON)
end

local function splitSegments(segments: {Segment}): {Segment}
	return Poly.SplitSegments(segments, Formex.EPSILON)
end

local function buildDirectedEdges(segments: {Segment}): {DirectedEdge}
	return Poly.BuildDirectedEdges(segments)
end

local function buildFaces(directedEdges: {DirectedEdge}): {Face}
	return Poly.BuildFaces(directedEdges)
end

local function selectFaceForPoint(faces: {Face}, point: Vector2): Face?
	local selected = nil
	for _, face in ipairs(faces) do
		if isPointInsidePolygon(point, face.Points, true) then
			if not selected or math.abs(face.Area) < math.abs(selected.Area) then
				selected = face
			end
		end
	end
	return selected
end

local function getFaceSamplePoint(points: {Vector2int16}): Vector2?
	if #points == 0 then return nil end
	local sumX = 0
	local sumY = 0
	local minX = points[1].X
	local maxX = points[1].X
	local minY = points[1].Y
	local maxY = points[1].Y
	for _, point in ipairs(points) do
		sumX += point.X
		sumY += point.Y
		minX = math.min(minX, point.X)
		maxX = math.max(maxX, point.X)
		minY = math.min(minY, point.Y)
		maxY = math.max(maxY, point.Y)
	end

	local centroid = Vector2.new(sumX / #points, sumY / #points)
	if isPointInsidePolygon(centroid, points, false) then return centroid end
	local center = Vector2.new((minX + maxX) / 2, (minY + maxY) / 2)
	if isPointInsidePolygon(center, points, false) then return center end
	local polygon = {}
	for _, point in ipairs(points) do
		table.insert(polygon, Vector2.new(point.X, point.Y))
	end
	if polygonArea(points) < 0 then
		local reversed = table.create(#polygon)
		for i = #polygon, 1, -1 do
			table.insert(reversed, polygon[i])
		end
		polygon = reversed
	end

	local function isPointInTriangle(point: Vector2, a: Vector2, b: Vector2, c: Vector2): boolean
		local ab = cross2(b - a, point - a)
		local bc = cross2(c - b, point - b)
		local ca = cross2(a - c, point - c)
		return ab >= -Formex.EPSILON and bc >= -Formex.EPSILON and ca >= -Formex.EPSILON
	end

	local indices = table.create(#polygon)
	for i = 1, #polygon do
		indices[i] = i
	end

	local guard = 0
	local maxGuard = #polygon * #polygon
	while #indices >= 3 and guard < maxGuard do
		guard += 1
		local earFound = false
		for i = 1, #indices do
			local prevIndex = indices[(i - 2 + #indices) % #indices + 1]
			local currIndex = indices[i]
			local nextIndex = indices[(i % #indices) + 1]
			local a = polygon[prevIndex]
			local b = polygon[currIndex]
			local c = polygon[nextIndex]

			if cross2(b - a, c - b) > Formex.EPSILON then
				local hasPointInside = false
				for j = 1, #indices do
					local idx = indices[j]
					if idx ~= prevIndex and idx ~= currIndex and idx ~= nextIndex then
						if isPointInTriangle(polygon[idx], a, b, c) then
							hasPointInside = true
							break
						end
					end
				end

				if not hasPointInside then
					local centroid2 = Vector2.new((a.X + b.X + c.X) / 3, (a.Y + b.Y + c.Y) / 3)
					if isPointInsidePolygon(centroid2, points, false) then return centroid2 end
					table.remove(indices, i)
					earFound = true
					break
				end
			end
		end

		if not earFound then
			break
		end
	end

	return nil
end

local function findContainedFloorBlocker(plotInfo: any, levelIndex: number, polygon: {Vector2int16}): (Instance?, {Vector2int16}?)
	local levelData = getLevelData(plotInfo, levelIndex)
	if not levelData or not levelData.Floors then
		return nil, nil
	end

	for _, floor in pairs(levelData.Floors) do
		if floor.Points and #floor.Points >= 3 then
			local cleaned = Formex.Floors.CleanPolygon(floor.Points)
			if #cleaned >= 3 then
				if isFloorDataValid(plotInfo, {
					FloorId = floor.FloorId,
					LevelIndex = levelIndex,
					Points = cleaned,
					RaiseHeight = floor.RaiseHeight or 0,
				} :: Formex.FloorData, Formex.BuildAction.Edit)
				and isPolygonInside(polygon, cleaned) then
					return floor.Model, cleaned
				end
			end
		end
	end

	return nil, nil
end

local function computeAutofill(
	plotInfo: any,
	levelIndex: number,
	cursorPoint: Vector2
): ({Vector2int16}?, boolean, string?, {Vector2int16}?)
	local function countSegments(list: {Segment})
		local counts = {
			Walls = 0,
			Floors = 0,
			Boundary = 0,
		}
		for _, segment in ipairs(list) do
			if segment.Kind == "Wall" then
				if segment.IsBoundary then
					counts.Boundary += 1
				else
					counts.Walls += 1
				end
			elseif segment.Kind == "Floor" then
				counts.Floors += 1
			end
		end
		return counts
	end

	debugWrite("Input", {
		PlotId = plotInfo and plotInfo.PlotId or nil,
		LevelIndex = levelIndex,
		Cursor = { cursorPoint.X, cursorPoint.Y },
	})
	local wallLines, floorPolygons = getLevelDebugData(plotInfo, levelIndex)
	debugWrite("LevelWalls", wallLines)
	debugWrite("LevelFloors", floorPolygons)

	local segments, boundaryCount = collectSegments(plotInfo, levelIndex)
	debugWrite("Segments", {
		Total = #segments,
		Boundary = boundaryCount,
		ByKind = countSegments(segments),
	})
	if #segments == 0 then
		debugMessage("No segments for trace.")
		return nil, false, "no-trace", nil
	end

	local split = splitSegments(segments)
	debugWrite("SplitSegments", {
		Total = #split,
		ByKind = countSegments(split),
	})
	if #split == 0 then
		debugMessage("Split segments empty.")
		return nil, false, "no-trace", nil
	end

	pruneWallSegments(split)
	debugWrite("PrunedSegments", {
		Total = #split,
	})
	if #split == 0 then
		debugMessage("Segments removed by pruning.")
		return nil, false, "no-trace", nil
	end

	local directedEdges = buildDirectedEdges(split)
	local faces = buildFaces(directedEdges)
	debugWrite("Faces", {
		Count = #faces,
	})
	if #faces == 0 then
		debugMessage("No faces after walk.")
		return nil, false, "no-trace", nil
	end

	local selected = selectFaceForPoint(faces, cursorPoint)
	if not selected then
		debugMessage("No face contains cursor.")
		return nil, false, "no-trace", nil
	end

	local cleaned = Formex.Floors.CleanPolygon(selected.Points)
	debugWrite("SelectedFace", {
		Area = selected.Area,
		CleanedPoints = #cleaned,
	})
	debugWrite("SelectedPolygonPoints", toPointList(cleaned))
	if #cleaned < 3 then
		debugMessage("Selected face cleaned to <3 points.")
		return nil, false, "no-trace", nil
	end
	if #cleaned > Formex.MaxFloorPoints then
		debugMessage("Selected face too complex.", { Count = #cleaned })
		return cleaned, false, "complex", nil
	end

	local selectedPoint = getFaceSamplePoint(cleaned)
	if selectedPoint then
		debugWrite("SelectedSamplePoint", { selectedPoint.X, selectedPoint.Y })
	end
	if not selectedPoint then
		debugMessage("Selected face has no interior sample.")
		return cleaned, false, "invalid", nil
	end

	local holePoints = nil :: {Vector2int16}?
	local holeStats = {
		Candidates = 0,
		InsideSelected = 0,
		EnclosingSelected = 0,
	}
	for _, face in ipairs(faces) do
		if face ~= selected then
			local candidate = Formex.Floors.CleanPolygon(face.Points)
			if #candidate >= 3 then
				holeStats.Candidates += 1
				if isPolygonInside(candidate, cleaned) then
					holeStats.EnclosingSelected += 1
				elseif isPolygonInside(cleaned, candidate) then
					holeStats.InsideSelected += 1
					holePoints = candidate
					break
				end
			end
		end
	end
	debugWrite("HoleStats", holeStats)

	if holePoints then
		debugWrite("HolePolygonPoints", toPointList(holePoints))
		debugMessage("Hole detected from traced faces.")
		return cleaned, false, "hole", holePoints
	end

	local _floorHole, floorHolePoints = findContainedFloorBlocker(plotInfo, levelIndex, cleaned)
	if floorHolePoints then
		debugWrite("HolePolygonPoints", toPointList(floorHolePoints))
		debugMessage("Hole detected from contained floor.")
		return cleaned, false, "hole", floorHolePoints
	end

	local isValid = isFloorDataValid(plotInfo, buildFloorDataFromPoints(cleaned), Formex.BuildAction.Add)
	if not isValid then
		debugMessage("IsTransactionValid rejected.")
		return cleaned, false, "invalid", nil
	end

	return cleaned, true, nil, nil
end

local function resetCache()
	cachedPolygon = nil
	cachedValid = false
	cachedError = nil
	cachedHolePoints = nil
	cachedPlotId = nil
	cachedLevelIndex = nil
	Highlight.ClearFloorHolePreview()
	setTipMessage(nil)
	if not DEBUG then
		setDebugOutput(nil)
	end
end

local function applyPreview(
	plotInfo: any,
	points: {Vector2int16}?,
	isValid: boolean,
	errorReason: string?,
	holePoints: {Vector2int16}?
)
	if not points or #points < 3 then
		Highlight.ClearFloorEdgePreview()
		updateHolePreview(plotInfo, nil)
		if errorReason == "no-trace" then
			setTipMessage("Autofill could not find a closed room here.")
		else
			setTipMessage(nil)
		end
		return
	end

	Highlight.UpdateFloorEdgePreview(plotInfo, getCurrentLevel(), points, isValid, getFloorRaiseHeight())
	updateHolePreview(plotInfo, holePoints)

	if errorReason == "complex" then
		setTipMessage("Floor is too complex for Autofill.")
	elseif errorReason == "hole" then
		setTipMessage("Floors cannot contain holes.")
	elseif errorReason == "invalid" then
		setTipMessage("Autofill outline is invalid for this plot.")
	elseif errorReason == "no-trace" then
		setTipMessage("Autofill could not find a closed room here.")
	else
		setTipMessage(nil)
	end
end

local function getCursorLocalPoint(plotInfo: any, input: any): Vector2?
	if not plotInfo or not plotInfo.PlotPart then return nil end
	if input and input.HitPosition then
		local localPosition = plotInfo.PlotPart.CFrame:PointToObjectSpace(input.HitPosition)
		return Vector2.new(localPosition.X, localPosition.Z)
	end
	if input and input.LayoutTile then
		local tileSize = Formex.LayoutGridSize
		local halfWidth = Formex.Dimensions.Width / 2
		local halfDepth = Formex.Dimensions.Depth / 2
		local centerX = input.LayoutTile.X * tileSize - halfWidth + (tileSize / 2)
		local centerY = input.LayoutTile.Y * tileSize - halfDepth + (tileSize / 2)
		return Vector2.new(centerX, centerY)
	end
	return nil
end

local function updatePreview(input: any)
	if not input or not input.PlotInfo then
		Highlight.ClearFloorEdgePreview()
		Highlight.ClearFloorHolePreview()
		setTipMessage(nil)
		return
	end

	local plotInfo = input.PlotInfo
	local levelIndex = getCurrentLevel()
	local cursorPoint = getCursorLocalPoint(plotInfo, input)
	if not cursorPoint then
		Highlight.ClearFloorEdgePreview()
		Highlight.ClearFloorHolePreview()
		setTipMessage(nil)
		return
	end

	if cachedPolygon
	and cachedPlotId == plotInfo.PlotId
	and cachedLevelIndex == levelIndex
	and isPointInsidePolygon(cursorPoint, cachedPolygon, true) then
		applyPreview(plotInfo, cachedPolygon, cachedValid, cachedError, cachedHolePoints)
		return
	end

	setDebugOutput(nil)
	local points, isValid, errorReason, holePoints = computeAutofill(plotInfo, levelIndex, cursorPoint)
	cachedPolygon = points
	cachedValid = isValid
	cachedError = errorReason
	cachedHolePoints = holePoints
	cachedPlotId = plotInfo.PlotId
	cachedLevelIndex = levelIndex

	applyPreview(plotInfo, points, isValid, errorReason, holePoints)
end

local function finalizeAutofill()
	if not cachedPolygon or not cachedValid then
		if cachedError then
			applyPreview(FormexClient.CurrentPlot, cachedPolygon, false, cachedError, cachedHolePoints)
		end
		return
	end

	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid then return end
	local floorData = buildFloorDataFromPoints(cachedPolygon)
	local result = buildFloor(floorData, getSelectionSnapshot())
	selectAfterFloorBuild(plotInfo, floorData.LevelIndex, floorData.Points, result)
	resetCache()
	setActionType(Enums.ActionType.Select)
	clearGhost()
	notifyDesignModeChange()
end

function Autofill.StartFloor()
	resetCache()
	clearSelection()
	clearGhost()
	setActionType(Enums.ActionType.Start)
	notifyDesignModeChange()
end

function Autofill.CancelAction()
	resetCache()
	clearGhost()
	setActionType(Enums.ActionType.Select)
	notifyDesignModeChange()
end

function Autofill.ClearSelection()
	resetCache()
end

function Autofill.HandleUpdate(input: any)
	if getActionType() ~= Enums.ActionType.Start then return end
	updatePreview(input)
end

function Autofill.HandlePrimaryClick(_input: any)
	if getActionType() ~= Enums.ActionType.Start then return end
	local selected = _input and _input.FloorData and select(_input) or false
	if selected then
		Autofill.CancelAction()
		return
	end
	if DEBUG then
		local plotInfo = FormexClient.CurrentPlot
		local cursorPoint = getCursorLocalPoint(plotInfo, _input)
		setDebugOutput({})
		if plotInfo and plotInfo.IsValid and cursorPoint then
			local points, isValid, errorReason, holePoints = computeAutofill(plotInfo, getCurrentLevel(), cursorPoint)
			debugWrite("Result", {
				Valid = isValid,
				Error = errorReason,
				Points = points and #points or 0,
				HolePoints = holePoints and #holePoints or 0,
			})
		else
			debugWrite("Result", {
				Valid = false,
				Error = "no-input",
			})
		end
		debugFlush()
	end
	finalizeAutofill()
end

function Autofill.HandleSecondaryClick(_input: any): boolean
	if getActionType() ~= Enums.ActionType.Start then return false end
	Autofill.CancelAction()
	return true
end

Autofill.DebugOutput = nil

return Autofill
