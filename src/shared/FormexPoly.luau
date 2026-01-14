--!strict
--[[
FormexPoly
Shared polygon/graph utilities for tracing wall/floor faces.
]]

local FormexPoly = {}

export type Segment = {
	Start: Vector2int16,
	End: Vector2int16,
	Kind: "Wall" | "Floor",
	WallId: number?,
	FloorId: number?,
	IsBoundary: boolean?,
}

export type DirectedEdge = {
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

export type Face = {
	Points: {Vector2int16},
	Edges: {DirectedEdge},
	Area: number,
}

local function toVector2(point: Vector2int16): Vector2
	return Vector2.new(point.X, point.Y)
end

local function cross2(a: Vector2, b: Vector2): number
	return a.X * b.Y - a.Y * b.X
end

function FormexPoly.GetPointKey(point: Vector2int16): string
	return tostring(point.X) .. "," .. tostring(point.Y)
end

function FormexPoly.PointsEqual(a: Vector2int16, b: Vector2int16): boolean
	return a.X == b.X and a.Y == b.Y
end

function FormexPoly.PolygonArea(points: {Vector2int16}): number
	local area = 0
	for i = 1, #points do
		local nextIndex = (i % #points) + 1
		local a = points[i]
		local b = points[nextIndex]
		area += (a.X * b.Y) - (b.X * a.Y)
	end
	return area / 2
end

local function isPointOnSegment(point: Vector2, a: Vector2, b: Vector2, epsilon: number): boolean
	if math.abs(cross2(b - a, point - a)) > epsilon then return false end	return math.min(a.X, b.X) - epsilon <= point.X and point.X <= math.max(a.X, b.X) + epsilon
		and math.min(a.Y, b.Y) - epsilon <= point.Y and point.Y <= math.max(a.Y, b.Y) + epsilon
end

local function isPointOnPolygonEdge(point: Vector2, polygon: {Vector2int16}, epsilon: number): boolean
	for i = 1, #polygon do
		local a = toVector2(polygon[i])
		local b = toVector2(polygon[(i % #polygon) + 1])
		if isPointOnSegment(point, a, b, epsilon) then return true end	end
	return false
end

function FormexPoly.IsPointInsidePolygon(point: Vector2, polygon: {Vector2int16}, includeBoundary: boolean?, epsilon: number): boolean
	if #polygon < 3 then return false end
	if isPointOnPolygonEdge(point, polygon, epsilon) then
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

local function orientation(a: Vector2, b: Vector2, c: Vector2, epsilon: number): number
	local value = (b.Y - a.Y) * (c.X - b.X) - (b.X - a.X) * (c.Y - b.Y)
	if math.abs(value) <= epsilon then return 0 end	return value > 0 and 1 or 2
end

local function onSegment(a: Vector2, b: Vector2, c: Vector2, epsilon: number): boolean
	return math.min(a.X, c.X) - epsilon <= b.X and b.X <= math.max(a.X, c.X) + epsilon
		and math.min(a.Y, c.Y) - epsilon <= b.Y and b.Y <= math.max(a.Y, c.Y) + epsilon
end

function FormexPoly.SegmentsIntersect(p1: Vector2, p2: Vector2, q1: Vector2, q2: Vector2, epsilon: number): boolean
	local o1 = orientation(p1, p2, q1, epsilon)
	local o2 = orientation(p1, p2, q2, epsilon)
	local o3 = orientation(q1, q2, p1, epsilon)
	local o4 = orientation(q1, q2, p2, epsilon)

	if o1 ~= o2 and o3 ~= o4 then return true end
	if o1 == 0 and onSegment(p1, q1, p2, epsilon) then return true end
	if o2 == 0 and onSegment(p1, q2, p2, epsilon) then return true end
	if o3 == 0 and onSegment(q1, p1, q2, epsilon) then return true end
	if o4 == 0 and onSegment(q1, p2, q2, epsilon) then return true end

	return false
end

function FormexPoly.PolygonsIntersect(a: {Vector2int16}, b: {Vector2int16}, epsilon: number): boolean
	if #a < 2 or #b < 2 then return false end
	for i = 1, #a do
		local a1 = toVector2(a[i])
		local a2 = toVector2(a[(i % #a) + 1])
		for j = 1, #b do
			local b1 = toVector2(b[j])
			local b2 = toVector2(b[(j % #b) + 1])
			if FormexPoly.SegmentsIntersect(a1, a2, b1, b2, epsilon) then return true end		end
	end

	return false
end

function FormexPoly.IsPolygonInside(outer: {Vector2int16}, inner: {Vector2int16}, epsilon: number): boolean
	if #inner < 3 or #outer < 3 then return false end
	if FormexPoly.PolygonsIntersect(outer, inner, epsilon) then return false end
	for _, point in ipairs(inner) do
		if not FormexPoly.IsPointInsidePolygon(Vector2.new(point.X, point.Y), outer, false, epsilon) then return false end	end

	return true
end

function FormexPoly.GetFaceSamplePoint(points: {Vector2int16}, epsilon: number): Vector2?
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
	if FormexPoly.IsPointInsidePolygon(centroid, points, false, epsilon) then return centroid end
	local center = Vector2.new((minX + maxX) / 2, (minY + maxY) / 2)
	if FormexPoly.IsPointInsidePolygon(center, points, false, epsilon) then return center end
	local polygon = {}
	for _, point in ipairs(points) do
		table.insert(polygon, Vector2.new(point.X, point.Y))
	end
	if FormexPoly.PolygonArea(points) < 0 then
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
		return ab >= -epsilon and bc >= -epsilon and ca >= -epsilon
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

			if cross2(b - a, c - b) > epsilon then
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
					if FormexPoly.IsPointInsidePolygon(centroid2, points, false, epsilon) then return centroid2 end					table.remove(indices, i)
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

local function addWallSegments(levelData: any, segments: {Segment})
	if not levelData or not levelData.Walls then return end
	for wallId, wall in pairs(levelData.Walls) do
		if wall.Start and wall.End and not FormexPoly.PointsEqual(wall.Start, wall.End) then
			table.insert(segments, {
				Start = wall.Start,
				End = wall.End,
				Kind = "Wall",
				WallId = wallId,
				IsBoundary = false,
			})
		end
	end
end

local function addFloorSegments(levelData: any, segments: {Segment}, cleanPolygon: (({Vector2int16}) -> {Vector2int16})?)
	if not levelData or not levelData.Floors then return end
	for floorId, floor in pairs(levelData.Floors) do
		if floor.Points and #floor.Points >= 3 then
			local cleaned = cleanPolygon and cleanPolygon(floor.Points) or floor.Points
			if #cleaned >= 3 then
				for i = 1, #cleaned do
					local a = cleaned[i]
					local b = cleaned[(i % #cleaned) + 1]
					if not FormexPoly.PointsEqual(a, b) then
						table.insert(segments, {
							Start = a,
							End = b,
							Kind = "Floor",
							FloorId = floorId,
							IsBoundary = false,
						})
					end
				end
			end
		end
	end
end

function FormexPoly.AddPlotBoundarySegments(formex: any, segments: {Segment}, segmentsUnlocked: number?): number
	if not formex then return 0 end
	local mask = segmentsUnlocked or 0
	if mask == 0 then return 0 end
	local edgeMap = {} :: {[string]: Segment}

	local function canonicalKey(a: Vector2int16, b: Vector2int16): string
		local aKey = FormexPoly.GetPointKey(a)
		local bKey = FormexPoly.GetPointKey(b)
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
				Kind = "Wall",
				IsBoundary = true,
			}
		end
	end

	local halfWidth = formex.SegmentSize.Width / 2
	local halfDepth = formex.SegmentSize.Depth / 2

	for index = 1, formex.Segments.Count do
		if formex.Segments.IsUnlocked(mask, index) then
			local row, column = formex.Segments.GetRowColumn(index)
			local centerX = (column - (formex.Segments.GridWidth + 1) / 2) * formex.SegmentSize.Width
			local centerY = (row - (formex.Segments.GridHeight + 1) / 2) * formex.SegmentSize.Depth
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

function FormexPoly.CollectSegments(formex: any, plotData: any, levelIndex: number, options: {[string]: any}?): ({Segment}, number)
	local segments = {}
	local boundaryCount = 0
	if not plotData or not plotData.Levels then
		return segments, boundaryCount
	end

	local levelData = plotData.Levels[levelIndex]
	if not levelData then
		return segments, boundaryCount
	end

	local includeWalls = options == nil or options.IncludeWalls ~= false
	local includeFloors = options and options.IncludeFloors == true
	local includeBoundary = options == nil or options.IncludeBoundary ~= false
	local cleanPolygon = options and options.CleanPolygon or nil

	if includeWalls then
		addWallSegments(levelData, segments)
	end

	if includeFloors then
		addFloorSegments(levelData, segments, cleanPolygon)
	end

	if includeBoundary then
		boundaryCount = FormexPoly.AddPlotBoundarySegments(formex, segments, plotData.SegmentsUnlocked)
	end

	return segments, boundaryCount
end

local function computeDegrees(segments: {Segment}): {[string]: number}
	local degrees = {}
	for _, seg in ipairs(segments) do
		local startKey = FormexPoly.GetPointKey(seg.Start)
		local endKey = FormexPoly.GetPointKey(seg.End)
		degrees[startKey] = (degrees[startKey] or 0) + 1
		degrees[endKey] = (degrees[endKey] or 0) + 1
	end
	return degrees
end

function FormexPoly.PruneSegments(segments: {Segment}, epsilon: number)
	local changed = true
	while changed do
		changed = false
		local degrees = computeDegrees(segments)
		for i = #segments, 1, -1 do
			local seg = segments[i]
			if seg.Kind == "Wall" and not seg.IsBoundary then
				local startDegree = degrees[FormexPoly.GetPointKey(seg.Start)] or 0
				local endDegree = degrees[FormexPoly.GetPointKey(seg.End)] or 0
				if startDegree < 2 or endDegree < 2 then
					table.remove(segments, i)
					changed = true
				end
			end
		end
	end
end

function FormexPoly.SplitSegments(segments: {Segment}, epsilon: number): {Segment}
	local entries = table.create(#segments)
	local pointMaps = table.create(#segments)

	for index, segment in ipairs(segments) do
		entries[index] = segment
		local map = {}
		map[FormexPoly.GetPointKey(segment.Start)] = segment.Start
		map[FormexPoly.GetPointKey(segment.End)] = segment.End
		pointMaps[index] = map
	end

	local function addPoint(map: {[string]: Vector2int16}, point: Vector2int16)
		map[FormexPoly.GetPointKey(point)] = point
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

			if math.abs(rxs) <= epsilon and math.abs(qpxr) <= epsilon then
				if isPointOnSegment(a1, b1, b2, epsilon) then
					addPoint(pointMaps[j], segA.Start)
				end
				if isPointOnSegment(a2, b1, b2, epsilon) then
					addPoint(pointMaps[j], segA.End)
				end
				if isPointOnSegment(b1, a1, a2, epsilon) then
					addPoint(pointMaps[i], segB.Start)
				end
				if isPointOnSegment(b2, a1, a2, epsilon) then
					addPoint(pointMaps[i], segB.End)
				end
			elseif math.abs(rxs) > epsilon then
				local t = cross2(b1 - a1, s) / rxs
				local u = cross2(b1 - a1, r) / rxs
				if t >= -epsilon and t <= 1 + epsilon and u >= -epsilon and u <= 1 + epsilon then
					local intersection = a1 + r * t
					local ix = math.round(intersection.X)
					local iy = math.round(intersection.Y)
					if math.abs(intersection.X - ix) <= epsilon and math.abs(intersection.Y - iy) <= epsilon then
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
				if length2 <= epsilon then return false end				local ta = (toVector2(a) - start):Dot(dir) / length2
				local tb = (toVector2(b) - start):Dot(dir) / length2
				return ta < tb
			end)

			for i = 1, #points - 1 do
				local a = points[i]
				local b = points[i + 1]
				if not FormexPoly.PointsEqual(a, b) then
					local aKey = FormexPoly.GetPointKey(a)
					local bKey = FormexPoly.GetPointKey(b)
					local key = aKey < bKey and (aKey .. "|" .. bKey) or (bKey .. "|" .. aKey)
					local existing = segmentMap[key]
					if not existing then
						local newSegment = {
							Start = a,
							End = b,
							Kind = segment.Kind,
							WallId = segment.WallId,
							FloorId = segment.FloorId,
							IsBoundary = segment.IsBoundary,
						}
						segmentMap[key] = newSegment
						table.insert(deduped, newSegment)
					else
						if existing.Kind ~= "Wall" and segment.Kind == "Wall" then
							existing.Kind = "Wall"
							existing.WallId = segment.WallId or existing.WallId
						elseif existing.Kind == "Floor" and segment.Kind == "Floor" then
							existing.FloorId = existing.FloorId or segment.FloorId
						elseif existing.Kind == "Wall" and not existing.WallId and segment.WallId then
							existing.WallId = segment.WallId
						end
						if segment.IsBoundary then
							existing.IsBoundary = true
						end
					end
				end
			end
		end
	end

	return deduped
end

function FormexPoly.BuildDirectedEdges(segments: {Segment}): {DirectedEdge}
	local directedEdges = {}
	local adjacency = {}

	local function addDirected(segment: Segment, startPoint: Vector2int16, endPoint: Vector2int16)
		local id = #directedEdges + 1
		local edge = {
			Id = id,
			Start = startPoint,
			End = endPoint,
			StartKey = FormexPoly.GetPointKey(startPoint),
			EndKey = FormexPoly.GetPointKey(endPoint),
			Angle = math.atan2(endPoint.Y - startPoint.Y, endPoint.X - startPoint.X),
			Kind = segment.Kind,
			WallId = segment.WallId,
			FloorId = segment.FloorId,
			IsBoundary = segment.IsBoundary,
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
		addDirected(seg, seg.Start, seg.End)
		addDirected(seg, seg.End, seg.Start)
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

function FormexPoly.BuildFaces(directedEdges: {DirectedEdge}): {Face}
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
				Area = FormexPoly.PolygonArea(points),
			})
		end
	end

	return faces
end

function FormexPoly.TraceFaces(formex: any, plotData: any, levelIndex: number, options: {[string]: any}?): ({Face}, {Segment}, number)
	local segments, boundaryCount = FormexPoly.CollectSegments(formex, plotData, levelIndex, options)
	if #segments == 0 then
		return {}, segments, boundaryCount
	end

	local epsilon = formex and formex.EPSILON or 1e-4
	local split = FormexPoly.SplitSegments(segments, epsilon)
	if #split == 0 then
		return {}, split, boundaryCount
	end

	if options == nil or options.PruneWalls ~= false then
		FormexPoly.PruneSegments(split, epsilon)
	end
	if #split == 0 then
		return {}, split, boundaryCount
	end

	local directedEdges = FormexPoly.BuildDirectedEdges(split)
	local faces = FormexPoly.BuildFaces(directedEdges)
	return faces, split, boundaryCount
end

return FormexPoly
