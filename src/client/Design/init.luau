--!strict
local Formex = require(game:GetService("ReplicatedStorage"):WaitForChild("Formex"))

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local FormexClient = require(script.Parent:WaitForChild("Client"))
local DesignCamera = require(script.Parent:WaitForChild("DesignCamera"))
local FormexDesignContext = require(script:WaitForChild("Context"))
local FormexDesignHighlights = require(script:WaitForChild("Highlights"))

local localPlayer = Players.LocalPlayer

local formexWorkspace = Workspace:WaitForChild("Formex")
local overlayFolder = Formex.Util.EnsureFolder("FormexDesignOverlays", formexWorkspace)

local Enums = FormexDesignContext.Enums
local Constants = FormexDesignContext.Constants

local FormexDesign = {}

FormexDesign.Handles = require(script:WaitForChild("Handles"))

local Walls, Floors, Objects, Rooms

FormexDesign.WallMode = Enums.WallMode
FormexDesign.HandleLocation = Enums.HandleLocation
FormexDesign.FloorMode = Enums.FloorMode
FormexDesign.DesignMode = Enums.DesignMode
FormexDesign.DesignSubMode = Enums.DesignSubMode
FormexDesign.EditMode = Enums.EditMode
FormexDesign.ActionType = Enums.ActionType
FormexDesign.SelectionType = Enums.SelectionType

export type WallMode = FormexDesignContext.WallMode
export type HandleLocation = FormexDesignContext.HandleLocation
export type FloorMode = FormexDesignContext.FloorMode

type ViewSettings = {
	HandleLocation: HandleLocation,
	CameraMode: DesignCamera.CameraMode,
	WallMode: WallMode,
	ShowSegments: boolean,
	ShowGrid: boolean,
	ShowOtherLevels: boolean,
}

export type DesignMode = FormexDesignContext.DesignMode
export type DesignSubMode = FormexDesignContext.DesignSubMode
export type EditMode = FormexDesignContext.EditMode
export type ActionType = FormexDesignContext.ActionType

export type SelectionData = nil | Formex.WallData | Formex.FloorData | Formex.ObjectData | Formex.RoomData

export type SelectionType = FormexDesignContext.SelectionType

local playViewSettings: ViewSettings = {
	HandleLocation = FormexDesign.HandleLocation.Middle,
	CameraMode = DesignCamera.CameraMode.Play,
	WallMode = FormexDesign.WallMode.Full,
	ShowSegments = false,
	ShowGrid = false,
	ShowOtherLevels = true
} :: ViewSettings

local topDownViewSettings: ViewSettings = {
	HandleLocation = FormexDesign.HandleLocation.Bottom,
	CameraMode = DesignCamera.CameraMode.TopDown,
	WallMode = FormexDesign.WallMode.Half,
	ShowSegments = false,
	ShowGrid = true,
	ShowOtherLevels = false
} :: ViewSettings

local expandViewSettings: ViewSettings = {
	HandleLocation = FormexDesign.HandleLocation.Bottom,
	CameraMode = DesignCamera.CameraMode.TopDown,
	WallMode = FormexDesign.WallMode.Half,
	ShowSegments = true,
	ShowGrid = false,
	ShowOtherLevels = false
} :: ViewSettings

type InputInfo = {
	PlotInfo: FormexClient.PlotInfo,
	Ray: Ray?,
	HitPosition: Vector3?,
	HitNormal: Vector3?,
	SnapPoint: Vector2int16?,
	LayoutTile: Vector2int16?,
	LevelIndex: number,
	Target: Instance?,
	ActionHeld: boolean,
	AltHeld: boolean,
	
	-- InputInfo should be considered very reliable without requiring for fallback lookups
	PartType: Formex.PartType?,
	WallSide: Formex.ObjectSide?,
	WallData: Formex.WallData?,
	FloorSide: string?,
	FloorData: Formex.FloorData?,
	ObjectData: Formex.ObjectData?,
	ObjectDesignIndex: number?,
	RoomData: Formex.RoomData?,
}

local inputInfo: InputInfo? = nil
local designMode: DesignMode = FormexDesign.DesignMode.Play
local designSubMode: DesignSubMode = FormexDesign.DesignSubMode.Normal
local editMode: EditMode = FormexDesign.EditMode.PointMove
local actionType: ActionType = FormexDesign.ActionType.Select
local currentLevel: number = 1
local viewSettings: ViewSettings = playViewSettings
local designSessionActive = false
local designSessionPendingFocus = false
local lastPlotPart: BasePart? = nil
local ghost: Instance? = nil
local ghostWallData: Formex.WallData? = nil
local ghostFloorData: Formex.FloorData? = nil
local ghostType: Formex.PartType? = nil
local ghostActive = false
local ghostIsValid = false
local floorMaterialId = Formex.DefaultFloorMaterial
local ceilingMaterialId = Formex.DefaultCeilingMaterial
local floorColor = Color3.new(1, 1, 1)
local ceilingColor = Color3.new(1, 1, 1)
local foundationMaterialId = Formex.DefaultFoundationMaterial
local foundationColor = Color3.new(1, 1, 1)
local floorRaiseHeight: number = 0
local floorMode: FloorMode = FormexDesign.FloorMode.Manual
local actionHeld = false
local altHeld, alt1Held, alt2Held, alt3Held = false, false, false, false
local selectionType: SelectionType = FormexDesign.SelectionType.None
local selectionData: SelectionData = nil
local selectionPart: Instance? = nil
local lastPlotId = FormexClient.CurrentPlotId
local canUndo = false
local canRedo = false
local altDropperForced = false
local altDropperUsed = false
local lastSubModeBeforeAlt: DesignSubMode? = nil
local lastDesignModeBeforeAlt: DesignMode? = nil
local designTipMessage: string? = nil
type TopDownState = DesignCamera.TopDownState
local topDownStateByPlotId: {[number]: TopDownState} = {}

export type WallPaintSettings = FormexDesignContext.WallPaintSettings
export type WallBuildSettings = FormexDesignContext.WallBuildSettings
export type WallSelectedSettings = FormexDesignContext.WallSelectedSettings
export type FloorPaintSettings = FormexDesignContext.FloorPaintSettings
export type FloorSelectedSettings = FormexDesignContext.FloorSelectedSettings
export type ObjectPaintSettings = FormexDesignContext.ObjectPaintSettings
export type ObjectSelectedSettings = FormexDesignContext.ObjectSelectedSettings
export type DesignState = FormexDesignContext.DesignState
export type DesignStateUpdate = FormexDesignContext.DesignStateUpdate

type WallStateUpdate = FormexDesignContext.WallStateUpdate
type FloorStateUpdate = FormexDesignContext.FloorStateUpdate
type ObjectStateUpdate = FormexDesignContext.ObjectStateUpdate

local wallPaintSettings: WallPaintSettings = {
	Height = nil,
	SplitHeight = 0,
	TopMaterial = Formex.DefaultWallMaterial,
	BottomMaterial = Formex.DefaultWallMaterial,
	TopColor = Color3.new(1, 1, 1),
	BottomColor = Color3.new(1, 1, 1),
} :: WallPaintSettings

local wallBuildSettings: WallBuildSettings = {
	Height = nil,
	FrontSplitHeight = 0,
	BackSplitHeight = 0,
	FrontTopMaterial = Formex.DefaultWallMaterial,
	FrontBottomMaterial = Formex.DefaultWallMaterial,
	BackTopMaterial = Formex.DefaultWallMaterial,
	BackBottomMaterial = Formex.DefaultWallMaterial,
	FrontTopColor = Color3.new(1, 1, 1),
	FrontBottomColor = Color3.new(1, 1, 1),
	BackTopColor = Color3.new(1, 1, 1),
	BackBottomColor = Color3.new(1, 1, 1),
} :: WallBuildSettings

local wallSelectedSettings: WallSelectedSettings = {
	Height = nil,
	FrontSplitHeight = 0,
	BackSplitHeight = 0,
	FrontTopMaterial = Formex.DefaultWallMaterial,
	FrontBottomMaterial = Formex.DefaultWallMaterial,
	BackTopMaterial = Formex.DefaultWallMaterial,
	BackBottomMaterial = Formex.DefaultWallMaterial,
	FrontTopColor = Color3.new(1, 1, 1),
	FrontBottomColor = Color3.new(1, 1, 1),
	BackTopColor = Color3.new(1, 1, 1),
	BackBottomColor = Color3.new(1, 1, 1),
	HasSelection = false,
} :: WallSelectedSettings

local floorSelectedSettings: FloorSelectedSettings = {
	RaiseHeight = 0,
	FloorMaterial = Formex.DefaultFloorMaterial,
	CeilingMaterial = Formex.DefaultCeilingMaterial,
	FoundationMaterial = Formex.DefaultFoundationMaterial,
	FloorColor = Color3.new(1, 1, 1),
	CeilingColor = Color3.new(1, 1, 1),
	FoundationColor = Color3.new(1, 1, 1),
	HasSelection = false,
} :: FloorSelectedSettings

local objectPaintSettings: ObjectPaintSettings = {
	Design = {},
	DesignColors = {},
} :: ObjectPaintSettings

local objectSelectedSettings: ObjectSelectedSettings = {
	PrefabName = nil,
	Design = {},
	DesignColors = {},
	HasSelection = false,
} :: ObjectSelectedSettings

local objectPrefabName: string? = nil

do
	local prefabs = Formex.Objects.GetPrefabs()
	if #prefabs > 0 then
		objectPrefabName = prefabs[1].PrefabName
		objectPaintSettings.Design = {}
		objectPaintSettings.DesignColors = {}
		for index, materialId in ipairs(prefabs[1].DefaultDesign or {}) do
			objectPaintSettings.Design[index] = materialId
		end
	end
end

local designModeViewSettings: {DesignMode: ViewSettings}? = nil
local designModeBySelectionType: {[SelectionType]: DesignMode}? = nil

local designStateChangeDepth = 0
local designStateDirty = false

local wallSide = {
	[Formex.WallPart.FrontBottom] = Formex.ObjectSide.Front,
	[Formex.WallPart.FrontTop] = Formex.ObjectSide.Front,
	[Formex.WallPart.BackBottom] = Formex.ObjectSide.Back,
	[Formex.WallPart.BackTop] = Formex.ObjectSide.Back,
} :: {[string]: Formex.ObjectSide}

local floorSide = {
	["Floor"] = "Floor",
	["Floor (Client)"] = "Floor",
	["Ceiling"] = "Ceiling",
	["Ceiling (Client)"] = "Ceiling",
	["Foundation"] = "Foundation",
	["Foundation (Client)"] = "Foundation",
} :: {[string]: string}

type PartInfo = {
	PlotData: Formex.PlotData,
	WallSide: Formex.ObjectSide?,
	FloorSide: string?,
	PartType: Formex.PartType?,
	Data: Formex.WallData | Formex.FloorData | Formex.ObjectData | nil,
	Room: Formex.RoomData?,
	LevelIndex: number?,
}

local function getDataFromPart(target: Instance?): PartInfo?
	if not target then return nil end

	-- AGENT NOTE: Do not touch this function without consulting the original author.
	-- This function is delicate and tightly coupled to the structure of the Formex plot in the

	-- Part is as member of this plot
	local plotInfo = FormexClient.CurrentPlot
	local plotPart = plotInfo and plotInfo.PlotPart
	if not plotInfo.IsValid or not plotPart or not target:IsDescendantOf(plotPart) then return nil end

	-- Build hierarchy from plotPart to part
	local hierarchy = {} :: {Instance}

	local part = target:IsA("Model") and target or target:FindFirstAncestorWhichIsA("Model")
	while part and part ~= plotPart do
		table.insert(hierarchy, 1, part)
		part = part.Parent
	end

	-- Expecting hierarchy: Level (Folder) -> Type (Folder) -> Part (BasePart/Model)
	local levelPart, typeFolder, part = table.unpack(hierarchy)
	local levelIndex, typeName, partId = tonumber(levelPart.Name), typeFolder.Name, tonumber(part.Name)
	if not levelIndex or not typeName or not partId then return nil end
	
	local levelData = plotInfo.PlotData.Levels[levelIndex]
	if not levelData then return nil end

	local result: PartInfo = {
		PlotData = plotInfo.PlotData,
		LevelIndex = levelIndex,
		PartType = nil,
		Data = nil,
		Room = nil,
	}

	if typeName == "Walls" then
		local data = levelData.Walls and levelData.Walls[partId]
		if not data then return nil end

		result.PartType = Formex.PartType.Wall
		result.Data = data
		result.WallSide = wallSide[target.Name] or nil
		if result.WallSide == Formex.ObjectSide.Front then
			result.Room = levelData.Rooms and levelData.Rooms[data.ConnectedRoomFront] or nil
		elseif result.WallSide == Formex.ObjectSide.Back then	
			result.Room = levelData.Rooms and levelData.Rooms[data.ConnectedRoomBack] or nil
		end
	elseif typeName == "Floors" then
		local data = levelData.Floors and levelData.Floors[partId]
		if not data then return nil end

		result.PartType = Formex.PartType.Floor
		result.Data = data
		result.FloorSide = floorSide[target.Name] or nil
		result.Room = levelData.Rooms and levelData.Rooms[data.Room] or nil
	elseif typeName == "Objects" then
		local data = levelData.Objects and levelData.Objects[partId]
		if not data then return nil end

		result.PartType = Formex.PartType.Object
		result.Data = data
		result.Room = levelData.Rooms and levelData.Rooms[data.Room] or nil
	end

	return result
end

local function getWallSelectionPart(wallData: Formex.WallData): Instance?
	return wallData.Part
end

local function getFloorSelectionPart(floorData: Formex.FloorData): Instance?
	return floorData.Model
end

local function getObjectSelectionPart(objectData: Formex.ObjectData): Instance?
	return objectData.ObjectModel
		or objectData.Part
end

local function isPaintableDesignMode(mode: DesignMode): boolean
	return mode == FormexDesign.DesignMode.Wall
		or mode == FormexDesign.DesignMode.Floor
		or mode == FormexDesign.DesignMode.Object
end

local function updateAltDropperState(held: boolean)
	if held then
		if altDropperForced then return end		
		if isPaintableDesignMode(designMode)
			and (designSubMode == FormexDesign.DesignSubMode.Normal
			or designSubMode == FormexDesign.DesignSubMode.Paint) then
			lastSubModeBeforeAlt = designSubMode
			lastDesignModeBeforeAlt = designMode
			altDropperUsed = false
			altDropperForced = true
			FormexDesign.SetDesignMode(FormexDesign.DesignMode.Dropper, true)
		end
	else
		if not altDropperForced then return end		
		altDropperForced = false
		local nextMode = lastDesignModeBeforeAlt or FormexDesign.DesignMode.Select
		local nextSubMode = lastSubModeBeforeAlt or FormexDesign.DesignSubMode.Normal
		if altDropperUsed then
			nextSubMode = FormexDesign.DesignSubMode.Paint
		end
		lastDesignModeBeforeAlt = nil
		lastSubModeBeforeAlt = nil
		altDropperUsed = false
		FormexDesign.SetDesignMode(nextMode, true)
		FormexDesign.SetDesignSubMode(nextSubMode)
	end
end


local function snapToWallGrid(value: number): number
	return math.round(value / Formex.GridSize) * Formex.GridSize
end

local function clampWallHeight(value: number?): number?
	if value == nil then return nil end
	local snapped = snapToWallGrid(value)
	return math.clamp(snapped, Formex.GridSize, Formex.LevelHeight)
end

local function clampWallSplit(value: number?, height: number?): number?
	if value == nil then return nil end
	if value <= 0 then return 0 end
	local maxHeight = height
	if not maxHeight or maxHeight <= 0 then
		maxHeight = Formex.LevelHeight
	end
	if value <= Formex.GridSize or value >= maxHeight then return 0 end
	local snapped = snapToWallGrid(value)
	return math.clamp(snapped, Formex.GridSize, maxHeight - Formex.GridSize)
end

local function clampFloorRaiseHeight(value: number?): number
	local resolved = value or 0
	if resolved < 0 then
		resolved = 0
	end
	local snapped = snapToWallGrid(resolved)
	local maxHeight = Formex.LevelHeight - Formex.InterfloorHeight
	if maxHeight < 0 then
		maxHeight = 0
	end
	return math.clamp(snapped, 0, maxHeight)
end

local function notifyDesignStateChange()
	if designStateChangeDepth > 0 then
		designStateDirty = true
		return
	end

	FormexClient.FireEvent("DesignStateChanged")
	FormexClient.FireEvent("DesignModeChanged")
end

local function beginDesignStateBatch()
	designStateChangeDepth += 1
end

local function endDesignStateBatch()
	if designStateChangeDepth > 0 then
		designStateChangeDepth -= 1
	end
	if designStateChangeDepth == 0 and designStateDirty then
		designStateDirty = false
		notifyDesignStateChange()
	end
end

local function notifyDesignModeChange()
	FormexDesign.RefreshSelectionSettings()
	notifyDesignStateChange()
end

local function setWallPaintSettings(settings: WallPaintSettings)
	wallPaintSettings = {
		Height = settings.Height,
		SplitHeight = settings.SplitHeight,
		TopMaterial = settings.TopMaterial,
		BottomMaterial = settings.BottomMaterial,
		TopColor = settings.TopColor,
		BottomColor = settings.BottomColor,
	} :: WallPaintSettings
	notifyDesignModeChange()
end

local function updateWallPaintSettings(settings: WallPaintSettings)
	wallPaintSettings.Height = settings.Height
	wallPaintSettings.SplitHeight = settings.SplitHeight
	wallPaintSettings.TopMaterial = settings.TopMaterial
	wallPaintSettings.BottomMaterial = settings.BottomMaterial
	wallPaintSettings.TopColor = settings.TopColor
	wallPaintSettings.BottomColor = settings.BottomColor
	notifyDesignModeChange()
end

local function deleteAfterDelay(instance: Instance, delay: number)
	task.delay(delay, function()
		if instance and instance.Parent then
			instance:Destroy()
		end
	end)
end

-- Integration to gamepad or other input systems
function FormexDesign.SetAlt(held: boolean)
	alt3Held = held
	altHeld = alt1Held or alt2Held or alt3Held
	updateAltDropperState(altHeld)
end

local function cloneWallPaintSettings(settings: WallPaintSettings): WallPaintSettings
	return {
		Height = settings.Height,
		SplitHeight = settings.SplitHeight,
		TopMaterial = settings.TopMaterial,
		BottomMaterial = settings.BottomMaterial,
		TopColor = settings.TopColor,
		BottomColor = settings.BottomColor,
	} :: WallPaintSettings
end

local function cloneWallBuildSettings(settings: WallBuildSettings): WallBuildSettings
	return {
		Height = settings.Height,
		FrontSplitHeight = settings.FrontSplitHeight,
		BackSplitHeight = settings.BackSplitHeight,
		FrontTopMaterial = settings.FrontTopMaterial,
		FrontBottomMaterial = settings.FrontBottomMaterial,
		BackTopMaterial = settings.BackTopMaterial,
		BackBottomMaterial = settings.BackBottomMaterial,
		FrontTopColor = settings.FrontTopColor,
		FrontBottomColor = settings.FrontBottomColor,
		BackTopColor = settings.BackTopColor,
		BackBottomColor = settings.BackBottomColor,
	} :: WallBuildSettings
end

local function cloneWallSelectedSettings(settings: WallSelectedSettings): WallSelectedSettings
	return {
		Height = settings.Height,
		FrontSplitHeight = settings.FrontSplitHeight,
		BackSplitHeight = settings.BackSplitHeight,
		FrontTopMaterial = settings.FrontTopMaterial,
		FrontBottomMaterial = settings.FrontBottomMaterial,
		BackTopMaterial = settings.BackTopMaterial,
		BackBottomMaterial = settings.BackBottomMaterial,
		FrontTopColor = settings.FrontTopColor,
		FrontBottomColor = settings.FrontBottomColor,
		BackTopColor = settings.BackTopColor,
		BackBottomColor = settings.BackBottomColor,
		HasSelection = settings.HasSelection,
	} :: WallSelectedSettings
end

local function getFloorPaintSettings(): FloorPaintSettings
	return {
		RaiseHeight = floorRaiseHeight,
		FloorMaterial = floorMaterialId,
		CeilingMaterial = ceilingMaterialId,
		FoundationMaterial = foundationMaterialId,
		FloorColor = floorColor,
		CeilingColor = ceilingColor,
		FoundationColor = foundationColor,
	} :: FloorPaintSettings
end

local function cloneFloorSelectedSettings(settings: FloorSelectedSettings): FloorSelectedSettings
	return {
		RaiseHeight = settings.RaiseHeight,
		FloorMaterial = settings.FloorMaterial,
		CeilingMaterial = settings.CeilingMaterial,
		FoundationMaterial = settings.FoundationMaterial,
		FloorColor = settings.FloorColor,
		CeilingColor = settings.CeilingColor,
		FoundationColor = settings.FoundationColor,
		HasSelection = settings.HasSelection,
	} :: FloorSelectedSettings
end

function FormexDesign.GetDesignState(): DesignState
	return {
		Mode = designMode,
		SubMode = designSubMode,
		EditMode = editMode,
		ActionType = actionType,
		SelectionType = selectionType,
		CanUndo = canUndo,
		CanRedo = canRedo,
		Wall = {
			Selected = cloneWallSelectedSettings(wallSelectedSettings),
			Build = cloneWallBuildSettings(wallBuildSettings),
			Paint = cloneWallPaintSettings(wallPaintSettings),
		},
	Floor = {
		Mode = floorMode,
		Selected = cloneFloorSelectedSettings(floorSelectedSettings),
		Paint = getFloorPaintSettings(),
	},
	Object = {
		PrefabName = objectPrefabName,
		Selected = {
			PrefabName = objectSelectedSettings.PrefabName,
			Design = table.clone(objectSelectedSettings.Design),
			DesignColors = table.clone(objectSelectedSettings.DesignColors),
			HasSelection = objectSelectedSettings.HasSelection,
		},
		Paint = {
			Design = table.clone(objectPaintSettings.Design),
			DesignColors = table.clone(objectPaintSettings.DesignColors),
		},
	},
	} :: DesignState
end

function FormexDesign.GetTipMessage(): string?
	return designTipMessage
end

function FormexDesign.SetTipMessage(message: string?)
	if message == "" then
		message = nil
	end
	if designTipMessage == message then return end
	designTipMessage = message
	notifyDesignStateChange()
end

function FormexDesign.GetDesignMode(): DesignMode
	return designMode
end

function FormexDesign.GetDesignSubMode(): DesignSubMode
	return designSubMode
end

function FormexDesign.GetEditMode(): EditMode
	return editMode
end

function FormexDesign.SetDesignSubMode(mode: DesignSubMode?)
	mode = mode or FormexDesign.DesignSubMode.Normal
	if not isPaintableDesignMode(designMode) then
		mode = FormexDesign.DesignSubMode.Normal
	end
	if designSubMode == mode then return end
	if actionType ~= FormexDesign.ActionType.Select then
		FormexDesign.CancelAction()
	end
	if mode ~= FormexDesign.DesignSubMode.Normal then
		FormexDesign.ClearSelection()
	end
	designSubMode = mode
	notifyDesignModeChange()
end

function FormexDesign.GetActionType(): ActionType
	return actionType
end

function FormexDesign.GetSelection(): (SelectionType, SelectionData)
	return selectionType, selectionData
end

function FormexDesign.GetFloorMaterial(): number
	return floorMaterialId
end

local function setFloorMaterial(materialId: number, applyToSelection: boolean)
	floorMaterialId = materialId
	if applyToSelection and selectionType == FormexDesign.SelectionType.Floor then
		Floors.ApplySelectedAppearance({ FloorMaterial = materialId })
	end
	if ghostActive
	and (ghostType == Formex.PartType.Floor or ghostType == Formex.PartType.Ceiling)
	and ghostFloorData then
		ghostFloorData.FloorMaterial = materialId
	end
	notifyDesignModeChange()
end

function FormexDesign.SetFloorMaterial(materialId: number, applyToSelection: boolean?)
	setFloorMaterial(materialId, applyToSelection ~= false)
end

function FormexDesign.GetCeilingMaterial(): number
	return ceilingMaterialId
end

local function setCeilingMaterial(materialId: number, applyToSelection: boolean)
	ceilingMaterialId = materialId
	if applyToSelection and selectionType == FormexDesign.SelectionType.Floor then
		Floors.ApplySelectedAppearance({ CeilingMaterial = materialId })
	end
	if ghostActive
	and (ghostType == Formex.PartType.Floor or ghostType == Formex.PartType.Ceiling)
	and ghostFloorData then
		ghostFloorData.CeilingMaterial = materialId
	end
	notifyDesignModeChange()
end

function FormexDesign.SetCeilingMaterial(materialId: number, applyToSelection: boolean?)
	setCeilingMaterial(materialId, applyToSelection ~= false)
end

function FormexDesign.GetFloorRaiseHeight(): number
	return floorRaiseHeight
end

local function setFloorRaiseHeight(value: number, applyToSelection: boolean)
	local clamped = clampFloorRaiseHeight(value)
	floorRaiseHeight = clamped
	if applyToSelection and selectionType == FormexDesign.SelectionType.Floor then
		Floors.ApplySelectedAppearance({ RaiseHeight = clamped })
	end
	if ghostActive
	and (ghostType == Formex.PartType.Floor or ghostType == Formex.PartType.Ceiling)
	and ghostFloorData then
		ghostFloorData.RaiseHeight = clamped
	end
	notifyDesignModeChange()
end

function FormexDesign.SetFloorRaiseHeight(value: number, applyToSelection: boolean?)
	setFloorRaiseHeight(value, applyToSelection ~= false)
end

function FormexDesign.GetFloorColor(): Color3
	return floorColor
end

local function setFloorColor(color: Color3, applyToSelection: boolean)
	floorColor = color
	if applyToSelection and selectionType == FormexDesign.SelectionType.Floor then
		Floors.ApplySelectedAppearance({ FloorColor = color })
	end
	if ghostActive
	and (ghostType == Formex.PartType.Floor or ghostType == Formex.PartType.Ceiling)
	and ghostFloorData then
		ghostFloorData.FloorColor = color
	end
	notifyDesignModeChange()
end

function FormexDesign.SetFloorColor(color: Color3, applyToSelection: boolean?)
	setFloorColor(color, applyToSelection ~= false)
end

function FormexDesign.GetCeilingColor(): Color3
	return ceilingColor
end

local function setCeilingColor(color: Color3, applyToSelection: boolean)
	ceilingColor = color
	if applyToSelection and selectionType == FormexDesign.SelectionType.Floor then
		Floors.ApplySelectedAppearance({ CeilingColor = color })
	end
	if ghostActive
	and (ghostType == Formex.PartType.Floor or ghostType == Formex.PartType.Ceiling)
	and ghostFloorData then
		ghostFloorData.CeilingColor = color
	end
	notifyDesignModeChange()
end

function FormexDesign.SetCeilingColor(color: Color3, applyToSelection: boolean?)
	setCeilingColor(color, applyToSelection ~= false)
end

function FormexDesign.GetFoundationMaterial(): number
	return foundationMaterialId
end

local function setFoundationMaterial(materialId: number, applyToSelection: boolean)
	foundationMaterialId = materialId
	if applyToSelection and selectionType == FormexDesign.SelectionType.Floor then
		Floors.ApplySelectedAppearance({ FoundationMaterial = materialId })
	end
	if ghostActive
	and (ghostType == Formex.PartType.Floor or ghostType == Formex.PartType.Ceiling)
	and ghostFloorData then
		ghostFloorData.FoundationMaterial = materialId
	end
	notifyDesignModeChange()
end

function FormexDesign.SetFoundationMaterial(materialId: number, applyToSelection: boolean?)
	setFoundationMaterial(materialId, applyToSelection ~= false)
end

function FormexDesign.GetFoundationColor(): Color3
	return foundationColor
end

local function setFoundationColor(color: Color3, applyToSelection: boolean)
	foundationColor = color
	if applyToSelection and selectionType == FormexDesign.SelectionType.Floor then
		Floors.ApplySelectedAppearance({ FoundationColor = color })
	end
	if ghostActive
	and (ghostType == Formex.PartType.Floor or ghostType == Formex.PartType.Ceiling)
	and ghostFloorData then
		ghostFloorData.FoundationColor = color
	end
	notifyDesignModeChange()
end

function FormexDesign.SetFoundationColor(color: Color3, applyToSelection: boolean?)
	setFoundationColor(color, applyToSelection ~= false)
end

function FormexDesign.GetWallPaintSettings(): WallPaintSettings
	return table.clone(wallPaintSettings) :: WallPaintSettings
end

function FormexDesign.SetWallPaintSettings(settings: WallPaintSettings)
	setWallPaintSettings(settings)
end

function FormexDesign.UpdateWallPaintSettings(settings: WallPaintSettings)
	updateWallPaintSettings(settings)
end

function FormexDesign.CanUndo(): boolean
	return canUndo
end

function FormexDesign.CanRedo(): boolean
	return canRedo
end

local function resolveUndoRedoMode(selection: Formex.SelectionSnapshot?): DesignMode?
	if not selection then return nil end
	local mode = selection.Mode
	if type(mode) == "string" and designModeViewSettings[mode] then
		return mode :: DesignMode
	end

	local selectionMode = selection.SelectionType and designModeBySelectionType[selection.SelectionType :: SelectionType]
	if selectionMode then return selectionMode end
	return nil
end

local function getPlotModelFromPlotData(plotInfo: FormexClient.PlotInfo?, selectionKind: SelectionType, levelIndex: number, partId: number): Model?
	if not plotInfo or not plotInfo.PlotData or not plotInfo.PlotData.Levels then return nil end
	local levelData = plotInfo.PlotData.Levels[levelIndex]
	if not levelData then return nil end
	if selectionKind == FormexDesign.SelectionType.Wall then
		local wallData = levelData.Walls and levelData.Walls[partId]
		local model = wallData and wallData.Part
		if model and model:IsA("Model") then return model end
	elseif selectionKind == FormexDesign.SelectionType.Floor then
		local floorData = levelData.Floors and levelData.Floors[partId]
		local model = floorData and floorData.Model
		if model and model:IsA("Model") then return model end
	elseif selectionKind == FormexDesign.SelectionType.Object then
		local objectData = levelData.Objects and levelData.Objects[partId]
		local model = objectData and objectData.Part
		if model and model:IsA("Model") then return model end
	end

	return nil
end

local function selectPlotModelByIdAsync(
	plotInfo: FormexClient.PlotInfo?,
	selectionKind: SelectionType,
	levelIndex: number,
	partId: number,
	timeoutSeconds: number?
)
	if not plotInfo or not selectionKind then return end
	local model = getPlotModelFromPlotData(plotInfo, selectionKind, levelIndex, partId)
	if model then
		FormexDesign.Select(model)
		return
	end

	task.spawn(function()
		local deadline = time() + (timeoutSeconds or 2)
		while time() < deadline do
			local found = getPlotModelFromPlotData(plotInfo, selectionKind, levelIndex, partId)
			if found then
				FormexDesign.Select(found)
				return
			end
			task.wait(0.05)
		end
	end)
end

local function findSelectionModel(plotInfo: FormexClient.PlotInfo, selection: Formex.SelectionSnapshot?): Instance?
	if not selection or selection.SelectionType == FormexDesign.SelectionType.None then return nil end
	local levelIndex = selection.LevelIndex
	local partId = selection.PartId
	local selectionKind = selection.SelectionType
	if not levelIndex or partId == nil or not selectionKind then return nil end
	return getPlotModelFromPlotData(plotInfo, selectionKind :: SelectionType, levelIndex, partId)
end

local function applyUndoRedoSelection(selection: Formex.SelectionSnapshot?)
	if not selection then return end
	local targetMode = resolveUndoRedoMode(selection)
	if targetMode then
		FormexDesign.SetDesignMode(targetMode)
	end

	FormexDesign.ClearSelection()

	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid or not plotInfo.PlotPart then return end
	if selection.SelectionType == FormexDesign.SelectionType.None then return end
	local function trySelect(): boolean
		local model = findSelectionModel(plotInfo, selection)
		if model then
			FormexDesign.Select(model)
			return true
		end
		return false
	end

	if trySelect() then return end
	task.spawn(function()
		local deadline = time() + 2
		while time() < deadline do
			if trySelect() then return end
			task.wait(0.05)
		end
	end)
end

local function getSelectionSnapshot(): Formex.SelectionSnapshot
	local resolvedType = selectionType
	local partId = nil
	local level = nil
	if resolvedType ~= FormexDesign.SelectionType.None and selectionData then
		if resolvedType == FormexDesign.SelectionType.Wall then
			local data = selectionData :: Formex.WallData
			partId = data.WallId
			level = data.Level
		elseif resolvedType == FormexDesign.SelectionType.Floor then
			local data = selectionData :: Formex.FloorData
			partId = data.FloorId
			level = data.LevelIndex
		elseif resolvedType == FormexDesign.SelectionType.Object then
			local data = selectionData :: Formex.ObjectData
			partId = data.ObjectId
			level = data.Level
		elseif resolvedType == FormexDesign.SelectionType.Room then
			local data = selectionData :: Formex.RoomData
			partId = data.RoomId
			level = data.LevelIndex
		end
	end

	return {
		Mode = designMode,
		SelectionType = resolvedType,
		LevelIndex = level,
		PartId = partId,
	}
end

local function getSelectionPartForKind(selectionKind: SelectionType, data: SelectionData): Instance?
	if selectionKind == FormexDesign.SelectionType.Wall then
		return getWallSelectionPart(data :: Formex.WallData)
	end
	if selectionKind == FormexDesign.SelectionType.Floor then
		return getFloorSelectionPart(data :: Formex.FloorData)
	end
	if selectionKind == FormexDesign.SelectionType.Object then
		return getObjectSelectionPart(data :: Formex.ObjectData)
	end
	return nil
end

local function getSelectionFromInput(input: InputInfo): (SelectionType?, SelectionData?, Instance?, number?)
	if input.PartType == Formex.PartType.Wall and input.WallData then
		local data = input.WallData
		return FormexDesign.SelectionType.Wall, data, getWallSelectionPart(data), data.Level
	end
	if input.PartType == Formex.PartType.Floor and input.FloorData then
		local data = input.FloorData
		return FormexDesign.SelectionType.Floor, data, getFloorSelectionPart(data), data.LevelIndex
	end
	if input.PartType == Formex.PartType.Object and input.ObjectData then
		local data = input.ObjectData
		return FormexDesign.SelectionType.Object, data, getObjectSelectionPart(data), data.Level
	end
	return nil, nil, nil, nil
end

local function getSelectionFromInstance(instance: Instance): (SelectionType?, SelectionData?, Instance?, number?)
	local partInfo = getDataFromPart(instance)
	if not partInfo or not partInfo.PartType or not partInfo.Data then
		return nil, nil, nil, nil
	end

	if partInfo.PartType == Formex.PartType.Wall then
		local data = partInfo.Data :: Formex.WallData
		return FormexDesign.SelectionType.Wall, data, getWallSelectionPart(data), data.Level
	end
	if partInfo.PartType == Formex.PartType.Floor then
		local data = partInfo.Data :: Formex.FloorData
		return FormexDesign.SelectionType.Floor, data, getFloorSelectionPart(data), data.LevelIndex
	end
	if partInfo.PartType == Formex.PartType.Object then
		local data = partInfo.Data :: Formex.ObjectData
		return FormexDesign.SelectionType.Object, data, getObjectSelectionPart(data), data.Level
	end

	return nil, nil, nil, nil
end

function FormexDesign.Undo(): boolean
	FormexDesign.CancelAction()
	local ok, _, selection = FormexClient.Undo(getSelectionSnapshot())
	if ok ~= true then return false end
	FormexDesign.ClearSelection()
	applyUndoRedoSelection(selection)
	return true
end

function FormexDesign.Redo(): boolean
	FormexDesign.CancelAction()
	local ok, _, selection = FormexClient.Redo(getSelectionSnapshot())
	if ok ~= true then return false end
	FormexDesign.ClearSelection()
	applyUndoRedoSelection(selection)
	return true
end

local function getPlayerFocusPosition(): Vector3?
	local character = localPlayer.Character
	if not character then return nil end
	local root = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Head")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function saveTopDownState(plotInfo: FormexClient.PlotInfo?)
	if not plotInfo or not plotInfo.IsValid then return end
	topDownStateByPlotId[plotInfo.PlotId] = DesignCamera.GetTopDownState()
end

local function getSelectionFocusPosition(_plotPart: BasePart): Vector3?
	if selectionType == FormexDesign.SelectionType.None or not selectionPart then return nil end
	if selectionPart:IsA("Model") or selectionPart:IsA("BasePart") then
		return selectionPart:GetPivot().Position
	end
	return nil
end

local function clampFocusToPlot(plotPart: BasePart, boundsMin: Vector3?, boundsMax: Vector3?, worldPosition: Vector3): Vector3
	if not boundsMin or not boundsMax then return worldPosition end
	local offset = Vector2.new(worldPosition.X - plotPart.Position.X, worldPosition.Z - plotPart.Position.Z)
	local clamped = Vector2.new(
		math.clamp(offset.X, boundsMin.X, boundsMax.X),
		math.clamp(offset.Y, boundsMin.Z, boundsMax.Z)
	)
	return Vector3.new(plotPart.Position.X + clamped.X, worldPosition.Y, plotPart.Position.Z + clamped.Y)
end

local function focusTopDownOnSelectionOrPlayer(plotInfo: FormexClient.PlotInfo, boundsMin: Vector3?, boundsMax: Vector3?)
	if not plotInfo or not plotInfo.IsValid or not plotInfo.PlotPart then return end
	local plotPart = plotInfo.PlotPart
	local focusPosition = getSelectionFocusPosition(plotPart) or getPlayerFocusPosition() or plotPart.Position
	local clamped = clampFocusToPlot(plotPart, boundsMin, boundsMax, focusPosition)
	DesignCamera.Focus(clamped)
end

function FormexDesign.MoveCameraToPlayer()
	if viewSettings.CameraMode ~= DesignCamera.CameraMode.TopDown then return end
	local focusPosition = getPlayerFocusPosition()
	if focusPosition then
		DesignCamera.Focus(focusPosition)
	end
end

designModeViewSettings = {
	Play = playViewSettings,
	Design = playViewSettings,
	Select = topDownViewSettings,
	Dropper = topDownViewSettings,
	Expand = expandViewSettings,
	Wall = topDownViewSettings,
	Floor = topDownViewSettings,
	Object = topDownViewSettings,
	Room = topDownViewSettings,
}

local function clearOverlays()
	-- clears segment, expands, ghosts
	for _, child in overlayFolder:GetChildren() do
		if child ~= ghost and not FormexDesignHighlights.IsHighlightInstance(child) then
			child:Destroy()
		end
	end

	local plotInfo = FormexClient.CurrentPlot
	Formex.HideGhost(plotInfo and plotInfo.PlotPart or nil)
end

local function createExpandButton(parent: BasePart, segmentIndex: number)
	local clickDetector = Instance.new("ClickDetector", parent)
	local isBusy = false
	clickDetector.MaxActivationDistance = 1024
	clickDetector.MouseClick:Connect(function()
		if isBusy then return end
		isBusy = true
		local success = FormexClient.UnlockSegment(segmentIndex)
		if success == false then
			isBusy = false
		end
	end)

	local billboard = Instance.new("BillboardGui", parent)
	billboard.Name = "ExpandButton"
	billboard.Size = UDim2.new(0, 48, 0, 48)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 0.5, 0)
	billboard.LightInfluence = 0
	billboard.AlwaysOnTop = true
	billboard.Adornee = parent

	local button = Instance.new("ImageLabel", billboard)
	button.Name = "Button"
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundTransparency = 1
	button.ImageContent = Content.fromAssetId(88488799504419)
	button.ImageColor3 = Color3.fromRGB(84, 140, 255)
end

local function createSegmentOverlay(bounds: Formex.SegmentBounds, plotInfo: FormexClient.PlotInfo, unlocked: boolean)
	local part = Instance.new("Part", overlayFolder)
	part.Name = "Segment_" .. tostring(bounds.Index)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.CastShadow = false
	part.Transparency = unlocked and 0.78 or 0.88
	part.Material = Enum.Material.Glass
	part.Size = Vector3.new(bounds.Size.X - Formex.GridSize, 0.25, bounds.Size.Z - Formex.GridSize)

	local surfaceHeight = 0.05
	part.CFrame = bounds.CFrame * CFrame.new(0, surfaceHeight, 0)

	local lineColor = unlocked and Color3.fromRGB(74, 160, 118) or Color3.fromRGB(130, 135, 150)
	local fillColor = unlocked and Color3.fromRGB(98, 191, 143) or Color3.fromRGB(176, 180, 192)
	part.Color = fillColor

	local selection = Instance.new("SelectionBox")
	selection.Adornee = part
	selection.LineThickness = 0.08
	selection.SurfaceTransparency = 1
	selection.Color3 = lineColor
	selection.Parent = part

	if not unlocked then
		createExpandButton(part, bounds.Index)
	end
end

local function renderExpandOverlay(plotInfo: FormexClient.PlotInfo)
	if not plotInfo or not plotInfo.IsValid or not plotInfo.PlotPart then return end
	for index = 1, Formex.Segments.Count do
		local bounds = Formex.Segments.GetBounds(plotInfo.PlotPart, index, plotInfo.LevelsUnlocked)
		local unlocked = Formex.Segments.IsUnlocked(plotInfo.SegmentsUnlocked, index)
		createSegmentOverlay(bounds, plotInfo, unlocked)
	end
end

local function applyGridTexture(part: Part, side: Enum.NormalId)
	local texture = Instance.new("Texture", part)
	texture.Name = tostring(side) .. "Grid"
	texture.Face = side
	texture.ColorMapContent = Content.fromAssetId(116671576387684)
	texture.StudsPerTileU = Formex.LayoutGridSize * 2
	texture.StudsPerTileV = Formex.LayoutGridSize * 2
	texture.Transparency = 0.15
	texture.Color3 = Color3.fromRGB(200, 200, 200)
end

local function createGridOverlay(levelIndex: number, bounds: Formex.SegmentBounds, plotInfo: FormexClient.PlotInfo)
	local function createGridOverlaySide(side: Enum.NormalId, yOffset: number)
		local part = Instance.new("Part", overlayFolder)
		part.Name = "Grid_" .. tostring(bounds.Index)
		part.CollisionGroup = Formex.CollisionGroup.Grid
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = true
		part.CastShadow = false
		part.Material = Enum.Material.Air
		part.Size = Vector3.new(bounds.Size.X, 0.1, bounds.Size.Z)
		part.Transparency = 1
		part.CFrame = bounds.CFrame * CFrame.new(0, yOffset - 0.05, 0)
		applyGridTexture(part, side)
	end

	local thickness = levelIndex == 1 and Formex.FoundationHeight or Formex.InterfloorHeight
	local levelTop = Formex.LevelHeight * (levelIndex - 1)
	createGridOverlaySide(Enum.NormalId.Top, levelTop + 0.05)

	if levelIndex > 1 then
		local levelBottom = levelTop - thickness
		createGridOverlaySide(Enum.NormalId.Bottom, levelBottom - 0.05)
	end
end

local function renderGridOverlays(plotInfo: FormexClient.PlotInfo)
	if not plotInfo or not plotInfo.IsValid or not plotInfo.PlotPart then return end
	local gridLevel = currentLevel

	for _, index in ipairs(Formex.Segments.GetAllUnlocked(plotInfo.SegmentsUnlocked)) do
		local bounds = Formex.Segments.GetBounds(plotInfo.PlotPart, index, plotInfo.LevelsUnlocked)
		createGridOverlay(gridLevel, bounds, plotInfo)
	end
end

local function getPlotCameraBounds(plotInfo: FormexClient.PlotInfo, useFullPlot: boolean?): (Vector3?, Vector3?)
	if not plotInfo or not plotInfo.IsValid or not plotInfo.PlotPart then
		return nil, nil
	end

	local plotPart = plotInfo.PlotPart
	local minX, maxX, minZ, maxZ
	local function trackPoint(point: Vector3)
		if minX == nil then
			minX, maxX = point.X, point.X
			minZ, maxZ = point.Z, point.Z
		else
			minX = math.min(minX, point.X)
			maxX = math.max(maxX, point.X)
			minZ = math.min(minZ, point.Z)
			maxZ = math.max(maxZ, point.Z)
		end
	end

	if useFullPlot then
		local halfWidth = Formex.Dimensions.Width / 2
		local halfDepth = Formex.Dimensions.Depth / 2
		local offsets = {
			Vector3.new(-halfWidth, 0, -halfDepth),
			Vector3.new(-halfWidth, 0, halfDepth),
			Vector3.new(halfWidth, 0, -halfDepth),
			Vector3.new(halfWidth, 0, halfDepth),
		}
		for _, offset in ipairs(offsets) do
			trackPoint(plotPart.CFrame:PointToWorldSpace(offset))
		end
	else
		local unlocked = Formex.Segments.GetAllUnlocked(plotInfo.SegmentsUnlocked)
		if #unlocked == 0 then
			unlocked = {Formex.Segments.DefaultIndex}
		end

		for _, index in ipairs(unlocked) do
			local bounds = Formex.Segments.GetBounds(plotPart, index, plotInfo.LevelsUnlocked)
			local extents = bounds.Extents
			local offsets = {
				Vector3.new(-extents.X, 0, -extents.Z),
				Vector3.new(-extents.X, 0, extents.Z),
				Vector3.new(extents.X, 0, -extents.Z),
				Vector3.new(extents.X, 0, extents.Z),
			}
			for _, offset in ipairs(offsets) do
				trackPoint(bounds.CFrame:PointToWorldSpace(offset))
			end
		end
	end

	if not minX then
		return nil, nil
	end

	local center = plotPart.Position
	local boundMin = Vector3.new(minX - center.X, 0, minZ - center.Z)
	local boundMax = Vector3.new(maxX - center.X, 0, maxZ - center.Z)
	return boundMin, boundMax
end

local function getPlotFitDistance(): number?
	local camera = Workspace.CurrentCamera
	if not camera then return nil end
	local viewport = camera.ViewportSize
	if viewport.Y <= 0 then return nil end
	local aspect = viewport.X / viewport.Y
	if aspect <= 0 then return nil end
	local halfWidth = Formex.Dimensions.Width / 2
	local halfDepth = Formex.Dimensions.Depth / 2
	local halfFov = math.rad(camera.FieldOfView) * 0.5
	local tanHalfFov = math.tan(halfFov)
	if tanHalfFov <= 0 then return nil end
	local distanceForDepth = halfDepth / tanHalfFov
	local distanceForWidth = halfWidth / (tanHalfFov * aspect)
	return math.max(distanceForDepth, distanceForWidth)
end

local function refresh(preserveSelection: boolean?)
	clearOverlays()
	if preserveSelection then
		FormexDesignHighlights.UpdateSelectionHighlight()
	else
		FormexDesign.ClearSelection()
	end

	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid then return	end

	local plotPart = plotInfo.PlotPart
	if not plotPart then return end
	local plotChanged = plotPart ~= lastPlotPart
	if plotChanged then
		lastPlotPart = plotPart
	end

	local boundsMin, boundsMax
	local topDirection
	local isTopDown = viewSettings.CameraMode == DesignCamera.CameraMode.TopDown
	local isExpandMode = designMode == FormexDesign.DesignMode.Expand
	if isTopDown then
		boundsMin, boundsMax = getPlotCameraBounds(plotInfo, isExpandMode)
		topDirection = -plotPart.CFrame.LookVector
	end

	local wasTopDown = DesignCamera.GetCameraMode() == DesignCamera.CameraMode.TopDown
	DesignCamera.SetCameraMode(viewSettings.CameraMode, plotPart.Position, boundsMin, boundsMax, topDirection)

	if isTopDown then
		local activatedTopDown = not wasTopDown
		if plotChanged then
			DesignCamera.SetCameraCenter(plotPart.Position)
			designSessionPendingFocus = true
		end

		DesignCamera.SetCameraBounds(boundsMin, boundsMax)
		if isExpandMode then
			DesignCamera.SetZoomLimits(nil, getPlotFitDistance())
		else
			DesignCamera.SetZoomLimits(nil, nil)
		end

		if activatedTopDown or designSessionPendingFocus then
			local storedState = topDownStateByPlotId[plotInfo.PlotId]
			if storedState then
				DesignCamera.ApplyTopDownState(storedState)
			else
				focusTopDownOnSelectionOrPlayer(plotInfo, boundsMin, boundsMax)
			end
			designSessionPendingFocus = false
		end
	end

	-- Determine how to display half walls client-side

	-- hide other levels
	if false then
		for level = 1, Formex.MaxPlotSize.Levels, 1 do
			local levelPart = plotInfo.PlotPart:FindFirstChild(tostring(level), false)
			if not levelPart then continue end
			local transparency = (viewSettings.ShowOtherLevels or level == currentLevel) and 0 or 1
			for _, folder in levelPart:GetChildren() do
				for _, part in folder:GetChildren() do
					part.Transparency = transparency
				end
			end
		end
	end

	if viewSettings.ShowSegments then
		renderExpandOverlay(plotInfo)
	end

	if viewSettings.ShowGrid then
		renderGridOverlays(plotInfo)
	end
end

local function getLevel(): number
	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid then return	1 end

	local head: Instance =
		localPlayer.Character:WaitForChild("Head") or
		localPlayer.Character:WaitForChild("HumanoidRootPart")
	local position: Vector3 = head.Position

	-- TODO: calculate the current level in the plot from player's character's head
	local level = 1

	return level
end

function FormexDesign.ClearSelection()
	local wasObjectSelection = selectionType == FormexDesign.SelectionType.Object
	local wasObjectMode = designMode == FormexDesign.DesignMode.Object
	selectionType = FormexDesign.SelectionType.None
	selectionData = nil
	selectionPart = nil
	wallSelectedSettings.HasSelection = false
	floorSelectedSettings.HasSelection = false
	objectSelectedSettings.HasSelection = false
	if Walls then
		Walls.ClearSelection()
	end
	if Floors then
		Floors.ClearSelection()
	end
	if Rooms then
		Rooms.ClearSelection()
	end
	FormexDesignHighlights.UpdateSelectionHighlight()
	notifyDesignModeChange()
	if wasObjectSelection and wasObjectMode then
		FormexDesign.SetDesignMode(FormexDesign.DesignMode.Select, true)
	end
end

local function snapToGrid(value: number): number
	local grid = Formex.LayoutGridSize
	return math.round(value / grid) * grid
end

local function getSnappedPoint(plotPart: BasePart, worldPosition: Vector3): Vector2int16
	local localPosition = plotPart.CFrame:PointToObjectSpace(worldPosition)
	return Vector2int16.new(snapToGrid(localPosition.X), snapToGrid(localPosition.Z))
end

local function getLayoutTile(plotPart: BasePart, worldPosition: Vector3): Vector2int16
	local localPosition = plotPart.CFrame:PointToObjectSpace(worldPosition)
	local tileSize = Formex.LayoutGridSize
	local x = math.floor((localPosition.X + (Formex.Dimensions.Width / 2)) / tileSize)
	local y = math.floor((localPosition.Z + (Formex.Dimensions.Depth / 2)) / tileSize)
	return Vector2int16.new(x, y)
end

local function toSnappedVector2int16(point: Vector2): Vector2int16
	return Vector2int16.new(snapToGrid(point.X), snapToGrid(point.Y))
end

local function getLocalXZ(plotPart: BasePart, worldPosition: Vector3): Vector2
	local localPosition = plotPart.CFrame:PointToObjectSpace(worldPosition)
	return Vector2.new(localPosition.X, localPosition.Z)
end

local function snapWallEndPoint(startPoint: Vector2 | Vector2int16, rawEndPoint: Vector2): Vector2int16
	local dx = rawEndPoint.X - startPoint.X
	local dz = rawEndPoint.Y - startPoint.Y
	local length = math.sqrt(dx * dx + dz * dz)
	if length <= 1e-4 then return rawEndPoint end
	local snappedDx = dx
	local snappedDz = dz
	if Formex.SnapWallsTo45Degrees then
		local angle = math.atan2(dz, dx)
		local step = math.pi / 4
		local snappedAngle = math.round(angle / step) * step
		local snappedLength = math.max(math.abs(dx), math.abs(dz))

		snappedDx = math.cos(snappedAngle) * snappedLength
		snappedDz = math.sin(snappedAngle) * snappedLength
	end

	snappedDx = snapToGrid(snappedDx)
	snappedDz = snapToGrid(snappedDz)

	return Vector2int16.new(startPoint.X + snappedDx, startPoint.Y + snappedDz)
end

local function isPointInOwnedSegments(plotInfo: FormexClient.PlotInfo, point: Vector2): boolean
	local mask = plotInfo.SegmentsUnlocked
	if not mask or mask == 0 then return false end
	local halfWidth = Formex.SegmentSize.Width / 2
	local halfDepth = Formex.SegmentSize.Depth / 2

	for index = 1, Formex.Segments.Count do
		if Formex.Segments.IsUnlocked(mask, index) then
			local row, column = Formex.Segments.GetRowColumn(index)
			local centerX = (column - (Formex.Segments.GridWidth + 1) / 2) * Formex.SegmentSize.Width
			local centerZ = (row - (Formex.Segments.GridHeight + 1) / 2) * Formex.SegmentSize.Depth
			if math.abs(point.X - centerX) <= halfWidth + 1e-4
			and math.abs(point.Y - centerZ) <= halfDepth + 1e-4 then
				return true
			end
		end
	end

	return false
end

local function getPointerHit(forceGridCollision: boolean?): (Ray?, Vector3?, Vector3?, Instance?)
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil, nil, nil
	end

	local plotInfo = FormexClient.CurrentPlot
	local mousePosition = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePosition.X, mousePosition.Y)
	local params = RaycastParams.new()
	params.IgnoreWater = true

	local useGridSegmentsOnly =
		actionType ~= FormexDesign.ActionType.Select
		and (designMode == FormexDesign.DesignMode.Wall
			or designMode == FormexDesign.DesignMode.Floor
			or designMode == FormexDesign.DesignMode.Room)

	local objectRaycastInfo = nil
	if not useGridSegmentsOnly
		and designMode == FormexDesign.DesignMode.Object
		and actionType ~= FormexDesign.ActionType.Select
		and Objects
		and Objects.GetRaycastInfo
		and plotInfo then
		objectRaycastInfo = Objects.GetRaycastInfo(plotInfo, currentLevel)
	end

	if useGridSegmentsOnly then
		local gridSegments = {}
		for _, child in ipairs(overlayFolder:GetChildren()) do
			if child:IsA("BasePart") and child.Name:sub(1, 5) == "Grid_" then
				table.insert(gridSegments, child)
			end
		end
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = gridSegments
		params.RespectCanCollide = false
	else
		params.FilterType = objectRaycastInfo and objectRaycastInfo.FilterType or Enum.RaycastFilterType.Exclude
		local ignoreList = nil

		if objectRaycastInfo and objectRaycastInfo.FilterType == Enum.RaycastFilterType.Include then
			params.FilterDescendantsInstances = objectRaycastInfo.Instances
			params.RespectCanCollide = false
		elseif forceGridCollision then
			params.CollisionGroup = Formex.CollisionGroup.Grid
		elseif actionType == FormexDesign.ActionType.Select then
			ignoreList = { overlayFolder }
			if localPlayer.Character then
				table.insert(ignoreList, localPlayer.Character)
			end
			if ghost then
				table.insert(ignoreList, ghost)
			end
		elseif designMode == FormexDesign.DesignMode.Object then
			if not objectRaycastInfo then
				params.CollisionGroup = Formex.CollisionGroup.Object
			end
		else
			params.CollisionGroup = Formex.CollisionGroup.Grid
		end

		if designMode == FormexDesign.DesignMode.Object
			and actionType ~= FormexDesign.ActionType.Select
			and (not objectRaycastInfo or objectRaycastInfo.FilterType == Enum.RaycastFilterType.Exclude) then
			if not ignoreList then
				ignoreList = { overlayFolder }
			else
				table.insert(ignoreList, overlayFolder)
			end
			if localPlayer.Character then
				table.insert(ignoreList, localPlayer.Character)
			end
			if ghost then
				table.insert(ignoreList, ghost)
			end
		end

		if objectRaycastInfo and objectRaycastInfo.FilterType == Enum.RaycastFilterType.Exclude then
			ignoreList = ignoreList or {}
			for _, instance in ipairs(objectRaycastInfo.Instances) do
				table.insert(ignoreList, instance)
			end
		end

		if params.FilterType == Enum.RaycastFilterType.Exclude then
			if Objects and Objects.GetRaycastIgnoreInstances then
				local extraIgnore = Objects.GetRaycastIgnoreInstances()
				if extraIgnore and #extraIgnore > 0 then
					if not ignoreList then
						ignoreList = {}
					end
					for _, instance in ipairs(extraIgnore) do
						table.insert(ignoreList, instance)
					end
				end
			end

			if ignoreList then
				params.FilterDescendantsInstances = ignoreList
			end
		end
	end


	local result = Workspace:Raycast(ray.Origin, ray.Direction * 2048, params)
	if not result then
		return ray, nil, nil, nil
	end

	return ray, result.Position, result.Normal, result.Instance
end

local function getInputInfo(forceGridCollision: boolean?): InputInfo | nil
	if designMode == FormexDesign.DesignMode.Play then return nil end
	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid or not plotInfo.PlotPart then return nil end
	local ray, hitPosition, hitNormal, target = getPointerHit(forceGridCollision)
	local snapPoint = hitPosition and getSnappedPoint(plotInfo.PlotPart, hitPosition) or nil
	local layoutTile = hitPosition and getLayoutTile(plotInfo.PlotPart, hitPosition) or nil

	-- AGENT NOTE: Do not touch this function without consulting the original author.
	-- This function is delicate and tightly coupled to the structure of the Formex plot in the

	local partInfo = getDataFromPart(target)

	inputInfo = {
		PlotInfo = plotInfo,
		Ray = ray,
		HitPosition = hitPosition,
		HitNormal = hitNormal,
		SnapPoint = snapPoint,
		LayoutTile = layoutTile,
		PartType = partInfo and partInfo.PartType or nil,
		WallSide = partInfo and partInfo.WallSide or nil,
		FloorSide = partInfo and partInfo.FloorSide or nil,
		WallData = partInfo and partInfo.PartType == Formex.PartType.Wall and partInfo.Data or nil,
		FloorData = partInfo and partInfo.PartType == Formex.PartType.Floor and partInfo.Data or nil,
		ObjectData = partInfo and partInfo.PartType == Formex.PartType.Object and partInfo.Data or nil,
		LevelIndex = partInfo and partInfo.LevelIndex or currentLevel or 1,
		RoomData = partInfo and partInfo.Room or nil,
		Target = target,
		ActionHeld = actionHeld,
		AltHeld = altHeld
	} :: InputInfo

	return inputInfo
end

local function applyGhostAppearance(instance: Instance)
	local function applyToPart(part: BasePart)
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part:SetAttribute("IsGhost", true)
	end

	if instance:IsA("BasePart") then
		instance.Name = "Ghost"
		applyToPart(instance)
	elseif instance:IsA("Model") then
		instance.Name = "Ghost"
		for _, child in ipairs(instance:GetDescendants()) do
			if child:IsA("BasePart") then
				applyToPart(child)
			end
		end
	end
end

local function updateGhostValidity(isValid: boolean)
	ghostIsValid = isValid
	if ghost
		and (ghostType == Formex.PartType.Floor or ghostType == Formex.PartType.Ceiling)
		and ghost:IsA("BasePart") then
		ghost.Color = ghostIsValid and Constants.GhostValidColor or Constants.GhostInvalidColor
		ghost.Transparency = Constants.FloorGhostTransparency
	end
	FormexDesignHighlights.UpdateSelectionHighlight()
end

function Formex.HideGhost(plotPart: BasePart?)
	if not ghost then return end
	local hiddenCFrame = CFrame.new(0, -10000, 0)
	if plotPart then
		local offsetY = Formex.LevelHeight * (Formex.MaxPlotSize.Levels + 2)
		hiddenCFrame = plotPart.CFrame * CFrame.new(0, -offsetY, 0)
	end

	local function hidePart(part: BasePart)
		part.Size = Vector3.new(0, 0, 0)
		part.CFrame = hiddenCFrame
	end

	if ghost:IsA("BasePart") then
		hidePart(ghost)
	elseif ghost:IsA("Model") then
		for _, child in ipairs(ghost:GetDescendants()) do
			if child:IsA("BasePart") then
				hidePart(child)
			end
		end
	end

	ghostActive = false
	ghostIsValid = false
	FormexDesignHighlights.UpdateSelectionHighlight()
end

local function clearGhost()
	local plotInfo = FormexClient.CurrentPlot
	Formex.HideGhost(plotInfo and plotInfo.PlotPart or nil)
end

local function buildWallData(startPoint: Vector2int16, endPoint: Vector2int16): Formex.WallData
	return {
		WallId = 0,
		Level = currentLevel,
		Start = startPoint,
		End = endPoint,
		Height = wallBuildSettings.Height,
		FrontSplitHeight = wallBuildSettings.FrontSplitHeight,
		BackSplitHeight = wallBuildSettings.BackSplitHeight,
		FrontTopMaterial = wallBuildSettings.FrontTopMaterial,
		FrontBottomMaterial = wallBuildSettings.FrontBottomMaterial,
		BackTopMaterial = wallBuildSettings.BackTopMaterial,
		BackBottomMaterial = wallBuildSettings.BackBottomMaterial,
		FrontTopColor = wallBuildSettings.FrontTopColor,
		FrontBottomColor = wallBuildSettings.FrontBottomColor,
		BackTopColor = wallBuildSettings.BackTopColor,
		BackBottomColor = wallBuildSettings.BackBottomColor,
		Part = nil
	}
end

local function pointsEqual(a: Vector2int16, b: Vector2int16): boolean
	return a.X == b.X and a.Y == b.Y
end

local function getWallSegmentKey(startPoint: Vector2int16, endPoint: Vector2int16): string
	local aKey = Formex.Poly.GetPointKey(startPoint)
	local bKey = Formex.Poly.GetPointKey(endPoint)
	if aKey < bKey then
		return aKey .. "|" .. bKey
	end
	return bKey .. "|" .. aKey
end

local function buildRoomWalls(plotInfo: FormexClient.PlotInfo, levelIndex: number, points: {Vector2int16}): {Formex.WallData}
	local walls = {}
	local existing = {}
	local levelData = plotInfo.PlotData.Levels and plotInfo.PlotData.Levels[levelIndex]
	if levelData and levelData.Walls then
		for _, wall in pairs(levelData.Walls) do
			if wall.Start and wall.End then
				existing[getWallSegmentKey(wall.Start, wall.End)] = true
			end
		end
	end

	for i = 1, #points do
		local startPoint = points[i]
		local endPoint = points[(i % #points) + 1]
		if not pointsEqual(startPoint, endPoint) then
			local key = getWallSegmentKey(startPoint, endPoint)
			if not existing[key] then
				local wallData = buildWallData(startPoint, endPoint)
				wallData.Level = levelIndex
				table.insert(walls, wallData)
			end
		end
	end

	return walls
end

local function buildFloorGhostData(levelIndex: number, tile: Vector2int16): Formex.FloorData
	local tileSize = Formex.LayoutGridSize
	local x0 = tile.X * tileSize - (Formex.Dimensions.Width / 2)
	local z0 = tile.Y * tileSize - (Formex.Dimensions.Depth / 2)
	return {
		FloorId = 0,
		LevelIndex = levelIndex,
		Points = {
			Vector2int16.new(x0, z0),
			Vector2int16.new(x0 + tileSize, z0),
			Vector2int16.new(x0 + tileSize, z0 + tileSize),
			Vector2int16.new(x0, z0 + tileSize),
		},
		RaiseHeight = floorRaiseHeight,
		FloorMaterial = floorMaterialId,
		CeilingMaterial = ceilingMaterialId,
		FoundationMaterial = foundationMaterialId,
		FloorColor = floorColor,
		CeilingColor = ceilingColor,
		FoundationColor = foundationColor,
		Model = nil,
	}
end

local function ensureWallGhost(plotPart: BasePart, startPoint: Vector2, endPoint: Vector2)
	if ghostType ~= Formex.PartType.Wall then
		if ghost then
			ghost:Destroy()
		end
		ghost = nil
		ghostWallData = nil
		ghostFloorData = nil
		ghostType = Formex.PartType.Wall
	end

	if not ghostWallData then
		ghostWallData = buildWallData(startPoint, endPoint)
		ghost = Formex.Walls.Create(ghostWallData, plotPart)
		if ghost then
			ghost.Parent = overlayFolder
			applyGhostAppearance(ghost)
		end
	else
		ghostWallData.Level = currentLevel
		ghostWallData.Start = startPoint
		ghostWallData.End = endPoint
	end

	if ghostWallData then
		Formex.Walls.Edit(ghostWallData, plotPart)
	end

	ghostActive = ghost ~= nil
	FormexDesignHighlights.UpdateSelectionHighlight()
end

local function ensureFloorGhost(plotPart: BasePart, levelIndex: number, tile: Vector2int16, partType: Formex.PartType)
	if ghostType ~= partType then
		if ghost then
			ghost:Destroy()
		end
		ghost = nil
		ghostWallData = nil
		ghostFloorData = nil
		ghostType = partType
	end

	if not ghost then
		ghost = Instance.new("Part", overlayFolder)
		ghost.Anchored = true
		applyGhostAppearance(ghost)
		ghost.Transparency = 1
	end

	if not ghostFloorData then
		ghostFloorData = buildFloorGhostData(levelIndex, tile)
	else
		ghostFloorData.LevelIndex = levelIndex
		ghostFloorData.FloorId = 0
		ghostFloorData.RaiseHeight = floorRaiseHeight
		ghostFloorData.FloorMaterial = floorMaterialId
		ghostFloorData.CeilingMaterial = ceilingMaterialId
		ghostFloorData.FoundationMaterial = foundationMaterialId
		ghostFloorData.FloorColor = floorColor
		ghostFloorData.CeilingColor = ceilingColor
		ghostFloorData.FoundationColor = foundationColor
	end

	local tileSize = Formex.LayoutGridSize
	local xOffset = (tile.X + 0.5) * tileSize - (Formex.Dimensions.Width / 2)
	local zOffset = (tile.Y + 0.5) * tileSize - (Formex.Dimensions.Depth / 2)
	local levelTop = Formex.LevelHeight * (levelIndex - 1)
	local raiseHeight = ghostFloorData.RaiseHeight
	local yTop = levelTop
	local yBottom = levelTop - (levelIndex == 1 and Formex.SegmentSize.Foundation or Formex.SegmentSize.Interfloor)
	if raiseHeight and raiseHeight > 0 then
		yTop = levelTop + raiseHeight
		yBottom = levelTop
	end
	local thickness = math.abs(yTop - yBottom)
	local centerY = (yTop + yBottom) / 2

	ghost.Size = Vector3.new(tileSize, thickness, tileSize)
	ghost.CFrame = plotPart.CFrame * CFrame.new(xOffset, centerY, zOffset)
	ghost.Transparency = Constants.FloorGhostTransparency
	ghost.Color = ghostIsValid and Constants.GhostValidColor or Constants.GhostInvalidColor

	ghostActive = true
	FormexDesignHighlights.UpdateSelectionHighlight()
end

local allowedSelectionByMode = {
	[FormexDesign.DesignMode.Select] = {
		[FormexDesign.SelectionType.Wall] = true,
		[FormexDesign.SelectionType.Floor] = true,
		[FormexDesign.SelectionType.Object] = true,
	},
	[FormexDesign.DesignMode.Dropper] = {
		[FormexDesign.SelectionType.Wall] = true,
		[FormexDesign.SelectionType.Floor] = true,
		[FormexDesign.SelectionType.Object] = true,
	},
	[FormexDesign.DesignMode.Wall] = {
		[FormexDesign.SelectionType.Wall] = true,
	},
	[FormexDesign.DesignMode.Floor] = {
		[FormexDesign.SelectionType.Floor] = true,
	},
	[FormexDesign.DesignMode.Object] = {
		[FormexDesign.SelectionType.Object] = true,
	},
	[FormexDesign.DesignMode.Room] = {
		[FormexDesign.SelectionType.Room] = true,
	},
} :: { [DesignMode]: {[SelectionType]: boolean} }
designModeBySelectionType = {
	[FormexDesign.SelectionType.Wall] = FormexDesign.DesignMode.Wall,
	[FormexDesign.SelectionType.Floor] = FormexDesign.DesignMode.Floor,
	[FormexDesign.SelectionType.Object] = FormexDesign.DesignMode.Object,
} :: { [SelectionType]: DesignMode }

local function updateSelectionSettingsFromSelection()
	if selectionType == FormexDesign.SelectionType.Wall then
		floorSelectedSettings.HasSelection = false
		local wallData = Walls.GetSelectedWallData()
		if not wallData then
			wallSelectedSettings.HasSelection = false
			return
		end

		wallSelectedSettings = {
			Height = wallData.Height,
			FrontSplitHeight = wallData.FrontSplitHeight,
			BackSplitHeight = wallData.BackSplitHeight,
			FrontTopMaterial = wallData.FrontTopMaterial,
			FrontBottomMaterial = wallData.FrontBottomMaterial,
			BackTopMaterial = wallData.BackTopMaterial,
			BackBottomMaterial = wallData.BackBottomMaterial,
			FrontTopColor = wallData.FrontTopColor,
			FrontBottomColor = wallData.FrontBottomColor,
			BackTopColor = wallData.BackTopColor,
			BackBottomColor = wallData.BackBottomColor,
			HasSelection = true,
		} :: WallSelectedSettings
		return
	end

	if selectionType == FormexDesign.SelectionType.Floor then
		wallSelectedSettings.HasSelection = false
		local floorData = Floors.GetSelectedFloorData()
		if not floorData then
			floorSelectedSettings.HasSelection = false
			return
		end

		floorSelectedSettings = {
			RaiseHeight = floorData.RaiseHeight,
			FloorMaterial = floorData.FloorMaterial,
			CeilingMaterial = floorData.CeilingMaterial,
			FoundationMaterial = floorData.FoundationMaterial,
			FloorColor = floorData.FloorColor,
			CeilingColor = floorData.CeilingColor,
			FoundationColor = floorData.FoundationColor,
			HasSelection = true,
		} :: FloorSelectedSettings
		return
	end

	if selectionType == FormexDesign.SelectionType.Object then
		wallSelectedSettings.HasSelection = false
		floorSelectedSettings.HasSelection = false
		local objectData = Objects and Objects.GetSelectedObjectData and Objects.GetSelectedObjectData() or nil
		if not objectData then
			objectSelectedSettings.HasSelection = false
			return
		end
		objectSelectedSettings = {
			PrefabName = objectData.PrefabName,
			Design = table.clone(objectData.Design or {}),
			DesignColors = table.clone(objectData.DesignColors or {}),
			HasSelection = true,
		} :: ObjectSelectedSettings
		if objectData.PrefabName then
			objectPrefabName = objectData.PrefabName
		end
		return
	end

	wallSelectedSettings.HasSelection = false
	floorSelectedSettings.HasSelection = false
	objectSelectedSettings.HasSelection = false
end

local function updateSelectionHandles(plotInfo: any)
	if not plotInfo or not plotInfo.IsValid then return end
	if selectionType == FormexDesign.SelectionType.Wall then
		if Walls then
			Walls.UpdateHandles(plotInfo)
		end
		return
	end

	if selectionType == FormexDesign.SelectionType.Floor then
		if Floors then
			Floors.UpdateHandles(plotInfo)
		end
		return
	end

	if selectionType == FormexDesign.SelectionType.Object then
		if Objects then
			Objects.UpdateHandles(plotInfo)
		end
		return
	end

	if selectionType == FormexDesign.SelectionType.Room then
		if Rooms then
			Rooms.UpdateHandles(plotInfo)
		end
	end
end

local function setRoomSelection(roomData: Formex.RoomData?)
	beginDesignStateBatch()
	selectionPart = nil
	if roomData then
		selectionType = FormexDesign.SelectionType.Room
		selectionData = roomData
		currentLevel = roomData.LevelIndex
	else
		selectionType = FormexDesign.SelectionType.None
		selectionData = nil
	end
	updateSelectionSettingsFromSelection()
	FormexDesignHighlights.UpdateSelectionHighlight()
	updateSelectionHandles(FormexClient.CurrentPlot)
	notifyDesignModeChange()
	endDesignStateBatch()
end

local function selectRoomAtPoint(plotInfo: FormexClient.PlotInfo?, levelIndex: number, point: Vector2?)
	if not plotInfo or not plotInfo.PlotData or not plotInfo.PlotData.Rooms or not point then
		setRoomSelection(nil)
		return
	end

	local selected = nil
	for _, room in pairs(plotInfo.PlotData.Rooms) do
		if room.LevelIndex == levelIndex and room.Points and #room.Points >= 3 and not room.IsExterior then
			if Formex.Poly.IsPointInsidePolygon(point, room.Points, true, Formex.EPSILON) then
				if not selected or room.Area < selected.Area then
					selected = room
				end
			end
		end
	end

	setRoomSelection(selected)
end

local function setHandlesBusy(active: boolean)
	if FormexDesign.Handles and FormexDesign.Handles.SetBusy then
		FormexDesign.Handles.SetBusy(active)
	end
end

local function runBuildTransaction(changes: {Formex.BuildChange}, selection: Formex.SelectionSnapshot?): {Formex.BuildChangeResult}?
	setHandlesBusy(true)
	local results = FormexClient.BuildTransaction(changes, selection)
	setHandlesBusy(false)
	return results
end

local function buildFloor(floorData: Formex.FloorData, action: Formex.BuildAction, selection: Formex.SelectionSnapshot?): any
	local results = runBuildTransaction({
		{
			PartType = Formex.PartType.Floor,
			Action = action,
			Data = floorData,
		},
	}, selection)
	if not results then return nil end
	local changeResult = results[1]
	return changeResult and changeResult.Result or nil
end

local function buildRoomFromFloor(floorData: Formex.FloorData, selectionSnapshot: Formex.SelectionSnapshot?)
	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid then return nil end
	local walls = buildRoomWalls(plotInfo, floorData.LevelIndex, floorData.Points)
	local changes = {}
	if #walls > 0 then
		table.insert(changes, {
			PartType = Formex.PartType.Wall,
			Action = Formex.BuildAction.Add,
			Data = walls,
		})
	end
	table.insert(changes, {
		PartType = Formex.PartType.Floor,
		Action = Formex.BuildAction.Add,
		Data = floorData,
	})

	return runBuildTransaction(changes, selectionSnapshot or getSelectionSnapshot())
end

local function buildFloorForMode(floorData: Formex.FloorData, selectionSnapshot: Formex.SelectionSnapshot?)
	if designMode == FormexDesign.DesignMode.Room then
		return buildRoomFromFloor(floorData, selectionSnapshot)
	end
	return buildFloor(floorData, Formex.BuildAction.Add, selectionSnapshot or getSelectionSnapshot())
end

local function selectAfterFloorBuild(plotInfo: FormexClient.PlotInfo?, levelIndex: number, points: {Vector2int16}, result: any?)
	if not plotInfo or not plotInfo.IsValid then return end
	if designMode == FormexDesign.DesignMode.Room then
		local sample = Formex.Poly.GetFaceSamplePoint(points, Formex.EPSILON)
		if sample then
			selectRoomAtPoint(plotInfo, levelIndex, sample)
		end
		return
	end

	local floorId = nil
	if type(result) == "number" then
		floorId = result
	elseif type(result) == "table" and result.FloorId then
		floorId = result.FloorId
	elseif type(result) == "table" and #result >= 1 and type(result[1]) == "number" then
		floorId = result[1]
	elseif type(result) == "table" then
		for _, change in ipairs(result) do
			if change.PartType == Formex.PartType.Floor and change.Result then
				if type(change.Result) == "number" then
					floorId = change.Result
					break
				elseif type(change.Result) == "table" and change.Result.FloorId then
					floorId = change.Result.FloorId
					break
				end
			end
		end
	end
	if floorId then
		selectPlotModelByIdAsync(plotInfo, Enums.SelectionType.Floor, levelIndex, floorId)
	end
end

local function updateFloorPaintSettingsSilently(settings: FloorSelectedSettings)
	floorRaiseHeight = clampFloorRaiseHeight(settings.RaiseHeight)
	floorMaterialId = settings.FloorMaterial
	ceilingMaterialId = settings.CeilingMaterial
	foundationMaterialId = settings.FoundationMaterial
	floorColor = settings.FloorColor
	ceilingColor = settings.CeilingColor
	foundationColor = settings.FoundationColor

	if ghostActive
	and (ghostType == Formex.PartType.Floor or ghostType == Formex.PartType.Ceiling)
	and ghostFloorData then
		ghostFloorData.RaiseHeight = floorRaiseHeight
		ghostFloorData.FloorMaterial = floorMaterialId
		ghostFloorData.CeilingMaterial = ceilingMaterialId
		ghostFloorData.FoundationMaterial = foundationMaterialId
		ghostFloorData.FloorColor = floorColor
		ghostFloorData.CeilingColor = ceilingColor
		ghostFloorData.FoundationColor = foundationColor
	end
end

local function syncPaintFromSelection(silent: boolean?)
	if designMode == FormexDesign.DesignMode.Dropper then return end
	if designSubMode ~= FormexDesign.DesignSubMode.Normal then return end
	if selectionType == FormexDesign.SelectionType.Floor and floorSelectedSettings.HasSelection then
		updateFloorPaintSettingsSilently(floorSelectedSettings)
		if not silent then
			notifyDesignModeChange()
		end
		return
	end

	if selectionType == FormexDesign.SelectionType.Object and objectSelectedSettings.HasSelection then
		objectPaintSettings.Design = table.clone(objectSelectedSettings.Design)
		objectPaintSettings.DesignColors = table.clone(objectSelectedSettings.DesignColors)
		if not silent then
			notifyDesignModeChange()
		end
	end
end

function FormexDesign.RefreshSelectionSettings()
	updateSelectionSettingsFromSelection()
	syncPaintFromSelection(true)
end

local function applyWallStateUpdate(update: WallStateUpdate?)
	if not update then return end
	local overrides = {}
	local changed = false
	local inDropperMode = designMode == FormexDesign.DesignMode.Dropper
	local applyToSelection = not inDropperMode
		and designSubMode == FormexDesign.DesignSubMode.Normal
		and selectionType == FormexDesign.SelectionType.Wall
		and wallSelectedSettings.HasSelection
	local updatePaintSettings = inDropperMode or designSubMode == FormexDesign.DesignSubMode.Paint
	local updateBuildSettings = not inDropperMode
		and designSubMode == FormexDesign.DesignSubMode.Normal
		and not applyToSelection
	local heightValue = nil
	if updatePaintSettings then
		heightValue = wallPaintSettings.Height
	elseif updateBuildSettings then
		heightValue = wallBuildSettings.Height
	else
		heightValue = wallSelectedSettings.Height
	end

	if update.Height ~= nil then
		changed = true
		if update.Height == false then
			heightValue = nil
			overrides.Height = false
		else
			heightValue = clampWallHeight(update.Height)
			overrides.Height = heightValue
		end
		if updatePaintSettings then
			wallPaintSettings.Height = heightValue
			local splitHeight = wallPaintSettings.SplitHeight
			if splitHeight ~= nil then
				wallPaintSettings.SplitHeight = clampWallSplit(splitHeight, heightValue)
			end
		elseif updateBuildSettings then
			wallBuildSettings.Height = heightValue
			local frontSplit = wallBuildSettings.FrontSplitHeight
			if frontSplit ~= nil then
				wallBuildSettings.FrontSplitHeight = clampWallSplit(frontSplit, heightValue)
			end
			local backSplit = wallBuildSettings.BackSplitHeight
			if backSplit ~= nil then
				wallBuildSettings.BackSplitHeight = clampWallSplit(backSplit, heightValue)
			end
		end
	end

	if update.FrontSplitHeight ~= nil then
		local clamped = 0
		if update.FrontSplitHeight ~= false then
			clamped = clampWallSplit(update.FrontSplitHeight, heightValue) or 0
		end
		if applyToSelection then
			changed = true
			overrides.FrontSplitHeight = clamped
		end
		if updateBuildSettings then
			changed = true
			wallBuildSettings.FrontSplitHeight = clamped
		end
	end

	if update.BackSplitHeight ~= nil then
		local clamped = 0
		if update.BackSplitHeight ~= false then
			clamped = clampWallSplit(update.BackSplitHeight, heightValue) or 0
		end
		if applyToSelection then
			changed = true
			overrides.BackSplitHeight = clamped
		end
		if updateBuildSettings then
			changed = true
			wallBuildSettings.BackSplitHeight = clamped
		end
	end

	if update.FrontTopMaterial ~= nil then
		if applyToSelection then
			changed = true
			overrides.FrontTopMaterial = update.FrontTopMaterial
		end
		if updateBuildSettings then
			changed = true
			wallBuildSettings.FrontTopMaterial = update.FrontTopMaterial
		end
	end

	if update.FrontBottomMaterial ~= nil then
		if applyToSelection then
			changed = true
			overrides.FrontBottomMaterial = update.FrontBottomMaterial
		end
		if updateBuildSettings then
			changed = true
			wallBuildSettings.FrontBottomMaterial = update.FrontBottomMaterial
		end
	end

	if update.BackTopMaterial ~= nil then
		if applyToSelection then
			changed = true
			overrides.BackTopMaterial = update.BackTopMaterial
		end
		if updateBuildSettings then
			changed = true
			wallBuildSettings.BackTopMaterial = update.BackTopMaterial
		end
	end

	if update.BackBottomMaterial ~= nil then
		if applyToSelection then
			changed = true
			overrides.BackBottomMaterial = update.BackBottomMaterial
		end
		if updateBuildSettings then
			changed = true
			wallBuildSettings.BackBottomMaterial = update.BackBottomMaterial
		end
	end

	if update.FrontTopColor ~= nil then
		if applyToSelection then
			changed = true
			overrides.FrontTopColor = update.FrontTopColor
		end
		if updateBuildSettings then
			changed = true
			wallBuildSettings.FrontTopColor = update.FrontTopColor
		end
	end

	if update.FrontBottomColor ~= nil then
		if applyToSelection then
			changed = true
			overrides.FrontBottomColor = update.FrontBottomColor
		end
		if updateBuildSettings then
			changed = true
			wallBuildSettings.FrontBottomColor = update.FrontBottomColor
		end
	end

	if update.BackTopColor ~= nil then
		if applyToSelection then
			changed = true
			overrides.BackTopColor = update.BackTopColor
		end
		if updateBuildSettings then
			changed = true
			wallBuildSettings.BackTopColor = update.BackTopColor
		end
	end

	if update.BackBottomColor ~= nil then
		if applyToSelection then
			changed = true
			overrides.BackBottomColor = update.BackBottomColor
		end
		if updateBuildSettings then
			changed = true
			wallBuildSettings.BackBottomColor = update.BackBottomColor
		end
	end

	if update.SplitHeight ~= nil and updatePaintSettings then
		changed = true
		if update.SplitHeight == false then
			wallPaintSettings.SplitHeight = 0
		else
			wallPaintSettings.SplitHeight = clampWallSplit(update.SplitHeight, heightValue) or 0
		end
	end

	if update.TopMaterial ~= nil and updatePaintSettings then
		changed = true
		wallPaintSettings.TopMaterial = update.TopMaterial
	end

	if update.BottomMaterial ~= nil and updatePaintSettings then
		changed = true
		wallPaintSettings.BottomMaterial = update.BottomMaterial
	end

	if update.TopColor ~= nil and updatePaintSettings then
		changed = true
		wallPaintSettings.TopColor = update.TopColor
	end

	if update.BottomColor ~= nil and updatePaintSettings then
		changed = true
		wallPaintSettings.BottomColor = update.BottomColor
	end

	if changed then
		notifyDesignModeChange()
	end

	if applyToSelection and next(overrides) ~= nil then
		if Walls.ApplySelectedAppearance(overrides) then
			updateSelectionSettingsFromSelection()
		end
	end
end

local function applyFloorStateUpdate(update: FloorStateUpdate?)
	if not update then return end
	local inDropperMode = designMode == FormexDesign.DesignMode.Dropper
	local applyToSelection = not inDropperMode
		and designSubMode == FormexDesign.DesignSubMode.Normal
		and selectionType == FormexDesign.SelectionType.Floor
		and floorSelectedSettings.HasSelection
	local updatedSelection = false
	local modeChanged = false

	if update.Mode ~= nil and update.Mode ~= floorMode then
		if actionType ~= FormexDesign.ActionType.Select then
			FormexDesign.CancelAction()
		end
		floorMode = update.Mode
		modeChanged = true
	end

	if update.RaiseHeight ~= nil then
		local clamped = clampFloorRaiseHeight(update.RaiseHeight)
		setFloorRaiseHeight(clamped, applyToSelection)
		updatedSelection = true
	end

	if update.FloorMaterial ~= nil then
		setFloorMaterial(update.FloorMaterial, applyToSelection)
		updatedSelection = true
	end

	if update.CeilingMaterial ~= nil then
		setCeilingMaterial(update.CeilingMaterial, applyToSelection)
		updatedSelection = true
	end

	if update.FoundationMaterial ~= nil then
		setFoundationMaterial(update.FoundationMaterial, applyToSelection)
		updatedSelection = true
	end

	if update.FloorColor ~= nil then
		setFloorColor(update.FloorColor, applyToSelection)
		updatedSelection = true
	end

	if update.CeilingColor ~= nil then
		setCeilingColor(update.CeilingColor, applyToSelection)
		updatedSelection = true
	end

	if update.FoundationColor ~= nil then
		setFoundationColor(update.FoundationColor, applyToSelection)
		updatedSelection = true
	end

	if applyToSelection and updatedSelection then
		updateSelectionSettingsFromSelection()
	end
	if modeChanged then
		notifyDesignModeChange()
	end
end

local function applyObjectStateUpdate(update: ObjectStateUpdate?)
	if not update then return end
	local inDropperMode = designMode == FormexDesign.DesignMode.Dropper
	local applyToSelection = not inDropperMode
		and designSubMode == FormexDesign.DesignSubMode.Normal
		and selectionType == FormexDesign.SelectionType.Object
		and objectSelectedSettings.HasSelection

	local changed = false

	if update.PrefabName ~= nil and update.PrefabName ~= objectPrefabName then
		objectPrefabName = update.PrefabName
		changed = true

		local prefab = objectPrefabName and Formex.Objects.GetPrefab(objectPrefabName) or nil
		if prefab then
			objectPaintSettings.Design = {}
			objectPaintSettings.DesignColors = {}
			for index, materialId in ipairs(prefab.DefaultDesign or {}) do
				objectPaintSettings.Design[index] = materialId
			end
		end
	end

	local function applyDesignToTarget(targetDesign: {[number]: number}, targetColors: {[number]: Color3})
		if update.Design then
			table.clear(targetDesign)
			for index, materialId in pairs(update.Design) do
				targetDesign[index] = materialId
			end
			changed = true
		end
		if update.DesignColors then
			table.clear(targetColors)
			for index, color in pairs(update.DesignColors) do
				targetColors[index] = color
			end
			changed = true
		end
		if update.DesignIndex ~= nil then
			local index = update.DesignIndex
			if update.Material ~= nil then
				targetDesign[index] = update.Material
				changed = true
			end
			if update.Color ~= nil then
				targetColors[index] = update.Color
				changed = true
			end
		end
	end

	if applyToSelection then
		applyDesignToTarget(objectSelectedSettings.Design, objectSelectedSettings.DesignColors)
		if changed and Objects and Objects.ApplySelectedDesign then
			Objects.ApplySelectedDesign(objectSelectedSettings.Design, objectSelectedSettings.DesignColors)
		end
	else
		applyDesignToTarget(objectPaintSettings.Design, objectPaintSettings.DesignColors)
	end

	if changed then
		notifyDesignModeChange()
	end
end

function FormexDesign.UpdateDesignState(update: DesignStateUpdate)
	if not update then return end
	beginDesignStateBatch()

	if update.Mode ~= nil then
		FormexDesign.SetDesignMode(update.Mode)
	end

	if update.SubMode ~= nil then
		FormexDesign.SetDesignSubMode(update.SubMode)
	end

	if update.EditMode ~= nil and update.EditMode ~= editMode then
		editMode = update.EditMode
		notifyDesignStateChange()
	end

	if update.CanUndo ~= nil and update.CanUndo ~= canUndo then
		canUndo = update.CanUndo
		notifyDesignStateChange()
	end

	if update.CanRedo ~= nil and update.CanRedo ~= canRedo then
		canRedo = update.CanRedo
		notifyDesignStateChange()
	end

	if update.Wall ~= nil then
		applyWallStateUpdate(update.Wall)
	end

	if update.Floor ~= nil then
		applyFloorStateUpdate(update.Floor)
	end

	if update.Object ~= nil then
		applyObjectStateUpdate(update.Object)
	end

	endDesignStateBatch()
end


local function handleDropperDesignModeClick(input: InputInfo): boolean
	if designMode ~= FormexDesign.DesignMode.Dropper then return false end
	if not input.Target then return true end
	local function copyForMode(mode: DesignMode): boolean
		if mode == FormexDesign.DesignMode.Wall and Walls and Walls.CopyPaintFromTarget then
			return Walls.CopyPaintFromTarget(input)
		end
		if mode == FormexDesign.DesignMode.Floor and Floors and Floors.CopyPaintFromTarget then
			return Floors.CopyPaintFromTarget(input)
		end
		if mode == FormexDesign.DesignMode.Object and Objects and Objects.CopyPaintFromTarget then
			return Objects.CopyPaintFromTarget(input)
		end
		return false
	end

	if altDropperForced and lastDesignModeBeforeAlt then
		local copied = copyForMode(lastDesignModeBeforeAlt)
		if copied then
			altDropperUsed = true
		end
		return true
	end

	if copyForMode(FormexDesign.DesignMode.Wall) then
		FormexDesign.UpdateDesignState({
			Mode = FormexDesign.DesignMode.Wall,
			SubMode = FormexDesign.DesignSubMode.Paint,
		})
		return true
	end

	if copyForMode(FormexDesign.DesignMode.Floor) then
		FormexDesign.UpdateDesignState({
			Mode = FormexDesign.DesignMode.Floor,
			SubMode = FormexDesign.DesignSubMode.Paint,
		})
		return true
	end

	if copyForMode(FormexDesign.DesignMode.Object) then
		FormexDesign.UpdateDesignState({
			Mode = FormexDesign.DesignMode.Object,
			SubMode = FormexDesign.DesignSubMode.Paint,
		})
		return true
	end

	return true
end

local function handlePaintDropperClick(input: InputInfo): boolean
	if designSubMode == FormexDesign.DesignSubMode.Normal then return false	end
	if not input.Target then return true end
	if designSubMode ~= FormexDesign.DesignSubMode.Paint then return true end

	if designMode == FormexDesign.DesignMode.Wall then
		Walls.ApplyPaintToTarget(input)
	elseif designMode == FormexDesign.DesignMode.Floor then
		Floors.ApplyPaintToTarget(input)
	elseif designMode == FormexDesign.DesignMode.Object then
		Objects.ApplyPaintToTarget(input)
	end

	return true
end

-- Wall-specific helpers live in FormexDesignWalls.luau

function FormexDesign.GetSelectionInfo(): (SelectionType, number?, number?)
	if selectionType == FormexDesign.SelectionType.None or not selectionData then
		return selectionType, nil, nil
	end
	if selectionType == FormexDesign.SelectionType.Wall then
		local data = selectionData :: Formex.WallData
		return selectionType, data.WallId, data.Level
	end
	if selectionType == FormexDesign.SelectionType.Floor then
		local data = selectionData :: Formex.FloorData
		return selectionType, data.FloorId, data.LevelIndex
	end
	if selectionType == FormexDesign.SelectionType.Object then
		local data = selectionData :: Formex.ObjectData
		return selectionType, data.ObjectId, data.Level
	end
	if selectionType == FormexDesign.SelectionType.Room then
		local data = selectionData :: Formex.RoomData
		return selectionType, data.RoomId, data.LevelIndex
	end
	return selectionType, nil, nil
end

function FormexDesign.Select(selection: InputInfo | Instance)
	local input: InputInfo? = nil
	local target: Instance? = nil
	if typeof(selection) == "Instance" then
		target = selection
	elseif type(selection) == "table" then
		input = selection :: InputInfo
		target = input.Target
	end

	if designMode == FormexDesign.DesignMode.Room then
		local plotInfo = input and input.PlotInfo or FormexClient.CurrentPlot
		if input and input.RoomData then
			setRoomSelection(input.RoomData)
			return selectionType == FormexDesign.SelectionType.Room
		end
		if plotInfo and plotInfo.PlotPart and input and input.HitPosition then
			local targetLevel = input.LevelIndex or currentLevel
			local localPoint = getLocalXZ(plotInfo.PlotPart, input.HitPosition)
			selectRoomAtPoint(plotInfo, targetLevel, localPoint)
			return selectionType == FormexDesign.SelectionType.Room
		end
		FormexDesign.ClearSelection()
		return false
	end

	if not input and not target then
		FormexDesign.ClearSelection()
		return false
	end

	local selectionKind: SelectionType?
	local resolvedData: SelectionData? = nil
	local selectionTarget: Instance? = nil
	local level: number? = nil
	if input then
		selectionKind, resolvedData, selectionTarget, level = getSelectionFromInput(input)
	else
		selectionKind, resolvedData, selectionTarget, level = getSelectionFromInstance(target :: Instance)
	end

	if not selectionKind or not resolvedData or not level then
		FormexDesign.ClearSelection()
		return false
	end

	local allowedTypes = allowedSelectionByMode[designMode]
	if not allowedTypes or not allowedTypes[selectionKind] then
		FormexDesign.ClearSelection()
		return false
	end

	beginDesignStateBatch()
	selectionType = selectionKind
	selectionData = resolvedData
	selectionPart = selectionTarget or target
	if not selectionPart and selectionData then
		selectionPart = getSelectionPartForKind(selectionKind, selectionData)
	end
	currentLevel = level
	updateSelectionSettingsFromSelection()
	syncPaintFromSelection()

	local modeSwitched = false
	if designMode == FormexDesign.DesignMode.Select then
		local nextMode = designModeBySelectionType[selectionKind]
		if nextMode and nextMode ~= designMode then
			modeSwitched = true
			FormexDesign.SetDesignMode(nextMode, true)
		end
	end
	if not modeSwitched then
		notifyDesignModeChange()
	end
	FormexDesignHighlights.UpdateSelectionHighlight()
	updateSelectionHandles(FormexClient.CurrentPlot)
	endDesignStateBatch()
	return true
end

function FormexDesign.StartWall()
	if Walls then
		Walls.StartWall()
	end
end

function FormexDesign.StartFloor()
	if Floors then
		Floors.StartFloor()
	end
end

function FormexDesign.CancelAction()
	if actionType == FormexDesign.ActionType.Select then return end

	if Walls then
		Walls.CancelAction()
	end
	if Floors then
		Floors.CancelAction()
	end
	if Rooms then
		Rooms.CancelAction()
	end
	if Objects then
		Objects.CancelAction()
	end

	clearGhost()
	actionType = FormexDesign.ActionType.Select
	local plotInfo = FormexClient.CurrentPlot
	updateSelectionHandles(plotInfo)
	notifyDesignModeChange()
end

local function handleUpdate()
	local input = getInputInfo()
	if not input then return end

	if designMode == FormexDesign.DesignMode.Wall then
		if Walls then
			Walls.HandleUpdate(input)
		end
	elseif designMode == FormexDesign.DesignMode.Floor then
		if Floors then
			Floors.HandleUpdate(input)
		end
	elseif designMode == FormexDesign.DesignMode.Room then
		if actionType == FormexDesign.ActionType.Start or actionType == FormexDesign.ActionType.Step then
			if Floors then
				Floors.HandleUpdate(input)
			end
		elseif Rooms then
			Rooms.HandleUpdate(input)
		end
	elseif designMode == FormexDesign.DesignMode.Object then
		if Objects then
			Objects.HandleUpdate(input)
		end
	end
end

local function handlePrimaryRelease()
	local input = getInputInfo()
	if not input then return end

	if designMode == FormexDesign.DesignMode.Wall then
		if Walls then
			Walls.HandlePrimaryRelease(input)
		end
	elseif designMode == FormexDesign.DesignMode.Floor then
		if Floors then
			Floors.HandlePrimaryRelease(input)
		end
	elseif designMode == FormexDesign.DesignMode.Room then
		if actionType == FormexDesign.ActionType.Start or actionType == FormexDesign.ActionType.Step then
			if Floors then
				Floors.HandlePrimaryRelease(input)
			end
		elseif Rooms then
			Rooms.HandlePrimaryRelease(input)
		end
	elseif designMode == FormexDesign.DesignMode.Object then
		if Objects then
			Objects.HandlePrimaryRelease(input)
		end
	end
end

local function handlePrimaryClick()
	local input = getInputInfo()
	if not input then return end

	print("Input Info:", inputInfo)

	if FormexDesign.Handles.HandleClicked(input.Ray) then return end
	-- Clicking on empty space cancels selection
	if not input.HitPosition then
		if actionType == FormexDesign.ActionType.Select and designMode ~= FormexDesign.DesignMode.Select then
			FormexDesign.ClearSelection()
		end
		return
	end

	if designMode == FormexDesign.DesignMode.Select then
		FormexDesign.Select(input)
		return
	end

	if designMode == FormexDesign.DesignMode.Dropper then
		handleDropperDesignModeClick(input)
		return
	end

	if isPaintableDesignMode(designMode) and designSubMode == FormexDesign.DesignSubMode.Paint then
		handlePaintDropperClick(input)
		return
	end

	if designMode == FormexDesign.DesignMode.Wall then
		if Walls then
			Walls.HandlePrimaryClick(input)
		end
	elseif designMode == FormexDesign.DesignMode.Floor then
		if Floors then
			Floors.HandlePrimaryClick(input)
		end
	elseif designMode == FormexDesign.DesignMode.Room then
		if actionType == FormexDesign.ActionType.Start or actionType == FormexDesign.ActionType.Step then
			if Floors then
				Floors.HandlePrimaryClick(input)
			end
		elseif actionType == FormexDesign.ActionType.Select then
			local selectedRoom = Rooms and Rooms.HandlePrimaryClick(input)
			if not selectedRoom and input.LayoutTile and Floors then
				Floors.StartFloor()
			end
		end
	elseif designMode == FormexDesign.DesignMode.Object then
		if Objects then
			Objects.HandlePrimaryClick(input)
		end
	elseif actionType == FormexDesign.ActionType.Select then
		FormexDesign.ClearSelection()
	end
end

function FormexDesign.SetDesignMode(mode: DesignMode?, preserveSelection: boolean?)
	mode = mode or FormexDesign.DesignMode.Play
	if mode == FormexDesign.DesignMode.Design then
		mode = FormexDesign.DesignMode.Select
	end
	if designMode == mode then return end
	local previousMode = designMode
	local nextViewSettings = designModeViewSettings[mode]
	if viewSettings.CameraMode == DesignCamera.CameraMode.TopDown
		and nextViewSettings
		and nextViewSettings.CameraMode ~= DesignCamera.CameraMode.TopDown then
		saveTopDownState(FormexClient.CurrentPlot)
	end

	if actionType ~= FormexDesign.ActionType.Select then
		FormexDesign.CancelAction()
	end

	local wasInSession = designSessionActive
	designSessionActive = mode ~= FormexDesign.DesignMode.Play
	if designSessionActive and not wasInSession then
		currentLevel = getLevel()
		designSessionPendingFocus = true
	elseif not designSessionActive and wasInSession then
		designSessionPendingFocus = false
	end

	designMode = mode
	if previousMode == FormexDesign.DesignMode.Room
		and mode ~= FormexDesign.DesignMode.Room
		and FormexDesignHighlights.ClearRoomOverlays then
		FormexDesignHighlights.ClearRoomOverlays()
	end
	if not isPaintableDesignMode(mode) then
		designSubMode = FormexDesign.DesignSubMode.Normal
		if mode ~= FormexDesign.DesignMode.Dropper or not altDropperForced then
			altDropperForced = false
			altDropperUsed = false
			lastSubModeBeforeAlt = nil
			lastDesignModeBeforeAlt = nil
		end
	end
	if designMode ~= FormexDesign.DesignMode.Floor and designMode ~= FormexDesign.DesignMode.Room then
		designTipMessage = nil
	end
	viewSettings = designModeViewSettings[mode]
	actionType = FormexDesign.ActionType.Select
	refresh(preserveSelection)
	notifyDesignModeChange()
end

local function resetDesignForPlotChange()
	beginDesignStateBatch()
	clearGhost()
	FormexDesign.CancelAction()
	if designMode ~= FormexDesign.DesignMode.Play then
		FormexDesign.SetDesignMode(FormexDesign.DesignMode.Play)
	else
		designSubMode = FormexDesign.DesignSubMode.Normal
		altDropperForced = false
		altDropperUsed = false
		lastSubModeBeforeAlt = nil
		lastDesignModeBeforeAlt = nil
		designTipMessage = nil
		designSessionActive = false
		designSessionPendingFocus = false
		refresh()
	end
	endDesignStateBatch()
	DesignCamera.SetCameraMode(DesignCamera.CameraMode.Play)
end

FormexDesignContext.Init({
	FormexClient = FormexClient,
	DesignCamera = DesignCamera,
	Formex = Formex,
	OverlayFolder = overlayFolder,
	Handles = FormexDesign.Handles,
	Highlight = FormexDesignHighlights,
	Enums = Enums,
	Constants = Constants,
	Modules = {},
	GetActionType = function()
		return actionType
	end,
	SetActionType = function(value: ActionType)
		actionType = value
	end,
	SetActionHeld = function(value: boolean)
		actionHeld = value
	end,
	GetDesignMode = function()
		return designMode
	end,
	GetEditMode = function()
		return editMode
	end,
	GetCurrentLevel = function()
		return currentLevel
	end,
	SetCurrentLevel = function(value: number)
		currentLevel = value
	end,
	GetViewSettings = function()
		return viewSettings
	end,
	GetSelectionType = function()
		return selectionType
	end,
	GetSelectionPart = function()
		return selectionPart
	end,
	GetSelectionData = function()
		return selectionData
	end,
	SetRoomSelection = function(roomData: Formex.RoomData?)
		setRoomSelection(roomData)
	end,
	GetSelectionSnapshot = getSelectionSnapshot,
	GetLastInputInfo = function()
		return inputInfo
	end,
	GetPlotModelFromPlotData = getPlotModelFromPlotData,
	SelectPlotModelByIdAsync = selectPlotModelByIdAsync,
	GetSnappedPoint = getSnappedPoint,
	SnapWallEndPoint = snapWallEndPoint,
	ToSnappedVector2int16 = toSnappedVector2int16,
	GetLocalXZ = getLocalXZ,
	BuildFloor = buildFloorForMode,
	SelectAfterFloorBuild = selectAfterFloorBuild,
	IsPointInOwnedSegments = isPointInOwnedSegments,
	BuildWallData = buildWallData,
	UpdateGhostValidity = updateGhostValidity,
	EnsureWallGhost = ensureWallGhost,
	EnsureFloorGhost = ensureFloorGhost,
	ClearGhost = clearGhost,
	IsGhostActive = function()
		return ghostActive
	end,
	IsGhostValid = function()
		return ghostIsValid
	end,
	GetGhostType = function()
		return ghostType
	end,
	GetGhostInstance = function()
		return ghost
	end,
	GetGhostFloorData = function()
		return ghostFloorData
	end,
	GetFloorMode = function()
		return floorMode
	end,
	GetFloorMaterialId = function()
		return floorMaterialId
	end,
	GetCeilingMaterialId = function()
		return ceilingMaterialId
	end,
	GetFloorRaiseHeight = function()
		return floorRaiseHeight
	end,
	GetFloorColor = function()
		return floorColor
	end,
	GetCeilingColor = function()
		return ceilingColor
	end,
	GetFoundationMaterialId = function()
		return foundationMaterialId
	end,
	GetFoundationColor = function()
		return foundationColor
	end,
	GetWallPaintSettings = function()
		return cloneWallPaintSettings(wallPaintSettings)
	end,
	GetObjectPaintSettings = function()
		return {
			Design = table.clone(objectPaintSettings.Design),
			DesignColors = table.clone(objectPaintSettings.DesignColors),
		} :: ObjectPaintSettings
	end,
	GetObjectPrefabName = function()
		return objectPrefabName
	end,
	GetObjectSelectedSettings = function()
		return {
			PrefabName = objectSelectedSettings.PrefabName,
			Design = table.clone(objectSelectedSettings.Design),
			DesignColors = table.clone(objectSelectedSettings.DesignColors),
			HasSelection = objectSelectedSettings.HasSelection,
		} :: ObjectSelectedSettings
	end,
	UpdateDesignState = FormexDesign.UpdateDesignState,
	NotifyDesignModeChange = notifyDesignModeChange,
	GetTipMessage = function()
		return designTipMessage
	end,
	SetTipMessage = FormexDesign.SetTipMessage,
	ClearSelection = FormexDesign.ClearSelection,
	Select = FormexDesign.Select,
	DeleteAfterDelay = deleteAfterDelay,
	CancelAction = FormexDesign.CancelAction,
	HandlePrimaryRelease = handlePrimaryRelease,
})

FormexDesign.Handles.Init()
FormexDesignHighlights.Init()

Walls = require(script:WaitForChild("Walls"))
Floors = require(script:WaitForChild("Floors"))
Objects = require(script:WaitForChild("Objects"))
Rooms = require(script:WaitForChild("Rooms"))

Walls.Init()
Floors.Init()
Objects.Init()
Rooms.Init()

FormexDesignContext.RegisterModule("Walls", Walls)
FormexDesignContext.RegisterModule("Floors", Floors)
FormexDesignContext.RegisterModule("Objects", Objects)
FormexDesignContext.RegisterModule("Rooms", Rooms)
FormexDesignContext.RegisterModule("Handles", FormexDesign.Handles)
FormexDesignContext.RegisterModule("Highlights", FormexDesignHighlights)

local function syncUndoRedoAttributes()
	local nextCanUndo = localPlayer:GetAttribute("CanUndo") == true
	local nextCanRedo = localPlayer:GetAttribute("CanRedo") == true
	if nextCanUndo ~= canUndo or nextCanRedo ~= canRedo then
		canUndo = nextCanUndo
		canRedo = nextCanRedo
		notifyDesignStateChange()
	end
end

syncUndoRedoAttributes()
localPlayer:GetAttributeChangedSignal("CanUndo"):Connect(syncUndoRedoAttributes)
localPlayer:GetAttributeChangedSignal("CanRedo"):Connect(syncUndoRedoAttributes)

local function selectionMatchesPlotChange(partType: any, levelIndex: number?, partId: number?): boolean
	if selectionType == FormexDesign.SelectionType.None or not selectionData then return false end
	if not partType or not levelIndex or partId == nil then return false end

	if partType == Formex.PartType.Wall and selectionType == FormexDesign.SelectionType.Wall then
		local data = selectionData :: Formex.WallData
		return data.Level == levelIndex and data.WallId == partId
	end
	if partType == Formex.PartType.Floor and selectionType == FormexDesign.SelectionType.Floor then
		local data = selectionData :: Formex.FloorData
		return data.LevelIndex == levelIndex and data.FloorId == partId
	end
	if partType == Formex.PartType.Object and selectionType == FormexDesign.SelectionType.Object then
		local data = selectionData :: Formex.ObjectData
		local objectId = tonumber(data.ObjectId)
		return data.Level == levelIndex and objectId ~= nil and objectId == partId
	end

	return false
end

FormexClient.ClientEvents:Connect(function(eventName, plotId, _partType, _levelIndex, _partId, _model, changeType)
	if eventName == "CurrentPlotChanged" then
		local currentPlotId = FormexClient.CurrentPlotId
		if plotId ~= lastPlotId or currentPlotId ~= lastPlotId then
			lastPlotId = currentPlotId
			resetDesignForPlotChange()
		end
		return
	end

	if eventName == "PlotPartChanged" and selectionType == FormexDesign.SelectionType.Room then
		local room = selectionData
		local plotInfo = FormexClient.CurrentPlot
		if room and plotInfo and plotInfo.IsValid and room.Points and #room.Points >= 3 then
			local sample = Formex.Poly.GetFaceSamplePoint(room.Points, Formex.EPSILON)
			if sample then
				selectRoomAtPoint(plotInfo, room.LevelIndex, sample)
				return
			end
		end
		FormexDesign.ClearSelection()
		return
	end

	if eventName ~= "PlotPartChanged" then return end
	if not selectionMatchesPlotChange(_partType, _levelIndex, _partId) then return end

	if changeType == "Removed" then
		FormexDesign.ClearSelection()
		return
	end

	selectionPart = selectionData and getSelectionPartForKind(selectionType, selectionData) or nil
	updateSelectionSettingsFromSelection()
	local plotInfo = FormexClient.CurrentPlot
	updateSelectionHandles(plotInfo)
	FormexDesignHighlights.UpdateSelectionHighlight()
	notifyDesignModeChange()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1
	or input.UserInputType == Enum.UserInputType.Touch then
		actionHeld = true
		handlePrimaryClick()
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		if (designMode == FormexDesign.DesignMode.Floor or designMode == FormexDesign.DesignMode.Room) and Floors then
			local info = getInputInfo(true)
			if info and Floors.HandleSecondaryClick(info) then return end
		end
		FormexDesign.CancelAction()
		return
	end

	if input.UserInputType == Enum.UserInputType.Keyboard then
		if input.KeyCode == Enum.KeyCode.LeftAlt then
			alt1Held = true
			altHeld = true
			updateAltDropperState(altHeld)
		elseif input.KeyCode == Enum.KeyCode.RightAlt then
			alt2Held = true
			altHeld = true
			updateAltDropperState(altHeld)
		elseif input.KeyCode == Enum.KeyCode.Escape then
			FormexDesign.CancelAction()
		end
		return
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
	or input.UserInputType == Enum.UserInputType.Touch then
		actionHeld = false
		handlePrimaryRelease()
		return
	end

	if input.UserInputType == Enum.UserInputType.Keyboard then
		if input.KeyCode == Enum.KeyCode.LeftAlt then
			alt1Held = false
			altHeld = alt1Held or alt2Held or alt3Held
			updateAltDropperState(altHeld)
		elseif input.KeyCode == Enum.KeyCode.RightAlt then
			alt2Held = false
			altHeld = alt1Held or alt2Held or alt3Held
			updateAltDropperState(altHeld)
		end
		return
	end
end)

RunService.RenderStepped:Connect(function()
	if designMode == FormexDesign.DesignMode.Play then return end
	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid or not plotInfo.PlotPart then return end
	handleUpdate()
end)

return FormexDesign
