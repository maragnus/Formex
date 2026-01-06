--!strict
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local FormexClient = require(script.Parent:WaitForChild("FormexClient"))
local FormexCamera = require(script.Parent:WaitForChild("FormexCamera"))
local FormexDesignContext = require(script.Parent:WaitForChild("FormexDesignContext"))
local Formex = FormexClient.Formex
local localPlayer = Players.LocalPlayer

local formexWorkspace = Workspace:WaitForChild("Formex")
local overlayFolder = Formex.Util.EnsureFolder("FormexDesignOverlays", formexWorkspace)

local EPSILON = 1e-4

local HANDLE_OFFSET = 5

local FormexDesign = {}

FormexDesign.Handles = require(script.Parent:WaitForChild("FormexDesignHandles"))

local Walls, Floors, Objects

export type WallMode = "Full" | "Half" | "Hidden"
FormexDesign.WallMode = table.freeze({
	Full = "Full",
	Half = "Half",
	Hidden = "Hidden"
}) :: {WallMode: WallMode}

export type HandleLocation = "Top" | "Middle" | "Bottom"
FormexDesign.HandleLocation = table.freeze({
	Top = "Top",
	Middle = "Middle",
	Bottom = "Bottom"
}) :: {HandleLocation: HandleLocation}

type ViewSettings = {
	HandleLocation: HandleLocation,
	CameraMode: FormexCamera.CameraMode,
	WallMode: WallMode,
	ShowSegments: boolean,
	ShowGrid: boolean,
	ShowOtherLevels: boolean,
}

export type DesignMode = "Play" | "Design" | "Expand" | "Floor" | "Ceiling" | "Wall" | "Object" | "Paint"
FormexDesign.DesignMode = table.freeze({
	Play = "Play",
	Design = "Design",
	Expand = "Expand",
	Floor = "Floor",
	Ceiling = "Ceiling",
	Wall = "Wall",
	Object = "Object",
	Paint = "Paint"
}) :: {DesignMode: DesignMode}

export type ActionType = "Select" | "Start" | "Step" | "Rotate" | "Move"
FormexDesign.ActionType = {
	Select = "Select",
	Start = "Start",
	Step = "Step",
	Move = "Move",
	Rotate = "Rotate"
} :: {ActionType: ActionType}

export type SelectionData = nil | Formex.WallData | Formex.FloorData | Formex.ObjectData

export type SelectionType = "None" | "Wall" | "Floor" | "Object"
FormexDesign.SelectionType = {
	None = "None",
	Wall = "Wall",
	Floor = "Floor",
	Object = "Object"
} :: {SelectionType: SelectionType}

local playViewSettings: ViewSettings = {
	HandleLocation = FormexDesign.HandleLocation.Middle,
	CameraMode = FormexCamera.CameraMode.Play,
	WallMode = FormexDesign.WallMode.Full,
	ShowSegments = false,
	ShowGrid = false,
	ShowOtherLevels = true
} :: ViewSettings

type InputInfo = {
	PlotInfo: FormexClient.PlotInfo,
	Ray: Ray?,
	HitPosition: Vector3?,
	SnapPoint: Vector2int16?,
	LayoutTile: Vector2int16?,
	LevelIndex: number,
	Target: Instance?,
	ActionHeld: boolean,
	AltHeld: boolean,
}

local inputInfo: InputInfo? = nil
local designMode: DesignMode = FormexDesign.DesignMode.Play
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
local actionHeld = false
local altHeld, alt1Held, alt2Held, alt3Held = false, false, false, false
local selectionType: SelectionType = FormexDesign.SelectionType.None
local selectionData: SelectionData = nil
local selectionPart: Instance? = nil
local selectionHighlight: Highlight? = nil

local selectionColor = Color3.fromRGB(255, 201, 107)
local ghostValidColor = Color3.fromRGB(84, 140, 255)
local ghostInvalidColor = Color3.fromRGB(245, 110, 110)

local function notifyDesignModeChange()
	FormexClient.FireEvent("DesignModeChanged")
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
end

function FormexDesign.GetDesignMode(): DesignMode
	return designMode
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

function FormexDesign.SetFloorMaterial(materialId: number)
	floorMaterialId = materialId
	if ghostActive
	and (ghostType == Formex.PartType.Floor or ghostType == Formex.PartType.Ceiling)
	and ghostFloorData then
		ghostFloorData.FloorMaterial = materialId
	end
	notifyDesignModeChange()
end

function FormexDesign.GetCeilingMaterial(): number
	return ceilingMaterialId
end

function FormexDesign.SetCeilingMaterial(materialId: number)
	ceilingMaterialId = materialId
	if ghostActive
	and (ghostType == Formex.PartType.Floor or ghostType == Formex.PartType.Ceiling)
	and ghostFloorData then
		ghostFloorData.CeilingMaterial = materialId
	end
	notifyDesignModeChange()
end

function FormexDesign.GetFloorColor(): Color3
	return floorColor
end

function FormexDesign.SetFloorColor(color: Color3)
	floorColor = color
	if ghostActive
	and (ghostType == Formex.PartType.Floor or ghostType == Formex.PartType.Ceiling)
	and ghostFloorData then
		ghostFloorData.FloorColor = color
	end
	notifyDesignModeChange()
end

function FormexDesign.GetCeilingColor(): Color3
	return ceilingColor
end

function FormexDesign.SetCeilingColor(color: Color3)
	ceilingColor = color
	if ghostActive
	and (ghostType == Formex.PartType.Floor or ghostType == Formex.PartType.Ceiling)
	and ghostFloorData then
		ghostFloorData.CeilingColor = color
	end
	notifyDesignModeChange()
end

function FormexDesign.GetFoundationMaterial(): number
	return foundationMaterialId
end

function FormexDesign.SetFoundationMaterial(materialId: number)
	foundationMaterialId = materialId
	if ghostActive
	and (ghostType == Formex.PartType.Floor or ghostType == Formex.PartType.Ceiling)
	and ghostFloorData then
		ghostFloorData.FoundationMaterial = materialId
	end
	notifyDesignModeChange()
end

function FormexDesign.GetFoundationColor(): Color3
	return foundationColor
end

function FormexDesign.SetFoundationColor(color: Color3)
	foundationColor = color
	if ghostActive
	and (ghostType == Formex.PartType.Floor or ghostType == Formex.PartType.Ceiling)
	and ghostFloorData then
		ghostFloorData.FoundationColor = color
	end
	notifyDesignModeChange()
end

function FormexDesign.CanUndo(): boolean
	return FormexClient.CanUndo()
end

function FormexDesign.CanRedo(): boolean
	return FormexClient.CanRedo()
end

function FormexDesign.Undo(): boolean
	FormexDesign.CancelAction()
	local ok = FormexClient.Undo()
	if ok ~= true then
		return false
	end
	FormexDesign.ClearSelection()
	return true
end

function FormexDesign.Redo(): boolean
	FormexDesign.CancelAction()
	local ok = FormexClient.Redo()
	if ok ~= true then
		return false
	end
	FormexDesign.ClearSelection()
	return true
end

local function getPlayerFocusPosition(): Vector3?
	local character = localPlayer.Character
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Head")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

function FormexDesign.MoveCameraToPlayer()
	if viewSettings.CameraMode ~= FormexCamera.CameraMode.TopDown then
		return
	end

	local focusPosition = getPlayerFocusPosition()
	if focusPosition then
		FormexCamera.Focus(focusPosition)
	end
end

local designModeViewSettings: {DesignMode: ViewSettings} = {
	Play = playViewSettings,
	Design = playViewSettings,
	Expand = {
		HandleLocation = FormexDesign.HandleLocation.Bottom,
		CameraMode = FormexCamera.CameraMode.TopDown,
		WallMode = FormexDesign.WallMode.Half,
		ShowSegments = true,
		ShowGrid = false,
		ShowOtherLevels = false
	},
	Wall = {
		HandleLocation = FormexDesign.HandleLocation.Bottom,
		CameraMode = FormexCamera.CameraMode.TopDown,
		WallMode = FormexDesign.WallMode.Full,
		ShowSegments = false,
		ShowGrid = true,
		ShowOtherLevels = false
	},
	Floor = {
		HandleLocation = FormexDesign.HandleLocation.Bottom,
		CameraMode = FormexCamera.CameraMode.TopDown,
		WallMode = FormexDesign.WallMode.Half,
		ShowSegments = false,
		ShowGrid = true,
		ShowOtherLevels = false
	},
	Ceiling = {
		HandleLocation = FormexDesign.HandleLocation.Middle,
		CameraMode = FormexCamera.CameraMode.BottomUp,
		WallMode = FormexDesign.WallMode.Full,
		ShowSegments = false,
		ShowGrid = true,
		ShowOtherLevels = false
	},
	Object = {
		HandleLocation = FormexDesign.HandleLocation.Middle,
		CameraMode = FormexCamera.CameraMode.Play,
		WallMode = FormexDesign.WallMode.Full,
		ShowSegments = false,
		ShowGrid = true,
		ShowOtherLevels = false
	},
	Paint = {
		HandleLocation = FormexDesign.HandleLocation.Middle,
		CameraMode = FormexCamera.CameraMode.Play,
		WallMode = FormexDesign.WallMode.Full,
		ShowSegments = false,
		ShowGrid = false,
		ShowOtherLevels = false
	}
}

local function clearOverlays()
	-- clears segment, expands, ghosts
	for _, child in overlayFolder:GetChildren() do
		if child ~= ghost and child ~= selectionHighlight then
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
	part.Material = Enum.Material.ForceField
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
	if not plotInfo or not plotInfo.IsValid or not plotInfo.PlotPart then
		return
	end

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
	if not plotInfo or not plotInfo.IsValid or not plotInfo.PlotPart then
		return
	end

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
	if not camera then
		return nil
	end

	local viewport = camera.ViewportSize
	if viewport.Y <= 0 then
		return nil
	end

	local aspect = viewport.X / viewport.Y
	if aspect <= 0 then
		return nil
	end

	local halfWidth = Formex.Dimensions.Width / 2
	local halfDepth = Formex.Dimensions.Depth / 2
	local halfFov = math.rad(camera.FieldOfView) * 0.5
	local tanHalfFov = math.tan(halfFov)
	if tanHalfFov <= 0 then
		return nil
	end

	local distanceForDepth = halfDepth / tanHalfFov
	local distanceForWidth = halfWidth / (tanHalfFov * aspect)
	return math.max(distanceForDepth, distanceForWidth)
end

local function refresh()
	clearOverlays()
	FormexDesign.ClearSelection()

	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid then return	end

	local plotPart = plotInfo.PlotPart
	if not plotPart then
		return
	end

	local plotChanged = plotPart ~= lastPlotPart
	if plotChanged then
		lastPlotPart = plotPart
	end

	local boundsMin, boundsMax
	local topDirection
	local isTopDown = viewSettings.CameraMode == FormexCamera.CameraMode.TopDown
	local isExpandMode = designMode == FormexDesign.DesignMode.Expand
	if isTopDown then
		boundsMin, boundsMax = getPlotCameraBounds(plotInfo, isExpandMode)
		topDirection = -plotPart.CFrame.LookVector
	end

	FormexCamera.SetCameraMode(viewSettings.CameraMode, plotPart.Position, boundsMin, boundsMax, topDirection)

	if isTopDown then
		if plotChanged then
			FormexCamera.SetCameraCenter(plotPart.Position)
			designSessionPendingFocus = true
		end

		FormexCamera.SetCameraBounds(boundsMin, boundsMax)
		if isExpandMode then
			FormexCamera.SetZoomLimits(nil, getPlotFitDistance())
		else
			FormexCamera.SetZoomLimits(nil, nil)
		end

		if designSessionPendingFocus then
			FormexDesign.MoveCameraToPlayer()
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

local function ensureSelectionHighlight(): Highlight
	if selectionHighlight and selectionHighlight.Parent then
		return selectionHighlight
	end

	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 0
	highlight.OutlineColor = selectionColor
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = overlayFolder
	selectionHighlight = highlight
	return highlight
end

local function updateHighlightTarget()
	local highlight = ensureSelectionHighlight()

	if ghostActive and ghost then
		highlight.Adornee = ghost
		highlight.OutlineColor = ghostIsValid and ghostValidColor or ghostInvalidColor
		highlight.Enabled = true
		return
	end

	if selectionPart then
		highlight.Adornee = selectionPart
		highlight.OutlineColor = selectionColor
		highlight.Enabled = true
		return
	end

	highlight.Adornee = nil
	highlight.Enabled = false
end

function FormexDesign.ClearSelection()
	selectionType = FormexDesign.SelectionType.None
	selectionData = nil
	selectionPart = nil
	if Walls then
		Walls.ClearSelection()
	end
	if Floors then
		Floors.ClearSelection()
	end
	updateHighlightTarget()
	notifyDesignModeChange()
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
	if length <= 1e-4 then
		return rawEndPoint
	end

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
	if not mask or mask == 0 then
		return false
	end

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

local function getPointerHit(forceGridCollision: boolean?): (Ray?, Vector3?, Instance?)
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil, nil, nil
	end

	local mousePosition = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePosition.X, mousePosition.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true

	if forceGridCollision then
		params.CollisionGroup = Formex.CollisionGroup.Grid
	elseif actionType == FormexDesign.ActionType.Select then
		local filter = { overlayFolder }
		if localPlayer.Character then
			table.insert(filter, localPlayer.Character)
		end
		if ghost then
			table.insert(filter, ghost)
		end
		params.FilterDescendantsInstances = filter
	elseif designMode == FormexDesign.DesignMode.Object then
		params.CollisionGroup = Formex.CollisionGroup.Object
	else
		params.CollisionGroup = Formex.CollisionGroup.Grid
	end


	local result = Workspace:Raycast(ray.Origin, ray.Direction * 2048, params)
	if not result then
		return ray, nil, nil
	end

	return ray, result.Position, result.Instance
end

local function getInputInfo(forceGridCollision: boolean?): InputInfo | nil
	if designMode == FormexDesign.DesignMode.Play then
		return nil
	end

	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid or not plotInfo.PlotPart then
		return nil
	end

	local ray, hitPosition, target = getPointerHit(forceGridCollision)
	local snapPoint = hitPosition and getSnappedPoint(plotInfo.PlotPart, hitPosition) or nil
	local layoutTile = hitPosition and getLayoutTile(plotInfo.PlotPart, hitPosition) or nil

	inputInfo = {
		PlotInfo = plotInfo,
		Ray = ray,
		HitPosition = hitPosition,
		SnapPoint = snapPoint,
		LayoutTile = layoutTile,
		LevelIndex = 1, --getLevel(),
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
	updateHighlightTarget()
end

function Formex.HideGhost(plotPart: BasePart?)
	if not ghost then
		return
	end

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
	updateHighlightTarget()
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
		FrontTopMaterial = Formex.DefaultWallMaterial,
		FrontBottomMaterial = Formex.DefaultWallMaterial,
		BackTopMaterial = Formex.DefaultWallMaterial,
		BackBottomMaterial = Formex.DefaultWallMaterial,
		FrontTopColor = Color3.new(1, 1, 1),
		FrontBottomColor = Color3.new(1, 1, 1),
		BackTopColor = Color3.new(1, 1, 1),
		BackBottomColor = Color3.new(1, 1, 1),
		Part = nil
	}
end

local function buildFloorGhostData(levelIndex: number, tile: Vector2int16): Formex.FloorData
	local tileSize = Formex.LayoutGridSize
	local x0 = tile.X * tileSize - (Formex.Dimensions.Width / 2)
	local z0 = tile.Y * tileSize - (Formex.Dimensions.Depth / 2)
	return {
		FloorId = Formex.XYToIndex(tile.X, tile.Y),
		LevelIndex = levelIndex,
		Points = {
			Vector2int16.new(x0, z0),
			Vector2int16.new(x0 + tileSize, z0),
			Vector2int16.new(x0 + tileSize, z0 + tileSize),
			Vector2int16.new(x0, z0 + tileSize),
		},
		FloorMaterial = floorMaterialId,
		CeilingMaterial = ceilingMaterialId,
		FoundationMaterial = foundationMaterialId,
		FloorColor = floorColor,
		CeilingColor = ceilingColor,
		FoundationColor = foundationColor,
		FloorParts = {},
		CeilingParts = {},
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
	updateHighlightTarget()
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
		ghost = Instance.new("Part")
		ghost.Anchored = true
		ghost.Parent = overlayFolder
		applyGhostAppearance(ghost)
		ghost.Transparency = 1
	end

	if not ghostFloorData then
		ghostFloorData = buildFloorGhostData(levelIndex, tile)
	else
		ghostFloorData.LevelIndex = levelIndex
		ghostFloorData.FloorId = Formex.XYToIndex(tile.X, tile.Y)
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
	local thickness = levelIndex == 1 and Formex.SegmentSize.Foundation or Formex.SegmentSize.Interfloor
	local levelTop = Formex.LevelHeight * (levelIndex - 1)
	local centerY = levelTop - (thickness / 2)

	ghost.Size = Vector3.new(tileSize, thickness, tileSize)
	ghost.CFrame = plotPart.CFrame * CFrame.new(xOffset, centerY, zOffset)
	ghost.Transparency = 1

	ghostActive = true
	updateHighlightTarget()
end



local folderNames = { Walls = "Wall", Floors = "Floor", Objects = "Object" } :: {string: SelectionType}
local allowedSelectionByMode = {
	[FormexDesign.DesignMode.Wall] = FormexDesign.SelectionType.Wall,
	[FormexDesign.DesignMode.Floor] = FormexDesign.SelectionType.Floor,
	[FormexDesign.DesignMode.Ceiling] = FormexDesign.SelectionType.Floor,
	[FormexDesign.DesignMode.Object] = FormexDesign.SelectionType.Object,
} :: { [DesignMode]: SelectionType }

local function getSelectionInfoFromInstance(part: Instance?): (SelectionType?, number?, number?)
	local currentPart = part
	while currentPart do
		local parent = currentPart.Parent

		if not parent or not parent.Parent or parent.Parent:IsA("Workspace") then
			return nil, nil, nil
		end

		local partId = tonumber(currentPart.Name)
		local selectionKind = folderNames[parent.Name]
		local level = tonumber(parent.Parent.Name)

		if partId and level and selectionKind and parent:IsA("Folder") then
			return selectionKind, partId, level
		end

		if parent.Name == "Floors" and parent:IsA("Folder") then
			local floorId = tonumber(currentPart.Name)
			local floorLevel = tonumber(parent.Parent.Name)
			if floorId and floorLevel then
				return FormexDesign.SelectionType.Floor, floorId, floorLevel
			end
		end

		if parent.Parent and parent.Parent:IsA("Folder") and parent.Parent.Name == "Floors" then
			local floorId = tonumber(parent.Name)
			local floorLevel = tonumber(parent.Parent.Parent.Name)
			if floorId and floorLevel then
				return FormexDesign.SelectionType.Floor, floorId, floorLevel
			end
		end

		currentPart = parent
	end

	return nil, nil, nil
end

-- Wall-specific helpers live in FormexDesignWalls.luau

function FormexDesign.GetSelectionInfo(): (SelectionType, number?, number?)
	if not selectionPart then
		return selectionType, nil, nil
	end

	local selectionType, partId, level = getSelectionInfoFromInstance(selectionPart)
	return selectionType, partId, level
end

function FormexDesign.Select(part: Instance)
	if not part or part:IsDescendantOf(overlayFolder) then
		FormexDesign.ClearSelection()
		return false
	end

	-- Extract levelId, selectionType, partId from the path
	-- Workspace/Formex/Plots/PlotPlaceholder/{levelId:number}/{selectionType:SelectionType}/{partId:number}/*
	local selectionKind, partId, level = getSelectionInfoFromInstance(part)
	if selectionKind and partId and level then
		local allowedType = allowedSelectionByMode[designMode]
		if not allowedType or allowedType ~= selectionKind then
			FormexDesign.ClearSelection()
			return false
		end

		local selectionTarget: Instance = part
		if selectionKind == FormexDesign.SelectionType.Wall then
			local currentPart = part
			while currentPart do
				local parent = currentPart.Parent
				if parent and parent:IsA("Folder") and parent.Name == "Walls" then
					if currentPart:IsA("Model") then
						selectionTarget = currentPart
						break
					end
					if currentPart:IsA("BasePart") then
						selectionTarget = currentPart
						break
					end
					break
				end
				currentPart = parent
			end
		end
		if selectionKind == FormexDesign.SelectionType.Floor then
			local floorModel = part:IsA("Model") and part or part:FindFirstAncestorOfClass("Model")
			if floorModel and floorModel.Parent and floorModel.Parent:IsA("Folder") and floorModel.Parent.Name == "Floors" then
				if tostring(partId) == floorModel.Name then
					selectionTarget = floorModel
				end
			end
		end

		selectionType = selectionKind
		selectionData = nil -- TODO
		selectionPart = selectionTarget
		currentLevel = level
		notifyDesignModeChange()
		updateHighlightTarget()
		local plotInfo = FormexClient.CurrentPlot
		if plotInfo and plotInfo.IsValid then
			if Walls then
				Walls.UpdateHandles(plotInfo)
			end
			if Floors then
				Floors.UpdateHandles(plotInfo)
			end
		end
		return true
	end

	FormexDesign.ClearSelection()
	return false
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
	if Objects then
		Objects.CancelAction()
	end

	clearGhost()
	actionType = FormexDesign.ActionType.Select
	local plotInfo = FormexClient.CurrentPlot
	if plotInfo and plotInfo.IsValid then
		if Walls then
			Walls.UpdateHandles(plotInfo)
		end
		if Floors then
			Floors.UpdateHandles(plotInfo)
		end
	end
	notifyDesignModeChange()
end

local function handleUpdate()
	local input = getInputInfo()
	if not input then return end

	if designMode == FormexDesign.DesignMode.Wall then
		if Walls then
			Walls.HandleUpdate(input)
		end
	elseif designMode == FormexDesign.DesignMode.Floor or designMode == FormexDesign.DesignMode.Ceiling then
		if Floors then
			Floors.HandleUpdate(input)
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
	elseif designMode == FormexDesign.DesignMode.Floor or designMode == FormexDesign.DesignMode.Ceiling then
		if Floors then
			Floors.HandlePrimaryRelease(input)
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

	if FormexDesign.Handles.HandleClicked(input.Ray) then
		return
	end

	-- Clicking on empty space cancels selection
	if not input.HitPosition then
		if actionType == FormexDesign.ActionType.Select then
			FormexDesign.ClearSelection()
		end
		return
	end

	if designMode == FormexDesign.DesignMode.Wall then
		if Walls then
			Walls.HandlePrimaryClick(input)
		end
	elseif designMode == FormexDesign.DesignMode.Floor or designMode == FormexDesign.DesignMode.Ceiling then
		if Floors then
			Floors.HandlePrimaryClick(input)
		end
	elseif designMode == FormexDesign.DesignMode.Object then
		if Objects then
			Objects.HandlePrimaryClick(input)
		end
	elseif actionType == FormexDesign.ActionType.Select then
		FormexDesign.ClearSelection()
	end
end

function FormexDesign.SetDesignMode(mode: DesignMode?)
	mode = mode or FormexDesign.DesignMode.Play
	if designMode == mode then return end

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
	viewSettings = designModeViewSettings[mode]
	actionType = FormexDesign.ActionType.Select
	FormexDesign.ClearSelection()
	refresh()
	notifyDesignModeChange()
end

FormexDesignContext.Init({
	FormexClient = FormexClient,
	FormexCamera = FormexCamera,
	Formex = Formex,
	OverlayFolder = overlayFolder,
	Handles = FormexDesign.Handles,
	Enums = {
		DesignMode = FormexDesign.DesignMode,
		ActionType = FormexDesign.ActionType,
		SelectionType = FormexDesign.SelectionType,
		HandleLocation = FormexDesign.HandleLocation,
	},
	Constants = {
		Epsilon = EPSILON,
		HandleOffset = HANDLE_OFFSET,
		SelectionColor = selectionColor,
		GhostValidColor = ghostValidColor,
		GhostInvalidColor = ghostInvalidColor,
	},
	GetActionType = function()
		return actionType
	end,
	SetActionType = function(value: ActionType)
		actionType = value
	end,
	GetDesignMode = function()
		return designMode
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
	GetLastInputInfo = function()
		return inputInfo
	end,
	GetSnappedPoint = getSnappedPoint,
	SnapWallEndPoint = snapWallEndPoint,
	ToSnappedVector2int16 = toSnappedVector2int16,
	GetLocalXZ = getLocalXZ,
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
	GetGhostFloorData = function()
		return ghostFloorData
	end,
	GetFloorMaterialId = function()
		return floorMaterialId
	end,
	GetCeilingMaterialId = function()
		return ceilingMaterialId
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
	NotifyDesignModeChange = notifyDesignModeChange,
	ClearSelection = FormexDesign.ClearSelection,
	Select = FormexDesign.Select,
	GetSelectionInfoFromInstance = getSelectionInfoFromInstance,
	DeleteAfterDelay = deleteAfterDelay,
	CancelAction = FormexDesign.CancelAction,
})

Walls = require(script.Parent:WaitForChild("FormexDesignWalls"))
Floors = require(script.Parent:WaitForChild("FormexDesignFloors"))
Objects = require(script.Parent:WaitForChild("FormexDesignObjects"))

Walls.Init()
Floors.Init()
Objects.Init()

FormexClient.ClientEvents:Connect(function(eventName)
	if eventName == "CurrentPlotChanged" then
		FormexDesign.CancelAction()
		refresh()
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1
	or input.UserInputType == Enum.UserInputType.Touch then
		actionHeld = true
		handlePrimaryClick()
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		FormexDesign.CancelAction()
		return
	end

	if input.UserInputType == Enum.UserInputType.Keyboard then
		if input.KeyCode == Enum.KeyCode.LeftAlt then
			alt1Held = true
			altHeld = true
		elseif input.KeyCode == Enum.KeyCode.RightAlt then
			alt2Held = true
			altHeld = true
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
		elseif input.KeyCode == Enum.KeyCode.RightAlt then
			alt2Held = false
			altHeld = alt1Held or alt2Held or alt3Held
		end
		return
	end
end)

RunService.RenderStepped:Connect(function()
	if designMode == FormexDesign.DesignMode.Play then
		return
	end

	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid or not plotInfo.PlotPart then
		return
	end

	handleUpdate()
end)

return FormexDesign
