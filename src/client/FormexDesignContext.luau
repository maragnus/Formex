--!strict
local Context = {}

export type Context = {
	FormexClient: any,
	FormexCamera: any,
	Formex: any,
	OverlayFolder: Folder,
	Handles: any,
	Enums: {
		DesignMode: {DesignMode: string},
		ActionType: {ActionType: string},
		SelectionType: {SelectionType: string},
		HandleLocation: {HandleLocation: string},
	},
	Constants: {
		Epsilon: number,
		HandleOffset: number,
		SelectionColor: Color3,
		GhostValidColor: Color3,
		GhostInvalidColor: Color3,
		HandleIconMoveEnd: string,
		HandleIconMoveWall: string,
		HandleIconDeleteWall: string,
		HandleIconDisconnectWall: string,
		HandleIconExtendWall: string,
	},
	GetActionType: () -> string,
	SetActionType: (string) -> (),
	GetDesignMode: () -> string,
	GetCurrentLevel: () -> number,
	SetCurrentLevel: (number) -> (),
	GetViewSettings: () -> any,
	GetSelectionType: () -> string,
	GetSelectionPart: () -> BasePart?,
	GetLastInputInfo: () -> any?,
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
	GetGhostFloorData: () -> any?,
	GetFloorMaterialId: () -> number,
	NotifyDesignModeChange: () -> (),
	ClearSelection: () -> (),
	Select: (Instance) -> boolean,
	GetSelectionInfoFromInstance: (Instance?) -> (string?, number?, number?),
	DeleteAfterDelay: (Instance, number) -> (),
	CancelAction: () -> (),
}

local current: Context? = nil

function Context.Init(context: Context): Context
	current = context
	return context
end

function Context.Get(): Context
	if not current then
		error("FormexDesignContext not initialized", 2)
	end
	return current
end

return Context
