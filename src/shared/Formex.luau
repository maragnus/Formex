--!strict

--    ___
--   / __\__  _ __ _ __ ___   _____  __
--  / _\/ _ \| '__| '_ ` _ \ / _ \ \/ /
-- / / | (_) | |  | | | | | |  __/>  <
-- \/   \___/|_|  |_| |_| |_|\___/_/\_\
-- Formex by NexArc Solutions <roblox@nexarc.dev>

local DATA_VERSION: number = 2
local INITIAL_BUFFER_SIZE: number = 1024
local SNAP_WALLS_TO_45_DEGREES: boolean = false

local Buffer = require(script.Parent.Buffer)

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

--[[ Old LevelData and FloorData format
export type LevelData = {
	Walls: {[number]: WallData}, -- [WallId: WallData]
	Floors: {[number]: number | nil}, -- [Formex.XYToIndex(x, y)]: Formex.Materials[index] | nil
	Ceilings: {[number]: number | nil}, -- [Formex.XYToIndex(x, y)]: Formex.Materials[index] | nil
	Objects: {[number]: ObjectData}, -- [ObjectId: ObjectData]
	Part: Part?

export type FloorData = {
	FloorId: number,
	LevelIndex: number,
	Tile: Vector2int16,
	Type: FloorType,
	FloorMaterial: number?,
	CeilingMaterial: number?,
	FloorMaterial2: number?,
	CeilingMaterial2: number?,
	Part: Part?
}
]]

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

-- Module constants

local Formex = {}

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

Formex.Materials = {
	{
		Name = "Structure",
		Material = Enum.Material.Wood,
		StudsPerTile = 4,
		AssetId = 10536172711,
	},
	{
		Name = "Checked Tile",
		Material = Enum.Material.CeramicTiles,
		AssetId = 10536172734,
		StudsPerTile = 8,
		Categories = { "Floor", "Wall", "Ceiling" }
	},
	{
		Name = "Beige Tile",
		Material = Enum.Material.CeramicTiles,
		AssetId = 125491924817688,
		StudsPerTile = 4,
		Categories = { "Floor" }
	}
} :: {number: MaterialInfo}

Formex.Icons = { -- Content.fromAssetId(...)
    Menu = 123614418099512,
    Refresh = 123101975679190,
    AddItem = 128647721275129,
    MoveItem = 83970836971222,
	RotateItem = 101431557821612,
    ResizeItem = 78551851583998,
    DeleteItem = 91738865172085,
    WallExtend = 128647721275129,
    WallDivide = 116931266034105,
    WallDisconnect = 70397467113579,
    PlotExpand = 88488799504419,
    PlotRename = 74166756362476,
    PlotClaim = 85199762467908,
    PlotRelease = 137711830774408,
    PlotPermissions = 83277863761797,
    DesignStart = 78727585562674,
    DesignFurniture = 120639802680464,
    DesignCeilings = 86944909652185,
    DesignFloors = 136537860205120,
    DesignWalls =  105416010695180,
    DesignPaint = 92885878760720,
    Undo = 118863163301402,
    Redo = 118241293985419,
    ChevronDown = 84853982697443,
    ChevronUp = 125753605575669,
    AlertPrimary = 103853485477063,
    AlertSecondary = 115719232269249,
    AlertInfo = 119134101744939,
    AlertWarn = 111518129231234,
    AlertDanger = 73134495809587,
	SecurityLock = 71709652798579,
	SecurityUnlock = 95498189643385,
	SecurityKey = 115917399534136,
	Camera = 70772215979759,
    CircleBackground = 114484129436279,
} :: {[string]: number}

Formex.Furniture = {
	{
		Name = "Modern Chair",
		IconAssetId = 128201486227303,
		PrefabName = "Chairs/ModernChair",
		Size = Vector3.new(4, 6, 4),
		Categories = { "Seating", "Indoors" },
	},
} :: {ObjectInfo}

local TileColumns = Formex.LayoutGrid.Columns
function Formex.IndexToXY(index: number): Vector2int16
	local zeroIndex = index - 1
	local x = zeroIndex % TileColumns
	local y = math.floor(zeroIndex / TileColumns)
	return Vector2int16.new(x, y)
end

function Formex.XYToIndex(x: number, y: number): number
	return x + y * TileColumns + 1
end

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

local EPSILON = 1e-4

local function isGridSnapped(value: number): boolean
	local scaled = value / Formex.GridSize
	return math.abs(scaled - math.round(scaled)) <= EPSILON
end

local function isPointGridSnapped(point: Vector2): boolean
	return isGridSnapped(point.X) and isGridSnapped(point.Y)
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

local function resolveMaterial(materialName: string?): Enum.Material
	if materialName and Enum.Material[materialName] then
		return Enum.Material[materialName]
	end
	return Enum.Material.SmoothPlastic
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

local function isConvex(a: Vector2, b: Vector2, c: Vector2, isCCW: boolean): boolean
	local cross = (b.X - a.X) * (c.Y - b.Y) - (b.Y - a.Y) * (c.X - b.X)
	return isCCW and cross > EPSILON or not isCCW and cross < -EPSILON
end

local function isPointInTriangle(point: Vector2, a: Vector2, b: Vector2, c: Vector2): boolean
	local v0 = c - a
	local v1 = b - a
	local v2 = point - a

	local dot00 = v0:Dot(v0)
	local dot01 = v0:Dot(v1)
	local dot02 = v0:Dot(v2)
	local dot11 = v1:Dot(v1)
	local dot12 = v1:Dot(v2)

	local denom = dot00 * dot11 - dot01 * dot01
	if math.abs(denom) <= EPSILON then
		return false
	end

	local invDenom = 1 / denom
	local u = (dot11 * dot02 - dot01 * dot12) * invDenom
	local v = (dot00 * dot12 - dot01 * dot02) * invDenom

	return u >= -EPSILON and v >= -EPSILON and (u + v) <= 1 + EPSILON
end

local function triangulatePolygon(points: {Vector2}): {{Vector2}}
	local triangles = {}
	local count = #points
	if count < 3 then
		return triangles
	end

	local indices = {}
	for i = 1, count do
		indices[i] = i
	end

	local isCCW = polygonArea(points) > 0
	local guard = 0
	while #indices >= 3 and guard < 2048 do
		local earFound = false
		for i = 1, #indices do
			local prevIndex = indices[((i - 2) % #indices) + 1]
			local currIndex = indices[i]
			local nextIndex = indices[(i % #indices) + 1]

			local prev = points[prevIndex]
			local curr = points[currIndex]
			local next = points[nextIndex]

			if isConvex(prev, curr, next, isCCW) then
				local hasPointInside = false
				for _, testIndex in ipairs(indices) do
					if testIndex ~= prevIndex and testIndex ~= currIndex and testIndex ~= nextIndex then
						if isPointInTriangle(points[testIndex], prev, curr, next) then
							hasPointInside = true
							break
						end
					end
				end

				if not hasPointInside then
					table.insert(triangles, { prev, curr, next })
					table.remove(indices, i)
					earFound = true
					break
				end
			end
		end

		if not earFound then
			break
		end
		guard += 1
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
	local zAxis = Vector3.new(axisB.X, 0, axisB.Y)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Wedge
	part.Anchored = true
	part.CollisionGroup = Formex.CollisionGroup.Structure
	part.Size = Vector3.new(thickness, lengthA, lengthB)
	part.CFrame = plotPart.CFrame * CFrame.fromMatrix(center, Vector3.yAxis, yAxis, zAxis)
	part.Parent = parent
	return part
end

local function createTriangleWedges(plotPart: BasePart, parent: Instance, a: Vector2, b: Vector2, c: Vector2, levelIndex: number): {Part}
	local ab = b - a
	local ac = c - a
	local bc = c - b
	if ab.Magnitude <= EPSILON or ac.Magnitude <= EPSILON or bc.Magnitude <= EPSILON then
		return {}
	end

	local angleA = math.acos(math.clamp(ab:Dot(ac) / (ab.Magnitude * ac.Magnitude), -1, 1))
	local angleB = math.acos(math.clamp((-ab):Dot(bc) / (ab.Magnitude * bc.Magnitude), -1, 1))
	local angleC = math.pi - angleA - angleB

	local rightVertex = a
	local other1 = b
	local other2 = c

	if angleB <= angleA and angleB <= angleC then
		rightVertex = b
		other1 = a
		other2 = c
	elseif angleC <= angleA and angleC <= angleB then
		rightVertex = c
		other1 = a
		other2 = b
	end

	local baseDir = other2 - other1
	local baseLength = baseDir.Magnitude
	if baseLength <= EPSILON then
		return {}
	end

	local baseUnit = baseDir / baseLength
	local projectionLength = math.clamp((rightVertex - other1):Dot(baseUnit), 0, baseLength)
	local foot = other1 + baseUnit * projectionLength

	local wedges = {}
	local legA = rightVertex - foot
	local legB = other1 - foot
	if legA.Magnitude > EPSILON and legB.Magnitude > EPSILON then
		table.insert(wedges, createWedgePart(plotPart, parent, foot, legA, legB, levelIndex))
	end
	local legC = other2 - foot
	if legC.Magnitude > EPSILON and legA.Magnitude > EPSILON then
		table.insert(wedges, createWedgePart(plotPart, parent, foot, legA, legC, levelIndex))
	end

	return wedges
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
			local floorTexture = ensureTexture(part, "Floor", Enum.NormalId.Left)
			local ceilingTexture = ensureTexture(part, "Ceiling", Enum.NormalId.Right)
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

export type SegmentBounds = {
	Index: number,
	Row: number,
	Column: number,
	CFrame: CFrame,
	Position: Vector3,
	Size: Vector3,
	Extents: Vector3,
}

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

function Formex.SerializeLevelData(levels: LevelArray): string
	local writer = Buffer.new(INITIAL_BUFFER_SIZE)
	writer:WriteU16(DATA_VERSION)

	-- Serialize levels
	for levelIndex = 1, Formex.MaxPlotSize.Levels do
		local levelData = levels[levelIndex] :: LevelData

		if levelData then
			writer:WriteU8(levelIndex)

			-- Walls
			for wallId, wall in levelData.Walls do
				writer:WriteU16(wallId)
				writer:WriteI16(wall.Start.X)
				writer:WriteI16(wall.Start.Y)
				writer:WriteI16(wall.End.X)
				writer:WriteI16(wall.End.Y)
				writer:WriteU8(wall.FrontMaterial or 0)
				writer:WriteU8(wall.BackMaterial or 0)
				writer:WriteU8(wall.StartMaterial or 0)
				writer:WriteU8(wall.EndMaterial or 0)
			end
			writer:WriteU16(0)

			-- Floors
			for floorId, floor in levelData.Floors do
				local points = floor.Points or {}
				writer:WriteU16(floorId)
				writer:WriteU8(floor.FloorMaterial or 0)
				writer:WriteU8(floor.CeilingMaterial or 0)
				writer:WriteU8(#points)
				for _, point in ipairs(points) do
					writer:WriteI16(point.X)
					writer:WriteI16(point.Y)
				end
			end
			writer:WriteU16(0)

			-- Objects
			for objectId, object in levelData.Objects do
				writer:WriteU16(objectId)
				writer:WriteF32(object.Position.X)
				writer:WriteF32(object.Position.Y)
				writer:WriteF32(object.Position.Z)
				writer:WriteF32(object.Rotation.X)
				writer:WriteF32(object.Rotation.Y)
				writer:WriteF32(object.Rotation.Z)
				writer:WriteU16(object.WallId or 0)
				for designIndex, value in object.Design do
					writer:WriteU16(designIndex)
					writer:WriteString(value)
				end
				writer:WriteU16(0)
			end
			writer:WriteU16(0)

		else
			writer:WriteU8(0) -- levelIndex
			writer:WriteU16(0) -- walls terminator
			writer:WriteU16(0) -- floors terminator
			writer:WriteU16(0) -- objects terminator
		end
	end

	return writer:ToString()
end

local function deserializeLevelDataV1(reader): LevelArray
	local result = {} :: LevelArray

	for i = 1, Formex.MaxPlotSize.Levels do
		local levelData: LevelData = {
			Walls = {},
			Floors = {},
			Objects = {},
		}

		local levelIndex = reader:ReadU8()
		if levelIndex ~= 0 then
			result[levelIndex] = levelData
		end

		-- Walls
		while true do
			local wallId = reader:ReadU16()
			if wallId == 0 then break end

			local wall: WallData = {
				WallId = wallId,
				Level = levelIndex,
				Start = Vector2int16.new(reader:ReadI16(), reader:ReadI16()),
				End = Vector2int16.new(reader:ReadI16(), reader:ReadI16()),
				FrontMaterial = reader:ReadU8(),
				BackMaterial = reader:ReadU8(),
				StartMaterial = reader:ReadU8(),
				EndMaterial = reader:ReadU8(),
			}
			levelData.Walls[wallId] = wall
		end

		local legacyFloors = {}
		while true do
			local index = reader:ReadU16()
			if index == 0 then break end
			legacyFloors[index] = reader:ReadU8()
		end

		local legacyCeilings = {}
		while true do
			local index = reader:ReadU16()
			if index == 0 then break end
			legacyCeilings[index] = reader:ReadU8()
		end

		for index, floorMaterial in legacyFloors do
			local ceilingMaterial = legacyCeilings[index] or floorMaterial
			local tile = Formex.IndexToXY(index)
			local tileSize = Formex.LayoutGridSize
			local x0 = tile.X * tileSize - (Formex.Dimensions.Width / 2)
			local z0 = tile.Y * tileSize - (Formex.Dimensions.Depth / 2)
			levelData.Floors[index] = {
				FloorId = index,
				LevelIndex = levelIndex,
				Points = {
					Vector2int16.new(x0, z0),
					Vector2int16.new(x0 + tileSize, z0),
					Vector2int16.new(x0 + tileSize, z0 + tileSize),
					Vector2int16.new(x0, z0 + tileSize),
				},
				FloorMaterial = floorMaterial,
				CeilingMaterial = ceilingMaterial,
				FloorParts = {},
				CeilingParts = {},
			}
		end
		for index, ceilingMaterial in legacyCeilings do
			if not legacyFloors[index] then
				local tile = Formex.IndexToXY(index)
				local tileSize = Formex.LayoutGridSize
				local x0 = tile.X * tileSize - (Formex.Dimensions.Width / 2)
				local z0 = tile.Y * tileSize - (Formex.Dimensions.Depth / 2)
				levelData.Floors[index] = {
					FloorId = index,
					LevelIndex = levelIndex,
					Points = {
						Vector2int16.new(x0, z0),
						Vector2int16.new(x0 + tileSize, z0),
						Vector2int16.new(x0 + tileSize, z0 + tileSize),
						Vector2int16.new(x0, z0 + tileSize),
					},
					FloorMaterial = ceilingMaterial,
					CeilingMaterial = ceilingMaterial,
					FloorParts = {},
					CeilingParts = {},
				}
			end
		end

		-- Objects
		while true do
			local objectId = reader:ReadU16()
			if objectId == 0 then break end
			local obj = {
				ObjectId = tostring(objectId),
				Level = levelIndex,
				Position = Vector3.new(reader:ReadF32(), reader:ReadF32(), reader:ReadF32()),
				Rotation = Vector3.new(reader:ReadF32(), reader:ReadF32(), reader:ReadF32()),
				WallId = reader:ReadU16(),
				Design = {},
				Properties = {},
			}

			while true do
				local designIndex = reader:ReadU16()
				if designIndex == 0 then break end
				obj.Design[designIndex] = reader:ReadString()
			end

			levelData.Objects[objectId] = obj
		end
	end

	return result
end

local function deserializeLevelDataV2(reader): LevelArray
	local result = {} :: LevelArray

	for i = 1, Formex.MaxPlotSize.Levels do
		local levelData: LevelData = {
			Walls = {},
			Floors = {},
			Objects = {},
		}

		local levelIndex = reader:ReadU8()
		if levelIndex ~= 0 then
			result[levelIndex] = levelData
		end

		-- Walls
		while true do
			local wallId = reader:ReadU16()
			if wallId == 0 then break end

			local wall: WallData = {
				WallId = wallId,
				Level = levelIndex,
				Start = Vector2int16.new(reader:ReadI16(), reader:ReadI16()),
				End = Vector2int16.new(reader:ReadI16(), reader:ReadI16()),
				FrontMaterial = reader:ReadU8(),
				BackMaterial = reader:ReadU8(),
				StartMaterial = reader:ReadU8(),
				EndMaterial = reader:ReadU8(),
			}
			levelData.Walls[wallId] = wall
		end

		while true do
			local floorId = reader:ReadU16()
			if floorId == 0 then break end
			local floorMaterial = reader:ReadU8()
			local ceilingMaterial = reader:ReadU8()
			local pointCount = reader:ReadU8()
			local points = {}
			for _ = 1, pointCount do
				table.insert(points, Vector2int16.new(reader:ReadI16(), reader:ReadI16()))
			end
			levelData.Floors[floorId] = {
				FloorId = floorId,
				LevelIndex = levelIndex,
				Points = points,
				FloorMaterial = floorMaterial,
				CeilingMaterial = ceilingMaterial,
				FloorParts = {},
				CeilingParts = {},
			}
		end

		-- Objects
		while true do
			local objectId = reader:ReadU16()
			if objectId == 0 then break end
			local obj = {
				ObjectId = tostring(objectId),
				Level = levelIndex,
				Position = Vector3.new(reader:ReadF32(), reader:ReadF32(), reader:ReadF32()),
				Rotation = Vector3.new(reader:ReadF32(), reader:ReadF32(), reader:ReadF32()),
				WallId = reader:ReadU16(),
				Design = {},
				Properties = {},
			}

			while true do
				local designIndex = reader:ReadU16()
				if designIndex == 0 then break end
				obj.Design[designIndex] = reader:ReadString()
			end

			levelData.Objects[objectId] = obj
		end
	end

	return result
end

function Formex.DeserializeLevelData(dataString: string): LevelArray
	local reader = Buffer.read(dataString)
	local version = reader:ReadU16()

	if version == 1 then
		return deserializeLevelDataV1(reader)
	elseif version == 2 then
		return deserializeLevelDataV2(reader)
	else
		error("Unsupported data version: " .. tostring(version))
	end
end

return Formex
