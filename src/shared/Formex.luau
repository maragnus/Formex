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
export type FloorType = "Square" | "SlicedCW" | "SlicedCCW"
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

-- Stored representation
export type PlotData = {
	PlotId: number,
	UserId: number,
	SaveId: number,
	Name: string,
	LastPlayed: number,
	FoundationMaterial: number,
	Levels: {[number]: LevelData},
	LevelsUnlocked: number,
	SegmentsUnlocked: number,
	Permissions: {[number]: Permission},
}

export type LevelData = {
	Walls: {[number]: WallData}, -- [WallId: WallData]
	Floors: {[number]: number | nil}, -- [x + y * Formex.SegmentSize / Formex.LayoutGridSize * Formex.MaxPlotSize.Height]: Formex.Materials[index] | nil (none)
	Ceilings: {[number]: number | nil}, -- [x + y * Formex.SegmentSize / Formex.LayoutGridSize * Formex.MaxPlotSize.Height]: Formex.Materials[index] | nil (none)
	Objects: {[number]: ObjectData}, -- [ObjectId: ObjectData]
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
	Tile: Vector2int16,
	Type: FloorType,
	FloorMaterial: number?,
	CeilingMaterial: number?,
	FloorMaterial2: number?,
	CeilingMaterial2: number?,
	Part: Part?
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
	Categories: {string}
}

-- Module constants

local Formex = {}

Formex.GridSize = 2 -- studs
Formex.LayoutGridSize = 4 -- studs
Formex.MaxSaveSlots = 3
Formex.ProximityBorder = 25 -- studs
Formex.InterfloorHeight = 2  -- studs (thickness of floor on upper levels)
Formex.FoundationHeight = 10 -- studs (thickness of foundation floor)
Formex.LevelHeight = 16 -- studs (top of floor to top of floor)
Formex.WallThickness = 0.5 -- studs
Formex.SegmenteSize = 64 -- studs (square)
Formex.WallTopMaterial = 1
Formex.DefaultFloorMaterial = 2
Formex.DefaultCeilingMaterial = 2
Formex.DefaultWallMaterial = 2
Formex.DefaultFoundationMaterial = 2 -- Exterior of Level 1 floor

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
		texture.TextureContent = Content.fromAssetId(0)
	else
		part.Material = materialInfo.Material or Enum.Material.SmoothPlastic
		texture.TextureContent = Content.fromAssetId(materialInfo.AssetId)
		texture.StudsPerTileU = materialInfo.StudsPerTile
		texture.StudsPerTileV = materialInfo.StudsPerTile
	end
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
	BuildCeiling = "BuildCeiling",
	BuildObject = "BuildObject",
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

Formex.FloorType = table.freeze({
	Square = "Square",
	SlicedCW = "SlicedCW",
	SlicedCCW = "SlicedCCW",
}) :: {FloorType: FloorType}

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

local function isLineWithinUnlockedSegments(startPoint: Vector2, endPoint: Vector2, mask: number?): boolean
	if not isPointInUnlockedSegments(startPoint, mask) or not isPointInUnlockedSegments(endPoint, mask) then
		return false
	end

	local direction = endPoint - startPoint
	local length = direction.Magnitude
	if length <= EPSILON then
		return false
	end

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

local function getLevelOffset(plotPart: BasePart, level: number): number
	local plotBase = plotPart.Size.Y / 2
	return plotBase + (math.max(level, 1) - 1) * Formex.SegmentSize.Height
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

	if not isPointGridSnapped(wall.Start) or not isPointGridSnapped(wall.End) then
		return false
	end

	local dx = wall.End.X - wall.Start.X
	local dz = wall.End.Y - wall.Start.Y
	local length = math.sqrt(dx * dx + dz * dz)
	if length <= EPSILON then
		return false
	end

	if math.abs(dx) > EPSILON and math.abs(dz) > EPSILON
	and math.abs(math.abs(dx) - math.abs(dz)) > EPSILON then
		return false
	end

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

	local frontTexture = ensureTexture(part, "Front", Enum.NormalId.Front)
	local backTexture = ensureTexture(part, "Back", Enum.NormalId.Back)
	local startTexture = ensureTexture(part, "Start", Enum.NormalId.Left)
	local endTexture = ensureTexture(part, "End", Enum.NormalId.Right)
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

function Formex.IsFloorValid(plot: PlotData, floor: FloorData)
	if not floor or not floor.Tile then
		return false
	end

	local tile = floor.Tile
	if math.abs(tile.X - math.round(tile.X)) > EPSILON
	or math.abs(tile.Y - math.round(tile.Y)) > EPSILON then
		return false
	end

	if tile.X < 0 or tile.Y < 0
	or tile.X >= Formex.LayoutGrid.Columns
	or tile.Y >= Formex.LayoutGrid.Rows then
		return false
	end

	local halfGrid = Formex.LayoutGridSize / 2
	local xOffset = (tile.X + 0.5) * Formex.LayoutGridSize - (Formex.Dimensions.Width / 2)
	local yOffset = (tile.Y + 0.5) * Formex.LayoutGridSize - (Formex.Dimensions.Depth / 2)
	local center = Vector2.new(xOffset, yOffset)
	local corners = {
		Vector2.new(center.X - halfGrid, center.Y - halfGrid),
		Vector2.new(center.X + halfGrid, center.Y - halfGrid),
		Vector2.new(center.X - halfGrid, center.Y + halfGrid),
		Vector2.new(center.X + halfGrid, center.Y + halfGrid),
	}

	for _, corner in ipairs(corners) do
		if not isPointInUnlockedSegments(corner, plot.SegmentsUnlocked) then
			return false
		end
	end

	local levels = (plot :: any).Levels
	return true
end

function Formex.GetFloorPositionSize(floor: FloorData): (CFrame, Vector3)
	local tileSize = Formex.LayoutGridSize
	local xOffset = (floor.Tile.X + 0.5) * tileSize - (Formex.Dimensions.Width / 2)
	local zOffset = (floor.Tile.Y + 0.5) * tileSize - (Formex.Dimensions.Depth / 2)
	local thickness = floor.LevelIndex == 1 and Formex.SegmentSize.Foundation or Formex.SegmentSize.Interfloor
	local levelTop = Formex.LevelHeight * (floor.LevelIndex - 1)
	local centerY = levelTop - (thickness / 2)

	local position = CFrame.new(xOffset, centerY, zOffset)
	local size = Vector3.new(tileSize, thickness, tileSize)
	return position, size

end

function Formex.UpdateFloor(plotPart: BasePart, floor: FloorData, parent: Instance?): Part?
	if not floor.Tile then
		return nil
	end

	local part = floor.Part
	local altPart: Part?

	if not part then
		parent = parent or plotPart:FindFirstChild(tostring(floor.LevelIndex)):FindFirstChild("Floors")
		part = Instance.new("Part", parent)
		part.Name = tostring(floor.FloorId)
		part.Anchored = true
		part.CollisionGroup = Formex.CollisionGroup.Structure
	end

	if part.Shape ~= Enum.PartType.Block and floor.Type == Formex.FloorType.Square then
		part.Shape = Enum.PartType.Block
		part:FindFirstChildOfClass("Part"):Destroy()
	elseif part.Shape ~= Enum.PartType.Wedge and floor.Type ~= Formex.FloorType.Square then
		part.Shape = Enum.PartType.Wedge
		altPart = part:FindFirstChildOfClass("Part")
		if not altPart then
			altPart = Instance.new("Part", part)
			part.Anchored = true
			part.CollisionGroup = Formex.CollisionGroup.Structure
			part.Shape = Enum.PartType.Wedge
		end
	end

	-- Position and size (if partOverride or new is part)
	if not floor.Part then
		floor.Part = part

		local position, size = Formex.GetFloorPositionSize(floor)
		-- local levelIndex = floor.LevelIndex or 1
		-- local thickness = levelIndex == 1 and Formex.SegmentSize.Foundation or Formex.SegmentSize.Interfloor
		-- local tile = floor.Tile or Vector2.new(0, 0)
		-- local tileSize = Formex.LayoutGridSize
		-- local plotSize = part.Size
		-- local xOffset = (tile.X + 0.5) * tileSize - (plotSize.X / 2)
		-- local zOffset = (tile.Y + 0.5) * tileSize - (plotSize.Z / 2)
		-- local levelTop = (plotSize.Y / 2) + (Formex.LevelHeight * (levelIndex - 1))
		-- local centerY = levelTop - (thickness / 2)

		part.CFrame = plotPart.CFrame * position
		part.Size = size
		part.Transparency = 0
		if altPart then
			altPart.Size = part.Size
			altPart.CFrame = part.CFrame
			altPart.Transparency = 0

			-- TODO set orientations based on floor.Type
			if floor.Type == Formex.FloorType.SlicedCW then
				part.CFrame = part.CFrame * CFrame.Angles(0, math.rad(90), 0)
				altPart.CFrame = altPart.CFrame * CFrame.Angles(0, math.rad(-90), 0)
			elseif floor.Type == Formex.FloorType.SlicedCCW then
				part.CFrame = part.CFrame * CFrame.Angles(0, math.rad(-90), 0)
				altPart.CFrame = altPart.CFrame * CFrame.Angles(0, math.rad(90), 0)
			end
		end
	end

	local floorTexture = ensureTexture(floor.Part, "Floor", Enum.NormalId.Top)
	local ceilingTexture = ensureTexture(floor.Part, "Ceiling", Enum.NormalId.Bottom)

	Formex.UpdateTexture(floor.Part, floorTexture, floor.FloorMaterial or 0)
	Formex.UpdateTexture(floor.Part, ceilingTexture, floor.CeilingMaterial or 0)

	return part
end

function Formex.DivideFloor(floor: FloorData, point1: Vector2, point2: Vector2): {FloorData}
	-- TODO returns two new floors split at line from point1 to point2
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

local function getMaterialIdFromTexture(texture: Texture?): number?
	if not texture or not texture.ColorMap then	return nil end
	local assetId = tonumber(string.match(texture.ColorMap, "rbxassetid://(%d+)"))
	if not assetId then return nil end

	for index, materialInfo in Formex.Materials do
		if assetId == materialInfo.AssetId then
			return index
		end
	end

	return nil
end

function Formex.GetFloorData(plotPart: BasePart, levelIndex: number, tile: Vector2int16, floorPart: Part?): FloorData
	local index = Formex.XYToIndex(tile.X, tile.Y)
	local data = {
		FloorId = index,
		LevelIndex = levelIndex,
		Tile = tile,
		Type = Formex.FloorType.Square,
	} :: FloorData

	if floorPart then
		data.Part = floorPart
	else
		local levelPart = plotPart:FindFirstChild(tostring(levelIndex))
		if not levelPart then return data end

		local floorsFolder = levelPart:FindFirstChild("Floors")
		if not floorsFolder then return data end

		local part = floorsFolder:FindFirstChild(tostring(index))
		if not part then
			part = nil -- TODO: support performance grouping of floors
		end

		if not part then return data end
		data.Part = part
	end

	if data.Part.Shape == Enum.PartType.Wedge then
		local splitPart = data.Part:FindFirstChild("Split")
		if splitPart and splitPart:IsA("Part") then
			if true then -- TODO: identify clockwise vs counter-clockwise based on orientation
				data.Type = Formex.FloorType.SlicedCW
			else
				data.Type = Formex.FloorType.SlicedCCW
			end
			data.FloorMaterial2 = getMaterialIdFromTexture(splitPart:FindFirstChild("Floor"))
			data.CeilingMaterial2 = getMaterialIdFromTexture(splitPart:FindFirstChild("Ceiling"))
		end
	end

	data.FloorMaterial = getMaterialIdFromTexture(data.Part:FindFirstChild("Floor"))
	data.CeilingMaterial = getMaterialIdFromTexture(data.Part:FindFirstChild("Ceiling"))

	return data
end

return Formex
