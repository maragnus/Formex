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
export type ObjectMount = "Surface" | "Ceiling" | "Floor" | "Wall" | "Door" | "Window"

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
	NextId: number,
	FoundationMaterial: number,
	Levels: LevelArray,
	Rooms: {[number]: RoomData},
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
	Height: number?, -- studs
	FrontSplitHeight: number?, -- studs
	FrontTopColor: Color3?,
	FrontTopMaterial: number?, -- Formex.Materials[index]
	FrontBottomColor: Color3?,
	FrontBottomMaterial: number?, -- Formex.Materials[index]
	BackSplitHeight: number?, -- studs
	BackTopColor: Color3?,
	BackTopMaterial: number?, -- Formex.Materials[index]
	BackBottomColor: Color3?,
	BackBottomMaterial: number?, -- Formex.Materials[index]
	Part: Model?,
	FrontPart: Part?,
	BackPart: Part?,
	FrontTopPart: Part?,
	BackTopPart: Part?
}

export type FloorData = {
	FloorId: number,
	LevelIndex: number,
	Points: {Vector2int16},
	RaiseHeight: number, -- studs: 0..(LevelHeight-InterfloorHeight) in GridSize increments
	FloorMaterial: number?, -- Formex.Materials[index]
	FloorColor: Color3?,
	CeilingMaterial: number?, -- Formex.Materials[index]
	CeilingColor: Color3?,
	FoundationMaterial: number?, -- Formex.Materials[index]
	FoundationColor: Color3?,
	Model: Model?,
	FloorPart: BasePart?,
	FoundationPart: BasePart?,
	CeilingPart: BasePart?,
	FloorClientPart: BasePart?,
	FoundationClientPart: BasePart?,
	CeilingClientPart: BasePart?,
}

export type ObjectData = {
	ObjectId: number,
	Level: number,
	Position: Vector3,
	Rotation: Vector3,
	WallId: number?, -- if mounted to a wall
	Design: {[number]: number}, -- [part index]: material index
	DesignColors: {[number]: Color3},
	IsPortal: boolean, -- calculated from Prefab.ObjectMount=Door, indicates a doorway into adjacent room
	Prefab: ObjectPrefab,
	PrefabName: string?,
	Properties: {[string]: any}?,
	Part: Model?,
	Subtract: Model?,
	ObjectModel: Model?,
	SubtractModel: Model?,
	DesignParts: {[number]: {BasePart}}, -- [part index]: {parts}
}

export type MaterialInfo = {
	Name: string,
	Material: Enum.Material?,
	MaterialVariant: string?,
	PreviewAssetId: number?, -- Content.fromAssetId(...)
	Categories: {PartType}?
}

export type ObjectPrefab = {
	Name: string, -- Display Name
	IconAssetId: number,
	PrefabName: string, -- ReplicatedStorage / FormexPrefabs: Folder / PrefabName: Model
	ObjectMount: ObjectMount,
	Size: Vector3,
	Categories: {string},
	DefaultDesign: {[number]: number}, -- [part index]: material index
	Attributes: {[string]: any}?, -- Model:GetAttributes()
	Model: Model?,
}

export type RoomData = {
	RoomId: number,
	LevelIndex: number,
	Points: {Vector2int16},
	Wall: {[number]: WallData}, -- [WallId]: WallData
	Floor: {[number]: FloorData}, -- [FloorId]: FloorData
	Object: {[number]: ObjectData}, -- [ObjectId]: ObjectData
	NeighboringRooms: {[number]: RoomConnection}, -- [RoomId]: RoomData
	Area: number,
	IsExterior: boolean,
	IsCovered: boolean,
}

export type RoomConnection = {
	Room1: RoomData,
	Room2: RoomData,
	IsConnected: boolean,
	Portals: {[number]: ObjectData}
}

export type SelectionSnapshot = {
	Mode: string?,
	SelectionType: string?,
	LevelIndex: number?,
	PartId: number | string?,
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
	GetMaxPartId: (levels: LevelArray?) -> number,
}

Formex.GridSize = 2 -- studs
Formex.ObjectGridSize = 1 -- studs
Formex.LayoutGridSize = 4 -- studs
Formex.MaxSaveSlots = 3
Formex.MaxUndoQueueSize = 32
Formex.ProximityBorder = 25 -- studs
Formex.InterfloorHeight = 2  -- studs (thickness of floor on upper levels)
Formex.FoundationHeight = 8 -- studs (thickness of foundation floor)
Formex.LevelHeight = 12 -- studs (top of floor to top of floor)
Formex.WallThickness = 0.5 -- studs
Formex.SegmenteSize = 64 -- studs (square)
Formex.MaxFloorPoints = 12 -- per floor
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

Formex.MountType = table.freeze({
	Surface = "Surface", -- placeable on any surface, floor or table
	Ceiling = "Ceiling", -- must be placed on ceiling
	Floor = "Floor", -- must be placed on floor
	Wall = "Wall", -- must be placed on wall
	Door = "Door", -- must be placed in wall opening on floor
	Window = "Window", -- must be placed in wall opening at any height
}) :: {ObjectMount: ObjectMount}

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
Formex.DefaultSegmentsUnlocked = 2 -- bits

Formex.Icons = {} :: {[string]: number}
Formex.Materials = {} :: {number: MaterialInfo}
Formex.Walls = {} :: {}
Formex.Floors = {} :: {}
Formex.Furniture = {} :: {ObjectPrefab}

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

return Formex
