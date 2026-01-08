--!strict

local Formex = require(script.Parent:FindFirstChild("Formex"))
Formex.Math = require(script.Parent:FindFirstChild("FormexMath"))

local AssetService = game:GetService("AssetService")
local RunService = game:GetService("RunService")
local isServer = RunService:IsServer()

local EPSILON = Formex.EPSILON
local MAX_TRIANGLES = 64 -- Make sure that a single floor does not exceed this triangle count for performance.
local CLIENT_MESH_SUFFIX = " (Client)"
local SURFACE_UV_SCALE = (type(Formex.LayoutGridSize) == "number" and Formex.LayoutGridSize > 0)
	and Formex.LayoutGridSize
	or 1
local MESH_PART_NAMES = {
	Floor = "Floor",
	Foundation = "Foundation",
	Ceiling = "Ceiling",
}

Formex.Floors = {}

type Triangle = { Vector2 }

-- Triangulation overview (ear clipping):
-- We clean the polygon to enforce CCW winding and remove collinear points, then iteratively clip "ears"
-- (convex vertices whose triangle does not contain any other vertex) until only triangles remain.


function Formex.EncodeFloorPoints(points: { Vector2int16 }): string
	-- Convert points to a compact string so floor data can be stored on attributes.
	local encoded = {}
	for _, point in ipairs(points) do
		table.insert(encoded, string.format("%d,%d", point.X, point.Y))
	end
	return table.concat(encoded, ";")
end

function Formex.DecodeFloorPoints(value: string?): { Vector2int16 }
	-- Restore points from the attribute string during selection/editing.
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
	-- Normalize point types for shared math helpers.
	if typeof(point) == "Vector2" then
		return point
	end
	return Vector2.new(point.X, point.Y)
end

local function cross2(a: Vector2, b: Vector2): number
	-- 2D cross product for orientation/area tests.
	return a.X * b.Y - a.Y * b.X
end

local function polygonArea(points: { Vector2 }): number
	-- Compute signed area so we can enforce CCW winding.
	local total = 0
	for index = 1, #points do
		local a = points[index]
		local b = points[(index % #points) + 1]
		total += (a.X * b.Y) - (b.X * a.Y)
	end
	return total / 2
end

local function isSamePoint(a: Vector2int16, b: Vector2int16): boolean
	-- Compare discrete floor points without float tolerance.
	return a.X == b.X and a.Y == b.Y
end

local function areCollinear(a: Vector2, b: Vector2, c: Vector2): boolean
	-- Remove redundant points that do not change the polygon shape.
	return math.abs(cross2(b - a, c - b)) <= EPSILON
end

local function reversePoints(points: { Vector2int16 }): { Vector2int16 }
	-- Reverse winding to enforce CCW orientation.
	local reversed = table.create(#points)
	for i = #points, 1, -1 do
		table.insert(reversed, points[i])
	end
	return reversed
end

local function toVector2Array(points: { Vector2int16 }): { Vector2 }
	-- Promote integer grid points to Vector2 for math.
	local result = table.create(#points)
	for _, point in ipairs(points) do
		table.insert(result, Vector2.new(point.X, point.Y))
	end
	return result
end

function Formex.Floors.CleanPolygon(points: { Vector2int16 }): { Vector2int16 }
	-- Remove duplicates/collinear points and normalize winding before triangulation.
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
	-- Helper for segment intersection tests.
	local value = (b.Y - a.Y) * (c.X - b.X) - (b.X - a.X) * (c.Y - b.Y)
	if math.abs(value) <= EPSILON then
		return 0
	end
	return value > 0 and 1 or 2
end

local function onSegment(a: Vector2, b: Vector2, c: Vector2): boolean
	-- Bounds check for collinear segment intersection handling.
	return math.min(a.X, c.X) - EPSILON <= b.X and b.X <= math.max(a.X, c.X) + EPSILON
		and math.min(a.Y, c.Y) - EPSILON <= b.Y and b.Y <= math.max(a.Y, c.Y) + EPSILON
end

local function segmentsIntersect(p1: Vector2, p2: Vector2, q1: Vector2, q2: Vector2): boolean
	-- Detect self-intersections so floors stay simple.
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
	-- Reject polygons with self-intersection before building wedges.
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
	-- Fallback to a rectangle if the polygon is invalid or degenerate.
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

local function isPolygonValid(points: { Vector2int16 }): boolean
	-- Geometry-only validation used when plot data is not available.
	local count = #points
	if count < 3 or count > Formex.MaxFloorPoints then
		return false
	end

	local polygon = toVector2Array(points)
	if polygonArea(polygon) <= EPSILON then
		return false
	end

	if not isSimplePolygon(polygon) then
		return false
	end

	return true
end

function Formex.Floors.IsValid(plot: Formex.PlotData, floor: Formex.FloorData): boolean
	-- Full validation including plot boundaries.
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

local function addTriangle(triangles: { Triangle }, a: Vector2, b: Vector2, c: Vector2, maxTriangles: number): boolean
	-- Insert a CCW triangle if it has area, while respecting the max triangle budget.
	if #triangles >= maxTriangles then
		return false
	end

	local area = cross2(b - a, c - a) / 2
	if math.abs(area) <= EPSILON then
		return true
	end
	if area < 0 then
		b, c = c, b
	end
	table.insert(triangles, { a, b, c })
	return #triangles < maxTriangles
end

local function isPointInTriangle(point: Vector2, a: Vector2, b: Vector2, c: Vector2): boolean
	local ab = cross2(b - a, point - a)
	local bc = cross2(c - b, point - b)
	local ca = cross2(a - c, point - c)
	return ab >= -EPSILON and bc >= -EPSILON and ca >= -EPSILON
end

local function triangulateEarClipping(points: { Vector2int16 }, maxTriangles: number): { Triangle }
	-- Clip convex ears until the polygon is fully triangulated.
	if #points < 3 then
		return {}
	end

	local polygon = toVector2Array(points)
	if polygonArea(polygon) < 0 then
		local reversed = table.create(#polygon)
		for i = #polygon, 1, -1 do
			table.insert(reversed, polygon[i])
		end
		polygon = reversed
	end

	local indices = table.create(#polygon)
	for i = 1, #polygon do
		indices[i] = i
	end

	local triangles = {}
	local guard = 0
	local maxGuard = #polygon * #polygon

	while #indices >= 3 and #triangles < maxTriangles and guard < maxGuard do
		guard += 1
		local earFound = false

		for i = 1, #indices do
			local prevIndex = indices[(i - 2 + #indices) % #indices + 1]
			local currIndex = indices[i]
			local nextIndex = indices[(i % #indices) + 1]

			local a = polygon[prevIndex]
			local b = polygon[currIndex]
			local c = polygon[nextIndex]

			if cross2(b - a, c - b) > EPSILON then
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
					if not addTriangle(triangles, a, b, c, maxTriangles) then
						return triangles
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

	return triangles
end

local function getFloorThickness(levelIndex: number): number
	-- Floor thickness depends on whether this is the foundation level.
	if levelIndex == 1 then
		return Formex.FoundationHeight
	end
	return Formex.InterfloorHeight
end

local function normalizeRaiseHeight(value: number?): number
	-- Raised floors are snapped to the grid and clamped to stay within a level.
	local resolved = value or 0
	if resolved < 0 then
		resolved = 0
	end

	local snapped = math.round(resolved / Formex.GridSize) * Formex.GridSize
	local maxHeight = Formex.LevelHeight - Formex.InterfloorHeight
	if maxHeight < 0 then
		maxHeight = 0
	end
	return math.clamp(snapped, 0, maxHeight)
end

local function resolveColor(value: Color3?, fallback: Color3?): Color3
	-- Normalize optional colors so downstream code can always use a Color3.
	return value or fallback or Color3.new(1, 1, 1)
end

local function normalizeMaterialId(value: number?): number?
	-- Treat 0/invalid material ids as nil.
	if type(value) ~= "number" or value <= 0 then
		return nil
	end
	return value
end

local function ensureFloorModel(floor: Formex.FloorData, parent: Instance?): Model
	-- Reuse or create the floor container model for mesh parts.
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
	-- Walk up the hierarchy to locate the plot root part.
	local current = instance
	while current do
		if current:IsA("BasePart") and current:GetAttribute("PlotId") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function matchesSuffix(value: string, suffix: string): boolean
	return string.sub(value, -#suffix) == suffix
end

local function getMeshPartName(baseName: string, suffix: string?): string
	if suffix then
		return baseName .. suffix
	end
	return baseName
end

local function clearMeshParts(parent: Instance, nameSuffix: string?)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("BasePart") then
			if not nameSuffix or matchesSuffix(child.Name, nameSuffix) then
				child:Destroy()
			end
		end
	end
end

local function applySurfaceMaterial(part: BasePart, materialId: number?, color: Color3?)
	Formex.Util.ApplyWallMaterial(part, materialId, color)
end

local function addFace(
	editableMesh: EditableMesh,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	normalId: number,
	colorId: number,
	uvA: Vector2,
	uvB: Vector2,
	uvC: Vector2
)
	local vA = editableMesh:AddVertex(a)
	local vB = editableMesh:AddVertex(b)
	local vC = editableMesh:AddVertex(c)
	local faceId = editableMesh:AddTriangle(vA, vB, vC)
	editableMesh:SetFaceNormals(faceId, { normalId, normalId, normalId })
	local uvIdA = editableMesh:AddUV(uvA)
	local uvIdB = editableMesh:AddUV(uvB)
	local uvIdC = editableMesh:AddUV(uvC)
	editableMesh:SetFaceUVs(faceId, { uvIdA, uvIdB, uvIdC })
	editableMesh:SetFaceColors(faceId, { colorId, colorId, colorId })
end

local function appendTopFaces(editableMesh: EditableMesh, triangles: { Triangle }, y: number, uvScale: number): number
	local normalId = editableMesh:AddNormal(Vector3.new(0, 1, 0))
	local colorId = editableMesh:AddColor(Color3.new(1, 1, 1), 1)
	local faceCount = 0

	for _, triangle in ipairs(triangles) do
		local a = triangle[1]
		local b = triangle[2]
		local c = triangle[3]
		local posA = Vector3.new(a.X, y, a.Y)
		local posB = Vector3.new(b.X, y, b.Y)
		local posC = Vector3.new(c.X, y, c.Y)
		local uvA = Vector2.new(a.X / uvScale, a.Y / uvScale)
		local uvB = Vector2.new(b.X / uvScale, b.Y / uvScale)
		local uvC = Vector2.new(c.X / uvScale, c.Y / uvScale)
		addFace(editableMesh, posA, posC, posB, normalId, colorId, uvA, uvC, uvB)
		faceCount += 1
	end

	return faceCount
end

local function appendBottomFaces(editableMesh: EditableMesh, triangles: { Triangle }, y: number, uvScale: number): number
	local normalId = editableMesh:AddNormal(Vector3.new(0, -1, 0))
	local colorId = editableMesh:AddColor(Color3.new(1, 1, 1), 1)
	local faceCount = 0

	for _, triangle in ipairs(triangles) do
		local a = triangle[1]
		local b = triangle[2]
		local c = triangle[3]
		local posA = Vector3.new(a.X, y, a.Y)
		local posB = Vector3.new(b.X, y, b.Y)
		local posC = Vector3.new(c.X, y, c.Y)
		local uvA = Vector2.new(a.X / uvScale, a.Y / uvScale)
		local uvB = Vector2.new(b.X / uvScale, b.Y / uvScale)
		local uvC = Vector2.new(c.X / uvScale, c.Y / uvScale)
		addFace(editableMesh, posA, posB, posC, normalId, colorId, uvA, uvB, uvC)
		faceCount += 1
	end

	return faceCount
end

local function appendSideFaces(editableMesh: EditableMesh, points: { Vector2int16 }, yTop: number, yBottom: number, uvScale: number): number
	local colorId = editableMesh:AddColor(Color3.new(1, 1, 1), 1)
	local faceCount = 0
	local thickness = math.abs(yTop - yBottom)

	for i = 1, #points do
		local startPoint = points[i]
		local endPoint = points[(i % #points) + 1]
		local dx = endPoint.X - startPoint.X
		local dz = endPoint.Y - startPoint.Y
		local length = math.sqrt((dx * dx) + (dz * dz))
		if length <= EPSILON then
			continue
		end

		local normal = Vector3.new(dz, 0, -dx)
		if normal.Magnitude <= EPSILON then
			continue
		end
		local normalId = editableMesh:AddNormal(normal.Unit)

		local u1 = length / uvScale
		local v1 = thickness / uvScale

		local topA = Vector3.new(startPoint.X, yTop, startPoint.Y)
		local topB = Vector3.new(endPoint.X, yTop, endPoint.Y)
		local bottomB = Vector3.new(endPoint.X, yBottom, endPoint.Y)
		local bottomA = Vector3.new(startPoint.X, yBottom, startPoint.Y)

		addFace(
			editableMesh,
			topA,
			topB,
			bottomB,
			normalId,
			colorId,
			Vector2.new(0, 0),
			Vector2.new(u1, 0),
			Vector2.new(u1, v1)
		)
		addFace(
			editableMesh,
			topA,
			bottomB,
			bottomA,
			normalId,
			colorId,
			Vector2.new(0, 0),
			Vector2.new(u1, v1),
			Vector2.new(0, v1)
		)
		faceCount += 2
	end

	return faceCount
end

local function createMeshPart(
	name: string,
	plotPart: BasePart,
	parent: Instance,
	canCollide: boolean,
	canQuery: boolean,
	buildFaces: (EditableMesh) -> number
): MeshPart?
	local editableMesh = AssetService:CreateEditableMesh()
	local faceCount = buildFaces(editableMesh)
	if faceCount <= 0 then
		editableMesh:Destroy()
		return nil
	end

	editableMesh:RemoveUnused()
	local fixedSizeMesh = AssetService:CreateEditableMeshAsync(Content.fromObject(editableMesh), { FixedSize = true })
	editableMesh:Destroy()

	local meshPart = AssetService:CreateMeshPartAsync(
		Content.fromObject(fixedSizeMesh),
		{ CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition }
	)

	meshPart.Name = name
	meshPart.Anchored = true
	meshPart.CanCollide = canCollide
	meshPart.CanQuery = canQuery
	meshPart.CanTouch = canCollide
	if canCollide then
		meshPart.CollisionGroup = Formex.CollisionGroup.Structure
	end
	meshPart.CFrame = plotPart.CFrame
	meshPart.Parent = parent
	meshPart.Destroying:Connect(function()
		fixedSizeMesh:Destroy()
		print("Destroyed mesh part and its mesh asset.", name, parent.Name, parent.Parent and parent.Parent.Name)
	end)
	meshPart.Transparency = isServer and 1 or 0
	return meshPart
end

local function applyMeshMaterials(
	parent: Instance,
	levelIndex: number,
	floorMaterial: number?,
	ceilingMaterial: number?,
	foundationMaterial: number?,
	floorColor: Color3,
	ceilingColor: Color3,
	foundationColor: Color3,
	nameSuffix: string?
)
	local floorPart = parent:FindFirstChild(getMeshPartName(MESH_PART_NAMES.Floor, nameSuffix))
	if floorPart and floorPart:IsA("BasePart") then
		applySurfaceMaterial(floorPart, floorMaterial, floorColor)
	end

	local foundationPart = parent:FindFirstChild(getMeshPartName(MESH_PART_NAMES.Foundation, nameSuffix))
	if foundationPart and foundationPart:IsA("BasePart") then
		applySurfaceMaterial(foundationPart, foundationMaterial, foundationColor)
	end

	local ceilingPart = parent:FindFirstChild(getMeshPartName(MESH_PART_NAMES.Ceiling, nameSuffix))
	if levelIndex == 1 then
		if ceilingPart and ceilingPart:IsA("BasePart") then
			ceilingPart:Destroy()
		end
	elseif ceilingPart and ceilingPart:IsA("BasePart") then
		applySurfaceMaterial(ceilingPart, ceilingMaterial, ceilingColor)
	end
end

local function resolveFloorHeights(levelIndex: number, raiseHeight: number): (number, number)
	local levelTop = Formex.LevelHeight * (levelIndex - 1)
	local resolvedRaise = normalizeRaiseHeight(raiseHeight)
	if resolvedRaise > 0 then
		return levelTop + resolvedRaise, levelTop
	end

	local thickness = getFloorThickness(levelIndex)
	return levelTop, levelTop - thickness
end

local function buildSurfaceMeshes(
	parent: Instance,
	plotPart: BasePart,
	points: { Vector2int16 },
	triangles: { Triangle },
	levelIndex: number,
	raiseHeight: number,
	floorMaterial: number?,
	ceilingMaterial: number?,
	foundationMaterial: number?,
	floorColor: Color3,
	ceilingColor: Color3,
	foundationColor: Color3,
	canCollide: boolean,
	canQuery: boolean,
	nameSuffix: string?
)
	clearMeshParts(parent, nameSuffix)

	local yTop, yBottom = resolveFloorHeights(levelIndex, raiseHeight)

	local floorPart = createMeshPart(
		getMeshPartName(MESH_PART_NAMES.Floor, nameSuffix),
		plotPart,
		parent,
		canCollide,
		canQuery,
		function(editableMesh)
			return appendTopFaces(editableMesh, triangles, yTop, SURFACE_UV_SCALE)
		end
	)
	if floorPart then
		applySurfaceMaterial(floorPart, floorMaterial, floorColor)
	end

	local foundationPart = createMeshPart(
		getMeshPartName(MESH_PART_NAMES.Foundation, nameSuffix),
		plotPart,
		parent,
		canCollide,
		canQuery,
		function(editableMesh)
			return appendSideFaces(editableMesh, points, yTop, yBottom, SURFACE_UV_SCALE)
		end
	)
	if foundationPart then
		applySurfaceMaterial(foundationPart, foundationMaterial, foundationColor)
	end

	if levelIndex > 1 then
		local ceilingPart = createMeshPart(
			getMeshPartName(MESH_PART_NAMES.Ceiling, nameSuffix),
			plotPart,
			parent,
			canCollide,
			canQuery,
			function(editableMesh)
				return appendBottomFaces(editableMesh, triangles, yBottom, SURFACE_UV_SCALE)
			end
		)
		if ceilingPart then
			applySurfaceMaterial(ceilingPart, ceilingMaterial, ceilingColor)
		end
	end
end

local function buildTriangles(points: { Vector2int16 }): { Triangle }
	-- Convert the polygon into triangles for mesh surfaces.
	if #points < 3 then
		return {}
	end

	return triangulateEarClipping(points, MAX_TRIANGLES)
end

local function resolveFloorAppearance(floor: Formex.FloorData)
	local floorMaterial = normalizeMaterialId(floor.FloorMaterial) or Formex.DefaultFloorMaterial
	local ceilingMaterial = normalizeMaterialId(floor.CeilingMaterial) or floorMaterial
	local foundationMaterial = normalizeMaterialId(floor.FoundationMaterial) or Formex.DefaultFoundationMaterial

	local floorColor = resolveColor(floor.FloorColor, nil)
	local ceilingColor = resolveColor(floor.CeilingColor, floorColor)
	local foundationColor = resolveColor(floor.FoundationColor, floorColor)

	return floorMaterial, ceilingMaterial, foundationMaterial, floorColor, ceilingColor, foundationColor
end

type AppearanceAttributes = {
	FloorMaterial: number?,
	CeilingMaterial: number?,
	FoundationMaterial: number?,
	FloorColor: Color3?,
	CeilingColor: Color3?,
	FoundationColor: Color3?,
}

local function readFloorAppearanceAttributes(model: Model): AppearanceAttributes
	return {
		FloorMaterial = model:GetAttribute("FloorMaterial"),
		CeilingMaterial = model:GetAttribute("CeilingMaterial"),
		FoundationMaterial = model:GetAttribute("FoundationMaterial"),
		FloorColor = model:GetAttribute("FloorColor"),
		CeilingColor = model:GetAttribute("CeilingColor"),
		FoundationColor = model:GetAttribute("FoundationColor"),
	}
end

local function resolveFloorAppearanceFromAttributes(attributes: AppearanceAttributes)
	local floorMaterial = normalizeMaterialId(attributes.FloorMaterial) or Formex.DefaultFloorMaterial
	local ceilingMaterial = normalizeMaterialId(attributes.CeilingMaterial) or floorMaterial
	local foundationMaterial = normalizeMaterialId(attributes.FoundationMaterial) or Formex.DefaultFoundationMaterial

	local floorColor = resolveColor(attributes.FloorColor, nil)
	local ceilingColor = resolveColor(attributes.CeilingColor, floorColor)
	local foundationColor = resolveColor(attributes.FoundationColor, floorColor)

	return floorMaterial, ceilingMaterial, foundationMaterial, floorColor, ceilingColor, foundationColor
end

local function getLevelIndexFromModel(model: Model): number
	local parent = model.Parent
	if parent and parent.Parent and parent.Parent:IsA("BasePart") then
		return tonumber(parent.Parent.Name) or 1
	end
	return 1
end

local function buildFloorDataFromAttributes(model: Model): Formex.FloorData
	local points = Formex.DecodeFloorPoints(model:GetAttribute("Points"))
	return {
		FloorId = tonumber(model.Name) or 0,
		LevelIndex = getLevelIndexFromModel(model),
		Points = points,
		RaiseHeight = model:GetAttribute("RaiseHeight") or 0,
		FloorMaterial = model:GetAttribute("FloorMaterial"),
		CeilingMaterial = model:GetAttribute("CeilingMaterial"),
		FoundationMaterial = model:GetAttribute("FoundationMaterial"),
		FloorColor = model:GetAttribute("FloorColor"),
		CeilingColor = model:GetAttribute("CeilingColor"),
		FoundationColor = model:GetAttribute("FoundationColor"),
		Model = model,
	}
end

local function applyFloorAttributes(model: Model, floor: Formex.FloorData)
	-- Store material/color attributes for selection and serialization.
	local floorMaterial, ceilingMaterial, foundationMaterial, floorColor, ceilingColor, foundationColor =
		resolveFloorAppearance(floor)
	local raiseHeight = normalizeRaiseHeight(floor.RaiseHeight)

	model:SetAttribute("FloorMaterial", floorMaterial)
	model:SetAttribute("CeilingMaterial", ceilingMaterial)
	model:SetAttribute("FoundationMaterial", foundationMaterial)
	model:SetAttribute("FloorColor", floorColor)
	model:SetAttribute("CeilingColor", ceilingColor)
	model:SetAttribute("FoundationColor", foundationColor)
	model:SetAttribute("Points", Formex.EncodeFloorPoints(floor.Points))
	model:SetAttribute("RaiseHeight", raiseHeight)

	return floorMaterial, ceilingMaterial, foundationMaterial, floorColor, ceilingColor, foundationColor
end

local function ensureValidShape(plot: Formex.PlotData?, floor: Formex.FloorData, cleaned: { Vector2int16 }): { Vector2int16 }
	-- Ensure points are valid or fall back to a bounds rectangle.
	local isValid = isPolygonValid(cleaned)
	if isValid and plot then
		isValid = Formex.Floors.IsValid(plot, { Points = cleaned } :: any)
	end

	if isValid then
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
	-- Main entry point to create/update floor mesh parts in-place.
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
	local previousPointsKey = model:GetAttribute("Points") or ""
	local previousRaiseHeight = model:GetAttribute("RaiseHeight") or 0

	local cleaned = Formex.Floors.CleanPolygon(floor.Points)
	local usablePoints = ensureValidShape(plotData, floor, cleaned)

	applyFloorAttributes(model, floor)
	local pointsKey = model:GetAttribute("Points") or ""
	local raiseHeight = model:GetAttribute("RaiseHeight") or 0
	local floorMaterial, ceilingMaterial, foundationMaterial, floorColor, ceilingColor, foundationColor =
		resolveFloorAppearanceFromAttributes(readFloorAppearanceAttributes(model))
	local levelIndex = floor.LevelIndex or 1

	if #usablePoints < 3 then
		clearMeshParts(model)
		return model
	end

	local geometryChanged = pointsKey ~= previousPointsKey or raiseHeight ~= previousRaiseHeight
	local floorPart = model:FindFirstChild(MESH_PART_NAMES.Floor)
	local hasGeometry = floorPart ~= nil and floorPart:IsA("BasePart")
	if not geometryChanged and hasGeometry then
		applyMeshMaterials(
			model,
			levelIndex,
			floorMaterial,
			ceilingMaterial,
			foundationMaterial,
			floorColor,
			ceilingColor,
			foundationColor,
			nil
		)
		return model
	end

	local triangles = buildTriangles(usablePoints)
	buildSurfaceMeshes(
		model,
		plotPart,
		usablePoints,
		triangles,
		levelIndex,
		raiseHeight,
		floorMaterial,
		ceilingMaterial,
		foundationMaterial,
		floorColor,
		ceilingColor,
		foundationColor,
		true,
		true,
		nil
	)

	return model
end

function Formex.Floors.RenderClientMeshes(model: Model, plotPartOverride: BasePart?): Model?
	if not model or not model:IsA("Model") then
		return nil
	end

	local plotPart = plotPartOverride or getPlotPartFromInstance(model)
	if not plotPart then
		return nil
	end

	local floorData = buildFloorDataFromAttributes(model)
	local cleaned = Formex.Floors.CleanPolygon(floorData.Points)
	local usablePoints = ensureValidShape(nil, floorData, cleaned)
	local levelIndex = getLevelIndexFromModel(model)
	local raiseHeight = normalizeRaiseHeight(floorData.RaiseHeight)
	local floorMaterial, ceilingMaterial, foundationMaterial, floorColor, ceilingColor, foundationColor =
		resolveFloorAppearanceFromAttributes(readFloorAppearanceAttributes(model))

	if #usablePoints < 3 then
		clearMeshParts(model, CLIENT_MESH_SUFFIX)
		return model
	end

	local triangles = buildTriangles(usablePoints)
	buildSurfaceMeshes(
		model,
		plotPart,
		usablePoints,
		triangles,
		levelIndex,
		raiseHeight,
		floorMaterial,
		ceilingMaterial,
		foundationMaterial,
		floorColor,
		ceilingColor,
		foundationColor,
		false,
		true,
		CLIENT_MESH_SUFFIX
	)

	return model
end

function Formex.Floors.ApplyClientMaterials(model: Model)
	local floorData = buildFloorDataFromAttributes(model)
	local floorMaterial, ceilingMaterial, foundationMaterial, floorColor, ceilingColor, foundationColor =
		applyFloorAttributes(model, floorData)
	local levelIndex = floorData.LevelIndex or getLevelIndexFromModel(model)
	applyMeshMaterials(
		model,
		levelIndex,
		floorMaterial,
		ceilingMaterial,
		foundationMaterial,
		floorColor,
		ceilingColor,
		foundationColor,
		CLIENT_MESH_SUFFIX
	)
end

function Formex.Floors.DestroyClientMeshes(model: Model)
	if not model or model.Parent == nil then
		return
	end
	clearMeshParts(model, CLIENT_MESH_SUFFIX)
end

function Formex.Floors.Create(
	floor: Formex.FloorData,
	plotPartOverride: BasePart?,
	parentOverride: Instance?,
	plotData: Formex.PlotData?
): Model?
	-- Create is currently an alias to Edit to reuse mesh generation logic.
	if not floor or not floor.Points then
		return nil
	end

	return Formex.Floors.Edit(floor, plotPartOverride, parentOverride, plotData)
end

return Formex.Floors
