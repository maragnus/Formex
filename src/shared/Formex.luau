--!strict

--    ___
--   / __\__  _ __ _ __ ___   _____  __
--  / _\/ _ \| '__| '_ ` _ \ / _ \ \/ /
-- / / | (_) | |  | | | | | |  __/>  <
-- \/   \___/|_|  |_| |_| |_|\___/_/\_\
-- Formex by NexArc Solutions <roblox@nexarc.dev>

-- Type constants

export type SurfaceType = "Square" | "Sliced"
export type Permission = "Guest" | "Banned" | "VIP" | "Manager" | "Owner"
export type PartType = "Wall" | "Floor" | "Ceiling" | "Object" | nil
export type BuildAction = "Add" | "Delete" | "Edit"
export type CollisionGroup = "Grid" | "Wall" | "Object"

-- Client shared represenation
export type PlotSaveInfo = {
	SaveId: number,
	Name: string,
	LastPlayed: number,
	Properties: {[string]: any}?
}

export type LevelArray = {[number]: LevelData}

-- Stored representation
export type PlotData = {
	PlotId: number,
	UserId: number,
	SaveId: number,
	Name: string,
	LastPlayed: number,
	FoundationMaterial: number,
	Levels: LevelArray,
	LevelsUnlocked: number,
	SegmentsUnlocked: number,
	Permissions: {[number]: Permission},
}

export type LevelData = {
	Walls: {[number]: WallData}, -- {[WallId]: WallData}
	Floors: {[number]: FloorData}, -- {[FloorId]: FloorData}
	Objects: {[number]: ObjectData}, -- {[ObjectId]: ObjectData}
	Part: Part?
}

export type WallData = {
	WallId: number,
	Level: number,
	Start: Vector2int16,
	End: Vector2int16,
	FrontMaterial: number, -- Formex.Materials[index]
	BackMaterial: number, -- Formex.Materials[index]
	StartMaterial: number?, -- Formex.Materials[index]
	EndMaterial: number?, -- Formex.Materials[index]
	Part: Part?
}

export type FloorData = {
	FloorId: number,
	LevelIndex: number,
	Points: {Vector2int16},
	FloorMaterial: number,
	CeilingMaterial: number,
	FloorParts: {Part},
	CeilingParts: {Part},
	Model: Model?,
}

export type ObjectData = {
	ObjectId: string,
	Level: number,
	Position: Vector3,
	Rotation: Vector3,
	WallId: number?, -- If mounted to a wall
	Design: {[number]: string},
	Properties: {[string]: any},
	Part: Part?
}

export type MaterialInfo = {
	Name: string,
	AssetId: number,
	Material: Enum.Material,
	StudsPerTile: number,
	Categories: {PartType}
}

export type ObjectInfo = {
	Name: string,
	IconAssetId: number,
	PrefabName: string,
	Size: Vector3,
	Categories: {string},
	Properties: {[string]: any}?,
}

export type SegmentBounds = {
	Index: number,
	Row: number,
	Column: number,
	CFrame: CFrame,
	Position: Vector3,
	Size: Vector3,
	Extents: Vector3,
}

-- Module constants

local Formex = {}

local EPSILON = 1e-4
Formex.EPSILON = EPSILON

Formex.Math = {} :: {
	DoLinesIntersect: (p1: Vector2, p2: Vector2, q1: Vector2, q2: Vector2) -> boolean,
	IsSimplePolygon: (polygon: {Vector2}) -> boolean,
	SimplifyPolygon: (polygon: {Vector2}) -> {Vector2},
}
Formex.Serialization = {} :: {
	SerializeLevelData: (levels: LevelArray) -> string,
	DeserializeLevelData: (dataString: string) -> LevelArray,
}

Formex.GridSize = 2 -- studs
Formex.LayoutGridSize = 4 -- studs
Formex.MaxSaveSlots = 3
Formex.ProximityBorder = 25 -- studs
Formex.InterfloorHeight = 2  -- studs (thickness of floor on upper levels)
Formex.FoundationHeight = 8 -- studs (thickness of foundation floor)
Formex.LevelHeight = 12 -- studs (top of floor to top of floor)
Formex.WallThickness = 0.5 -- studs
Formex.SegmenteSize = 64 -- studs (square)
Formex.WallTopMaterial = 1
Formex.DefaultFloorMaterial = 2
Formex.DefaultCeilingMaterial = 2
Formex.DefaultWallMaterial = 2
Formex.DefaultFoundationMaterial = 2 -- Exterior of Level 1 floor
Formex.SnapWallsTo45Degrees = false

Formex.Permission = table.freeze({
        Banned = "Banned",
        Guest = "Guest",
        VIP = "VIP",
        Manager = "Manager",
        Owner = "Owner"
    }) :: { Permission: Permission }

Formex.BuildAction = table.freeze({
        Add = "Add",
        Delete = "Delete",
        Edit = "Edit"
    }) :: {BuildAction: BuildAction}

Formex.PartType = table.freeze({
        Wall = "Wall",
        Floor = "Floor",
        Ceiling = "Ceiling",
        Object = "Object",
        All = nil,
    }) :: {PartType: PartType}

Formex.CollisionGroup = {
	Grid = "FormexGrids",
	Object = "FormexObjects",
	Structure = "FormexStructure",
} :: {CollisionGroup: string}

Formex.MaxPlotSize = {
	Width = 3, -- segments
	Height = 3, -- segments
	Levels = 4 -- segments
}
Formex.Dimensions = {
	Width = Formex.SegmenteSize * Formex.MaxPlotSize.Width, -- studs
	Depth = Formex.SegmenteSize * Formex.MaxPlotSize.Height, -- studs
	Height = Formex.LevelHeight * Formex.MaxPlotSize.Levels -- studs
}
Formex.SegmentSize = {
	Width = Formex.SegmenteSize,
	Depth = Formex.SegmenteSize,
	Height = Formex.LevelHeight,
	Foundation = Formex.FoundationHeight,
	Interfloor = Formex.InterfloorHeight,
}
Formex.LayoutGrid = {
	Columns = math.floor(Formex.Dimensions.Width / Formex.LayoutGridSize),
	Rows = math.floor(Formex.Dimensions.Depth / Formex.LayoutGridSize),
}
Formex.LayoutGrid.Count = Formex.LayoutGrid.Columns * Formex.LayoutGrid.Rows

Formex.Segments = {
	GridWidth = Formex.MaxPlotSize.Width,
	GridHeight = Formex.MaxPlotSize.Height,
	DefaultIndex = math.ceil((Formex.MaxPlotSize.Width * Formex.MaxPlotSize.Height) / 2), -- Starting segment index
}
Formex.Segments.Count = Formex.Segments.GridWidth * Formex.Segments.GridHeight

Formex.Icons = {} :: {[string]: number}
Formex.Materials = {} :: {number: MaterialInfo}
Formex.Furniture = {} :: {ObjectInfo}

-- Network function names
Formex.Function = table.freeze({
	ClaimPlot = "ClaimPlot",
	ReleasePlot = "ReleasePlot",
	RenamePlot = "RenamePlot",
	ListSaves = "ListSaves",
	LoadSave = "LoadSave",
	NewSave = "NewSave",
	GetPermissions = "GetPermissions",
	SetPermission = "SetPermission",
	UnlockSegment = "UnlockSegment",
	BuildWall = "BuildWall",
	BuildFloor = "BuildFloor",
	BuildObject = "BuildObject",
	CanUndo = "CanUndo",
	CanRedo = "CanRedo",
	Undo = "Undo",
	Redo = "Redo",
}) :: {Function: string}

function Formex.UpdateTexture(part: BasePart, texture: Texture, materialId: number)
	local materialInfo = Formex.Materials[materialId]
	if not materialInfo then
		-- part.Material = Enum.Material.Air
		texture.ColorMapContent = Content.fromAssetId(0)
	else
		part.Material = materialInfo.Material or Enum.Material.SmoothPlastic
		texture.ColorMapContent = Content.fromAssetId(materialInfo.AssetId)
		texture.StudsPerTileU = materialInfo.StudsPerTile
		texture.StudsPerTileV = materialInfo.StudsPerTile
	end
end

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
			local x = tonumber(xStr)
			local y = tonumber(yStr)
			if x and y then
				table.insert(points, Vector2int16.new(x, y))
			end
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

local function getSegmentCenter(index: number): (number, number)
	local row, column = Formex.Segments.GetRowColumn(index)
	local xOffset = (column - (Formex.Segments.GridWidth + 1) / 2) * Formex.SegmentSize.Width
	local zOffset = (row - (Formex.Segments.GridHeight + 1) / 2) * Formex.SegmentSize.Depth
	return xOffset, zOffset
end

local function isPointInUnlockedSegments(point: Vector2, mask: number?): boolean
	if not mask or mask == 0 then
		return false
	end

	local halfWidth = Formex.SegmentSize.Width / 2
	local halfDepth = Formex.SegmentSize.Depth / 2

	for index = 1, Formex.Segments.Count do
		if Formex.Segments.IsUnlocked(mask, index) then
			local centerX, centerZ = getSegmentCenter(index)
			if math.abs(point.X - centerX) <= halfWidth + EPSILON
			and math.abs(point.Y - centerZ) <= halfDepth + EPSILON then
				return true
			end
		end
	end

	return false
end

local function isLineWithinUnlockedSegments(startPoint: Vector2 | Vector2int16, endPoint: Vector2 | Vector2int16, mask: number?): boolean
	if not isPointInUnlockedSegments(startPoint, mask) or not isPointInUnlockedSegments(endPoint, mask) then
		return false
	end

	if typeof(startPoint) ~= "Vector2" or typeof(endPoint) ~= "Vector2" then
		startPoint = Vector2.new(startPoint.X, startPoint.Y)
		endPoint = Vector2.new(endPoint.X, endPoint.Y)
	end

	local direction: Vector2 = endPoint - startPoint
	local length = direction.Magnitude
	if length <= EPSILON then return false end

	local step = math.max(Formex.GridSize, 1)
	local steps = math.floor(length / step)
	local unit = direction / length

	for i = 1, steps do
		local point = startPoint + unit * (i * step)
		if not isPointInUnlockedSegments(point, mask) then
			return false
		end
	end

	return true
end

local function cross2(a: Vector2, b: Vector2): number
	return a.X * b.Y - a.Y * b.X
end

local function isPointOnSegment(point: Vector2, startPoint: Vector2, endPoint: Vector2): boolean
	if math.abs(cross2(endPoint - startPoint, point - startPoint)) > EPSILON then
		return false
	end
	local minX = math.min(startPoint.X, endPoint.X) - EPSILON
	local maxX = math.max(startPoint.X, endPoint.X) + EPSILON
	local minY = math.min(startPoint.Y, endPoint.Y) - EPSILON
	local maxY = math.max(startPoint.Y, endPoint.Y) + EPSILON
	return point.X >= minX and point.X <= maxX and point.Y >= minY and point.Y <= maxY
end

local function segmentsIntersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2): boolean
	local ab = b - a
	local cd = d - c
	local ac = c - a
	local ad = d - a
	local ca = a - c
	local cb = b - c

	local cross1 = cross2(ab, ac)
	local cross2Value = cross2(ab, ad)
	local cross3 = cross2(cd, ca)
	local cross4 = cross2(cd, cb)

	if math.abs(cross1) <= EPSILON and isPointOnSegment(c, a, b) then
		return true
	end
	if math.abs(cross2Value) <= EPSILON and isPointOnSegment(d, a, b) then
		return true
	end
	if math.abs(cross3) <= EPSILON and isPointOnSegment(a, c, d) then
		return true
	end
	if math.abs(cross4) <= EPSILON and isPointOnSegment(b, c, d) then
		return true
	end

	return (cross1 > 0 and cross2Value < 0 or cross1 < 0 and cross2Value > 0)
		and (cross3 > 0 and cross4 < 0 or cross3 < 0 and cross4 > 0)
end

local function getOverlapLength(a: Vector2, b: Vector2, c: Vector2, d: Vector2): number
	if math.abs(b.X - a.X) >= math.abs(b.Y - a.Y) then
		local min1, max1 = math.min(a.X, b.X), math.max(a.X, b.X)
		local min2, max2 = math.min(c.X, d.X), math.max(c.X, d.X)
		return math.min(max1, max2) - math.max(min1, min2)
	else
		local min1, max1 = math.min(a.Y, b.Y), math.max(a.Y, b.Y)
		local min2, max2 = math.min(c.Y, d.Y), math.max(c.Y, d.Y)
		return math.min(max1, max2) - math.max(min1, min2)
	end
end

local function isWallIntersectionDisallowed(newStart: Vector2, newEnd: Vector2, existingStart: Vector2, existingEnd: Vector2): boolean
	local newDir = newEnd - newStart
	if math.abs(cross2(newDir, existingStart - newStart)) <= EPSILON
	and math.abs(cross2(newDir, existingEnd - newStart)) <= EPSILON then
		local overlap = getOverlapLength(newStart, newEnd, existingStart, existingEnd)
		if overlap > EPSILON then
			return true
		end
		if isPointOnSegment(newStart, existingStart, existingEnd) or isPointOnSegment(newEnd, existingStart, existingEnd) then
			return false
		end
		return true
	end

	if not segmentsIntersect(newStart, newEnd, existingStart, existingEnd) then
		return false
	end

	if isPointOnSegment(newStart, existingStart, existingEnd) or isPointOnSegment(newEnd, existingStart, existingEnd) then
		return false
	end

	return true
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

local function getLevelOffset(_plotPart: BasePart, level: number): number
	return (math.max(level, 1) - 1) * Formex.SegmentSize.Height
end

local function ensureTexture(part: BasePart, name: string, face: Enum.NormalId): Texture
	local existing = part:FindFirstChild(name)
	if existing and existing:IsA("Texture") then
		existing.Face = face
		return existing
	end

	local texture = Instance.new("Texture")
	texture.Name = name
	texture.Face = face
	texture.Parent = part
	return texture
end

function Formex.IsWallValid(plot: PlotData, wall: WallData)
	if not wall or not wall.Start or not wall.End then
		return false
	end

	if not isPointLayoutGridSnapped(wall.Start) or not isPointLayoutGridSnapped(wall.End) then
		return false
	end

	local dx = wall.End.X - wall.Start.X
	local dz = wall.End.Y - wall.Start.Y
	local length = math.sqrt(dx * dx + dz * dz)
	if length <= EPSILON then
		return false
	end

	-- if math.abs(dx) > EPSILON and math.abs(dz) > EPSILON
	-- and math.abs(math.abs(dx) - math.abs(dz)) > EPSILON then
	-- 	return false
	-- end

	if not isLineWithinUnlockedSegments(wall.Start, wall.End, plot.SegmentsUnlocked) then
		return false
	end

	local levelIndex = wall.Level or 1
	local levels = (plot :: any).Levels
	if levels and levels[levelIndex] then
		local walls = levels[levelIndex].Walls
		if walls then
			for wallId, existing in walls do
				if wallId ~= wall.WallId and existing and existing.Start and existing.End then
					if isWallIntersectionDisallowed(wall.Start, wall.End, existing.Start, existing.End) then
						return false
					end
				end
			end
		end
	end

	return true
end

function Formex.CreateWall(wall: WallData, plotPartOverride: BasePart?): Part
	local part = Instance.new("Part")
	part.Name = tostring(wall.WallId)
	part.Anchored = true
	part.CollisionGroup = Formex.CollisionGroup.Structure
	wall.Part = part
	Formex.EditWall(wall, plotPartOverride)
	return part
end

function Formex.EditWall(wall: WallData, plotPartOverride: BasePart?)
	local part = wall.Part
	if not part then
		return
	end

	local plotPart = plotPartOverride or getPlotPartFromInstance(part)
	if not plotPart then
		return
	end

	local height = Formex.SegmentSize.Height
	local levelIndex = wall.Level or 1
	local startPoint = wall.Start
	local endPoint = wall.End
	local dx = endPoint.X - startPoint.X
	local dz = endPoint.Y - startPoint.Y
	local length = math.max(math.sqrt(dx * dx + dz * dz), 1)

	local levelOffset = getLevelOffset(plotPart, levelIndex)
	local midLocal = Vector3.new((startPoint.X + endPoint.X) / 2, levelOffset + height / 2, (startPoint.Y + endPoint.Y) / 2)
	local worldMid = plotPart.CFrame:PointToWorldSpace(midLocal)

	local dirLocal = Vector3.new(dx, 0, dz)
	if dirLocal.Magnitude <= EPSILON then
		dirLocal = Vector3.new(0, 0, 1)
	end
	local worldDir = plotPart.CFrame:VectorToWorldSpace(dirLocal)

	part.Size = Vector3.new(1, height, length)
	part.CFrame = CFrame.lookAt(worldMid, worldMid + worldDir)
	part.Transparency = 0 -- Disable invisibility in case it was set

	local frontMaterial = wall.FrontMaterial or Formex.DefaultWallMaterial
	local backMaterial = wall.BackMaterial or frontMaterial
	local startMaterial = wall.StartMaterial or frontMaterial
	local endMaterial = wall.EndMaterial or frontMaterial

	local frontTexture = ensureTexture(part, "Front", Enum.NormalId.Left)
	local backTexture = ensureTexture(part, "Back", Enum.NormalId.Right)
	local startTexture = ensureTexture(part, "Start", Enum.NormalId.Back)
	local endTexture = ensureTexture(part, "End", Enum.NormalId.Front)
	local topTexture = ensureTexture(part, "Top", Enum.NormalId.Top)

	Formex.UpdateTexture(part, frontTexture, frontMaterial)
	Formex.UpdateTexture(part, backTexture, backMaterial)
	Formex.UpdateTexture(part, startTexture, startMaterial)
	Formex.UpdateTexture(part, endTexture, endMaterial)
	Formex.UpdateTexture(part, topTexture, Formex.WallTopMaterial)
end

function Formex.DivideWall(wall: WallData, distance: number): {WallData}
	-- TODO returns two new walls split at `distance` from `wall.Start`
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
		if isPointOnSegment(point, a, b) then
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

function Formex.IsFloorValid(plot: PlotData, floor: FloorData)
	if not floor or not floor.Points or #floor.Points < 3 then
		return false
	end

	local points = floor.Points
	local polygon = {}
	for _, point in ipairs(points) do
		if not isPointLayoutGridSnapped(point) then
			return false
		end
		if not isPointInUnlockedSegments(point, plot.SegmentsUnlocked) then
			return false
		end
		table.insert(polygon, toVector2(point))
	end

	for i = 1, #polygon do
		local startPoint = polygon[i]
		local endPoint = polygon[(i % #polygon) + 1]
		if not isLineWithinUnlockedSegments(startPoint, endPoint, plot.SegmentsUnlocked) then
			return false
		end
	end

	local area = math.abs(polygonArea(polygon))
	if area <= EPSILON then
		return false
	end

	return true
end

function Formex.CreateFloor(floor: FloorData, plotPartOverride: BasePart?, parentOverride: Instance?): Model?
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
			local floorTexture = ensureTexture(part, "Floor", floorFace)
			local ceilingTexture = ensureTexture(part, "Ceiling", ceilingFace)
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

function Formex.Segments.GetRowColumn(index: number): (number, number)
	if index < 1 or index > Formex.Segments.Count then
		error("Segment index out of range: " .. tostring(index))
	end

	local row = math.ceil(index / Formex.Segments.GridWidth)
	local column = ((index - 1) % Formex.Segments.GridWidth) + 1
	return row, column
end

function Formex.Segments.GetIndex(row: number, column: number): number
	if row < 1 or row > Formex.Segments.GridHeight or column < 1 or column > Formex.Segments.GridWidth then
		error("Segment row/column out of range: " .. tostring(row) .. "," .. tostring(column))
	end

	return (row - 1) * Formex.Segments.GridWidth + column
end

function Formex.Segments.Bit(index: number): number
	if index < 1 or index > Formex.Segments.Count then
		error("Segment index out of range: " .. tostring(index))
	end

	return bit32.lshift(1, index - 1)
end

function Formex.Segments.IsUnlocked(mask: number?, index: number): boolean
	return bit32.band(mask or 0, Formex.Segments.Bit(index)) ~= 0
end

function Formex.Segments.Unlock(mask: number?, index: number): number
	return bit32.bor(mask or 0, Formex.Segments.Bit(index))
end

function Formex.Segments.CountUnlocked(mask: number?): number
	local unlocked = 0
	for index = 1, Formex.Segments.Count do
		if Formex.Segments.IsUnlocked(mask, index) then
			unlocked += 1
		end
	end
	return unlocked
end

function Formex.Segments.GetAllUnlocked(mask: number?): {number}
	local unlocked = {}
	for index = 1, Formex.Segments.Count do
		if Formex.Segments.IsUnlocked(mask, index) then
			table.insert(unlocked, index)
		end
	end
	return unlocked
end

function Formex.Segments.GetBounds(plotPart: BasePart, segmentIndex: number, levelsUnlocked: number?): SegmentBounds
	local row, column = Formex.Segments.GetRowColumn(segmentIndex)
	local xOffset = (column - (Formex.Segments.GridWidth + 1) / 2) * Formex.SegmentSize.Width
	local zOffset = (row - (Formex.Segments.GridHeight + 1) / 2) * Formex.SegmentSize.Depth
	local height = math.max(1, levelsUnlocked or 1) * Formex.LevelHeight

	local segmentCFrame = plotPart.CFrame * CFrame.new(xOffset, 0, zOffset)
	local size = Vector3.new(Formex.SegmentSize.Width, height, Formex.SegmentSize.Depth)

	return {
		Index = segmentIndex,
		Row = row,
		Column = column,
		CFrame = segmentCFrame,
		Position = segmentCFrame.Position,
		Size = size,
		Extents = size / 2,
	}
end

function Formex.IsNearPlot(plotCenter: Vector3, position: Vector3, border: number): boolean
	local plotDimensions = Formex.Dimensions
	local plotWidth = plotDimensions.Width
	local plotDepth = plotDimensions.Depth
	local plotHeight = plotDimensions.Height

	local xDiff = math.abs(position.X - plotCenter.X)
	local yDiff = math.abs(position.Y - plotCenter.Y)
	local zDiff = math.abs(position.Z - plotCenter.Z)

	return xDiff <= (plotWidth / 2 + border) and yDiff <= (plotHeight / 2 + border) and zDiff <= (plotDepth / 2 + border)
end

function Formex.DeepClone(original)
    local clone = table.clone(original)
    for key, value in original do
        if type(value) == "table" then
            clone[key] = Formex.DeepClone(value)
        end
    end
    return clone
end

function Formex.EnsureFolder(name: string, parent: Instance): Folder
	local folder = parent:FindFirstChild(name)
	if folder and folder:IsA("Folder") then
		return folder :: Folder
	end
	folder = Instance.new("Folder", parent)
	folder.Name = name
	return folder
end

return Formex
