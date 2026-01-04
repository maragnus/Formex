--!strict

--    ___
--   / __\__  _ __ _ __ ___   _____  __
--  / _\/ _ \| '__| '_ ` _ \ / _ \ \/ /
-- / / | (_) | |  | | | | | |  __/>  <
-- \/   \___/|_|  |_| |_| |_|\___/_/\_\
-- Formex by NexArc Solutions <roblox@nexarc.dev>

-- Type constants

export type Permission = "Guest" | "Banned" | "VIP" | "Manager" | "Owner"
export type PartType = "Wall" | "Floor" | "Object" | nil
export type CollisionGroup = "Grid" | "Wall" | "Object"
export type DesignMode = "Play" | "Wall" | "Floor" | "Object"

export type MaterialInfo = {
	Name: string,
	AssetId: number,
	Material: Enum.Material,
	StudsPerTile: number,
	Categories: {PartType}
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

export type Wall = {
    Id: number,
    Part: Part,
    Level: Level,
    Start: Vector2int16,
    End: Vector2int16,
    Height: number,
    FrontMaterial: number,
    BackMaterial: number,
    IsGhost: boolean,
    IsSelected: boolean,

    UpdatePoints: (this: Wall, newStart: Vector2int16, newEnd: Vector2int16) -> (),
    SetHeight: (this: Wall, newHeight: number) -> (),
    SetFrontMaterial: (this: Wall, materialId: number) -> (),
    SetBackMaterial: (this: Wall, materialId: number) -> (),
    Select: (this: Wall) -> (),
    Finish: (this: Wall) -> (),
    Delete: (this: Wall) -> (),
}

export type Floor = {
    Id: number,
    Part: Part,
    Level: Level,
    Points: {Vector2int16},
    IsGhost: boolean,
    IsSelected: boolean,

    UpdatePoints: (this: Floor, newPoints: {Vector2int16}) -> (),
    SetHeight: (this: Floor, newHeight: number) -> (),
    SetFloorMaterial: (this: Floor, materialId: number) -> (),
    SetCeilingMaterial: (this: Floor, materialId: number) -> (),
    SetFoundationMaterial: (this: Floor, materialId: number) -> (),
    Select: (this: Floor) -> (),
    Finish: (this: Floor) -> (),
    Delete: (this: Floor) -> (),
}

export type Object = {
    Id: number,
    Part: Part,
    Level: Level,
    ModelId: number,
    Position: Vector3,
    Orientation: Vector3,
    IsGhost: boolean,
    IsSelected: boolean,

    SetPosition: (this: Object, newPosition: Vector3) -> (),
    SetOrientation: (this: Object, newOrientation: Vector3) -> (),
    Select: (this: Object) -> (),
    Finish: (this: Object) -> (),
    Delete: (this: Object) -> (),
}

export type Level = {
    Id: number,
	Plot: Plot,
    Part: Part,
    IsUnlocked: boolean,
    IsActive: boolean,
    CanUnlock: boolean,
    Unlock: () -> (),

    Walls: {this: Level, number: Wall},
    Floors: {this: Level, number: Floor},
    Objects: {this: Level, number: Object},

    AddWall: (this: Level, start: Vector2int16) -> Wall,
    AddFloor: (this: Level, start: Vector2int16) -> Floor,
    AddObject: (this: Level, start: Vector2int16, modelId: number) -> Object,
}

export type Segment = {
    Position: Vector2int16,
    IsUnlocked: boolean,
    CanUnlock: boolean,
    Unlock: () -> (),
}

export type PlotPlayer = {
    UserId: number,
    UserName: string,
    Permission: Permission,
    Color: Color3,
    IsPresent: boolean,
    DesignMode: DesignMode,
    SortOrder: number, -- Plot.Owner = 0, Owner = 1, Manager = 2, VIP = 3, Guest = 4, Banned = 5
}

export type Plot = {
    Id: number,
    Name: string,
    Part: Part,
    OwnerUserId: number?,
    OwnerName: string?,
    MyPermission: Permission,
    SegmentsUnlocked: number,
    LevelsUnlocked: number,
    Segments: {Segment},
    Levels: {number: Level},
    Players: {PlotPlayer},
    CanUndo: boolean,
    CanRedo: boolean,
    DesignMode: DesignMode,
    SelectedPart: Wall | Floor | Object | nil,

    SetName: (this: Plot, newName: string) -> (),
    SetPermission: (this: Plot, userId: number, permission: Permission) -> (),

    SetDesignMode: (this: Plot, mode: DesignMode, levelIndex: number) -> (),
    SelectPart: (this: Plot, part: Wall | Floor | Object) -> (),
    DeselectAll: (this: Plot) -> (),
    Undo: (this: Plot) -> (),
    Redo: (this: Plot) -> (),

    IsPointValid: (this: Plot, point: Vector2 | Vector2int16) -> boolean,
    IsLineValid: (this: Plot, lineStart: Vector2 | Vector2int16, lineEnd: Vector2 | Vector2int16) -> boolean,
    IsPolygonValid: (this: Plot, points: {Vector2 | Vector2int16}) -> boolean,
    IsPointNearBoundary: (this: Plot, point: Vector3, threshold: number) -> boolean,

    -- Events
    -- When Plot.*, Plot.Players, Plot.Segments, or Plot.Levels change (no arguments)
    OnPlotChanged: BindableEvent,
    -- When a Part is added, removed, or changed (part: Wall | Floor | Object)
    OnPartChanged: BindableEvent,
    -- When Plot.SelectedPart changes (no arguments)
    OnSelectionChanged: BindableEvent,
}

-- Module constants

local Formex = {}

local EPSILON = 1e-4
Formex.EPSILON = EPSILON

Formex.GridSize = 2 -- studs
Formex.LayoutGridSize = 4 -- studs
Formex.MaxSaveSlots = 3
Formex.ProximityBorder = 25 -- studs
Formex.InterfloorHeight = 2 -- studs (thickness of floor on upper levels)
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

Formex.DesignMode = table.freeze({
	Play = "Play",
	Wall = "Wall",
	Floor = "Floor",
	Object = "Object",
}) :: {DesignMode: DesignMode}

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

return Formex
