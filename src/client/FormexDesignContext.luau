--!strict
--[[
FormexDesignContext
Owns shared enums/types/constants and stores design dependencies/modules.
Exports:
- Enums, Constants
- Init(context): Context
- Get(): Context
- RegisterModule(name, module): any
- GetModule(name): any?
]]

local Context = {}

export type WallMode = "Full" | "Half" | "Hidden"
export type HandleLocation = "Top" | "Middle" | "Bottom"
export type DesignMode = "Play" | "Design" | "Select" | "Expand" | "Floor" | "Wall" | "Object"
export type DesignSubMode = "Normal" | "Paint" | "Dropper"
export type EditMode = "PointMove" | "PartMove"
export type ActionType = "Select" | "Start" | "Step" | "Rotate" | "Move"
export type SelectionType = "None" | "Wall" | "Floor" | "Object"
export type FloorMode = "Manual" | "Autofill"

export type WallPaintSettings = {
	Height: number?,
	SplitHeight: number?,
	TopMaterial: number,
	BottomMaterial: number,
	TopColor: Color3,
	BottomColor: Color3,
}

export type WallBuildSettings = {
	Height: number?,
	FrontSplitHeight: number?,
	BackSplitHeight: number?,
	FrontTopMaterial: number,
	FrontBottomMaterial: number,
	BackTopMaterial: number,
	BackBottomMaterial: number,
	FrontTopColor: Color3,
	FrontBottomColor: Color3,
	BackTopColor: Color3,
	BackBottomColor: Color3,
}

export type WallSelectedSettings = {
	Height: number?,
	FrontSplitHeight: number?,
	BackSplitHeight: number?,
	FrontTopMaterial: number,
	FrontBottomMaterial: number,
	BackTopMaterial: number,
	BackBottomMaterial: number,
	FrontTopColor: Color3,
	FrontBottomColor: Color3,
	BackTopColor: Color3,
	BackBottomColor: Color3,
	HasSelection: boolean,
}

export type FloorPaintSettings = {
	RaiseHeight: number,
	FloorMaterial: number,
	CeilingMaterial: number,
	FoundationMaterial: number,
	FloorColor: Color3,
	CeilingColor: Color3,
	FoundationColor: Color3,
}

export type FloorSelectedSettings = {
	RaiseHeight: number,
	FloorMaterial: number,
	CeilingMaterial: number,
	FoundationMaterial: number,
	FloorColor: Color3,
	CeilingColor: Color3,
	FoundationColor: Color3,
	HasSelection: boolean,
}

export type ObjectPaintSettings = {
	Design: {[number]: number},
	DesignColors: {[number]: Color3},
}

export type ObjectSelectedSettings = {
	PrefabName: string?,
	Design: {[number]: number},
	DesignColors: {[number]: Color3},
	HasSelection: boolean,
}

export type WallStateUpdate = {
	Height: number | false | nil, -- TODO What does false and nil mean?
	FrontSplitHeight: number | false | nil,
	BackSplitHeight: number | false | nil,
	FrontTopMaterial: number?,
	FrontBottomMaterial: number?,
	BackTopMaterial: number?,
	BackBottomMaterial: number?,
	FrontTopColor: Color3?,
	FrontBottomColor: Color3?,
	BackTopColor: Color3?,
	BackBottomColor: Color3?,
	SplitHeight: number | false | nil,
	TopMaterial: number?,
	BottomMaterial: number?,
	TopColor: Color3?,
	BottomColor: Color3?,
}

export type FloorStateUpdate = {
	Mode: FloorMode?,
	RaiseHeight: number?,
	FloorMaterial: number?,
	CeilingMaterial: number?,
	FoundationMaterial: number?,
	FloorColor: Color3?,
	CeilingColor: Color3?,
	FoundationColor: Color3?,
}

export type DesignState = {
	Mode: DesignMode,
	SubMode: DesignSubMode,
	EditMode: EditMode,
	ActionType: ActionType,
	SelectionType: SelectionType,
	CanUndo: boolean,
	CanRedo: boolean,
	Wall: {
		Selected: WallSelectedSettings,
		Build: WallBuildSettings,
		Paint: WallPaintSettings,
	},
	Floor: {
		Mode: FloorMode,
		Selected: FloorSelectedSettings,
		Paint: FloorPaintSettings,
	},
	Object: {
		PrefabName: string?,
		Selected: ObjectSelectedSettings,
		Paint: ObjectPaintSettings,
	},
}

export type ObjectStateUpdate = {
	PrefabName: string?,
	DesignIndex: number?,
	Material: number?,
	Color: Color3?,
	Design: {[number]: number}?,
	DesignColors: {[number]: Color3}?,
}

export type DesignStateUpdate = {
	Mode: DesignMode?,
	SubMode: DesignSubMode?,
	EditMode: EditMode?,
	CanUndo: boolean?,
	CanRedo: boolean?,
	Wall: WallStateUpdate?,
	Floor: FloorStateUpdate?,
	Object: ObjectStateUpdate?,
}

export type WallModeEnum = {
	Full: WallMode,
	Half: WallMode,
	Hidden: WallMode,
}

export type HandleLocationEnum = {
	Top: HandleLocation,
	Middle: HandleLocation,
	Bottom: HandleLocation,
}

export type FloorModeEnum = {
	Manual: FloorMode,
	Autofill: FloorMode,
}

export type DesignModeEnum = {
	Play: DesignMode,
	Design: DesignMode,
	Select: DesignMode,
	Expand: DesignMode,
	Floor: DesignMode,
	Wall: DesignMode,
	Object: DesignMode,
}

export type DesignSubModeEnum = {
	Normal: DesignSubMode,
	Paint: DesignSubMode,
	Dropper: DesignSubMode,
}

export type EditModeEnum = {
	PointMove: EditMode,
	PartMove: EditMode,
}

export type ActionTypeEnum = {
	Select: ActionType,
	Start: ActionType,
	Step: ActionType,
	Move: ActionType,
	Rotate: ActionType,
}

export type SelectionTypeEnum = {
	None: SelectionType,
	Wall: SelectionType,
	Floor: SelectionType,
	Object: SelectionType,
}

export type Enums = {
	WallMode: WallModeEnum,
	HandleLocation: HandleLocationEnum,
	FloorMode: FloorModeEnum,
	DesignMode: DesignModeEnum,
	DesignSubMode: DesignSubModeEnum,
	EditMode: EditModeEnum,
	ActionType: ActionTypeEnum,
	SelectionType: SelectionTypeEnum,
}

export type Constants = {
	Epsilon: number,
	HandleOffset: number,
	SelectionColor: Color3,
	GhostValidColor: Color3,
	GhostInvalidColor: Color3,
	HandleMoveColor: Color3,
	HandleDeleteColor: Color3,
	HandleAddColor: Color3,
	HandleDisconnectColor: Color3,
	HandleFlipColor: Color3,
	HandleHeightColor: Color3,
	FloorGhostTransparency: number,
}

export type Modules = {
	Walls: any?,
	Floors: any?,
	Objects: any?,
	Handles: any?,
	Highlights: any?,
}

export type Context = {
	FormexClient: any,
	FormexCamera: any,
	Formex: any,
	OverlayFolder: Folder,
	Handles: any,
	Highlight: any,
	Enums: Enums,
	Constants: Constants,
	Modules: Modules,
	GetActionType: () -> ActionType,
	SetActionType: (ActionType) -> (),
	GetDesignMode: () -> DesignMode,
	GetEditMode: () -> EditMode,
	GetCurrentLevel: () -> number,
	SetCurrentLevel: (number) -> (),
	GetViewSettings: () -> any,
	GetSelectionType: () -> SelectionType,
	GetSelectionPart: () -> Instance?,
	GetSelectionSnapshot: () -> any?,
	GetLastInputInfo: () -> any?,
	GetPlotModelFromPlotData: (any, SelectionType, number, number) -> Model?,
	SelectPlotModelByIdAsync: (any, SelectionType, number, number, number?) -> (),
	GetSnappedPoint: (BasePart, Vector3) -> Vector2int16,
	SnapWallEndPoint: (Vector2 | Vector2int16, Vector2) -> Vector2int16,
	ToSnappedVector2int16: (Vector2) -> Vector2int16,
	GetLocalXZ: (BasePart, Vector3) -> Vector2,
	IsPointInOwnedSegments: (any, Vector2) -> boolean,
	BuildWallData: (Vector2int16, Vector2int16) -> any,
	UpdateGhostValidity: (boolean) -> (),
	EnsureWallGhost: (BasePart, Vector2, Vector2) -> (),
	EnsureFloorGhost: (BasePart, number, Vector2int16, any) -> (),
	ClearGhost: () -> (),
	IsGhostActive: () -> boolean,
	IsGhostValid: () -> boolean,
	GetGhostType: () -> any?,
	GetGhostInstance: () -> Instance?,
	GetGhostFloorData: () -> any?,
	GetFloorMode: () -> FloorMode,
	GetFloorMaterialId: () -> number,
	GetCeilingMaterialId: () -> number,
	GetFloorRaiseHeight: () -> number,
	GetFloorColor: () -> Color3,
	GetCeilingColor: () -> Color3,
	GetFoundationMaterialId: () -> number,
	GetFoundationColor: () -> Color3,
	GetWallPaintSettings: () -> WallPaintSettings,
	GetObjectPaintSettings: () -> ObjectPaintSettings,
	GetObjectPrefabName: () -> string?,
	GetObjectSelectedSettings: () -> ObjectSelectedSettings,
	UpdateDesignState: (DesignStateUpdate) -> (),
	NotifyDesignModeChange: () -> (),
	GetTipMessage: () -> string?,
	SetTipMessage: (string?) -> (),
	ClearSelection: () -> (),
	Select: (Instance) -> boolean,
	GetSelectionInfoFromInstance: (Instance?) -> (SelectionType?, number?, number?),
	DeleteAfterDelay: (Instance, number) -> (),
	CancelAction: () -> (),
}

Context.Enums = table.freeze({
	WallMode = table.freeze({
		Full = "Full",
		Half = "Half",
		Hidden = "Hidden",
	}),
	HandleLocation = table.freeze({
		Top = "Top",
		Middle = "Middle",
		Bottom = "Bottom",
	}),
	FloorMode = table.freeze({
		Manual = "Manual",
		Autofill = "Autofill",
	}),
	DesignMode = table.freeze({
		Play = "Play",
		Design = "Design",
		Select = "Select",
		Expand = "Expand",
		Floor = "Floor",
		Wall = "Wall",
		Object = "Object",
	}),
	DesignSubMode = table.freeze({
		Normal = "Normal",
		Paint = "Paint",
		Dropper = "Dropper",
	}),
	EditMode = table.freeze({
		PointMove = "PointMove",
		PartMove = "PartMove",
	}),
	ActionType = table.freeze({
		Select = "Select",
		Start = "Start",
		Step = "Step",
		Move = "Move",
		Rotate = "Rotate",
	}),
	SelectionType = table.freeze({
		None = "None",
		Wall = "Wall",
		Floor = "Floor",
		Object = "Object",
	}),
}) :: Enums

local selectionColor = Color3.fromRGB(255, 201, 107)
local handleDeleteColor = Color3.fromRGB(245, 110, 110)
local handleAddColor = Color3.fromRGB(118, 214, 136)
local handleDisconnectColor = Color3.fromRGB(255, 164, 92)
local handleAdjustColor = Color3.fromRGB(104, 170, 255)

Context.Constants = table.freeze({
	Epsilon = 1e-4,
	HandleOffset = 5,
	SelectionColor = selectionColor,
	GhostValidColor = selectionColor,
	GhostInvalidColor = handleDeleteColor,
	HandleMoveColor = selectionColor,
	HandleDeleteColor = handleDeleteColor,
	HandleAddColor = handleAddColor,
	HandleDisconnectColor = handleDisconnectColor,
	HandleFlipColor = handleAdjustColor,
	HandleHeightColor = handleAdjustColor,
	FloorGhostTransparency = 0.6,
}) :: Constants

local current: Context? = nil

function Context.Init(context: Context): Context
	if not context.Enums then
		context.Enums = Context.Enums
	end
	if not context.Constants then
		context.Constants = Context.Constants
	end
	if not context.Modules then
		context.Modules = {}
	end
	current = context
	return context
end

function Context.Get(): Context
	if not current then
		error("FormexDesignContext not initialized", 2)
	end
	return current
end

function Context.RegisterModule(name: string, module: any): any
	local ctx = Context.Get()
	ctx.Modules[name] = module
	return module
end

function Context.GetModule(name: string): any?
	local ctx = Context.Get()
	return ctx.Modules[name]
end

return Context
