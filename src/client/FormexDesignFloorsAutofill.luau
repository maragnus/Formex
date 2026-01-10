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
   - Formex.Floors.IsFloorValid(): final validation (simple polygon, within plot bounds, etc).
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
local Context = require(script.Parent:WaitForChild("FormexDesignContext"))
local Formex = Context.Formex

local Autofill = {}

local DEBUG = false
local DEBUG_OUTPUT: {[string]: any}? = nil

type BlockerKind = "Wall" | "Floor"

type Segment = {
	Start: Vector2int16,
	End: Vector2int16,
	Blocker: Instance?,
	BlockerKind: BlockerKind?,
}

type DirectedEdge = {
	Id: number,
	Start: Vector2int16,
	End: Vector2int16,
	StartKey: string,
	EndKey: string,
	Angle: number,
	Blocker: Instance?,
	BlockerKind: BlockerKind?,
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
local setTipMessage: (string?) -> ()
local notifyDesignModeChange: () -> ()
local clearSelection: () -> ()
local clearGhost: () -> ()
local select: (Instance) -> boolean
local selectPlotModelByIdAsync: (any, string, number, number, number?) -> ()

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
	if not DEBUG_OUTPUT then
		return
	end
	DEBUG_OUTPUT[key] = value
end

local function debugMessage(message: string, data: any?)
	if not DEBUG_OUTPUT then
		return
	end
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
	if type(value) ~= "table" then
		return false
	end
	local count = 0
	for key, _ in pairs(value) do
		if type(key) ~= "number" then
			return false
		end
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
	if not DEBUG_OUTPUT then
		return
	end
	local output = serializeValue(DEBUG_OUTPUT, 0, {})
	print("[AutofillDebug]\n" .. output)
end

function Autofill.Init()
	local ctx = Context.Get()
	FormexClient = ctx.FormexClient
	Formex = ctx.Formex
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
	setTipMessage = ctx.SetTipMessage
	notifyDesignModeChange = ctx.NotifyDesignModeChange
	clearSelection = ctx.ClearSelection
	clearGhost = ctx.ClearGhost
	select = ctx.Select
	selectPlotModelByIdAsync = ctx.SelectPlotModelByIdAsync
end

local function getPointKey(point: Vector2int16): string
	return tostring(point.X) .. "," .. tostring(point.Y)
end

local function toVector2(point: Vector2int16): Vector2
	return Vector2.new(point.X, point.Y)
end

local function pointsEqual(a: Vector2int16, b: Vector2int16): boolean
	return a.X == b.X and a.Y == b.Y
end

local function cross2(a: Vector2, b: Vector2): number
	return a.X * b.Y - a.Y * b.X
end

local function isPointOnSegment(point: Vector2, a: Vector2, b: Vector2): boolean
	if math.abs(cross2(b - a, point - a)) > Formex.EPSILON then
		return false
	end
	return math.min(a.X, b.X) - Formex.EPSILON <= point.X and point.X <= math.max(a.X, b.X) + Formex.EPSILON
		and math.min(a.Y, b.Y) - Formex.EPSILON <= point.Y and point.Y <= math.max(a.Y, b.Y) + Formex.EPSILON
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

local function selectFloorAfterBuild(plotInfo: any, levelIndex: number, floorId: number?)
	if not plotInfo or not floorId then
		return
	end

	selectPlotModelByIdAsync(plotInfo, Enums.SelectionType.Floor, levelIndex, floorId)
end

local function getLevelData(plotInfo: any, levelIndex: number): Formex.LevelData?
	if not plotInfo or not plotInfo.PlotData or not plotInfo.PlotData.Levels then
		return nil
	end
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
	local area = 0
	for i = 1, #points do
		local nextIndex = (i % #points) + 1
		local a = points[i]
		local b = points[nextIndex]
		area += (a.X * b.Y) - (b.X * a.Y)
	end
	return area / 2
end

local function isPointOnPolygonEdge(point: Vector2, polygon: {Vector2int16}): boolean
	for i = 1, #polygon do
		local a = toVector2(polygon[i])
		local b = toVector2(polygon[(i % #polygon) + 1])
		if isPointOnSegment(point, a, b) then
			return true
		end
	end
	return false
end

local function isPointInsidePolygon(point: Vector2, polygon: {Vector2int16}, includeBoundary: boolean?): boolean
	if #polygon < 3 then
		return false
	end

	if isPointOnPolygonEdge(point, polygon) then
		return includeBoundary == true
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
	if math.abs(value) <= Formex.EPSILON then
		return 0
	end
	return value > 0 and 1 or 2
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

	if o1 ~= o2 and o3 ~= o4 then
		return true
	end

	if o1 == 0 and onSegment(p1, q1, p2) then return true end
	if o2 == 0 and onSegment(p1, q2, p2) then return true end
	if o3 == 0 and onSegment(q1, p1, q2) then return true end
	if o4 == 0 and onSegment(q1, p2, q2) then return true end

	return false
end

local function polygonsIntersect(a: {Vector2int16}, b: {Vector2int16}): boolean
	if #a < 2 or #b < 2 then
		return false
	end

	for i = 1, #a do
		local a1 = toVector2(a[i])
		local a2 = toVector2(a[(i % #a) + 1])
		for j = 1, #b do
			local b1 = toVector2(b[j])
			local b2 = toVector2(b[(j % #b) + 1])
			if segmentsIntersect(a1, a2, b1, b2) then
				return true
			end
		end
	end

	return false
end

local function isPolygonInside(outer: {Vector2int16}, inner: {Vector2int16}): boolean
	if #inner < 3 or #outer < 3 then
		return false
	end

	if polygonsIntersect(outer, inner) then
		return false
	end

	for _, point in ipairs(inner) do
		if not isPointInsidePolygon(Vector2.new(point.X, point.Y), outer, false) then
			return false
		end
	end

	return true
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

local function collectSegments(plotInfo: any, levelIndex: number): {Segment}
	local segments = {}
	local levelData = getLevelData(plotInfo, levelIndex)
	if not levelData then
		return segments
	end

	if levelData.Walls then
		for _, wall in pairs(levelData.Walls) do
			if wall.Start and wall.End and not pointsEqual(wall.Start, wall.End) then
				table.insert(segments, {
					Start = wall.Start,
					End = wall.End,
					Blocker = wall.Part,
					BlockerKind = "Wall",
				})
			end
		end
	end

	if levelData.Floors then
		for _, floor in pairs(levelData.Floors) do
			if floor.Points and #floor.Points >= 3 then
				local cleaned = Formex.Floors.CleanPolygon(floor.Points)
				if #cleaned >= 3 then
					for i = 1, #cleaned do
						local a = cleaned[i]
						local b = cleaned[(i % #cleaned) + 1]
						if not pointsEqual(a, b) then
							table.insert(segments, {
								Start = a,
								End = b,
								Blocker = floor.Model,
								BlockerKind = "Floor",
							})
						end
					end
				end
			end
		end
	end

	return segments
end

local function computeDegrees(segments: {Segment}): {[string]: number}
	local degrees = {}
	for _, seg in ipairs(segments) do
		local startKey = getPointKey(seg.Start)
		local endKey = getPointKey(seg.End)
		degrees[startKey] = (degrees[startKey] or 0) + 1
		degrees[endKey] = (degrees[endKey] or 0) + 1
	end
	return degrees
end

local function pruneWallSegments(segments: {Segment})
	local changed = true
	while changed do
		changed = false
		local degrees = computeDegrees(segments)
		for i = #segments, 1, -1 do
			local seg = segments[i]
			if seg.BlockerKind == "Wall" then
				local startDegree = degrees[getPointKey(seg.Start)] or 0
				local endDegree = degrees[getPointKey(seg.End)] or 0
				if startDegree < 2 or endDegree < 2 then
					table.remove(segments, i)
					changed = true
				end
			end
		end
	end
end

local function addPlotBoundarySegments(plotInfo: any, segments: {Segment}): number
	if not plotInfo then
		return 0
	end

	local mask = plotInfo.SegmentsUnlocked
	if not mask or mask == 0 then
		return 0
	end

	local edgeMap = {} :: {[string]: Segment}

	local function canonicalKey(a: Vector2int16, b: Vector2int16): string
		local aKey = getPointKey(a)
		local bKey = getPointKey(b)
		if aKey < bKey then
			return aKey .. "|" .. bKey
		end
		return bKey .. "|" .. aKey
	end

	local function toggleEdge(a: Vector2int16, b: Vector2int16)
		local key = canonicalKey(a, b)
		if edgeMap[key] then
			edgeMap[key] = nil
		else
			edgeMap[key] = {
				Start = a,
				End = b,
				Blocker = nil,
				BlockerKind = "Wall",
			}
		end
	end

	local halfWidth = Formex.SegmentSize.Width / 2
	local halfDepth = Formex.SegmentSize.Depth / 2

	for index = 1, Formex.Segments.Count do
		if Formex.Segments.IsUnlocked(mask, index) then
			local row, column = Formex.Segments.GetRowColumn(index)
			local centerX = (column - (Formex.Segments.GridWidth + 1) / 2) * Formex.SegmentSize.Width
			local centerY = (row - (Formex.Segments.GridHeight + 1) / 2) * Formex.SegmentSize.Depth
			local minX = centerX - halfWidth
			local maxX = centerX + halfWidth
			local minY = centerY - halfDepth
			local maxY = centerY + halfDepth

			local a = Vector2int16.new(minX, minY)
			local b = Vector2int16.new(maxX, minY)
			local c = Vector2int16.new(maxX, maxY)
			local d = Vector2int16.new(minX, maxY)

			toggleEdge(a, b)
			toggleEdge(b, c)
			toggleEdge(c, d)
			toggleEdge(d, a)
		end
	end

	local added = 0
	for _, segment in pairs(edgeMap) do
		table.insert(segments, segment)
		added += 1
	end

	return added
end

local function splitSegments(segments: {Segment}): {Segment}
	local entries = table.create(#segments)
	local pointMaps = table.create(#segments)

	for index, segment in ipairs(segments) do
		entries[index] = segment
		local map = {}
		map[getPointKey(segment.Start)] = segment.Start
		map[getPointKey(segment.End)] = segment.End
		pointMaps[index] = map
	end

	local function addPoint(map: {[string]: Vector2int16}, point: Vector2int16)
		map[getPointKey(point)] = point
	end

	for i = 1, #entries do
		local segA = entries[i]
		local a1 = toVector2(segA.Start)
		local a2 = toVector2(segA.End)
		for j = i + 1, #entries do
			local segB = entries[j]
			local b1 = toVector2(segB.Start)
			local b2 = toVector2(segB.End)
			local r = a2 - a1
			local s = b2 - b1
			local rxs = cross2(r, s)
			local qpxr = cross2(b1 - a1, r)

			if math.abs(rxs) <= Formex.EPSILON and math.abs(qpxr) <= Formex.EPSILON then
				if isPointOnSegment(a1, b1, b2) then
					addPoint(pointMaps[j], segA.Start)
				end
				if isPointOnSegment(a2, b1, b2) then
					addPoint(pointMaps[j], segA.End)
				end
				if isPointOnSegment(b1, a1, a2) then
					addPoint(pointMaps[i], segB.Start)
				end
				if isPointOnSegment(b2, a1, a2) then
					addPoint(pointMaps[i], segB.End)
				end
			elseif math.abs(rxs) > Formex.EPSILON then
				local t = cross2(b1 - a1, s) / rxs
				local u = cross2(b1 - a1, r) / rxs
				if t >= -Formex.EPSILON and t <= 1 + Formex.EPSILON and u >= -Formex.EPSILON and u <= 1 + Formex.EPSILON then
					local intersection = a1 + r * t
					local ix = math.round(intersection.X)
					local iy = math.round(intersection.Y)
					if math.abs(intersection.X - ix) <= Formex.EPSILON and math.abs(intersection.Y - iy) <= Formex.EPSILON then
						local point = Vector2int16.new(ix, iy)
						addPoint(pointMaps[i], point)
						addPoint(pointMaps[j], point)
					end
				end
			end
		end
	end

	local deduped = {}
	local segmentMap = {} :: {[string]: Segment}
	for index, segment in ipairs(entries) do
		local points = {}
		for _, point in pairs(pointMaps[index]) do
			table.insert(points, point)
		end
		if #points >= 2 then
			local start = toVector2(segment.Start)
			local dir = toVector2(segment.End) - start
			local length2 = dir:Dot(dir)
			table.sort(points, function(a, b)
				if length2 <= Formex.EPSILON then
					return false
				end
				local ta = (toVector2(a) - start):Dot(dir) / length2
				local tb = (toVector2(b) - start):Dot(dir) / length2
				return ta < tb
			end)

			for i = 1, #points - 1 do
				local a = points[i]
				local b = points[i + 1]
				if not pointsEqual(a, b) then
					local aKey = getPointKey(a)
					local bKey = getPointKey(b)
					local key = aKey < bKey and (aKey .. "|" .. bKey) or (bKey .. "|" .. aKey)
					local existing = segmentMap[key]
					if not existing then
						local newSegment = {
							Start = a,
							End = b,
							Blocker = segment.Blocker,
							BlockerKind = segment.BlockerKind,
						}
						segmentMap[key] = newSegment
						table.insert(deduped, newSegment)
					elseif existing.BlockerKind ~= "Wall" and segment.BlockerKind == "Wall" then
						existing.BlockerKind = "Wall"
						existing.Blocker = segment.Blocker or existing.Blocker
					end
				end
			end
		end
	end

	return deduped
end

local function buildDirectedEdges(segments: {Segment}): {DirectedEdge}
	local directedEdges = {}
	local adjacency = {}

	local function addDirected(startPoint: Vector2int16, endPoint: Vector2int16, blocker: Instance?, kind: BlockerKind?)
		local id = #directedEdges + 1
		local edge = {
			Id = id,
			Start = startPoint,
			End = endPoint,
			StartKey = getPointKey(startPoint),
			EndKey = getPointKey(endPoint),
			Angle = math.atan2(endPoint.Y - startPoint.Y, endPoint.X - startPoint.X),
			Blocker = blocker,
			BlockerKind = kind,
			NextId = nil,
			Visited = false,
		} :: DirectedEdge
		directedEdges[id] = edge
		local list = adjacency[edge.StartKey]
		if not list then
			list = {}
			adjacency[edge.StartKey] = list
		end
		table.insert(list, id)
	end

	for _, seg in ipairs(segments) do
		addDirected(seg.Start, seg.End, seg.Blocker, seg.BlockerKind)
		addDirected(seg.End, seg.Start, seg.Blocker, seg.BlockerKind)
	end

	for _, list in pairs(adjacency) do
		table.sort(list, function(aId, bId)
			return directedEdges[aId].Angle < directedEdges[bId].Angle
		end)
	end

	for _, edge in ipairs(directedEdges) do
		local list = adjacency[edge.EndKey]
		if not list then
			continue
		end
		local reverseIndex = nil
		for i, id in ipairs(list) do
			local candidate = directedEdges[id]
			if candidate.EndKey == edge.StartKey then
				reverseIndex = i
				break
			end
		end
		if reverseIndex then
			local nextIndex = reverseIndex - 1
			if nextIndex < 1 then
				nextIndex = #list
			end
			edge.NextId = list[nextIndex]
		end
	end

	return directedEdges
end

local function buildFaces(directedEdges: {DirectedEdge}): {Face}
	local faces = {}
	local maxSteps = #directedEdges + 5

	for _, edge in ipairs(directedEdges) do
		if edge.Visited or not edge.NextId then
			continue
		end

		local points = {}
		local edges = {}
		local current = edge
		local steps = 0
		local closed = false

		while current and not current.Visited and steps < maxSteps do
			steps += 1
			current.Visited = true
			table.insert(points, current.Start)
			table.insert(edges, current)
			if current.NextId == nil then
				break
			end
			current = directedEdges[current.NextId]
			if current == edge then
				closed = true
				break
			end
		end

		if closed and #points >= 3 then
			table.insert(faces, {
				Points = points,
				Edges = edges,
				Area = polygonArea(points),
			})
		end
	end

	return faces
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
	if #points == 0 then
		return nil
	end

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
	if isPointInsidePolygon(centroid, points, false) then
		return centroid
	end

	local center = Vector2.new((minX + maxX) / 2, (minY + maxY) / 2)
	if isPointInsidePolygon(center, points, false) then
		return center
	end

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
					if isPointInsidePolygon(centroid2, points, false) then
						return centroid2
					end
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

local function findHoleBlockerFromFace(face: Face): Instance?
	for _, edge in ipairs(face.Edges) do
		if edge.Blocker and edge.BlockerKind == "Wall" then
			return edge.Blocker
		end
	end
	for _, edge in ipairs(face.Edges) do
		if edge.Blocker and edge.BlockerKind == "Floor" then
			return edge.Blocker
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
				if Formex.Floors.IsFloorValid(plotInfo.PlotData, { Points = cleaned } :: any)
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
			if segment.BlockerKind == "Wall" then
				if segment.Blocker == nil then
					counts.Boundary += 1
				else
					counts.Walls += 1
				end
			elseif segment.BlockerKind == "Floor" then
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

	local segments = collectSegments(plotInfo, levelIndex)
	local boundaryCount = addPlotBoundarySegments(plotInfo, segments)
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

	local isValid = Formex.Floors.IsFloorValid(plotInfo.PlotData, { Points = cleaned } :: any)
	if not isValid then
		debugMessage("IsFloorValid rejected.")
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
	if not plotInfo or not plotInfo.PlotPart then
		return nil
	end
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
	if not plotInfo or not plotInfo.IsValid then
		return
	end

	local floorData = buildFloorDataFromPoints(cachedPolygon)
	local result = FormexClient.BuildFloor(floorData, Formex.BuildAction.Add, getSelectionSnapshot())
	if result and result.FloorId then
		selectFloorAfterBuild(plotInfo, floorData.LevelIndex, result.FloorId)
	end
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
	if getActionType() ~= Enums.ActionType.Start then
		return
	end
	updatePreview(input)
end

function Autofill.HandlePrimaryClick(_input: any)
	if getActionType() ~= Enums.ActionType.Start then
		return
	end
	local targetFloor = getFloorModelFromTarget(_input and _input.Target or nil)
	if targetFloor and select(targetFloor) then
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
	if getActionType() ~= Enums.ActionType.Start then
		return false
	end
	Autofill.CancelAction()
	return true
end

Autofill.DebugOutput = nil

return Autofill
