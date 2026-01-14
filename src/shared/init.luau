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
export type ObjectSide = "Front" | "Back"
export type WallPart = "FrontBottom" | "FrontTop" | "BackBottom" | "BackTop"

-- Client shared represenation
export type PlotSaveInfo = {
	SaveId: number,
	Name: string,
	LastPlayed: number,
	Properties: {[string]: any}?
}

export type LevelArray = {[number]: LevelData}

--[[
	PlotData representations the full data structure of a Formex plot,
	including all levels, walls, floors, objects, and rooms.

	It is synchronized between the client and server.
	Client-side uses Attribute subscriptions to maintain the in-memory structures.
]]

-- Stored representation
export type PlotData = {
	-- Serialized properties
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
	-- Serialized properties
	LevelIndex: number,
	Walls: {[number]: WallData}, -- {[WallId]: WallData}
	Floors: {[number]: FloorData}, -- {[FloorId]: FloorData}
	Objects: {[number]: ObjectData}, -- {[ObjectId]: ObjectData}
	Rooms: {[number]: RoomData}, -- {[RoomId]: RoomData}

	-- Runtime properties
	Part: Part,
	WallFolder: Folder,
	FloorFolder: Folder,
	ObjectFolder: Folder,
}

export type WallData = {
	-- Serialized properties
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

	-- Runtime properties
	Part: Model?,
	FrontBottomPart: Part?,
	BackBottomPart: Part?,
	FrontTopPart: Part?,
	BackTopPart: Part?,
	FrontRoom: number?, -- HELPER: rooms on either side of wall
	BackRoom: number?, -- HELPER: rooms on either side of wall
}

export type FloorData = {
	-- Serialized properties
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

	-- Runtime properties
	Model: Model?,
	FloorPart: BasePart?,
	FoundationPart: BasePart?,
	CeilingPart: BasePart?,
	FloorClientPart: BasePart?,
	FoundationClientPart: BasePart?,
	CeilingClientPart: BasePart?,
	Room: number, -- HELPER: rooms on either side of wall
}

export type ObjectData = {
	-- Serialized properties
	ObjectId: number,
	Level: number,
	Position: Vector3,
	Rotation: Vector3,
	Side: ObjectSide,
	WallId: number?, -- if mounted to a wall
	Design: {[number]: number}, -- [part index]: material index
	DesignColors: {[number]: Color3},
	PrefabName: string?,
	Properties: {[string]: any}?,

	-- Runtime properties
	IsPortal: boolean, -- calculated from Prefab.ObjectMount=Door, indicates a doorway into adjacent room
	Prefab: ObjectPrefab,
	Part: Model?,
	ObjectModel: Model?,
	SubtractModel: Model?,
	DesignParts: {[number]: {BasePart}}, -- [part index]: {parts}
	Room: number?, -- HELPER: room containing this object
}

export type BuildChange = {
	PartType: PartType,
	Action: BuildAction,
	Data: WallData | {WallData} | FloorData | {FloorData} | ObjectData,
}

export type BuildChangeResult = {
	PartType: PartType,
	Action: BuildAction,
	Result: any?,
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
	EdgeWalls: {number?},
	Walls: {number},  -- HELPER: [WallId]
	Floors: {number}, -- HELPER: [FloorId]
	Objects: {number}, -- HELPER: [ObjectId]
	NeighboringRooms: {[number]: RoomConnection}, -- [RoomId]: RoomData
	Area: number,
	IsExterior: boolean,
	IsCovered: boolean,
}

export type RoomConnection = {
	Room1: RoomData,
	Room2: RoomData,
	IsConnected: boolean,
	Portals: {number} -- HELPER: [ObjectId]
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

export type PolySegment = {
	Start: Vector2int16,
	End: Vector2int16,
	Kind: "Wall" | "Floor",
	WallId: number?,
	FloorId: number?,
	IsBoundary: boolean?,
}

export type PolyDirectedEdge = {
	Id: number,
	Start: Vector2int16,
	End: Vector2int16,
	StartKey: string,
	EndKey: string,
	Angle: number,
	Kind: "Wall" | "Floor",
	WallId: number?,
	FloorId: number?,
	IsBoundary: boolean?,
	NextId: number?,
	Visited: boolean,
}

export type PolyFace = {
	Points: {Vector2int16},
	Edges: {PolyDirectedEdge},
	Area: number,
}

export type TransactionOptions = {
	Commit: boolean?,
}

export type TransactionResult = {
	IsValid: boolean,
	Error: string?,
	DidChange: boolean,
	Results: {BuildChangeResult},
	LevelsTouched: {number},
	MergeSegments: {{ Level: number, Start: Vector2int16, End: Vector2int16 }},
	RemovedObjects: {{ Level: number, ObjectId: number | string }},
	UpdatedWalls: {{ Level: number, WallId: number }},
	AddedWalls: {{ Level: number, WallId: number }},
	RemovedWalls: {{ Level: number, WallId: number }},
	UpdatedFloors: {{ Level: number, FloorId: number }},
	AddedFloors: {{ Level: number, FloorId: number }},
	RemovedFloors: {{ Level: number, FloorId: number }},
	UpdatedObjects: {{ Level: number, ObjectId: number | string }},
	AddedObjects: {{ Level: number, ObjectId: number | string }},
	Levels: LevelArray?,
	NextId: number?,
	Rollback: (() -> ())?,
}

-- Module constants

local Formex = {}

local EPSILON = 1e-4
Formex.EPSILON = EPSILON

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
}) :: { [Permission]: Permission }

Formex.BuildAction = table.freeze({
	Add = "Add",
	Delete = "Delete",
	Edit = "Edit"
}) :: {[BuildAction]: BuildAction}

Formex.PartType = table.freeze({
	Wall = "Wall",
	Floor = "Floor",
	Ceiling = "Ceiling",
	Object = "Object",
	All = nil,
}) :: {[PartType]: PartType}

Formex.CollisionGroup = {
	Grid = "FormexGrids",
	Object = "FormexObjects",
	Structure = "FormexStructure",
} :: {[CollisionGroup]: string}

Formex.ObjectMount = table.freeze({
	Surface = "Surface", -- placeable on any surface, floor or table
	Ceiling = "Ceiling", -- must be placed on ceiling
	Floor = "Floor", -- must be placed on floor
	Wall = "Wall", -- must be placed on wall
	Door = "Door", -- must be placed in wall opening on floor
	Window = "Window", -- must be placed in wall opening at any height
}) :: {[ObjectMount]: ObjectMount}

Formex.ObjectSide = table.freeze({
	Front = "Front",
	Back = "Back",
}) :: {[ObjectSide]: ObjectSide}

Formex.WallPart = table.freeze({
	FrontBottom = "FrontBottom",
	FrontTop = "FrontTop",
	BackBottom = "BackBottom",
	BackTop = "BackTop",
}) :: {[WallPart]: WallPart}

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
Formex.Materials = {} :: {[number]: MaterialInfo}
Formex.Furniture = {} :: {ObjectPrefab}

-- Network function names
Formex.Function = table.freeze({
	ClaimPlot = "ClaimPlot",
	ReleasePlot = "ReleasePlot",
	RenamePlot = "RenamePlot",
	ListSaves = "ListSaves",
	LoadSave = "LoadSave",
	PlotLoad = "PlotLoad",
	DeletePlot = "DeletePlot",
	NewSave = "NewSave",
	GetPermissions = "GetPermissions",
	SetPermission = "SetPermission",
	UnlockSegment = "UnlockSegment",
	BuildWall = "BuildWall",
	BuildFloor = "BuildFloor",
	BuildObject = "BuildObject",
	BuildTransaction = "BuildTransaction",
	CanUndo = "CanUndo",
	CanRedo = "CanRedo",
	Undo = "Undo",
	Redo = "Redo",
}) :: {[string]: string}

Formex.Walls = {} :: {
	IsValid: (plot: PlotData, wall: WallData) -> boolean,
	Create: (wall: WallData, plotPart: BasePart?) -> Model,
	Edit: (wall: WallData, plotPart: BasePart?, allowCreateParts: boolean?) -> (),
	Divide: (wall: WallData, distance: number) -> {WallData},
}
Formex.Floors = {} :: {
	EncodeFloorPoints: (points: {Vector2int16}) -> string,
	DecodeFloorPoints: (value: string?) -> {Vector2int16},
	CleanPolygon: (points: {Vector2int16}) -> {Vector2int16},
	IsValid: (plot: PlotData, floor: FloorData) -> boolean,
	IsFloorValid: (plot: PlotData, floor: FloorData) -> boolean,
	Edit: (floor: FloorData, plotPartOverride: BasePart?, parentOverride: Instance?, plotData: PlotData?) -> Model?,
	RenderClientMeshes: (model: Model, plotPartOverride: BasePart?) -> Model?,
	ApplyClientMaterials: (model: Model) -> (),
	DestroyClientMeshes: (model: Model) -> (),
	Create: (floor: FloorData, plotPartOverride: BasePart?, parentOverride: Instance?, plotData: PlotData?) -> Model?,
}
Formex.Poly = {} :: {
	GetPointKey: (point: Vector2int16) -> string,
	PointsEqual: (a: Vector2int16, b: Vector2int16) -> boolean,
	PolygonArea: (points: {Vector2int16}) -> number,
	IsPointInsidePolygon: (point: Vector2, polygon: {Vector2int16}, includeBoundary: boolean?, epsilon: number) -> boolean,
	SegmentsIntersect: (p1: Vector2, p2: Vector2, q1: Vector2, q2: Vector2, epsilon: number) -> boolean,
	PolygonsIntersect: (a: {Vector2int16}, b: {Vector2int16}, epsilon: number) -> boolean,
	IsPolygonInside: (outer: {Vector2int16}, inner: {Vector2int16}, epsilon: number) -> boolean,
	GetFaceSamplePoint: (points: {Vector2int16}, epsilon: number) -> Vector2?,
	AddPlotBoundarySegments: (formex: any, segments: {PolySegment}, segmentsUnlocked: number?) -> number,
	CollectSegments: (formex: any, plotData: any, levelIndex: number, options: {[string]: any}?) -> ({PolySegment}, number),
	PruneSegments: (segments: {PolySegment}, epsilon: number) -> (),
	SplitSegments: (segments: {PolySegment}, epsilon: number) -> {PolySegment},
	BuildDirectedEdges: (segments: {PolySegment}) -> {PolyDirectedEdge},
	BuildFaces: (directedEdges: {PolyDirectedEdge}) -> {PolyFace},
	TraceFaces: (formex: any, plotData: any, levelIndex: number, options: {[string]: any}?) -> ({PolyFace}, {PolySegment}, number),
}
Formex.Rooms = {} :: {
	RebuildPlotRooms: (formex: any, plotData: any) -> (),
}
Formex.Transaction = {} :: {
	Apply: (plotData: PlotData, changes: {BuildChange}, options: TransactionOptions?) -> TransactionResult,
	Validate: (plotData: PlotData, changes: {BuildChange}) -> TransactionResult,
}
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
Formex.Util = {} :: {
	EnsureFolder: (name: string, parent: Instance) -> Folder,
	DeepClone: (original: any) -> any,
	ApplyMaterial: (part: BasePart, materialId: number?, color: Color3?) -> (),
	UpdateTexture: (part: BasePart, texture: Texture, materialId: number?, color: Color3?) -> (),
	DecodeFloorPoints: (value: string?) -> { Vector2int16 },
	EncodeFloorPoints: (points: { Vector2int16 }) -> string,
}
Formex.Objects = {} :: {
	GetPrefabs: () -> {ObjectPrefab},
	GetPrefab: (prefabName: string?) -> ObjectPrefab?,
	ResolvePrefabModels: (prefab: ObjectPrefab) -> (Model?, Model?),
	GetPrefabRotationOffset: (prefab: ObjectPrefab?) -> CFrame,
	ResolveObjectSide: (side: ObjectSide?) -> ObjectSide,
	GetFloorSurfaceY: (floor: FloorData) -> number,
	GetCeilingSurfaceY: (floor: FloorData) -> number,
	GetFloorAtPosition: (plotData: PlotData?, levelIndex: number, position: Vector2) -> FloorData?,
	GetPrefabBounds: (prefab: ObjectPrefab?, objectModel: Model?) -> (CFrame, Vector3),
	BuildDesignParts: (model: Model) -> {[number]: {BasePart}},
	ApplyDesign: (objectData: ObjectData, objectModel: Model?) -> (),
	EncodeDesign: (design: {[number]: number}?, designColors: {[number]: Color3}?) -> string,
	DecodeDesign: (value: string?) -> ({[number]: number}, {[number]: Color3}),
	EnsureDesignDefaults: (objectData: ObjectData, prefab: ObjectPrefab) -> (),
	SnapVector: (position: Vector3) -> Vector3,
	GetWallBasis: (wall: WallData) -> (Vector3, Vector3, Vector3, number),
	PlaceInWall: (
		plotPart: BasePart,
		boundsOffset: CFrame,
		boundsSize: Vector3,
		baseRotation: CFrame,
		floorHeight: number,
		wall: WallData,
		side: ObjectSide,
		elevation: number,
		distance: number
	) -> CFrame,
	PlaceOnWall: (
		plotPart: BasePart,
		boundsOffset: CFrame,
		boundsSize: Vector3,
		baseRotation: CFrame,
		floorHeight: number,
		wall: WallData,
		side: ObjectSide,
		elevation: number,
		distance: number
	) -> CFrame,
	PlaceOnFloor: (
		plotPart: BasePart,
		boundsOffset: CFrame,
		boundsSize: Vector3,
		baseRotation: CFrame,
		floorHeight: number,
		positionX: number,
		positionZ: number,
		rotationY: number
	) -> CFrame,
	PlaceOnCeiling: (
		plotPart: BasePart,
		boundsOffset: CFrame,
		boundsSize: Vector3,
		baseRotation: CFrame,
		ceilingHeight: number,
		positionX: number,
		positionZ: number,
		rotationY: number
	) -> CFrame,
	PlaceOnSurface: (
		plotPart: BasePart,
		boundsOffset: CFrame,
		boundsSize: Vector3,
		baseRotation: CFrame,
		position: Vector3,
		rotationY: number
	) -> CFrame,
	GetWallCFrame: (
		plotPart: BasePart,
		wall: WallData,
		localPosition: Vector3,
		rotation: Vector3,
		rotationOffset: CFrame?
	) -> CFrame,
	GetWorldCFrame: (plotPart: BasePart, position: Vector3, rotation: Vector3, rotationOffset: CFrame?) -> CFrame,
	GetObjectCFrame: (objectData: ObjectData, prefab: ObjectPrefab, plotPart: BasePart, plotData: PlotData?) -> CFrame?,
	CarveWallObjects: (plotData: PlotData, wallData: WallData, plotPart: BasePart?) -> (),
	CreateObject: (parent: Instance, objectData: ObjectData, plotPart: BasePart?, plotData: PlotData?) -> Model?,
	EditObject: (objectData: ObjectData, plotPart: BasePart?, plotData: PlotData?) -> (),
}
Formex.Segments = Formex.Segments :: {
	GridWidth: number,
	GridHeight: number,
	DefaultIndex: number,
	Count: number,
	GetRowColumn: (index: number) -> (number, number),
	GetIndex: (row: number, column: number) -> number,
	Bit: (index: number) -> number,
	IsUnlocked: (mask: number?, index: number) -> boolean,
	Unlock: (mask: number?, index: number) -> number,
	CountUnlocked: (mask: number?) -> number,
	GetAllUnlocked: (mask: number?) -> {number},
	GetBounds: (plotPart: BasePart, segmentIndex: number, levelsUnlocked: number?) -> SegmentBounds,
}
Formex.Plot = {} :: {
	IsPointNear: (plotCenter: Vector3, position: Vector3, border: number) -> boolean,
	GetLevelOffset: (level: number) -> number,
	IsPointOnSegment: (point: Vector2, startPoint: Vector2, endPoint: Vector2) -> boolean,
	IsPointInUnlockedSegments: (point: Vector2, mask: number?) -> boolean,
	IsLineWithinUnlockedSegments: (
		startPoint: Vector2 | Vector2int16,
		endPoint: Vector2 | Vector2int16,
		mask: number?
	) -> boolean,
}

return Formex
