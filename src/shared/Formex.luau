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
	Height: number?, -- studs <NEW FEATURE>
	FrontSplitHeight: number?, -- studs <NEW FEATURE>
	FrontTopColor: Color3?, -- <NEW FEATURE>
	FrontTopMaterial: number?, -- Formex.WallMaterials[index] <NEW FEATURE>
	FrontBottomColor: Color3?, -- <NEW FEATURE>
	FrontBottomMaterial: number?, -- Formex.WallMaterials[index] <NEW FEATURE>
	BackSplitHeight: number?, -- studs <NEW FEATURE>
	BackTopColor: Color3?, -- <NEW FEATURE>
	BackTopMaterial: number?, -- Formex.WallMaterials[index] <NEW FEATURE>
	BackBottomColor: Color3?, -- <NEW FEATURE>
	BackBottomMaterial: number?, -- Formex.WallMaterials[index] <NEW FEATURE>
	Part: Model?,
	FrontPart: Part?,
	BackPart: Part?
}

export type FloorData = {
	FloorId: number,
	LevelIndex: number,
	Points: {Vector2int16},
	FloorMaterial: number?, -- Formex.FloorMaterials[index]
	FloorColor: Color3?, -- <NEW FEATURE>
	CeilingMaterial: number?, -- Formex.FloorMaterials[index]
	CeilingColor: Color3?, -- <NEW FEATURE>
	FoundationMaterial: number?, -- Formex.WallMaterials[index] <NEW FEATURE>
	FoundationColor: Color3?, -- <NEW FEATURE>
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

export type WallMaterialInfo = {
	Name: string,
	Material: Enum.Material?,
	MaterialVariant: string?,
	PreviewAssetId: number?, -- Image
}

export type FloorMaterialInfo = {
	Name: string,
	AssetId: number?, -- Texture.ColorMapContent = Content.fromAssetId(...)
	StudsPerTile: number,
}

export type MaterialInfo = {
	Name: string,
	AssetId: number?,
	Material: Enum.Material,
	StudsPerTile: number,
	Categories: {PartType} -- REMOVE
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
Formex.WallMaterials = {} :: {number: WallMaterialInfo}
Formex.FloorMaterials = {} :: {number: FloorMaterialInfo}
Formex.Walls = {} :: {}
Formex.Floors = {} :: {}
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

return Formex
