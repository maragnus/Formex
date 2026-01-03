--!strict
local Context = require(script.Parent:WaitForChild("FormexDesignContext"))

local Floors = {}

local FormexClient: any
local Formex: any
local Enums: any

local getActionType: () -> string
local setActionType: (string) -> ()
local getDesignMode: () -> string
local getFloorMaterialId: () -> number
local updateGhostValidity: (boolean) -> ()
local ensureFloorGhost: (BasePart, number, Vector2int16, any) -> ()
local clearGhost: () -> ()
local isGhostValid: () -> boolean
local getGhostFloorData: () -> any?
local notifyDesignModeChange: () -> ()
local deleteAfterDelay: (Instance, number) -> ()
local cancelAction: () -> ()

local lastFloorPaintTile: Vector2int16? = nil
local lastFloorPaintMaterial: number? = nil

function Floors.Init()
	local ctx = Context.Get()
	FormexClient = ctx.FormexClient
	Formex = ctx.Formex
	Enums = ctx.Enums

	getActionType = ctx.GetActionType
	setActionType = ctx.SetActionType
	getDesignMode = ctx.GetDesignMode
	getFloorMaterialId = ctx.GetFloorMaterialId
	updateGhostValidity = ctx.UpdateGhostValidity
	ensureFloorGhost = ctx.EnsureFloorGhost
	clearGhost = ctx.ClearGhost
	isGhostValid = ctx.IsGhostValid
	getGhostFloorData = ctx.GetGhostFloorData
	notifyDesignModeChange = ctx.NotifyDesignModeChange
	deleteAfterDelay = ctx.DeleteAfterDelay
	cancelAction = ctx.CancelAction
end

local function setFloorTile(plotInfo: any, levelIndex: number, tile: Vector2int16, altSide: boolean, materialId: number?)
	if not plotInfo.PlotPart then return end

	local floorData = Formex.GetFloorData(plotInfo.PlotPart, levelIndex, tile)
	if not altSide then
		if floorData.FloorMaterial == materialId then return end
		floorData.FloorMaterial = materialId
	else
		if floorData.FloorMaterial2 == materialId then return end
		floorData.FloorMaterial2 = materialId
	end

	if materialId then
		local isGhost = not floorData.Part
		floorData.Part = Formex.UpdateFloor(plotInfo.PlotPart, floorData, floorData.Part)
		FormexClient.BuildFloor(levelIndex, tile.X, tile.Y, floorData.FloorMaterial, floorData.FloorMaterial2)

		if isGhost then
			deleteAfterDelay(floorData.Part, 1)
		end
	else
		if floorData.Part then
			floorData.Part:Destroy()
			FormexClient.BuildFloor(levelIndex, tile.X, tile.Y, nil)
		end
	end
end

local function updateFloorGhost(input: any)
	if not input.LayoutTile or not input.PlotInfo.PlotPart then
		clearGhost()
		return
	end

	local partType = if getDesignMode() == Enums.DesignMode.Ceiling then Formex.PartType.Ceiling else Formex.PartType.Floor
	ensureFloorGhost(input.PlotInfo.PlotPart, input.LevelIndex, input.LayoutTile, partType)

	local floorData = getGhostFloorData()
	local valid = floorData and Formex.IsFloorValid(input.PlotInfo :: any, floorData :: any) or false
	updateGhostValidity(valid)
end

local function handleFloorUpdate(input: any)
	updateFloorGhost(input)

	if not input.ActionHeld or not input.LayoutTile then return end
	if not isGhostValid() then return end

	local materialId = input.AltHeld and nil or getFloorMaterialId()
	if lastFloorPaintTile
	and lastFloorPaintMaterial == materialId
	and input.LayoutTile == lastFloorPaintTile then
		return
	end

	lastFloorPaintTile = input.LayoutTile
	lastFloorPaintMaterial = materialId
	setFloorTile(input.PlotInfo, input.LevelIndex, input.LayoutTile, input.AltHeld, materialId)
end

function Floors.StartFloor()
	cancelAction()

	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid or not plotInfo.PlotPart then
		return
	end

	setActionType(Enums.ActionType.Step)
	lastFloorPaintTile = nil
	lastFloorPaintMaterial = nil
	notifyDesignModeChange()
end

function Floors.CancelAction()
	lastFloorPaintTile = nil
	lastFloorPaintMaterial = nil
end

function Floors.HandleUpdate(input: any)
	handleFloorUpdate(input)
end

function Floors.HandlePrimaryRelease(_input: any)
	lastFloorPaintTile = nil
	lastFloorPaintMaterial = nil
end

function Floors.HandlePrimaryClick(input: any)
	local actionType = getActionType()
	if actionType == Enums.ActionType.Select then
		Floors.StartFloor()
		return
	end

	if actionType == Enums.ActionType.Step then
		handleFloorUpdate(input)
	end
end

return Floors
