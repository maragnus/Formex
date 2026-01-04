--!strict

local Formex = require(script.Parent:FindFirstChild("Formex"))
Formex.Math = require(script.Parent:FindFirstChild("FormexMath"))

local EPSILON = Formex.EPSILON

Formex.Floors = {}

function Formex.EncodeFloorPoints(points: {Vector2int16}): string
	local encoded = {}
	for _, point in ipairs(points) do
		table.insert(encoded, string.format("%d,%d", point.X, point.Y))
	end
	return table.concat(encoded, ";")
end

function Formex.DecodeFloorPoints(value: string?): {Vector2int16}
	local points = {}
	if not value or value == "" then
		return points
	end

	for entry in string.gmatch(value, "([^;]+)") do
		local xStr, yStr = string.match(entry, "([^,]+),([^,]+)")
		if xStr and yStr then
			table.insert(points, Vector2int16.new(tonumber(xStr), tonumber(yStr)))
		end
	end

	return points
end

local function isLayoutGridSnapped(value: number): boolean
	local scaled = value / Formex.LayoutGridSize
	return math.abs(scaled - math.round(scaled)) <= EPSILON
end

local function isPointLayoutGridSnapped(point: Vector2): boolean
	return isLayoutGridSnapped(point.X) and isLayoutGridSnapped(point.Y)
end

local function getPlotPartFromInstance(instance: Instance): BasePart?
	local current: Instance? = instance
	while current do
		if current:IsA("BasePart") and current:GetAttribute("PlotId") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function toVector2(point: Vector2 | Vector2int16): Vector2
	if typeof(point) == "Vector2" then
		return point
	end
	return Vector2.new(point.X, point.Y)
end

local function polygonArea(points: {Vector2}): number
	local total = 0
	for i = 1, #points do
		local a = points[i]
		local b = points[(i % #points) + 1]
		total += (a.X * b.Y) - (b.X * a.Y)
	end
	return total / 2
end

local function quantize(value: number): number
	return math.round(value / EPSILON) * EPSILON
end

local function addUniqueNumber(values: {number}, value: number): boolean
	value = quantize(value)
	for _, existing in ipairs(values) do
		if math.abs(existing - value) <= EPSILON then
			return false
		end
	end
	table.insert(values, value)
	return true
end

local function addUniquePoint(points: {Vector2}, point: Vector2): boolean
	point = Vector2.new(quantize(point.X), quantize(point.Y))
	for _, existing in ipairs(points) do
		if (existing - point).Magnitude <= EPSILON then
			return false
		end
	end
	table.insert(points, point)
	return true
end

local function isPointInPolygon(point: Vector2, polygon: {Vector2}): boolean
	local inside = false
	for i = 1, #polygon do
		local a = polygon[i]
		local b = polygon[(i % #polygon) + 1]
		if Formex.Plot.IsPointOnSegment(point, a, b) then
			return true
		end
		if (a.Y > point.Y) ~= (b.Y > point.Y) then
			local x = (b.X - a.X) * (point.Y - a.Y) / (b.Y - a.Y) + a.X
			if point.X < x then
				inside = not inside
			end
		end
	end
	return inside
end

local function getEdgeParam(a: Vector2, b: Vector2, point: Vector2): number
	local dx = b.X - a.X
	local dy = b.Y - a.Y
	if math.abs(dx) >= math.abs(dy) then
		if math.abs(dx) <= EPSILON then
			return 0
		end
		return (point.X - a.X) / dx
	end
	if math.abs(dy) <= EPSILON then
		return 0
	end
	return (point.Y - a.Y) / dy
end

local function buildPolygonGrid(points: {Vector2}): ({number}, {number})
	local xs = {}
	local ys = {}
	for _, point in ipairs(points) do
		addUniqueNumber(xs, point.X)
		addUniqueNumber(ys, point.Y)
	end
	table.sort(xs, function(a, b) return a < b end)
	table.sort(ys, function(a, b) return a < b end)

	local guard = 0
	local changed = true
	while changed and guard < 256 do
		guard += 1
		changed = false
		for i = 1, #points do
			local a = points[i]
			local b = points[(i % #points) + 1]
			local dx = b.X - a.X
			local dy = b.Y - a.Y
			if math.abs(dx) > EPSILON then
				local minX = math.min(a.X, b.X)
				local maxX = math.max(a.X, b.X)
				for _, x in ipairs(xs) do
					if x > minX + EPSILON and x < maxX - EPSILON then
						local t = (x - a.X) / dx
						local y = a.Y + t * dy
						if addUniqueNumber(ys, y) then
							changed = true
						end
					end
				end
			end
			if math.abs(dy) > EPSILON then
				local minY = math.min(a.Y, b.Y)
				local maxY = math.max(a.Y, b.Y)
				for _, y in ipairs(ys) do
					if y > minY + EPSILON and y < maxY - EPSILON then
						local t = (y - a.Y) / dy
						local x = a.X + t * dx
						if addUniqueNumber(xs, x) then
							changed = true
						end
					end
				end
			end
		end

		if changed then
			table.sort(xs, function(a, b) return a < b end)
			table.sort(ys, function(a, b) return a < b end)
		end
	end

	return xs, ys
end

local function getEdgePoints(a: Vector2, b: Vector2, xs: {number}, ys: {number}): {Vector2}
	local points = {}
	addUniquePoint(points, a)
	addUniquePoint(points, b)

	local dx = b.X - a.X
	local dy = b.Y - a.Y

	if math.abs(dx) > EPSILON then
		local minX = math.min(a.X, b.X)
		local maxX = math.max(a.X, b.X)
		for _, x in ipairs(xs) do
			if x > minX + EPSILON and x < maxX - EPSILON then
				local t = (x - a.X) / dx
				local y = a.Y + t * dy
				addUniquePoint(points, Vector2.new(x, y))
			end
		end
	end

	if math.abs(dy) > EPSILON then
		local minY = math.min(a.Y, b.Y)
		local maxY = math.max(a.Y, b.Y)
		for _, y in ipairs(ys) do
			if y > minY + EPSILON and y < maxY - EPSILON then
				local t = (y - a.Y) / dy
				local x = a.X + t * dx
				addUniquePoint(points, Vector2.new(x, y))
			end
		end
	end

	table.sort(points, function(p1, p2)
		return getEdgeParam(a, b, p1) < getEdgeParam(a, b, p2)
	end)
	return points
end

local function segmentPolygonEdges(points: {Vector2}, xs: {number}, ys: {number}): {{A: Vector2, B: Vector2}}
	local segments = {}
	for i = 1, #points do
		local a = points[i]
		local b = points[(i % #points) + 1]
		local edgePoints = getEdgePoints(a, b, xs, ys)
		for index = 1, #edgePoints - 1 do
			local p1 = edgePoints[index]
			local p2 = edgePoints[index + 1]
			if (p2 - p1).Magnitude > EPSILON then
				table.insert(segments, { A = p1, B = p2 })
			end
		end
	end
	return segments
end

local function findNumberIndex(values: {number}, value: number): number?
	for index, existing in ipairs(values) do
		if math.abs(existing - value) <= EPSILON then
			return index
		end
	end
	return nil
end

local function buildDiagonalMap(segments: {{A: Vector2, B: Vector2}}, xs: {number}, ys: {number}): {[number]: {[number]: string}}
	local diagonals = {}
	for _, segment in ipairs(segments) do
		local a = segment.A
		local b = segment.B
		if math.abs(a.X - b.X) <= EPSILON or math.abs(a.Y - b.Y) <= EPSILON then
			continue
		end

		local i1 = findNumberIndex(xs, a.X)
		local i2 = findNumberIndex(xs, b.X)
		local j1 = findNumberIndex(ys, a.Y)
		local j2 = findNumberIndex(ys, b.Y)
		if not i1 or not i2 or not j1 or not j2 then
			continue
		end

		if math.abs(i1 - i2) == 1 and math.abs(j1 - j2) == 1 then
			local iCell = math.min(i1, i2)
			local jCell = math.min(j1, j2)
			local orientation = ((i1 < i2 and j1 < j2) or (i1 > i2 and j1 > j2)) and "BLTR" or "BRTL"
			diagonals[iCell] = diagonals[iCell] or {}
			diagonals[iCell][jCell] = orientation
		end
	end

	return diagonals
end

-- Tessellate into axis-aligned right triangles to keep wedge rotations on-grid.
local function triangulatePolygon(points: {Vector2}): {{Vector2}}
	local triangles = {}
	if #points < 3 then
		return triangles
	end

	local xs, ys = buildPolygonGrid(points)
	local segments = segmentPolygonEdges(points, xs, ys)
	local diagonals = buildDiagonalMap(segments, xs, ys)

	for i = 1, #xs - 1 do
		local x0, x1 = xs[i], xs[i + 1]
		if (x1 - x0) <= EPSILON then
			continue
		end
		for j = 1, #ys - 1 do
			local y0, y1 = ys[j], ys[j + 1]
			if (y1 - y0) <= EPSILON then
				continue
			end

			local bl = Vector2.new(x0, y0)
			local br = Vector2.new(x1, y0)
			local tr = Vector2.new(x1, y1)
			local tl = Vector2.new(x0, y1)

			local diagonal = diagonals[i] and diagonals[i][j] or nil
			if diagonal then
				local tri1
				local tri2
				if diagonal == "BLTR" then
					tri1 = { bl, br, tr }
					tri2 = { bl, tr, tl }
				else
					tri1 = { br, tr, tl }
					tri2 = { br, tl, bl }
				end

				local center1 = (tri1[1] + tri1[2] + tri1[3]) / 3
				local center2 = (tri2[1] + tri2[2] + tri2[3]) / 3
				if isPointInPolygon(center1, points) then
					table.insert(triangles, tri1)
				end
				if isPointInPolygon(center2, points) then
					table.insert(triangles, tri2)
				end
			else
				local center = Vector2.new((x0 + x1) / 2, (y0 + y1) / 2)
				if isPointInPolygon(center, points) then
					table.insert(triangles, { bl, br, tr })
					table.insert(triangles, { bl, tr, tl })
				end
			end
		end
	end

	return triangles
end

local function getFloorThickness(levelIndex: number): number
	if levelIndex == 1 then
		return Formex.SegmentSize.Foundation
	end
	return Formex.SegmentSize.Interfloor
end

local function applyTextureOffset(plotPart: BasePart, part: BasePart, texture: Texture)
	local localCFrame = plotPart.CFrame:ToObjectSpace(part.CFrame)
	texture.OffsetStudsU = localCFrame.Position.X + (Formex.Dimensions.Width / 2)
	texture.OffsetStudsV = localCFrame.Position.Z + (Formex.Dimensions.Depth / 2)
end

local function createWedgePart(plotPart: BasePart, parent: Instance, origin: Vector2, legA: Vector2, legB: Vector2, levelIndex: number): Part
	local thickness = getFloorThickness(levelIndex)
	local levelTop = Formex.LevelHeight * (levelIndex - 1)
	local centerY = levelTop - (thickness / 2)

	local lengthA = legA.Magnitude
	local lengthB = legB.Magnitude
	local axisA = legA.Magnitude > EPSILON and legA.Unit or Vector2.new(1, 0)
	local axisB = legB.Magnitude > EPSILON and legB.Unit or Vector2.new(0, 1)

	local center = Vector3.new(
		origin.X + axisA.X * (lengthA / 2) + axisB.X * (lengthB / 2),
		centerY,
		origin.Y + axisA.Y * (lengthA / 2) + axisB.Y * (lengthB / 2)
	)

	local yAxis = Vector3.new(axisA.X, 0, axisA.Y)
	local zAxis = Vector3.new(-axisB.X, 0, -axisB.Y)
	-- Wedge triangle uses local +Y and -Z legs; pick the right-handed X axis to set the top side.
	local xAxis = yAxis:Cross(zAxis)
	if xAxis.Magnitude > EPSILON then
		xAxis = xAxis.Unit
	else
		xAxis = Vector3.yAxis
	end
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Wedge
	part.Anchored = true
	part.CollisionGroup = Formex.CollisionGroup.Structure
	part.Size = Vector3.new(thickness, lengthA, lengthB)
	part.CFrame = plotPart.CFrame * CFrame.fromMatrix(center, xAxis, yAxis, zAxis)
	part.Parent = parent
	return part
end

local function createTriangleWedges(plotPart: BasePart, parent: Instance, a: Vector2, b: Vector2, c: Vector2, levelIndex: number): {Part}
	local function tryRightTriangle(origin: Vector2, p1: Vector2, p2: Vector2): (Vector2?, Vector2?, Vector2?)
		if math.abs(p1.Y - origin.Y) <= EPSILON and math.abs(p2.X - origin.X) <= EPSILON then
			return origin, p1 - origin, p2 - origin
		end
		if math.abs(p2.Y - origin.Y) <= EPSILON and math.abs(p1.X - origin.X) <= EPSILON then
			return origin, p2 - origin, p1 - origin
		end
		return nil, nil, nil
	end

	local origin, legA, legB = tryRightTriangle(a, b, c)
	if not origin then
		origin, legA, legB = tryRightTriangle(b, a, c)
	end
	if not origin then
		origin, legA, legB = tryRightTriangle(c, a, b)
	end
	if not origin or not legA or not legB then
		return {}
	end

	if legA.Magnitude <= EPSILON or legB.Magnitude <= EPSILON then
		return {}
	end

	local part = createWedgePart(plotPart, parent, origin, legA, legB, levelIndex)
	if not part then
		return {}
	end
	return { part }
end

function Formex.Floors.IsValid(plot: Formex.PlotData, floor: Formex.FloorData)
	if not floor or not floor.Points or #floor.Points < 3 then
		return false
	end

	local points = floor.Points
	local polygon = {}
	for _, point in ipairs(points) do
		if not isPointLayoutGridSnapped(point) then
			return false
		end
		if not Formex.Plot.IsPointInUnlockedSegments(point, plot.SegmentsUnlocked) then
			return false
		end
		table.insert(polygon, toVector2(point))
	end

	for i = 1, #polygon do
		local startPoint = polygon[i]
		local endPoint = polygon[(i % #polygon) + 1]
		if not Formex.Plot.IsLineWithinUnlockedSegments(startPoint, endPoint, plot.SegmentsUnlocked) then
			return false
		end
	end

	local area = math.abs(polygonArea(polygon))
	if area <= EPSILON then
		return false
	end

	return true
end

function Formex.Floors.Create(floor: Formex.FloorData, plotPartOverride: BasePart?, parentOverride: Instance?): Model?
	if not floor or not floor.Points or #floor.Points < 3 then
		return nil
	end

	local parent = parentOverride
	local plotPart = plotPartOverride
	if not plotPart and parent then
		plotPart = getPlotPartFromInstance(parent)
	end
	if not plotPart then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = tostring(floor.FloorId)
	model.Parent = parent
	floor.Model = model

	floor.FloorParts = {}
	floor.CeilingParts = {}

	model:SetAttribute("FloorMaterial", floor.FloorMaterial or 0)
	model:SetAttribute("CeilingMaterial", floor.CeilingMaterial or 0)
	model:SetAttribute("Points", Formex.EncodeFloorPoints(floor.Points))

	local points = {}
	for _, point in ipairs(floor.Points) do
		table.insert(points, toVector2(point))
	end

	local triangles = triangulatePolygon(points)
	local floorMaterial = floor.FloorMaterial or 0
	local ceilingMaterial = floor.CeilingMaterial or 0

	for _, triangle in ipairs(triangles) do
		local wedges = createTriangleWedges(plotPart, model, triangle[1], triangle[2], triangle[3], floor.LevelIndex)
		for _, part in ipairs(wedges) do
			local floorFace = Enum.NormalId.Left
			local ceilingFace = Enum.NormalId.Right
			if part.CFrame.RightVector.Y > 0 then
				floorFace = Enum.NormalId.Right
				ceilingFace = Enum.NormalId.Left
			end
			local floorTexture = Formex.Util.EnsureTexture(part, "Floor", floorFace)
			local ceilingTexture = Formex.Util.EnsureTexture(part, "Ceiling", ceilingFace)
			Formex.UpdateTexture(part, floorTexture, floorMaterial)
			Formex.UpdateTexture(part, ceilingTexture, ceilingMaterial)
			applyTextureOffset(plotPart, part, floorTexture)
			applyTextureOffset(plotPart, part, ceilingTexture)
			table.insert(floor.FloorParts, part)
			table.insert(floor.CeilingParts, part)
		end
	end

	return model
end

return Formex.Floors