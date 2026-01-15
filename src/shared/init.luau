--!strict

--    ___
--   / __\__  _ __ _ __ ___   _____  __
--  / _\/ _ \| '__| '_ ` _ \ / _ \ \/ /
-- / / | (_) | |  | | | | | |  __/>  <
-- \/   \___/|_|  |_| |_| |_|\___/_/\_\
-- Formex by NexArc Solutions <roblox@nexarc.dev>

local SegmenteSize = 64 		-- studs (square) of plot upgrade segment
local LevelHeight = 12 			-- studs (top of floor to top of floor)
local FoundationHeight = 8 		-- studs (thickness of foundation floor)
local InterfloorHeight = 2 		-- studs (thickness of floor on upper levels)
local GridSize = 2 				-- studs (grid texture size)
local ObjectGridSize = 1 		-- studs (object placement grid size)
local LayoutGridSize = 4 		-- studs (wall and floor layout grid size)
local StartingSegments = 2 		-- bits
local MaxPlotSize = {
	Width = 3, -- segments
	Height = 3, -- segments
	Levels = 4 -- segments
}

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
local EPSILON = 1e-4

local Formex = {
	EPSILON = EPSILON,

	GridSize = GridSize, -- studs
	ObjectGridSize = ObjectGridSize, -- studs
	LayoutGridSize = LayoutGridSize, -- studs
	MaxSaveSlots = 3,
	MaxUndoQueueSize = 32,
	ProximityBorder = 25, -- studs
	InterfloorHeight = InterfloorHeight,
	FoundationHeight = FoundationHeight,
	LevelHeight = LevelHeight,
	WallThickness = 0.5, -- studs
	SegmenteSize = 64, -- studs (square)
	MaxFloorPoints = 12, -- per floor
	WallTopMaterial = 1,
	DefaultFloorMaterial = 2,
	DefaultCeilingMaterial = 2,
	DefaultWallMaterial = 2,
	DefaultFoundationMaterial = 2, -- Exterior of Level 1 floor
	SnapWallsTo45Degrees = false,

	Permission = table.freeze({
		Banned = "Banned" :: Permission,
		Guest = "Guest" :: Permission,
		VIP = "VIP" :: Permission,
		Manager = "Manager" :: Permission,
		Owner = "Owner" :: Permission
	}),

	BuildAction = table.freeze({
		Add = "Add" :: BuildAction,
		Delete = "Delete" :: BuildAction,
		Edit = "Edit" :: BuildAction
	}),

	PartType = table.freeze({
		Wall = "Wall" :: PartType,
		Floor = "Floor" :: PartType,
		Ceiling = "Ceiling" :: PartType,
		Object = "Object" :: PartType,
		All = nil,
	}),

	CollisionGroup = {
		Grid = "FormexGrids",
		Object = "FormexObjects",
		Structure = "FormexStructure",
	},

	ObjectMount = table.freeze({
		Surface = "Surface" :: ObjectMount, -- placeable on any surface, floor or table
		Ceiling = "Ceiling" :: ObjectMount, -- must be placed on ceiling
		Floor = "Floor" :: ObjectMount, -- must be placed on floor
		Wall = "Wall" :: ObjectMount, -- must be placed on wall
		Door = "Door" :: ObjectMount, -- must be placed in wall opening on floor
		Window = "Window" :: ObjectMount, -- must be placed in wall opening at any height
	}) :: {[ObjectMount]: ObjectMount},

	ObjectSide = table.freeze({
		Front = "Front" :: ObjectSide,
		Back = "Back" :: ObjectSide,
	}),

	WallPart = table.freeze({
		FrontBottom = "FrontBottom" :: WallPart,
		FrontTop = "FrontTop" :: WallPart,
		BackBottom = "BackBottom" :: WallPart,
		BackTop = "BackTop" :: WallPart,
	}),

	MaxPlotSize = {
		Width = MaxPlotSize.Width, -- segments
		Height = MaxPlotSize.Height, -- segments
		Levels = MaxPlotSize.Levels -- segments
	},

	Dimensions = {
		Width = SegmenteSize * MaxPlotSize.Width, -- studs
		Depth = SegmenteSize * MaxPlotSize.Height, -- studs
		Height = LevelHeight * MaxPlotSize.Levels -- studs
	},

	SegmentSize = {
		Width = SegmenteSize,
		Depth = SegmenteSize,
		Height = LevelHeight,
		Foundation = FoundationHeight,
		Interfloor = InterfloorHeight,
	},

	LayoutGrid = {
		Columns = math.floor(SegmenteSize * MaxPlotSize.Width / LayoutGridSize),
		Rows = math.floor(SegmenteSize * MaxPlotSize.Height / LayoutGridSize),
		Count = 0		
	},

	DefaultSegmentsUnlocked = 2, -- bits

	Icons = {} :: {[string]: number},
	Materials = {} :: {[number]: MaterialInfo},
	Furniture = {} :: {ObjectPrefab},

	-- Network function names
	Function = table.freeze({
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
	}) :: {[string]: string},

	Walls = {} :: {
		IsValid: (plot: PlotData, wall: WallData) -> boolean,
		Create: (wall: WallData, plotPart: BasePart?) -> Model,
		Edit: (wall: WallData, plotPart: BasePart?, allowCreateParts: boolean?) -> (),
		Divide: (wall: WallData, distance: number) -> {WallData},
	},
	Floors = {} :: {
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
	},
	Poly = {} :: {
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
	},
	Rooms = {} :: {
		RebuildPlotRooms: (formex: any, plotData: any) -> (),
	},
	Transaction = {} :: {
		Apply: (plotData: PlotData, changes: {BuildChange}, options: TransactionOptions?) -> TransactionResult,
		Validate: (plotData: PlotData, changes: {BuildChange}) -> TransactionResult,
	},
	Math = {} :: {
		DoLinesIntersect: (p1: Vector2, p2: Vector2, q1: Vector2, q2: Vector2) -> boolean,
		IsSimplePolygon: (polygon: {Vector2}) -> boolean,
		SimplifyPolygon: (polygon: {Vector2}) -> {Vector2},
	},
	Serialization = {} :: {
		SerializeLevelData: (levels: LevelArray) -> string,
		DeserializeLevelData: (dataString: string) -> LevelArray,
		GetMaxPartId: (levels: LevelArray?) -> number,
	},
	Util = {} :: {
		EnsureFolder: (name: string, parent: Instance) -> Folder,
		DeepClone: (original: any) -> any,
		ApplyMaterial: (part: BasePart, materialId: number?, color: Color3?) -> (),
		UpdateTexture: (part: BasePart, texture: Texture, materialId: number?, color: Color3?) -> (),
		DecodeFloorPoints: (value: string?) -> { Vector2int16 },
		EncodeFloorPoints: (points: { Vector2int16 }) -> string,
	},
	Objects = {} :: {
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
	},
	Segments = {
		GridWidth = MaxPlotSize.Width,
		GridHeight = MaxPlotSize.Height,
		DefaultIndex = StartingSegments, -- Starting segment index
		Count = 0,
	} :: {
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
	},
	Plot = {} :: {
		IsPointNear: (plotCenter: Vector3, position: Vector3, border: number) -> boolean,
		GetLevelOffset: (level: number) -> number,
		IsPointOnSegment: (point: Vector2, startPoint: Vector2, endPoint: Vector2) -> boolean,
		IsPointInUnlockedSegments: (point: Vector2, mask: number?) -> boolean,
		IsLineWithinUnlockedSegments: (
			startPoint: Vector2 | Vector2int16,
			endPoint: Vector2 | Vector2int16,
			mask: number?
		) -> boolean,
	},
}

Formex.LayoutGrid.Count = Formex.LayoutGrid.Columns * Formex.LayoutGrid.Rows
Formex.Segments.Count = Formex.Segments.GridWidth * Formex.Segments.GridHeight

return Formex
