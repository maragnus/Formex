--!strict

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GridTexture: Texture = ReplicatedStorage:WaitForChild("GridTexture")
local FormexClient = require(script.Parent:WaitForChild("FormexClient"))
local FormexCamera = require(script.Parent:WaitForChild("FormexCamera"))
local Formex = FormexClient.Formex

local localPlayer = Players.LocalPlayer
local PlayerGui: ScreenGui = localPlayer:WaitForChild("PlayerGui")

local formexWorkspace = Workspace:WaitForChild("Formex")
local overlayFolder = Instance.new("Folder", formexWorkspace)
overlayFolder.Name = "FormexDesignOverlays"

local FormexDesign = {}

export type WallMode = "Full" | "Half" | "Hidden"
FormexDesign.WallModes = {
	Full = "Full",
	Half = "Half",
	Hidden = "Hidden"
}

type ViewSettings = {
	CameraMode: FormexCamera.CameraMode,
	WallMode: WallMode,
	ShowSegments: boolean,
	ShowGrid: boolean,
	ShowOtherLevels: boolean,
}

export type DesignMode = "Play" | "Expand" | "Floor" | "Ceiling" | "Wall" | "Furniture" | "Paint"
FormexDesign.DesignModes = {
	Play = "Play",
	Expand = "Expand",
	Floor = "Floor",
	Ceiling = "Ceiling",
	Wall = "Wall",
	Furniture = "Furniture",
	Paint = "Paint"
} :: {DesignMode: DesignMode}

export type ActionType = "Select" | "Start" | "Step" | "Rotate" | "Move"
FormexDesign.ActionTypes = {
	Select = "Select",
	Start = "Start",
	Step = "Step",
	Move = "Move",
	Rotate = "Rotate"
} :: {ActionType: ActionType}

export type SelectionType = "None" | "Wall" | "Floor" | "Object"
FormexDesign.SelectionTypes = {
	None = "None",
	Wall = "Wall",
	Floor = "Floor",
	Object = "Object"
} :: {ActionType: ActionType}

local playViewSettings: ViewSettings = {
	CameraMode = FormexCamera.CameraModes.Play,
	WallMode = FormexDesign.WallModes.Full,
	ShowSegments = false,
	ShowGrid = false,
	ShowOtherLevels = true
}

local currentMode: DesignMode = FormexDesign.DesignModes.Play
local currentLevel: number = 1
local actionType: ActionType = FormexDesign.ActionTypes.Select
local viewSettings: ViewSettings = playViewSettings
local ghost: BasePart? = nil
local selectionType: SelectionType = FormexDesign.SelectionTypes.None
local selectionData: nil | Formex.WallData | Formex.FloorData | Formex.ObjectData

local designModeViewSettings: {DesignMode: ViewSettings} = {
	Play = playViewSettings,
	Expand = {
		CameraMode = FormexCamera.CameraModes.TopDown,
		WallMode = FormexDesign.WallModes.Half,
		ShowSegments = true,
		ShowGrid = false,
		ShowOtherLevels = false
	},
	Wall = {
		CameraMode = FormexCamera.CameraModes.TopDown,
		WallMode = FormexDesign.WallModes.Full,
		ShowSegments = false,
		ShowGrid = true,
		ShowOtherLevels = false
	},
	Floor = {
		CameraMode = FormexCamera.CameraModes.TopDown,
		WallMode = FormexDesign.WallModes.Half,
		ShowSegments = false,
		ShowGrid = true,
		ShowOtherLevels = false
	},
	Ceiling = {
		CameraMode = FormexCamera.CameraModes.BottomUp,
		WallMode = FormexDesign.WallModes.Full,
		ShowSegments = false,
		ShowGrid = true,
		ShowOtherLevels = false
	},
	Furniture = {
		CameraMode = FormexCamera.CameraModes.Play,
		WallMode = FormexDesign.WallModes.Full,
		ShowSegments = false,
		ShowGrid = true,
		ShowOtherLevels = false
	},
	Paint = {
		CameraMode = FormexCamera.CameraModes.Play,
		WallMode = FormexDesign.WallModes.Full,
		ShowSegments = false,
		ShowGrid = false,
		ShowOtherLevels = false
	}
}

local function clearOverlays()
	-- clears segment, expands, ghosts
	overlayFolder:ClearAllChildren()
end

local function createExpandButton(parent: BasePart, segmentIndex: number)
	local clickDetector = Instance.new("ClickDetector", parent)
	local isBusy = false
	clickDetector.MaxActivationDistance = 1024
	clickDetector.MouseHoverEnter:Connect(function() print("enter") end)
	clickDetector.MouseHoverLeave:Connect(function() print("leave") end)
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
	button.Image = "rbxassetid://88488799504419"
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
	part.Material = Enum.Material.ForceField
	part.Size = Vector3.new(bounds.Size.X - Formex.GridSize, 0.25, bounds.Size.Z - Formex.GridSize)

	local surfaceHeight = ((plotInfo.PlotPart and plotInfo.PlotPart.Size.Y) or 1) / 2 + 0.05
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
	if not plotInfo or not plotInfo.IsValid or not plotInfo.PlotPart then
		return
	end

	for index = 1, Formex.Segments.Count do
		local bounds = Formex.GetSegmentBounds(plotInfo.PlotPart, index, plotInfo.LevelsUnlocked)
		local unlocked = Formex.Segments.IsUnlocked(plotInfo.SegmentsUnlocked, index)
		createSegmentOverlay(bounds, plotInfo, unlocked)
	end
end

local function createGridOverlay(bounds: Formex.SegmentBounds, plotInfo: FormexClient.PlotInfo)
	local part = Instance.new("Part", overlayFolder)
	part.Name = "Grid_" .. tostring(bounds.Index)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.CastShadow = false
	part.Material = Enum.Material.Air
	part.Size = Vector3.new(bounds.Size.X, 0.1, bounds.Size.Z)
	part.Transparency = 1
	local surfaceHeight = ((plotInfo.PlotPart and plotInfo.PlotPart.Size.Y) or 1) / 2 + 0.05
	part.CFrame = bounds.CFrame * CFrame.new(0, surfaceHeight, 0)
	GridTexture:Clone().Parent = part
end

local function renderGridOverlays(plotInfo: FormexClient.PlotInfo)
	if not plotInfo or not plotInfo.IsValid or not plotInfo.PlotPart then
		return
	end

	for _, index in ipairs(Formex.Segments.GetAllUnlocked(plotInfo.SegmentsUnlocked)) do
		local bounds = Formex.GetSegmentBounds(plotInfo.PlotPart, index, plotInfo.LevelsUnlocked)
		createGridOverlay(bounds, plotInfo)
	end
end

local function refresh()
	clearOverlays()

	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid then return	end

	FormexCamera.SetCameraMode(viewSettings.CameraMode)

	-- Determine how to display half walls client-side

	for i = 1, Formex.MaxPlotSize.Levels, 1 do
		local level = plotInfo.PlotPart:FindFirstChild(tostring(i), false)
		if not level then continue end
		local transparency = (viewSettings.ShowOtherLevels or level == currentLevel) and 0 or 1
		for _, part in level:GetChildren() do
			part.Transparency = transparency
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

function FormexDesign.Select(part: Instance)
	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid then return	1 end
	local plotPart = plotInfo.PlotPart

	-- TODO determine the level, type, and id from the heirarchy
	--[[ 
	 	PlotPlaceholder/1/Floors/5/...
		PlotPlaceholder/{Level}/{ObjectType}/{Id}
		ObjectType is "Walls" | "Floors" | "Objects"
		Trace backwards until `plotPart` then capture Level (currentLevel), ObjectType (selectionType), and Id (selectedId)
		If Workspace is found instead, the selection is invalid
	]]--
	selectionType = FormexDesign.SelectionTypes.None
	selectionData = nil -- TODO
	currentLevel = currentLevel
end

function FormexDesign.StartWall()
	-- TODO start the action
end

function FormexDesign.StartFloor()
	-- TODO start the action
end

function FormexDesign.CancelAction()
	if actionType == FormexDesign.ActionTypes.Select then return end

	-- TODO gracefully cancel the action
end

function FormexDesign.SetDesignMode(mode: DesignMode?)
	mode = mode or FormexDesign.DesignModes.Play
	local lastMode = currentMode
	if currentMode == mode then return end

	if actionType ~= FormexDesign.ActionTypes.Select then
		FormexDesign.CancelAction()
	end

	if mode ~= FormexDesign.DesignModes.Play
	and lastMode == FormexDesign.DesignModes.Play then
		currentLevel = getLevel()
	end

	currentMode = mode
	viewSettings = designModeViewSettings[mode]
	actionType = FormexDesign.ActionTypes.Select
	refresh()
end

FormexClient.ClientEvents:Connect(function(eventName)
	if eventName == "CurrentPlotChanged" then
		refresh()
	end
end)

return FormexDesign
