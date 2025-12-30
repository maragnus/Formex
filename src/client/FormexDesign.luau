--!strict
local ContentProvider = game:GetService("ContentProvider")

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GridTexture: Texture = ReplicatedStorage:WaitForChild("GridTexture")
local FormexClient = require(script.Parent:WaitForChild("FormexClient"))
local FormexCamera = require(script.Parent:WaitForChild("FormexCamera"))
local Formex = FormexClient.Formex
local localPlayer = Players.LocalPlayer
local PlayerGui: ScreenGui = localPlayer:WaitForChild("PlayerGui")

local formexWorkspace = Workspace:WaitForChild("Formex")
local overlayFolder = Formex.EnsureFolder("FormexDesignOverlays", formexWorkspace)

local FormexDesign = {}

export type WallMode = "Full" | "Half" | "Hidden"
FormexDesign.WallMode = table.freeze({
	Full = "Full",
	Half = "Half",
	Hidden = "Hidden"
}) :: {WallMode: WallMode}

type ViewSettings = {
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
	CameraMode = FormexCamera.CameraModes.Play,
	WallMode = FormexDesign.WallMode.Full,
	ShowSegments = false,
	ShowGrid = false,
	ShowOtherLevels = true
} :: ViewSettings

type InputInfo = {
	PlotInfo: FormexClient.PlotInfo,
	HitPosition: Vector3?,
	SnapPoint: Vector2int16?,
	LayoutTile: Vector2int16?,
	LevelIndex: number,
	Target: Instance?,
	ActionHeld: boolean,
	AltHeld: boolean,
}

local designMode: DesignMode = FormexDesign.DesignMode.Play
local actionType: ActionType = FormexDesign.ActionType.Select
local currentLevel: number = 1
local viewSettings: ViewSettings = playViewSettings
local ghost: BasePart? = nil
local ghostWallData: Formex.WallData? = nil
local ghostFloorData: Formex.FloorData? = nil
local ghostType: Formex.PartType? = nil
local ghostActive = false
local ghostIsValid = false
local floorMaterialId = Formex.DefaultFloorMaterial
local actionHeld = false
local altHeld, alt1Held, alt2Held, alt3Held = false, false, false, false
local lastFloorPaintTile: Vector2int16? = nil
local lastFloorPaintMaterial: number? = nil
local selectionType: SelectionType = FormexDesign.SelectionType.None
local selectionData: SelectionData = nil
local selectionPart: BasePart? = nil
local selectionHighlight: Highlight? = nil
local wallStart: Vector2int16? = nil
local lastPreviewPoint: Vector2? = nil
local floorDragActive = false

type SelectedWall = {
	WallId: number,
	Level: number,
	Start: Vector2int16,
	End: Vector2int16,
	Part: BasePart,
}

type WallHandleType = "Start" | "End" | "Center"

local selectedWall: SelectedWall? = nil
local wallHandleStart: BasePart? = nil
local wallHandleEnd: BasePart? = nil
local wallHandleCenter: BasePart? = nil
local activeWallHandle: WallHandleType? = nil
local moveWallOriginal: SelectedWall? = nil
local movePreviewStart: Vector2int16? = nil
local movePreviewEnd: Vector2int16? = nil
local moveDragOriginLocal: Vector2? = nil

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
		ghostFloorData.CeilingMaterial = materialId
	end
	notifyDesignModeChange()
end

local designModeViewSettings: {DesignMode: ViewSettings} = {
	Play = playViewSettings,
	Design = playViewSettings,
	Expand = {
		CameraMode = FormexCamera.CameraModes.TopDown,
		WallMode = FormexDesign.WallMode.Half,
		ShowSegments = true,
		ShowGrid = false,
		ShowOtherLevels = false
	},
	Wall = {
		CameraMode = FormexCamera.CameraModes.TopDown,
		WallMode = FormexDesign.WallMode.Full,
		ShowSegments = false,
		ShowGrid = true,
		ShowOtherLevels = false
	},
	Floor = {
		CameraMode = FormexCamera.CameraModes.TopDown,
		WallMode = FormexDesign.WallMode.Half,
		ShowSegments = false,
		ShowGrid = true,
		ShowOtherLevels = false
	},
	Ceiling = {
		CameraMode = FormexCamera.CameraModes.BottomUp,
		WallMode = FormexDesign.WallMode.Full,
		ShowSegments = false,
		ShowGrid = true,
		ShowOtherLevels = false
	},
	Object = {
		CameraMode = FormexCamera.CameraModes.Play,
		WallMode = FormexDesign.WallMode.Full,
		ShowSegments = false,
		ShowGrid = true,
		ShowOtherLevels = false
	},
	Paint = {
		CameraMode = FormexCamera.CameraModes.Play,
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

local function refresh()
	clearOverlays()
	FormexDesign.ClearSelection()

	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid then return	end

	FormexCamera.SetCameraMode(viewSettings.CameraMode)

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

local function destroyHandle(handle: BasePart?)
	if handle and handle.Parent then
		handle:Destroy()
	end
end

local function clearWallHandles()
	destroyHandle(wallHandleStart)
	destroyHandle(wallHandleEnd)
	destroyHandle(wallHandleCenter)
	wallHandleStart = nil
	wallHandleEnd = nil
	wallHandleCenter = nil
end

function FormexDesign.ClearSelection()
	selectionType = FormexDesign.SelectionType.None
	selectionData = nil
	selectionPart = nil
	selectedWall = nil
	clearWallHandles()
	updateHighlightTarget()
	notifyDesignModeChange()
end

local function snapToGrid(value: number): number
	local grid = Formex.GridSize
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

local function getWallEndpoints(plotPart: BasePart, wallPart: BasePart): (Vector2int16, Vector2int16)
	local midLocal = plotPart.CFrame:PointToObjectSpace(wallPart.Position)
	local dirLocal = plotPart.CFrame:VectorToObjectSpace(wallPart.CFrame.LookVector)
	dirLocal = Vector3.new(dirLocal.X, 0, dirLocal.Z)
	if dirLocal.Magnitude <= 1e-4 then
		dirLocal = Vector3.new(0, 0, 1)
	else
		dirLocal = dirLocal.Unit
	end

	local halfLength = wallPart.Size.Z / 2
	local startLocal = midLocal - dirLocal * halfLength
	local endLocal = midLocal + dirLocal * halfLength

	local startPoint = Vector2int16.new(snapToGrid(startLocal.X), snapToGrid(startLocal.Z))
	local endPoint = Vector2int16.new(snapToGrid(endLocal.X), snapToGrid(endLocal.Z))
	return startPoint, endPoint
end

local function snapWallEndPoint(startPoint: Vector2 | Vector2int16, rawEndPoint: Vector2): Vector2int16
	local dx = rawEndPoint.X - startPoint.X
	local dz = rawEndPoint.Y - startPoint.Y
	local length = math.sqrt(dx * dx + dz * dz)
	if length <= 1e-4 then
		return rawEndPoint
	end

	local angle = math.atan2(dz, dx)
	local step = math.pi / 4
	local snappedAngle = math.round(angle / step) * step
	local snappedLength = math.max(math.abs(dx), math.abs(dz))

	local snappedDx = math.cos(snappedAngle) * snappedLength
	local snappedDz = math.sin(snappedAngle) * snappedLength

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

local function getPointerHit(): (Vector3?, Instance?)
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil, nil
	end

	local mousePosition = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePosition.X, mousePosition.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true

	if actionType == FormexDesign.ActionType.Select then
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
		return nil, nil
	end

	return result.Position, result.Instance
end

local function getInputInfo() : InputInfo | nil
	if designMode == FormexDesign.DesignMode.Play then
		return nil
	end

	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid or not plotInfo.PlotPart then
		return nil
	end

	local hitPosition, target = getPointerHit()
	local snapPoint = hitPosition and getSnappedPoint(plotInfo.PlotPart, hitPosition) or nil
	local layoutTile = hitPosition and getLayoutTile(plotInfo.PlotPart, hitPosition) or nil

	return {
		PlotInfo = plotInfo,
		HitPosition = hitPosition,
		SnapPoint = snapPoint,
		LayoutTile = layoutTile,
		LevelIndex = 1, --getLevel(),
		Target = target,
		ActionHeld = actionHeld,
		AltHeld = altHeld
	} :: InputInfo
end

local function applyGhostAppearance(part: BasePart)
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Name = "Ghost"
	part:SetAttribute("IsGhost", true)
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
		hiddenCFrame = plotPart.CFrame * CFrame.new(0, -(plotPart.Size.Y / 2 + 10), 0)
	end

	ghost.Size = Vector3.new(0, 0, 0)
	ghost.CFrame = hiddenCFrame
	ghostActive = false
	ghostIsValid = false
	updateHighlightTarget()
end

local function clearGhost()
	local plotInfo = FormexClient.CurrentPlot
	Formex.HideGhost(plotInfo and plotInfo.PlotPart or nil)
	lastPreviewPoint = nil
end

local function buildWallData(startPoint: Vector2int16, endPoint: Vector2int16): Formex.WallData
	local wallMaterial = Formex.DefaultWallMaterial
	return {
		WallId = 0,
		Level = currentLevel,
		Start = startPoint,
		End = endPoint,
		FrontMaterial = wallMaterial,
		BackMaterial = wallMaterial,
		StartMaterial = wallMaterial,
		EndMaterial = wallMaterial,
		Part = nil
	}
end

local function buildFloorGhostData(levelIndex: number, tile: Vector2int16): Formex.FloorData
	return {
		FloorId = Formex.XYToIndex(tile.X, tile.Y),
		LevelIndex = levelIndex,
		Tile = tile,
		Type = Formex.FloorType.Square,
		FloorMaterial = floorMaterialId,
		CeilingMaterial = floorMaterialId,
		Part = ghost
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
		ghost = Formex.CreateWall(ghostWallData, plotPart)
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
		Formex.EditWall(ghostWallData, plotPart)
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
		ghostFloorData.Part = ghost
	else
		ghostFloorData.LevelIndex = levelIndex
		ghostFloorData.Tile = tile
		ghostFloorData.FloorId = Formex.XYToIndex(tile.X, tile.Y)
		ghostFloorData.FloorMaterial = floorMaterialId
		ghostFloorData.CeilingMaterial = floorMaterialId
		ghostFloorData.Part = ghost
	end

	local localCFrame, size = Formex.GetFloorPositionSize(ghostFloorData)
	ghost.Size = size
	ghost.CFrame = plotPart.CFrame * localCFrame
	ghost.Transparency = 1

	ghostActive = true
	updateHighlightTarget()
end

local function updateWallGhost(plotInfo: FormexClient.PlotInfo, plotPart: BasePart)
	if not wallStart then
		return
	end

	local hitPosition = getPointerHit()
	if not hitPosition then
		return
	end

	local endPoint = getSnappedPoint(plotPart, hitPosition)
	local snappedEndPoint = snapWallEndPoint(wallStart, endPoint)
	if lastPreviewPoint and snappedEndPoint == lastPreviewPoint then
		return
	end
	lastPreviewPoint = snappedEndPoint

	ensureWallGhost(plotPart, wallStart, snappedEndPoint)

	local previewData = buildWallData(wallStart, snappedEndPoint)
	local valid = Formex.IsWallValid(plotInfo :: any, previewData) -- PlotInfo is not PlotData, but shares SegmentsUnlocked
	updateGhostValidity(valid)
end

local function updateWallStartGhost(plotInfo: FormexClient.PlotInfo, plotPart: BasePart)
	local hitPosition = getPointerHit()
	if not hitPosition then
		return
	end

	local startPoint = getSnappedPoint(plotPart, hitPosition)
	if lastPreviewPoint and startPoint == lastPreviewPoint then
		return
	end
	lastPreviewPoint = startPoint

	ensureWallGhost(plotPart, startPoint, startPoint)
	updateGhostValidity(isPointInOwnedSegments(plotInfo, startPoint))
end

local function updateFloorGhost(input: InputInfo)
	if not input.LayoutTile or not input.PlotInfo.PlotPart then
		clearGhost()
		return
	end

	local partType = if designMode == FormexDesign.DesignMode.Ceiling then Formex.PartType.Ceiling else Formex.PartType.Floor
	ensureFloorGhost(input.PlotInfo.PlotPart, input.LevelIndex, input.LayoutTile, partType)

	local valid = Formex.IsFloorValid(input.PlotInfo :: any, ghostFloorData :: any)
	updateGhostValidity(valid)
end

local function createWallHandle(name: string, color: Color3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.2, 1.2, 1.2)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Parent = overlayFolder
	return part
end

local function setWallHandlesVisible(visible: boolean)
	local transparency = visible and 0 or 1
	for _, handle in ipairs({ wallHandleStart, wallHandleEnd, wallHandleCenter }) do
		if handle then
			handle.Transparency = transparency
			handle.CanQuery = visible
		end
	end
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

		currentPart = parent
	end

	return nil, nil, nil
end

local function updateWallHandles(plotInfo: FormexClient.PlotInfo)
	if designMode ~= FormexDesign.DesignMode.Wall
	or actionType ~= FormexDesign.ActionType.Select
	or selectionType ~= FormexDesign.SelectionType.Wall
	or not selectionPart
	or not plotInfo
	or not plotInfo.PlotPart then
		clearWallHandles()
		selectedWall = nil
		return
	end

	local selectionKind, partId, level = getSelectionInfoFromInstance(selectionPart)
	if not selectionKind or selectionKind ~= FormexDesign.SelectionType.Wall or not level then
		clearWallHandles()
		selectedWall = nil
		return
	end

	local wallPart = selectionPart :: BasePart
	local startPoint, endPoint = getWallEndpoints(plotInfo.PlotPart, wallPart)
	local wallId = partId or tonumber(wallPart.Name) or 0
	selectedWall = {
		WallId = wallId,
		Level = level,
		Start = startPoint,
		End = endPoint,
		Part = wallPart,
	}

	if not wallHandleStart then
		wallHandleStart = createWallHandle("WallHandleStart", selectionColor)
	end
	if not wallHandleEnd then
		wallHandleEnd = createWallHandle("WallHandleEnd", selectionColor)
	end
	if not wallHandleCenter then
		wallHandleCenter = createWallHandle("WallHandleCenter", ghostValidColor)
	end

	local centerY = plotInfo.PlotPart.Size.Y / 2 + (level - 1) * Formex.LevelHeight + Formex.LevelHeight / 2
	local function toWorld(point: Vector2)
		return plotInfo.PlotPart.CFrame:PointToWorldSpace(Vector3.new(point.X, centerY, point.Y))
	end

	wallHandleStart.Position = toWorld(Vector2.new(startPoint.X, startPoint.Y))
	wallHandleEnd.Position = toWorld(Vector2.new(endPoint.X, endPoint.Y))
	local midPoint = Vector2.new((startPoint.X + endPoint.X) / 2, (startPoint.Y + endPoint.Y) / 2)
	wallHandleCenter.Position = toWorld(midPoint)
	setWallHandlesVisible(true)
end

local function getWallHandleHit(): WallHandleType?
	if not wallHandleStart and not wallHandleEnd and not wallHandleCenter then
		return nil
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end

	local mousePosition = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePosition.X, mousePosition.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.IgnoreWater = true

	local handles = {}
	if wallHandleStart then
		table.insert(handles, wallHandleStart)
	end
	if wallHandleEnd then
		table.insert(handles, wallHandleEnd)
	end
	if wallHandleCenter then
		table.insert(handles, wallHandleCenter)
	end

	params.FilterDescendantsInstances = handles
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 2048, params)
	if not result then
		return nil
	end

	if result.Instance == wallHandleStart then
		return "Start"
	end
	if result.Instance == wallHandleEnd then
		return "End"
	end
	if result.Instance == wallHandleCenter then
		return "Center"
	end

	return nil
end

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

		selectionType = selectionKind
		selectionData = nil -- TODO
		selectionPart = part
		currentLevel = level
		notifyDesignModeChange()
		updateHighlightTarget()
		local plotInfo = FormexClient.CurrentPlot
		if plotInfo and plotInfo.IsValid then
			updateWallHandles(plotInfo)
		end
		return true
	end

	FormexDesign.ClearSelection()
	return false
end

local function beginWallAtPosition(plotInfo: FormexClient.PlotInfo, startPosition: Vector3)
	if not plotInfo.PlotPart then
		return
	end

	local startPoint = getSnappedPoint(plotInfo.PlotPart, startPosition)
	if not isPointInOwnedSegments(plotInfo, startPoint) then
		updateGhostValidity(false)
		return
	end

	clearGhost()
	FormexDesign.ClearSelection()
	wallStart = startPoint
	actionType = FormexDesign.ActionType.Step
	lastPreviewPoint = nil
	ensureWallGhost(plotInfo.PlotPart, startPoint, startPoint)
	notifyDesignModeChange()
end

function FormexDesign.StartWall()
	if actionType ~= FormexDesign.ActionType.Select then
		FormexDesign.CancelAction()
	end

	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid or not plotInfo.PlotPart then
		return
	end

	actionType = FormexDesign.ActionType.Start
	wallStart = nil
	lastPreviewPoint = nil
	clearGhost()
	FormexDesign.ClearSelection()
	notifyDesignModeChange()
end

local function setFloorTile(plotInfo: FormexClient.PlotInfo, levelIndex: number, tile: Vector2int16, altSide: boolean, materialId: number?)
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
		-- Add or update floor
		local isGhost = not floorData.Part
		
		-- Create and update local copy
		floorData.Part = Formex.UpdateFloor(plotInfo.PlotPart, floorData, floorData.Part)
		
		-- Send command to server
		FormexClient.BuildFloor(levelIndex, tile.X, tile.Y, floorData.FloorMaterial, floorData.FloorMaterial2)

		-- If it was a ghost floor, remove it after a delay
		if isGhost then
			deleteAfterDelay(floorData.Part, 1)
		end
	else
		-- Remove floor
		if floorData.Part then
			floorData.Part:Destroy()
			FormexClient.BuildFloor(levelIndex, tile.X, tile.Y, nil)
			return
		end
	end
end

function FormexDesign.StartFloor()
	FormexDesign.CancelAction()

	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid or not plotInfo.PlotPart then
		return
	end

	actionType = FormexDesign.ActionType.Step
	floorDragActive = false
	lastFloorPaintTile = nil
	lastFloorPaintMaterial = nil
	notifyDesignModeChange()
end

local function resetMoveState()
	activeWallHandle = nil
	moveWallOriginal = nil
	movePreviewStart = nil
	movePreviewEnd = nil
	moveDragOriginLocal = nil
end

function FormexDesign.CancelAction()
	if actionType == FormexDesign.ActionType.Select then return end

	clearGhost()
	wallStart = nil
	lastPreviewPoint = nil
	floorDragActive = false
	lastFloorPaintTile = nil
	lastFloorPaintMaterial = nil
	resetMoveState()
	actionType = FormexDesign.ActionType.Select
	local plotInfo = FormexClient.CurrentPlot
	if plotInfo and plotInfo.IsValid then
		updateWallHandles(plotInfo)
	end
	notifyDesignModeChange()
end

local function finalizeWall(plotInfo: FormexClient.PlotInfo, endPosition: Vector3)
	if not wallStart or not plotInfo.PlotPart then
		return
	end

	local endPoint = getSnappedPoint(plotInfo.PlotPart, endPosition)
	local snappedEndPoint = snapWallEndPoint(wallStart, endPoint)
	local wallData = buildWallData(wallStart, snappedEndPoint)
	if not Formex.IsWallValid(plotInfo :: any, wallData) then
		updateGhostValidity(false)
		return
	end

	local result = FormexClient.BuildWall(wallData, Formex.BuildAction.Add) :: Formex.WallData?
	FormexDesign.CancelAction()

	if result and result.WallId then
		local levelIndex = result.Level or currentLevel
		local plotPart = plotInfo.PlotPart
		task.spawn(function()
			local deadline = time() + 2
			while time() < deadline do
				local levelPart = plotPart:FindFirstChild(tostring(levelIndex))
				if levelPart then
					local wallsFolder = levelPart:FindFirstChild("Walls")
					if wallsFolder then
						local wallPart = wallsFolder:FindFirstChild(tostring(result.WallId))
						if wallPart and wallPart:IsA("BasePart") then
							FormexDesign.Select(wallPart)
							return
						end
					end
				end
				task.wait(0.05)
			end
		end)
	end
end

local function beginWallMove(handleType: WallHandleType, input: InputInfo)
	if not selectedWall or not input.PlotInfo.PlotPart then
		return
	end

	activeWallHandle = handleType
	moveWallOriginal = {
		WallId = selectedWall.WallId,
		Level = selectedWall.Level,
		Start = selectedWall.Start,
		End = selectedWall.End,
		Part = selectedWall.Part,
	}
	movePreviewStart = selectedWall.Start
	movePreviewEnd = selectedWall.End
	moveDragOriginLocal = nil

	if handleType == "Center" and input.HitPosition then
		moveDragOriginLocal = getLocalXZ(input.PlotInfo.PlotPart, input.HitPosition)
	end

	actionType = FormexDesign.ActionType.Move
	lastPreviewPoint = nil
	setWallHandlesVisible(false)
	ensureWallGhost(input.PlotInfo.PlotPart, Vector2.new(selectedWall.Start.X, selectedWall.Start.Y), Vector2.new(selectedWall.End.X, selectedWall.End.Y))
	updateGhostValidity(true)
	notifyDesignModeChange()
end

local function updateWallMoveGhost(input: InputInfo)
	if not moveWallOriginal or not input.PlotInfo.PlotPart then
		return
	end

	local startPoint = moveWallOriginal.Start
	local endPoint = moveWallOriginal.End
	local newStart = startPoint
	local newEnd = endPoint

	if activeWallHandle == "Center" then
		if not input.HitPosition or not moveDragOriginLocal then
			return
		end
		local currentLocal = getLocalXZ(input.PlotInfo.PlotPart, input.HitPosition)
		local delta = currentLocal - moveDragOriginLocal
		local startRaw = Vector2.new(startPoint.X + delta.X, startPoint.Y + delta.Y)
		local endRaw = Vector2.new(endPoint.X + delta.X, endPoint.Y + delta.Y)
		newStart = toSnappedVector2int16(startRaw)
		newEnd = toSnappedVector2int16(endRaw)
	else
		if not input.SnapPoint then
			return
		end
		local rawPoint = Vector2.new(input.SnapPoint.X, input.SnapPoint.Y)
		if activeWallHandle == "Start" then
			local snapped = snapWallEndPoint(Vector2.new(endPoint.X, endPoint.Y), rawPoint)
			newStart = toSnappedVector2int16(snapped)
			newEnd = endPoint
		elseif activeWallHandle == "End" then
			local snapped = snapWallEndPoint(Vector2.new(startPoint.X, startPoint.Y), rawPoint)
			newStart = startPoint
			newEnd = toSnappedVector2int16(snapped)
		end
	end

	movePreviewStart = newStart
	movePreviewEnd = newEnd

	ensureWallGhost(input.PlotInfo.PlotPart, Vector2.new(newStart.X, newStart.Y), Vector2.new(newEnd.X, newEnd.Y))

	local previewData = buildWallData(newStart, newEnd)
	local valid = Formex.IsWallValid(input.PlotInfo :: any, previewData)
	updateGhostValidity(valid)
end

local function finalizeWallMove(plotInfo: FormexClient.PlotInfo)
	if not moveWallOriginal or not movePreviewStart or not movePreviewEnd then
		return
	end

	local editData = {
		WallId = moveWallOriginal.WallId,
		Level = moveWallOriginal.Level,
		Start = movePreviewStart,
		End = movePreviewEnd,
	} :: any

	local valid = Formex.IsWallValid(plotInfo :: any, editData)
	if not valid then
		updateGhostValidity(false)
		resetMoveState()
		actionType = FormexDesign.ActionType.Select
		clearGhost()
		updateWallHandles(plotInfo)
		notifyDesignModeChange()
		return
	end

	FormexClient.BuildWall(editData :: Formex.WallData, Formex.BuildAction.Edit)
	selectedWall = {
		WallId = moveWallOriginal.WallId,
		Level = moveWallOriginal.Level,
		Start = movePreviewStart,
		End = movePreviewEnd,
		Part = moveWallOriginal.Part,
	}
	resetMoveState()
	actionType = FormexDesign.ActionType.Select
	clearGhost()
	updateWallHandles(plotInfo)
	notifyDesignModeChange()
end

local function handleWallUpdate(input: InputInfo)
	if not input.PlotInfo.PlotPart then
		return
	end

	if actionType == FormexDesign.ActionType.Start then
		updateWallStartGhost(input.PlotInfo, input.PlotInfo.PlotPart)
	elseif actionType == FormexDesign.ActionType.Step then
		updateWallGhost(input.PlotInfo, input.PlotInfo.PlotPart)
	elseif actionType == FormexDesign.ActionType.Move then
		updateWallMoveGhost(input)
	elseif ghostActive and ghostType == Formex.PartType.Wall then
		clearGhost()
	end
end

local function handleFloorUpdate(input: InputInfo)
	updateFloorGhost(input)

	floorDragActive = input.ActionHeld
	if not input.ActionHeld or not input.LayoutTile then return end
	if not ghostIsValid then return end

	local materialId = input.AltHeld and nil or floorMaterialId
	if lastFloorPaintTile
	and lastFloorPaintMaterial == materialId
	and input.LayoutTile == lastFloorPaintTile then
		return
	end

	lastFloorPaintTile = input.LayoutTile
	lastFloorPaintMaterial = materialId
	setFloorTile(input.PlotInfo, input.LevelIndex, input.LayoutTile, input.AltHeld, materialId)
end

local function handleUpdate()
	local input = getInputInfo()
	if not input then return end

	if designMode == FormexDesign.DesignMode.Wall then
		if actionType == FormexDesign.ActionType.Select then
			updateWallHandles(input.PlotInfo)
		end
		handleWallUpdate(input)
	elseif designMode == FormexDesign.DesignMode.Floor or designMode == FormexDesign.DesignMode.Ceiling then
		handleFloorUpdate(input)
	end
end

local function handlePrimaryRelease()
	local input = getInputInfo()
	if not input then return end

	if designMode == FormexDesign.DesignMode.Wall
	and actionType == FormexDesign.ActionType.Step
	and input.HitPosition then
		finalizeWall(input.PlotInfo, input.HitPosition)
	end

	if designMode == FormexDesign.DesignMode.Wall
	and actionType == FormexDesign.ActionType.Move then
		finalizeWallMove(input.PlotInfo)
	end

	if designMode == FormexDesign.DesignMode.Floor
	or designMode == FormexDesign.DesignMode.Ceiling then
		floorDragActive = false
		lastFloorPaintTile = nil
		lastFloorPaintMaterial = nil
	end
end

local function handlePrimaryClick()
	if designMode == FormexDesign.DesignMode.Wall
	and actionType == FormexDesign.ActionType.Select
	and selectionType == FormexDesign.SelectionType.Wall then
		local handleType = getWallHandleHit()
		if handleType then
			local input = getInputInfo()
			if input then
				beginWallMove(handleType, input)
			end
			return
		end
	end

	local input = getInputInfo()
	if not input then return end

	-- Clicking on empty space cancels selection
	if not input.HitPosition then
		if actionType == FormexDesign.ActionType.Select then
			FormexDesign.ClearSelection()
		end
		return
	end

	if actionType == FormexDesign.ActionType.Select then

		if designMode == FormexDesign.DesignMode.Wall then
			-- Select wall if clicked on existing wall			
			local selected = input.Target and FormexDesign.Select(input.Target) or false
			if selected then
				return
			end

			-- Start new wall if clicked on empty space
			FormexDesign.StartWall()

		elseif designMode == FormexDesign.DesignMode.Floor
		or designMode == FormexDesign.DesignMode.Ceiling then
			-- Start floor painting
			FormexDesign.StartFloor()

		else
			-- In other modes, just clear selection for now
			FormexDesign.ClearSelection()
		end
		return
	end

	if actionType == FormexDesign.ActionType.Start then
		if designMode == FormexDesign.DesignMode.Wall and input.HitPosition then
			beginWallAtPosition(input.PlotInfo, input.HitPosition)
		end
		return
	end

	if actionType == FormexDesign.ActionType.Step then
		if designMode == FormexDesign.DesignMode.Wall then
			return
		elseif designMode == FormexDesign.DesignMode.Floor
		or designMode == FormexDesign.DesignMode.Ceiling then
			handleFloorUpdate(input)
		end
	end
end

function FormexDesign.SetDesignMode(mode: DesignMode?)
	mode = mode or FormexDesign.DesignMode.Play
	local lastMode = designMode
	if designMode == mode then return end

	if actionType ~= FormexDesign.ActionType.Select then
		FormexDesign.CancelAction()
	end

	if mode ~= FormexDesign.DesignMode.Play
	and lastMode == FormexDesign.DesignMode.Play then
		currentLevel = getLevel()
	end

	designMode = mode
	viewSettings = designModeViewSettings[mode]
	actionType = FormexDesign.ActionType.Select
	FormexDesign.ClearSelection()
	refresh()
	notifyDesignModeChange()
end

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
