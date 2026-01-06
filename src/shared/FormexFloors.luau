--!strict

local Formex = require(script.Parent:FindFirstChild("Formex"))
Formex.Math = require(script.Parent:FindFirstChild("FormexMath"))

local EPSILON = Formex.EPSILON
local MAX_TRIANGLES = 64 -- Make sure that a single floor does not exceed this triangle count for performance.

Formex.Floors = {}

type Edge = { A: Vector2, B: Vector2 }
type Triangle = { Vector2 }

-- Wedge orientation options keep wedges axis aligned while flipping the hypotenuse.
local WEDGE_ROTATIONS = {
	RightTop = {
		CFrame.Angles(0, math.rad(180), math.rad(90)),
		CFrame.Angles(0, 0, math.rad(-90)),
	},
	LeftTop = {
		CFrame.Angles(0, 0, math.rad(-90)),
		CFrame.Angles(0, math.rad(180), math.rad(-90)),
	},
}

function Formex.EncodeFloorPoints(points: { Vector2int16 }): string
	local encoded = {}
	for _, point in ipairs(points) do
		table.insert(encoded, string.format("%d,%d", point.X, point.Y))
	end
	return table.concat(encoded, ";")
end

function Formex.DecodeFloorPoints(value: string?): { Vector2int16 }
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

local function toVector2(point: Vector2 | Vector2int16): Vector2
	if typeof(point) == "Vector2" then
		return point
	end
	return Vector2.new(point.X, point.Y)
end

local function toVector2int16(point: Vector2): Vector2int16
	return Vector2int16.new(math.round(point.X), math.round(point.Y))
end

local function cross2(a: Vector2, b: Vector2): number
	return a.X * b.Y - a.Y * b.X
end

local function polygonArea(points: { Vector2 }): number
	local total = 0
	for index = 1, #points do
		local a = points[index]
		local b = points[(index % #points) + 1]
		total += (a.X * b.Y) - (b.X * a.Y)
	end
	return total / 2
end

local function isSamePoint(a: Vector2int16, b: Vector2int16): boolean
	return a.X == b.X and a.Y == b.Y
end

local function areCollinear(a: Vector2, b: Vector2, c: Vector2): boolean
	return math.abs(cross2(b - a, c - b)) <= EPSILON
end

local function reversePoints(points: { Vector2int16 }): { Vector2int16 }
	local reversed = table.create(#points)
	for i = #points, 1, -1 do
		table.insert(reversed, points[i])
	end
	return reversed
end


local function toVector2Array(points: { Vector2int16 }): { Vector2 }
	local result = table.create(#points)
	for _, point in ipairs(points) do
		table.insert(result, Vector2.new(point.X, point.Y))
	end
	return result
end


function Formex.Floors.CleanPolygon(points: { Vector2int16 }): { Vector2int16 }
	if #points == 0 then
		return {}
	end

	local deduped = {}
	for _, point in ipairs(points) do
		local last = deduped[#deduped]
		if not last or not isSamePoint(last, point) then
			table.insert(deduped, point)
		end
	end
	if #deduped > 1 and isSamePoint(deduped[1], deduped[#deduped]) then
		table.remove(deduped, #deduped)
	end

	if #deduped < 3 then
		return deduped
	end

	local cleaned = deduped
	local changed = true
	while changed and #cleaned >= 3 do
		changed = false
		local nextPass = {}
		for i = 1, #cleaned do
			local prev = toVector2(cleaned[(i - 2 + #cleaned) % #cleaned + 1])
			local current = toVector2(cleaned[i])
			local nxt = toVector2(cleaned[(i % #cleaned) + 1])
			if not areCollinear(prev, current, nxt) then
				table.insert(nextPass, cleaned[i])
			else
				changed = true
			end
		end
		cleaned = nextPass
	end

	if #cleaned < 3 then
		return cleaned
	end

	local area = polygonArea(toVector2Array(cleaned))
	local ccwPoints = cleaned
	if area < 0 then
		ccwPoints = reversePoints(cleaned)
	end

	return ccwPoints
end

local function orientation(a: Vector2, b: Vector2, c: Vector2): number
	local value = (b.Y - a.Y) * (c.X - b.X) - (b.X - a.X) * (c.Y - b.Y)
	if math.abs(value) <= EPSILON then
		return 0
	end
	return value > 0 and 1 or 2
end

local function onSegment(a: Vector2, b: Vector2, c: Vector2): boolean
	return math.min(a.X, c.X) - EPSILON <= b.X and b.X <= math.max(a.X, c.X) + EPSILON
		and math.min(a.Y, c.Y) - EPSILON <= b.Y and b.Y <= math.max(a.Y, c.Y) + EPSILON
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

local function isSimplePolygon(points: { Vector2 }): boolean
	local count = #points
	if count < 3 then
		return false
	end

	for i = 1, count do
		local a1 = points[i]
		local a2 = points[(i % count) + 1]
		for j = i + 1, count do
			local b1 = points[j]
			local b2 = points[(j % count) + 1]

			local isAdjacent = j == i + 1 or (i == 1 and j == count)
			if not isAdjacent and segmentsIntersect(a1, a2, b1, b2) then
				return false
			end
		end
	end

	return true
end

local function getBoundsRectangle(points: { Vector2int16 }): { Vector2int16 }
	if #points == 0 then
		return {}
	end

	local minX = points[1].X
	local maxX = points[1].X
	local minY = points[1].Y
	local maxY = points[1].Y

	for i = 2, #points do
		local point = points[i]
		minX = math.min(minX, point.X)
		maxX = math.max(maxX, point.X)
		minY = math.min(minY, point.Y)
		maxY = math.max(maxY, point.Y)
	end

	if math.abs(maxX - minX) <= EPSILON or math.abs(maxY - minY) <= EPSILON then
		return {}
	end

	return {
		Vector2int16.new(minX, minY),
		Vector2int16.new(maxX, minY),
		Vector2int16.new(maxX, maxY),
		Vector2int16.new(minX, maxY),
	}
end

function Formex.Floors.IsValid(plot: Formex.PlotData, floor: Formex.FloorData): boolean
	local cleaned = Formex.Floors.CleanPolygon(floor.Points or {})
	local count = #cleaned
	if count < 3 or count > Formex.MaxFloorPoints then
		return false
	end

	local polygon = toVector2Array(cleaned)
	if polygonArea(polygon) <= EPSILON then
		return false
	end

	if not isSimplePolygon(polygon) then
		return false
	end

	for i = 1, count do
		local a = polygon[i]
		local b = polygon[(i % count) + 1]
		if not Formex.Plot.IsLineWithinUnlockedSegments(a, b, plot.SegmentsUnlocked) then
			return false
		end
	end

	return true
end

local function collectUniqueXs(points: { Vector2 }): { number }
	local values = {}
	for _, point in ipairs(points) do
		local existing = nil
		for _, value in ipairs(values) do
			if math.abs(value - point.X) <= EPSILON then
				existing = value
				break
			end
		end
		if not existing then
			table.insert(values, point.X)
		end
	end
	table.sort(values, function(a, b)
		return a < b
	end)
	return values
end

local function buildEdges(points: { Vector2 }): { Edge }
	local edges = {}
	for i = 1, #points do
		local a = points[i]
		local b = points[(i % #points) + 1]
		table.insert(edges, { A = a, B = b })
	end
	return edges
end

local function evaluateEdgeAtX(edge: Edge, x: number): number?
	local dx = edge.B.X - edge.A.X
	if math.abs(dx) <= EPSILON then
		return nil
	end
	local t = (x - edge.A.X) / dx
	return edge.A.Y + t * (edge.B.Y - edge.A.Y)
end

local function gatherIntersections(edges: { Edge }, x: number): { { Y: number, EdgeIndex: number } }
	local intersections = {}
	for index, edge in ipairs(edges) do
		local minX = math.min(edge.A.X, edge.B.X)
		local maxX = math.max(edge.A.X, edge.B.X)
		if math.abs(maxX - minX) > EPSILON then
			local crosses = (edge.A.X <= x and edge.B.X > x) or (edge.B.X <= x and edge.A.X > x)
			if crosses then
				local y = evaluateEdgeAtX(edge, x)
				if y then
					table.insert(intersections, { Y = y, EdgeIndex = index })
				end
			end
		end
	end

	table.sort(intersections, function(a, b)
		return a.Y < b.Y
	end)
	return intersections
end

local function addTriangle(triangles: { Triangle }, a: Vector2, b: Vector2, c: Vector2)
	local area = cross2(b - a, c - a) / 2
	if math.abs(area) <= EPSILON then
		return
	end
	if area < 0 then
		b, c = c, b
	end
	table.insert(triangles, { a, b, c })
end

local function addSpanTriangles(
	triangles: { Triangle },
	x0: number,
	x1: number,
	bottom0: number,
	bottom1: number,
	top0: number,
	top1: number
)
	if x1 - x0 <= EPSILON then
		return
	end

	if bottom0 < bottom1 - EPSILON then
		addTriangle(triangles,
			Vector2.new(x0, bottom0),
			Vector2.new(x1, bottom1),
			Vector2.new(x0, bottom1))
	elseif bottom0 > bottom1 + EPSILON then
		addTriangle(triangles,
			Vector2.new(x1, bottom1),
			Vector2.new(x0, bottom0),
			Vector2.new(x1, bottom0))
	end

	if top0 > top1 + EPSILON then
		addTriangle(triangles,
			Vector2.new(x0, top0),
			Vector2.new(x0, top1),
			Vector2.new(x1, top1))
	elseif top0 < top1 - EPSILON then
		addTriangle(triangles,
			Vector2.new(x1, top1),
			Vector2.new(x1, top0),
			Vector2.new(x0, top0))
	end

	local bottomFlat = math.max(bottom0, bottom1)
	local topFlat = math.min(top0, top1)
	if topFlat - bottomFlat > EPSILON then
		addTriangle(triangles,
			Vector2.new(x0, bottomFlat),
			Vector2.new(x1, bottomFlat),
			Vector2.new(x1, topFlat))
		addTriangle(triangles,
			Vector2.new(x0, bottomFlat),
			Vector2.new(x1, topFlat),
			Vector2.new(x0, topFlat))
	end
end

local function triangulateVerticalSlices(points: { Vector2 }): { Triangle }
	if #points < 3 then
		return {}
	end

	local xs = collectUniqueXs(points)
	if #xs < 2 then
		return {}
	end

	local edges = buildEdges(points)
	local triangles = {}

	for i = 1, #xs - 1 do
		local x0 = xs[i]
		local x1 = xs[i + 1]
		if x1 - x0 <= EPSILON then
			continue
		end

		local sampleX = (x0 + x1) / 2
		local intersections = gatherIntersections(edges, sampleX)
		for j = 1, #intersections, 2 do
			local lower = intersections[j]
			local upper = intersections[j + 1]
			if not upper then
				break
			end

			local bottomEdge = edges[lower.EdgeIndex]
			local topEdge = edges[upper.EdgeIndex]
			local bottom0 = evaluateEdgeAtX(bottomEdge, x0) or lower.Y
			local bottom1 = evaluateEdgeAtX(bottomEdge, x1) or lower.Y
			local top0 = evaluateEdgeAtX(topEdge, x0) or upper.Y
			local top1 = evaluateEdgeAtX(topEdge, x1) or upper.Y

			if top0 <= bottom0 + EPSILON and top1 <= bottom1 + EPSILON then
				continue
			end

			addSpanTriangles(triangles, x0, x1, bottom0, bottom1, top0, top1)
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

local function resolveColor(value: Color3?, fallback: Color3?): Color3
	return value or fallback or Color3.new(1, 1, 1)
end

local function normalizeMaterialId(value: number?): number?
	if type(value) ~= "number" or value <= 0 then
		return nil
	end
	return value
end

local function applyFoundationMaterial(part: BasePart, foundationMaterial: number?, foundationColor: Color3?, levelIndex: number)
	if levelIndex == 1 then
		Formex.Util.ApplyWallMaterial(part, foundationMaterial, foundationColor)
	else
		part.Material = Enum.Material.SmoothPlastic
		part.MaterialVariant = ""
		part.Color = Color3.new(1, 1, 1)
	end
end

local function applyTextureOffset(plotPart: BasePart, part: BasePart, texture: Texture)
	local localCFrame = plotPart.CFrame:ToObjectSpace(part.CFrame)
	texture.OffsetStudsU = localCFrame.Position.X + (Formex.Dimensions.Width / 2)
	texture.OffsetStudsV = localCFrame.Position.Z + (Formex.Dimensions.Depth / 2)
end

local function ensureFloorModel(floor: Formex.FloorData, parent: Instance?): Model
	local model = floor.Model
	if not model or not model.Parent then
		model = Instance.new("Model")
		model.Name = tostring(floor.FloorId)
		model.Parent = parent
		floor.Model = model
	else
		model.Name = tostring(floor.FloorId)
		if parent and model.Parent ~= parent then
			model.Parent = parent
		end
	end
	return model
end

local function getPlotPartFromInstance(instance: Instance?): BasePart?
	local current = instance
	while current do
		if current:IsA("BasePart") and current:GetAttribute("PlotId") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function getExistingParts(model: Model): { Part }
	local parts = {}
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(parts, child)
		end
	end
	table.sort(parts, function(a, b)
		return a.Name < b.Name
	end)
	return parts
end

local function getTriangleLegs(triangle: Triangle): (Vector2?, Vector2?, Vector2?)
	local vx1, vx2, vy1, vy2 = nil, nil, nil, nil
	for i = 1, 3 do
		for j = i + 1, 3 do
			if math.abs(triangle[i].X - triangle[j].X) <= EPSILON then
				vx1, vx2 = i, j
			end
			if math.abs(triangle[i].Y - triangle[j].Y) <= EPSILON then
				vy1, vy2 = i, j
			end
		end
	end

	if not vx1 or not vx2 or not vy1 or not vy2 then
		return nil, nil, nil
	end

	local originIndex
	if vx1 == vy1 or vx1 == vy2 then
		originIndex = vx1
	elseif vx2 == vy1 or vx2 == vy2 then
		originIndex = vx2
	end

	if not originIndex then
		return nil, nil, nil
	end

	local verticalIndex = vx1 == originIndex and vx2 or vx1
	local horizontalIndex = vy1 == originIndex and vy2 or vy1

	local origin = triangle[originIndex]
	local legA = triangle[horizontalIndex] - origin
	local legB = triangle[verticalIndex] - origin

	if legA.Magnitude <= EPSILON or legB.Magnitude <= EPSILON then
		return nil, nil, nil
	end

	return origin, legA, legB
end

local function applyTriangleToPart(
	part: Part,
	plotPart: BasePart,
	origin: Vector2,
	legA: Vector2,
	legB: Vector2,
	levelIndex: number,
	index: number
)
	local thickness = getFloorThickness(levelIndex)
	local levelTop = Formex.LevelHeight * (levelIndex - 1)
	local centerY = levelTop - (thickness / 2)

	local center = Vector3.new(
		origin.X + (legA.X / 2) + (legB.X / 2),
		centerY,
		origin.Y + (legA.Y / 2) + (legB.Y / 2)
	)

	local axisA = Vector2.new(
		math.abs(legA.X) > EPSILON and (legA.X > 0 and 1 or -1) or 0,
		math.abs(legA.Y) > EPSILON and (legA.Y > 0 and 1 or -1) or 0
	)
	local axisB = Vector2.new(
		math.abs(legB.X) > EPSILON and (legB.X > 0 and 1 or -1) or 0,
		math.abs(legB.Y) > EPSILON and (legB.Y > 0 and 1 or -1) or 0
	)

	local yAxis = Vector3.new(axisA.X, 0, axisA.Y)
	local zAxis = Vector3.new(-axisB.X, 0, -axisB.Y)
	local xAxis = yAxis:Cross(zAxis)
	if xAxis.Magnitude <= EPSILON then
		xAxis = Vector3.new(0, 1, 0)
	else
		xAxis = xAxis.Unit
	end

	part.Shape = Enum.PartType.Wedge
	part.Name = tostring(index)
	part.Anchored = true
	part.CollisionGroup = Formex.CollisionGroup.Structure
	part.Size = Vector3.new(thickness, math.abs(legA.Magnitude), math.abs(legB.Magnitude))
	part.CFrame = plotPart.CFrame * CFrame.fromMatrix(center, xAxis, yAxis, zAxis)
end

local function updateTextures(
	part: Part,
	plotPart: BasePart,
	floorMaterial: number?,
	ceilingMaterial: number?,
	foundationMaterial: number?,
	floorColor: Color3,
	ceilingColor: Color3,
	foundationColor: Color3,
	levelIndex: number
)
	applyFoundationMaterial(part, foundationMaterial, foundationColor, levelIndex)

	local floorFace = Enum.NormalId.Left
	local ceilingFace = Enum.NormalId.Right
	if part.CFrame.RightVector.Y > 0 then
		floorFace = Enum.NormalId.Right
		ceilingFace = Enum.NormalId.Left
	end

	local floorTexture = Formex.Util.EnsureTexture(part, "Floor", floorFace)
	local ceilingTexture = Formex.Util.EnsureTexture(part, "Ceiling", ceilingFace)

	Formex.UpdateTexture(part, floorTexture, floorMaterial, floorColor)
	Formex.UpdateTexture(part, ceilingTexture, ceilingMaterial, ceilingColor)
	applyTextureOffset(plotPart, part, floorTexture)
	applyTextureOffset(plotPart, part, ceilingTexture)
end

local function buildTriangles(points: { Vector2int16 }): { Triangle }
	local cleaned = Formex.Floors.CleanPolygon(points)
	if #cleaned < 3 then
		return {}
	end

	local polygon = toVector2Array(cleaned)
	return triangulateVerticalSlices(polygon)
end

local function applyFloorAttributes(model: Model, floor: Formex.FloorData)
	local floorMaterial = normalizeMaterialId(floor.FloorMaterial) or Formex.DefaultFloorMaterial
	local ceilingMaterial = normalizeMaterialId(floor.CeilingMaterial) or floorMaterial
	local foundationMaterial = normalizeMaterialId(floor.FoundationMaterial) or Formex.DefaultFoundationMaterial

	local floorColor = resolveColor(floor.FloorColor, nil)
	local ceilingColor = resolveColor(floor.CeilingColor, floorColor)
	local foundationColor = resolveColor(floor.FoundationColor, floorColor)

	model:SetAttribute("FloorMaterial", floorMaterial)
	model:SetAttribute("CeilingMaterial", ceilingMaterial)
	model:SetAttribute("FoundationMaterial", foundationMaterial)
	model:SetAttribute("FloorColor", floorColor)
	model:SetAttribute("CeilingColor", ceilingColor)
	model:SetAttribute("FoundationColor", foundationColor)
	model:SetAttribute("Points", Formex.EncodeFloorPoints(floor.Points))

	return floorMaterial, ceilingMaterial, foundationMaterial, floorColor, ceilingColor, foundationColor
end

local function ensureValidShape(plot: Formex.PlotData?, floor: Formex.FloorData, cleaned: { Vector2int16 }): { Vector2int16 }
	if not plot then
		return cleaned
	end

	if Formex.Floors.IsValid(plot, { Points = cleaned } :: any) then
		return cleaned
	end

	local bounds = getBoundsRectangle(floor.Points or {})
	if #bounds >= 3 then
		return Formex.Floors.CleanPolygon(bounds)
	end

	return {}
end

function Formex.Floors.Edit(
	floor: Formex.FloorData,
	plotPartOverride: BasePart?,
	parentOverride: Instance?,
	plotData: Formex.PlotData?
): Model?
	if not floor or not floor.Points then
		return nil
	end

	local parent = parentOverride or (floor.Model and floor.Model.Parent) or nil
	local plotPart = plotPartOverride or getPlotPartFromInstance(parent)
	if not plotPart then
		return nil
	end

	local model = ensureFloorModel(floor, parent)
	model.Name = tostring(floor.FloorId)

	local cleaned = Formex.Floors.CleanPolygon(floor.Points)
	local usablePoints = ensureValidShape(plotData, floor, cleaned)
	if #usablePoints < 3 then
		for _, leftover in ipairs(getExistingParts(model)) do
			leftover:Destroy()
		end
		return model
	end

	local floorMaterial, ceilingMaterial, foundationMaterial, floorColor, ceilingColor, foundationColor =
		applyFloorAttributes(model, floor)

	local triangles = buildTriangles(usablePoints)
	local existing = getExistingParts(model)

	for index, triangle in ipairs(triangles) do
		local origin, legA, legB = getTriangleLegs(triangle)
		if origin and legA and legB then
			local part = table.remove(existing, 1) or Instance.new("Part")
			part.Parent = model
			applyTriangleToPart(part, plotPart, origin, legA, legB, floor.LevelIndex, index)
			updateTextures(part, plotPart, floorMaterial, ceilingMaterial, foundationMaterial, floorColor, ceilingColor, foundationColor, floor.LevelIndex)
		end
	end

	for _, leftover in ipairs(existing) do
		leftover:Destroy()
	end

	return model
end

function Formex.Floors.Create(
	floor: Formex.FloorData,
	plotPartOverride: BasePart?,
	parentOverride: Instance?,
	plotData: Formex.PlotData?
): Model?
	if not floor or not floor.Points then
		return nil
	end

	return Formex.Floors.Edit(floor, plotPartOverride, parentOverride, plotData)
end

return Formex.Floors
