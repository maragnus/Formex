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
	Levels: {[number]: LevelData},
	LevelsUnlocked: number,
	SegmentsUnlocked: number,
	Permissions: {[number]: Permission},
}

export type LevelData = {
	Walls: {[number]: WallData},
	Floors: {[number]: FloorData},
	Objects: {[number]: ObjectData},
	Part: BasePart?
}

export type WallData = {
	WallId: number,
	Level: number,
	Start: Vector2,
	End: Vector2,
	FrontMaterial: string,
	BackMaterial: string,
	Part: BasePart?
}

export type FloorData = {
	FloorId: number,
	Level: number,
	Points: {Vector2},
	FloorType: SurfaceType,
	FloorMaterial: string,
	CeilingType: SurfaceType,
	CeilingMaterial: string,
	Part: BasePart?
}

export type ObjectData = {
	ObjectId: string,
	Level: number,
	Position: Vector3,
	Rotation: Vector3,
	WallId: number?, -- If mounted to a wall
	Design: {[number]: string},
	Properties: {[string]: any},
	Part: BasePart?
}

export type BuildAction = "Add" | "Delete" | "Edit"

-- Module constants

local Formex = {}

Formex.Permissions = {
	Banned = "Banned",
	Guest = "Guest",
	VIP = "VIP",
	Manager = "Manager",
	Owner = "Owner"
} :: { Permission: Permission }
Formex.LevelHeight = 10 -- studs
Formex.GridSize = 2 -- studs
Formex.MaxSaveSlots = 3
Formex.ProximityBorder = 25 -- studs

-- Upgrade segment size
Formex.SegmentSize = {
	Width = 64,  -- studs
	Depth = 64,  -- studs
	Height = 10, -- studs (level height)
	Interfloor = 2,  -- studs (thickness of floor on upper levels)
	Foundation = 10 -- studs (thickness of foundation floor)
}
Formex.MaxPlotSize = {
	Width = 3, -- segments
	Height = 3, -- segments
	Levels = 4 -- segments
}
Formex.Dimensions = {
	Width = Formex.SegmentSize.Width * Formex.MaxPlotSize.Width, -- studs
	Depth = Formex.SegmentSize.Depth * Formex.MaxPlotSize.Height, -- studs
	Height = Formex.LevelHeight * Formex.MaxPlotSize.Levels -- studs
}
Formex.Grid = Formex.GridSize
Formex.Functions = {
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
}
Formex.Segments = {
	GridWidth = Formex.MaxPlotSize.Width,
	GridHeight = Formex.MaxPlotSize.Height,
	DefaultIndex = math.ceil((Formex.MaxPlotSize.Width * Formex.MaxPlotSize.Height) / 2),
}
Formex.Segments.Count = Formex.Segments.GridWidth * Formex.Segments.GridHeight
Formex.BuildActions = {
	Add = "Add",
	Delete = "Delete",
	Edit = "Edit"
} :: {BuildAction: BuildAction}

function Formex.IsWallValid(plot: PlotData, wall: WallData)
	return true -- TODO walls can appear along the outside border of owned segments, but cannot start, end, or overlap unowned segments
end

function Formex.CreateWall(level: BasePart, wall: WallData): Part
	local part = Instance.new("Part", level)
	part.Name = tostring(wall.WallId)
	wall.Part = part
	Formex.EditWall(wall)
	return part
end

function Formex.EditWall(wall: WallData)
	local part = wall.Part
	local height = Formex.Dimensions.Height
	-- TODO set Position and Size
end

function Formex.DivideWall(wall: WallData, distance: number): {WallData}
	-- TODO returns two new walls split at `distance` from `wall.Start`
end

function Formex.IsFloorValid(plot: PlotData, floor: FloorData)
	return true -- TODO walls can appear along the outside border of owned segments, but cannot have points in or overlap with unowned segments, they also cannot overlap each other
end

function Formex.CreateFloor(level: BasePart, floor: FloorData): Part
	local part = Instance.new("MeshPart", level)
	floor.Part = part
	part.Name = tostring(floor.WallId)
	Formex.EditFloor(floor)
	return floor
end

function Formex.EditFloor(floor: FloorData)
	local part = floor.Part
	local height = floor.Level == 1 and Formex.Dimensions.Foundation or Formex.Dimensions.Interfloor
	-- TODO set Position, Size, EditableMesh
	-- Mesh should always have Top as the floor, and Bottom as the ceiling below
	-- Mesh needs UV points set relative to the entire plot
end

function Formex.DivideFloor(wall: WallData, point1: Vector2, point2: Vector2): {FloorData}
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

function Formex.GetSegmentBounds(plotPart: BasePart, segmentIndex: number, levelsUnlocked: number?): SegmentBounds
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

return Formex
