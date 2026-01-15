--!strict
--[[
FormexDesignWalls
Handles wall design actions (placement, handles, paint/dropper).
Exports:
- Init(): load shared dependencies
- ApplyPaintToTarget(input): boolean
- CopyPaintFromTarget(input): boolean
- ApplySelectedAppearance(overrides): boolean
- GetSelectedWallData(): Formex.WallData?
- UpdateHandles(plotInfo): ()
- StartWall(): ()
- CancelAction(): ()
- ClearSelection(): ()
- HandleUpdate(input): ()
- HandlePrimaryRelease(input): ()
- HandlePrimaryClick(input): ()
]]

local Formex = require(game:GetService("ReplicatedStorage"):WaitForChild("Formex"))

local Workspace = game:GetService("Workspace")
local Context = require(script.Parent:WaitForChild("Context"))

local Walls = {}

type SelectedWall = {
	WallId: number,
	Level: number,
	Start: Vector2int16,
	End: Vector2int16,
	Part: Model,
}

type WallInfo = {
	WallId: number,
	Level: number,
	Start: Vector2int16,
	End: Vector2int16,
	Part: Model,
}

type ConnectedWall = {
	Wall: WallInfo,
	EndType: "Start" | "End",
}

type WallHandleType = "Start" | "End" | "Center" | "StartSolo" | "EndSolo" | "ExtendStart" | "ExtendEnd" | "Delete"

type WallSide = "Front" | "Back"

type WallPaintSettings = Context.WallPaintSettings

local FormexClient: any
local Formex: any
local Handles: any
local OverlayFolder: Folder
local Highlight: any
local Enums: any
local Constants: any

local getActionType: () -> string
local setActionType: (string) -> ()
local getDesignMode: () -> string
local getEditMode: () -> string
local getCurrentLevel: () -> number
local getViewSettings: () -> any
local getSelectionType: () -> string
local getSelectionData: () -> any?
local getSelectionSnapshot: () -> any?
local getLastInputInfo: () -> any?
local getSnappedPoint: (BasePart, Vector3) -> Vector2int16
local snapWallEndPoint: (Vector2 | Vector2int16, Vector2) -> Vector2int16
local toSnappedVector2int16: (Vector2) -> Vector2int16
local getLocalXZ: (BasePart, Vector3) -> Vector2
local isPointInOwnedSegments: (any, Vector2) -> boolean
local buildWallData: (Vector2int16, Vector2int16) -> any
local updateGhostValidity: (boolean) -> ()
local ensureWallGhost: (BasePart, Vector2, Vector2) -> ()
local clearGhost: () -> ()
local isGhostActive: () -> boolean
local getGhostType: () -> any?
local notifyDesignModeChange: () -> ()
local clearSelection: () -> ()
local select: (any) -> boolean
local selectPlotModelByIdAsync: (any, string, number, number, number?) -> ()
local deleteAfterDelay: (Instance, number) -> ()
local cancelAction: () -> ()
local getWallPaintSettings: () -> any
local updateDesignState: (any) -> ()

local wallStart: Vector2int16? = nil
local wallBuildMode: "Pending" | "Click" | "Drag" | nil = nil
local lastPreviewPoint: Vector2? = nil

local selectedWall: SelectedWall? = nil
local wallHandleStart: BasePart? = nil
local wallHandleEnd: BasePart? = nil
local wallHandleCenter: BasePart? = nil
local wallHandleStartSolo: BasePart? = nil
local wallHandleEndSolo: BasePart? = nil
local wallHandleExtendStart: BasePart? = nil
local wallHandleExtendEnd: BasePart? = nil
local wallHandleDelete: BasePart? = nil
local wallHandleFlip: BasePart? = nil
local wallHandleDivide: BasePart? = nil
local activeWallHandle: WallHandleType? = nil
local moveWallOriginal: SelectedWall? = nil
local moveWallOriginals: {[number]: WallInfo} = {}
local moveWallConnections = {
	Start = {} :: {ConnectedWall},
	End = {} :: {ConnectedWall},
}
local moveWallUpdated: {[number]: WallInfo} = {}
local movePreviewStart: Vector2int16? = nil
local movePreviewEnd: Vector2int16? = nil
local moveDragOriginLocal: Vector2? = nil

function Walls.Init()
	local ctx = Context.Get()
	FormexClient = ctx.FormexClient
	Formex = ctx.Formex
	Handles = ctx.Handles
	OverlayFolder = ctx.OverlayFolder
	Highlight = ctx.Highlight
	Enums = ctx.Enums
	Constants = ctx.Constants

	getActionType = ctx.GetActionType
	setActionType = ctx.SetActionType
	getDesignMode = ctx.GetDesignMode
	getEditMode = ctx.GetEditMode
	getCurrentLevel = ctx.GetCurrentLevel
	getViewSettings = ctx.GetViewSettings
	getSelectionType = ctx.GetSelectionType
	getSelectionData = ctx.GetSelectionData
	getSelectionSnapshot = ctx.GetSelectionSnapshot
	getLastInputInfo = ctx.GetLastInputInfo
	getSnappedPoint = ctx.GetSnappedPoint
	snapWallEndPoint = ctx.SnapWallEndPoint
	toSnappedVector2int16 = ctx.ToSnappedVector2int16
	getLocalXZ = ctx.GetLocalXZ
	isPointInOwnedSegments = ctx.IsPointInOwnedSegments
	buildWallData = ctx.BuildWallData
	updateGhostValidity = ctx.UpdateGhostValidity
	ensureWallGhost = ctx.EnsureWallGhost
	clearGhost = ctx.ClearGhost
	isGhostActive = ctx.IsGhostActive
	getGhostType = ctx.GetGhostType
	notifyDesignModeChange = ctx.NotifyDesignModeChange
	clearSelection = ctx.ClearSelection
	select = ctx.Select
	selectPlotModelByIdAsync = ctx.SelectPlotModelByIdAsync
	deleteAfterDelay = ctx.DeleteAfterDelay
	cancelAction = ctx.CancelAction
	getWallPaintSettings = ctx.GetWallPaintSettings
	updateDesignState = ctx.UpdateDesignState
end

local function getWallHandleY(level: number, location: string): number
	local base = (math.max(level, 1) - 1) * Formex.LevelHeight
	if location == Enums.HandleLocation.Top then
		return base + Formex.LevelHeight
	elseif location == Enums.HandleLocation.Middle then
		return base + (Formex.LevelHeight / 2)
	end
	return base
end

local function pointsEqual(a: Vector2int16, b: Vector2int16): boolean
	return a.X == b.X and a.Y == b.Y
end

local function getLevelWallInfos(plotInfo: any, level: number): {WallInfo}
	local results = {}
	local plotData = plotInfo and plotInfo.PlotData
	if not plotData or not plotData.Levels then return results end
	local levelData = plotData.Levels[level]
	if not levelData or not levelData.Walls then return results end
	for _, wallData in pairs(levelData.Walls) do
		local model = wallData.Part
		if model and model:IsA("Model") then
			local startPoint = wallData.Start
			local endPoint = wallData.End
			if startPoint and endPoint and wallData.WallId then
				table.insert(results, {
					WallId = wallData.WallId,
					Level = level,
					Start = startPoint,
					End = endPoint,
					Part = model,
				})
			end
		end
	end

	return results
end

local function getConnectedWallsAtPoint(walls: {WallInfo}, point: Vector2int16, wallId: number): {ConnectedWall}
	local connected = {}
	for _, wall in ipairs(walls) do
		if wall.WallId ~= wallId then
			if pointsEqual(wall.Start, point) then
				table.insert(connected, { Wall = wall, EndType = "Start" })
			elseif pointsEqual(wall.End, point) then
				table.insert(connected, { Wall = wall, EndType = "End" })
			end
		end
	end
	return connected
end

local function getPerpOffset(startPoint: Vector2int16, endPoint: Vector2int16, distance: number): Vector2
	local dir = Vector2.new(endPoint.X - startPoint.X, endPoint.Y - startPoint.Y)
	if dir.Magnitude <= Constants.Epsilon then
		dir = Vector2.new(0, 1)
	else
		dir = dir.Unit
	end
	local perp = Vector2.new(-dir.Y, dir.X)
	return perp * distance
end

local function getHandleIcon(handle: BasePart?): GuiObject?
	if not handle then return nil end
	if Handles and Handles.GetHandleIcon then
		return Handles.GetHandleIcon(handle)
	end

	local billboard = handle:FindFirstChild("HandleBillboard")
	if billboard and billboard:IsA("BillboardGui") then
		local icon = billboard:FindFirstChild("Icon")
		if icon and (icon:IsA("ImageButton") or icon:IsA("ImageLabel")) then return icon end
	end

	return nil
end

local function setHandleIconRotation(handle: BasePart?, rotation: number)
	local icon = getHandleIcon(handle)
	if icon then
		icon.Rotation = rotation
	end
end

local function getScreenRotationForDirection(direction: Vector3): number
	local camera = Workspace.CurrentCamera
	if not camera then return 0 end
	local right = camera.CFrame.RightVector
	local up = camera.CFrame.UpVector
	local x = direction:Dot(right)
	local y = direction:Dot(up)
	if math.abs(x) <= Constants.Epsilon and math.abs(y) <= Constants.Epsilon then return 0 end
	return math.deg(math.atan2(x, y))
end

local function getModelBottomCenter(model: Model): Vector3
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	return boundsCFrame.Position - Vector3.new(0, boundsSize.Y / 2, 0)
end

local function isZeroLength(startPoint: Vector2int16, endPoint: Vector2int16): boolean
	return startPoint.X == endPoint.X and startPoint.Y == endPoint.Y
end

local function setHandlesBusy(active: boolean)
	if Handles and Handles.SetBusy then
		Handles.SetBusy(active)
	end
end

local function runBuildTransaction(changes: {Formex.BuildChange}, selection: Formex.SelectionSnapshot?): {Formex.BuildChangeResult}?
	setHandlesBusy(true)
	local results = FormexClient.BuildTransaction(changes, selection)
	setHandlesBusy(false)
	return results
end

local function buildWall(wallData: any, action: any, selection: Formex.SelectionSnapshot?): any
	local results = runBuildTransaction({
		{
			PartType = Formex.PartType.Wall,
			Action = action,
			Data = wallData,
		},
	}, selection)
	if not results then return nil end
	local changeResult = results[1]
	return changeResult and changeResult.Result or nil
end

local function safeBuildWall(wallData: any, action: any): (boolean, any)
	local result = buildWall(wallData, action, getSelectionSnapshot())
	return true, result
end

local function getResultWallId(result: any): number?
	if type(result) == "number" then return result end
	if type(result) == "table" then
		if result.WallId then
			return result.WallId
		end
		if #result >= 1 then
			return tonumber(result[1])
		end
	end
	return nil
end

local function createWallPreview(plotPart: BasePart, wallData: any): Model?
	local preview = Formex.Walls.Create(wallData, plotPart)
	if preview then
		for _, child in ipairs(preview:GetDescendants()) do
			if child:IsA("BasePart") then
				child.CanCollide = false
				child.CanTouch = false
				child.CanQuery = false
				child.CastShadow = false
			end
		end
		preview.Parent = OverlayFolder
		deleteAfterDelay(preview, 1)
	end
	return preview
end

local function updateMergePreview(plotInfo: any, levelIndex: number, validation: any?)
	if not Highlight or not validation or not validation.MergeSegments then
		if Highlight and Highlight.ClearMergeEdgePreview then
			Highlight.ClearMergeEdgePreview()
		end
		return
	end

	local segments = {}
	for _, entry in ipairs(validation.MergeSegments) do
		if entry.Level == levelIndex then
			table.insert(segments, {
				Start = entry.Start,
				End = entry.End,
			})
		end
	end

	if #segments > 0 then
		Highlight.UpdateMergeEdgePreview(plotInfo, levelIndex, segments, Constants.HandleAddColor)
	else
		Highlight.ClearMergeEdgePreview()
	end
end

local function getWallDataFromPlot(plotInfo: any, level: number, wallId: number): Formex.WallData?
	local plotData = plotInfo and plotInfo.PlotData
	local levelData = plotData and plotData.Levels and plotData.Levels[level]
	return levelData and levelData.Walls and levelData.Walls[wallId] or nil
end

function Walls.GetSelectedWallData(): Formex.WallData?
	if getSelectionType() ~= Enums.SelectionType.Wall then return nil end
	return getSelectionData()
end

local function applyWallAppearance(plotInfo: any, wallData: Formex.WallData, overrides: {[string]: any})
	if not plotInfo or not plotInfo.PlotPart then return end
	if not wallData or not wallData.Part then return end

	local height = wallData.Height
	if overrides.Height ~= nil then
		height = overrides.Height == false and nil or overrides.Height
	end

	local frontSplitHeight = wallData.FrontSplitHeight
	if overrides.FrontSplitHeight ~= nil then
		frontSplitHeight = overrides.FrontSplitHeight == false and 0 or overrides.FrontSplitHeight
	end

	local backSplitHeight = wallData.BackSplitHeight
	if overrides.BackSplitHeight ~= nil then
		backSplitHeight = overrides.BackSplitHeight == false and 0 or overrides.BackSplitHeight
	end

	local updated = {
		WallId = wallData.WallId,
		Level = wallData.Level,
		Start = wallData.Start,
		End = wallData.End,
		Height = height,
		FrontSplitHeight = frontSplitHeight,
		BackSplitHeight = backSplitHeight,
		FrontTopMaterial = overrides.FrontTopMaterial or wallData.FrontTopMaterial,
		FrontBottomMaterial = overrides.FrontBottomMaterial or wallData.FrontBottomMaterial,
		BackTopMaterial = overrides.BackTopMaterial or wallData.BackTopMaterial,
		BackBottomMaterial = overrides.BackBottomMaterial or wallData.BackBottomMaterial,
		FrontTopColor = overrides.FrontTopColor or wallData.FrontTopColor,
		FrontBottomColor = overrides.FrontBottomColor or wallData.FrontBottomColor,
		BackTopColor = overrides.BackTopColor or wallData.BackTopColor,
		BackBottomColor = overrides.BackBottomColor or wallData.BackBottomColor,
		Part = wallData.Part,
	}

	Formex.Walls.Edit(updated, plotInfo.PlotPart, false)
	local serverData = table.clone(updated)
	serverData.Part = nil
	buildWall(serverData, Formex.BuildAction.Edit, getSelectionSnapshot())
end

function Walls.ApplySelectedAppearance(overrides: {[string]: any}): boolean
	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid or not plotInfo.PlotPart then return false end
	local wallData = getSelectionData()
	if not wallData then return false end
	applyWallAppearance(plotInfo, wallData, overrides)
	return true
end

function Walls.ApplyPaintToTarget(input: any): boolean
	if not input or not input.PlotInfo or not input.WallData or not input.WallSide then return false end
	local plotInfo = input.PlotInfo

	local paintSettings = getWallPaintSettings() :: WallPaintSettings

	local overrides = {
		Height = paintSettings.Height == nil and false or paintSettings.Height,
	}

	if input.WallSide == Formex.ObjectSide.Front then
		overrides.FrontSplitHeight = paintSettings.SplitHeight == nil and false or paintSettings.SplitHeight
		overrides.FrontTopMaterial = paintSettings.TopMaterial
		overrides.FrontBottomMaterial = paintSettings.BottomMaterial
		overrides.FrontTopColor = paintSettings.TopColor
		overrides.FrontBottomColor = paintSettings.BottomColor
	else
		overrides.BackSplitHeight = paintSettings.SplitHeight == nil and false or paintSettings.SplitHeight
		overrides.BackTopMaterial = paintSettings.TopMaterial
		overrides.BackBottomMaterial = paintSettings.BottomMaterial
		overrides.BackTopColor = paintSettings.TopColor
		overrides.BackBottomColor = paintSettings.BottomColor
	end

	applyWallAppearance(plotInfo, input.WallData, overrides)
	return true
end

function Walls.CopyPaintFromTarget(input: any): boolean
	if not input or not input.WallData or not input.WallSide then return false end
	local wallData = input.WallData
	local isFront = input.WallSide == Formex.ObjectSide.Front
	local splitHeight = isFront and wallData.FrontSplitHeight or wallData.BackSplitHeight
	local topMaterial = isFront and wallData.FrontTopMaterial or wallData.BackTopMaterial
	local bottomMaterial = isFront and wallData.FrontBottomMaterial or wallData.BackBottomMaterial
	local topColor = isFront and wallData.FrontTopColor or wallData.BackTopColor
	local bottomColor = isFront and wallData.FrontBottomColor or wallData.BackBottomColor

	updateDesignState({
		Wall = {
			Height = wallData.Height == nil and false or wallData.Height,
			SplitHeight = splitHeight == nil and 0 or splitHeight,
			TopMaterial = topMaterial,
			BottomMaterial = bottomMaterial,
			TopColor = topColor,
			BottomColor = bottomColor,
		},
	})

	return true
end

local function applyWallTransform(plotInfo: any, wall: WallInfo)
	if not wall.Part or not plotInfo or not plotInfo.PlotPart then return end
	local baseData = getWallDataFromPlot(plotInfo, wall.Level, wall.WallId)
	if not baseData then return end
	local wallData = table.clone(baseData)
	wallData.Start = wall.Start
	wallData.End = wall.End
	wallData.Part = wall.Part
	Formex.Walls.Edit(wallData, plotInfo.PlotPart, false)
end

local function isPointOnSegment(point: Vector2int16, startPoint: Vector2int16, endPoint: Vector2int16): boolean
	if pointsEqual(point, startPoint) or pointsEqual(point, endPoint) then return false end
	local dx = endPoint.X - startPoint.X
	local dy = endPoint.Y - startPoint.Y
	local px = point.X - startPoint.X
	local py = point.Y - startPoint.Y
	local cross = (px * dy) - (py * dx)
	if math.abs(cross) > Constants.Epsilon then return false end
	local minX = math.min(startPoint.X, endPoint.X) - Constants.Epsilon
	local maxX = math.max(startPoint.X, endPoint.X) + Constants.Epsilon
	local minY = math.min(startPoint.Y, endPoint.Y) - Constants.Epsilon
	local maxY = math.max(startPoint.Y, endPoint.Y) + Constants.Epsilon
	return point.X >= minX and point.X <= maxX and point.Y >= minY and point.Y <= maxY
end

local function getGreatestCommonDivisor(a: number, b: number): number
	a = math.abs(a)
	b = math.abs(b)
	while b ~= 0 do
		local temp = a % b
		a = b
		b = temp
	end
	return a
end

local function getGridSplitPointOnLine(startPoint: Vector2int16, endPoint: Vector2int16, grid: number): Vector2int16?
	local dx = endPoint.X - startPoint.X
	local dy = endPoint.Y - startPoint.Y
	local gcdStuds = getGreatestCommonDivisor(dx, dy)
	if gcdStuds <= 1 then return nil end
	local stepX = dx / gcdStuds
	local stepY = dy / gcdStuds
	local midIndex = gcdStuds / 2
	local bestIndex = nil
	local bestDistance = math.huge

	for i = 1, gcdStuds - 1 do
		local x = startPoint.X + stepX * i
		local y = startPoint.Y + stepY * i
		if x % grid == 0 and y % grid == 0 then
			local distance = math.abs(i - midIndex)
			if distance < bestDistance then
				bestDistance = distance
				bestIndex = i
			end
		end
	end

	if not bestIndex then return nil end
	return Vector2int16.new(
		startPoint.X + stepX * bestIndex,
		startPoint.Y + stepY * bestIndex
	)
end

local function getNearestGridPointToMidpoint(startPoint: Vector2int16, endPoint: Vector2int16, grid: number): Vector2int16
	local midX = (startPoint.X + endPoint.X) / 2
	local midY = (startPoint.Y + endPoint.Y) / 2
	local baseX = math.round(midX / grid) * grid
	local baseY = math.round(midY / grid) * grid

	local function isEndpoint(point: Vector2int16): boolean
		return pointsEqual(point, startPoint) or pointsEqual(point, endPoint)
	end

	local basePoint = Vector2int16.new(baseX, baseY)
	if not isEndpoint(basePoint) then return basePoint end
	local bestPoint = nil
	local bestDistance = math.huge
	for offsetX = -1, 1 do
		for offsetY = -1, 1 do
			if offsetX ~= 0 or offsetY ~= 0 then
				local point = Vector2int16.new(baseX + offsetX * grid, baseY + offsetY * grid)
				if not isEndpoint(point) then
					local dist = (point.X - midX) * (point.X - midX) + (point.Y - midY) * (point.Y - midY)
					if dist < bestDistance then
						bestDistance = dist
						bestPoint = point
					end
				end
			end
		end
	end

	return bestPoint or basePoint
end

local function hasWallSplitRoom(startPoint: Vector2int16, endPoint: Vector2int16): boolean
	local dx = endPoint.X - startPoint.X
	local dy = endPoint.Y - startPoint.Y
	local length = math.sqrt(dx * dx + dy * dy)
	local grid = Formex.LayoutGridSize > 0 and Formex.LayoutGridSize or 1
	return length + Constants.Epsilon >= grid * 2
end

local function getWallSplitPoint(startPoint: Vector2int16, endPoint: Vector2int16): Vector2int16
	local grid = Formex.LayoutGridSize > 0 and Formex.LayoutGridSize or 1
	local onLine = getGridSplitPointOnLine(startPoint, endPoint, grid)
	if onLine then return onLine end
	return getNearestGridPointToMidpoint(startPoint, endPoint, grid)
end

local function splitWallAtPoint(plotInfo: any, wall: WallInfo, splitPoint: Vector2int16): (boolean, Formex.WallData?, Formex.WallData?)
	if not plotInfo.PlotPart or not wall.Part then return false end
	local baseData = getWallDataFromPlot(plotInfo, wall.Level, wall.WallId)
	if not baseData then return false end
	local distance = (Vector2.new(splitPoint.X - baseData.Start.X, splitPoint.Y - baseData.Start.Y)).Magnitude
	local halves = Formex.Walls.Divide(baseData, distance)
	if not halves or #halves < 2 then
		return false
	end

	local editedWall = halves[1]
	local addedWall = halves[2]
	editedWall.Part = nil
	addedWall.Part = nil

	local previewA = createWallPreview(plotInfo.PlotPart, editedWall)
	local previewB = createWallPreview(plotInfo.PlotPart, addedWall)

	local results = runBuildTransaction({
		{
			PartType = Formex.PartType.Wall,
			Action = Formex.BuildAction.Edit,
			Data = editedWall,
		},
		{
			PartType = Formex.PartType.Wall,
			Action = Formex.BuildAction.Add,
			Data = addedWall,
		},
	}, getSelectionSnapshot())
	if not results then
		if previewA then previewA:Destroy() end
		if previewB then previewB:Destroy() end
		return false
	end

	return true, results[1] and results[1].Result or nil, results[2] and results[2].Result or nil
end

local function splitWallsAtPoints(plotInfo: any, level: number, points: {Vector2int16}, ignoreIds: {[number]: boolean})
	local walls = getLevelWallInfos(plotInfo, level)
	local splitWalls: {[number]: boolean} = {}
	for _, point in ipairs(points) do
		for _, wall in ipairs(walls) do
			if splitWalls[wall.WallId] then
				continue
			end
			if ignoreIds and ignoreIds[wall.WallId] then
				continue
			end
			if isPointOnSegment(point, wall.Start, wall.End) then
				local ok = splitWallAtPoint(plotInfo, wall, point)
				if not ok then
					cancelAction()
				end
				splitWalls[wall.WallId] = true
				break
			end
		end
	end
end

local function beginWall(plotInfo: any, startPoint: Vector2int16)
	if not plotInfo.PlotPart then return end
	if not isPointInOwnedSegments(plotInfo, Vector2.new(startPoint.X, startPoint.Y)) then
		updateGhostValidity(false)
		return
	end

	clearGhost()
	clearSelection()
	wallStart = startPoint
	wallBuildMode = "Pending"
	setActionType(Enums.ActionType.Step)
	lastPreviewPoint = nil
	ensureWallGhost(plotInfo.PlotPart, startPoint, startPoint)
	notifyDesignModeChange()
end

local function beginWallAtPosition(plotInfo: any, startPosition: Vector3)
	local startPoint = getSnappedPoint(plotInfo.PlotPart, startPosition)
	beginWall(plotInfo, startPoint)
end

local function onWallExtendStart()
	local input = getLastInputInfo()
	if selectedWall and input then
		beginWall(input.PlotInfo, selectedWall.Start)
	end
end

local function onWallExtendEnd()
	local input = getLastInputInfo()
	if selectedWall and input then
		beginWall(input.PlotInfo, selectedWall.End)
	end
end

local function onWallDelete()
	if not selectedWall then return end

	local deleteData = {
		WallId = selectedWall.WallId,
		Level = selectedWall.Level,
		Start = selectedWall.Start,
		End = selectedWall.End,
		Part = nil,
	}
	local ok = safeBuildWall(deleteData, Formex.BuildAction.Delete)
	if not ok then
		cancelAction()
		return
	end
	clearSelection()
end

local function onWallFlip()
	local input = getLastInputInfo()
	if not selectedWall or not input or not input.PlotInfo or not input.PlotInfo.PlotPart then return end
	local wallModel = selectedWall.Part
	if not wallModel then return end
	local wallData = getWallDataFromPlot(input.PlotInfo, selectedWall.Level, selectedWall.WallId)
	if not wallData then return end
	wallData = table.clone(wallData)
	wallData.Start = selectedWall.End
	wallData.End = selectedWall.Start
	wallData.Part = nil

	buildWall(wallData, Formex.BuildAction.Edit, getSelectionSnapshot())

	selectedWall.Start = wallData.Start
	selectedWall.End = wallData.End
	Walls.UpdateHandles(input.PlotInfo)
	notifyDesignModeChange()
end

local function selectWallByIdAsync(plotInfo: any, levelIndex: number, wallId: number)
	selectPlotModelByIdAsync(plotInfo, Enums.SelectionType.Wall, levelIndex, wallId)
end

local function onWallDivide()
	local input = getLastInputInfo()
	if not selectedWall or not input or not input.PlotInfo or not input.PlotInfo.PlotPart then return end
	local startPoint = selectedWall.Start
	local endPoint = selectedWall.End
	local selectedLevel = selectedWall.Level
	if not hasWallSplitRoom(startPoint, endPoint) then return end
	local splitPoint = getWallSplitPoint(startPoint, endPoint)

	local ok, resultA, resultB = splitWallAtPoint(input.PlotInfo, {
		WallId = selectedWall.WallId,
		Level = selectedWall.Level,
		Start = startPoint,
		End = endPoint,
		Part = selectedWall.Part,
	}, splitPoint)

	if not ok then
		cancelAction()
		return
	end

	clearSelection()
	notifyDesignModeChange()

	local resultWallId = getResultWallId(resultB or resultA)
	if resultWallId then
		selectWallByIdAsync(input.PlotInfo, selectedLevel, resultWallId)
	end
end

local function resetMoveState()
	activeWallHandle = nil
	moveWallOriginal = nil
	moveWallOriginals = {}
	moveWallConnections = {
		Start = {},
		End = {},
	}
	moveWallUpdated = {}
	movePreviewStart = nil
	movePreviewEnd = nil
	moveDragOriginLocal = nil
	Highlight.ClearMergeEdgePreview()
end

local function setWallHandlesVisible(visible: boolean)
	for _, handle in ipairs({
		wallHandleStart,
		wallHandleEnd,
		wallHandleCenter,
		wallHandleStartSolo,
		wallHandleEndSolo,
		wallHandleExtendStart,
		wallHandleExtendEnd,
		wallHandleDelete,
		wallHandleFlip,
		wallHandleDivide,
	}) do
		Handles.SetHandleVisible(handle, visible)
	end
end

local function onWallMove(handleType: WallHandleType)
	local input = getLastInputInfo()
	if not selectedWall or not input or not input.PlotInfo.PlotPart then return end
	activeWallHandle = handleType
	wallBuildMode = nil
	moveWallOriginal = {
		WallId = selectedWall.WallId,
		Level = selectedWall.Level,
		Start = selectedWall.Start,
		End = selectedWall.End,
		Part = selectedWall.Part,
	}
	moveWallOriginals = {}
	moveWallConnections = {
		Start = {},
		End = {},
	}
	movePreviewStart = selectedWall.Start
	movePreviewEnd = selectedWall.End
	moveDragOriginLocal = nil

	if handleType == "Center" and input.HitPosition then
		moveDragOriginLocal = getLocalXZ(input.PlotInfo.PlotPart, input.HitPosition)
	end

	setActionType(Enums.ActionType.Move)
	lastPreviewPoint = nil
	setWallHandlesVisible(false)
	clearGhost()

	local walls = getLevelWallInfos(input.PlotInfo, selectedWall.Level)
	local connectedAtStart = getConnectedWallsAtPoint(walls, selectedWall.Start, selectedWall.WallId)
	local connectedAtEnd = getConnectedWallsAtPoint(walls, selectedWall.End, selectedWall.WallId)

	moveWallOriginals[selectedWall.WallId] = {
		WallId = selectedWall.WallId,
		Level = selectedWall.Level,
		Start = selectedWall.Start,
		End = selectedWall.End,
		Part = selectedWall.Part,
	}

	for _, connected in ipairs(connectedAtStart) do
		moveWallOriginals[connected.Wall.WallId] = connected.Wall
	end
	for _, connected in ipairs(connectedAtEnd) do
		moveWallOriginals[connected.Wall.WallId] = connected.Wall
	end

	if handleType == "Start" or handleType == "Center" then
		moveWallConnections.Start = connectedAtStart
	end
	if handleType == "End" or handleType == "Center" then
		moveWallConnections.End = connectedAtEnd
	end

	notifyDesignModeChange()
end

local function updateWallHandles(plotInfo: any)
	if getDesignMode() ~= Enums.DesignMode.Wall
	or getActionType() ~= Enums.ActionType.Select
	or getSelectionType() ~= Enums.SelectionType.Wall
	or not plotInfo
	or not plotInfo.PlotPart then
		Walls.ClearSelection()
		return
	end

	local wallData = getSelectionData()
	if not wallData or not wallData.Part then
		Walls.ClearSelection()
		return
	end

	local wallModel = wallData.Part
	local startPoint = wallData.Start
	local endPoint = wallData.End
	if not startPoint or not endPoint then
		Walls.ClearSelection()
		return
	end
	selectedWall = {
		WallId = wallData.WallId,
		Level = wallData.Level,
		Start = startPoint,
		End = endPoint,
		Part = wallModel,
	}
	Highlight.UpdateWallEdgePreview(plotInfo, wallData.Level, startPoint, endPoint, true)

	local canSplit = hasWallSplitRoom(startPoint, endPoint)
	local splitPoint = getWallSplitPoint(startPoint, endPoint)
	local isPerfectSplit = isPointOnSegment(splitPoint, startPoint, endPoint)
	local divideHandleColor = isPerfectSplit and Constants.HandleAddColor or Constants.HandleDeleteColor

	wallHandleStart = Handles.CreateHandle("WallHandleStart", Constants.HandleMoveColor, Formex.Icons.ResizeItem, onWallMove, "Start")
	wallHandleEnd = Handles.CreateHandle("WallHandleEnd", Constants.HandleMoveColor, Formex.Icons.ResizeItem, onWallMove, "End")
	wallHandleCenter = Handles.CreateHandle("WallHandleCenter", Constants.HandleMoveColor, Formex.Icons.MoveItem, onWallMove, "Center")
	wallHandleStartSolo = Handles.CreateHandle("WallHandleStartSolo", Constants.HandleDisconnectColor, Formex.Icons.WallDisconnect, onWallMove, "StartSolo")
	wallHandleEndSolo = Handles.CreateHandle("WallHandleEndSolo", Constants.HandleDisconnectColor, Formex.Icons.WallDisconnect, onWallMove, "EndSolo")
	wallHandleExtendStart = Handles.CreateHandle("WallHandleExtendStart", Constants.HandleAddColor, Formex.Icons.WallExtend, onWallExtendStart)
	wallHandleExtendEnd = Handles.CreateHandle("WallHandleExtendEnd", Constants.HandleAddColor, Formex.Icons.WallExtend, onWallExtendEnd)
	wallHandleDelete = Handles.CreateHandle("WallHandleDelete", Constants.HandleDeleteColor, Formex.Icons.DeleteItem, onWallDelete)
	wallHandleFlip = Handles.CreateHandle("WallHandleFlip", Constants.HandleFlipColor, Formex.Icons.DirectionIndicator, onWallFlip)
	wallHandleDivide = Handles.CreateHandle("WallHandleDivide", divideHandleColor, Formex.Icons.WallDivide, onWallDivide)

	local viewSettings = getViewSettings()
	local handleY = getWallHandleY(wallData.Level, viewSettings.HandleLocation or Enums.HandleLocation.Middle)
	local function toWorld(point: Vector2)
		return plotInfo.PlotPart.CFrame:PointToWorldSpace(Vector3.new(point.X, handleY, point.Y))
	end

	local offset = getPerpOffset(startPoint, endPoint, Constants.HandleOffset)
	local extendOffset = Vector2.new(-offset.X, -offset.Y)
	local frontNormal = getPerpOffset(startPoint, endPoint, 1)
	local startPoint2 = Vector2.new(startPoint.X, startPoint.Y)
	local endPoint2 = Vector2.new(endPoint.X, endPoint.Y)
	local midPoint = Vector2.new((startPoint.X + endPoint.X) / 2, (startPoint.Y + endPoint.Y) / 2)
	local dividePoint = Vector2.new(splitPoint.X, splitPoint.Y)

	wallHandleStart.Position = toWorld(startPoint2)
	wallHandleEnd.Position = toWorld(endPoint2)
	wallHandleCenter.Position = toWorld(midPoint)
	wallHandleStartSolo.Position = toWorld(startPoint2)
	wallHandleEndSolo.Position = toWorld(endPoint2)
	wallHandleExtendStart.Position = toWorld(startPoint2 + extendOffset)
	wallHandleExtendEnd.Position = toWorld(endPoint2 + extendOffset)
	local deletePosition = toWorld(Vector2.new(midPoint.X, math.min(startPoint.Y, endPoint.Y) - Constants.HandleOffset * 2))
	wallHandleDelete.Position = deletePosition - Vector3.new(0, wallHandleDelete.Size.Y / 2, 0)
	wallHandleFlip.Position = toWorld(midPoint + offset)
	wallHandleDivide.Position = toWorld(dividePoint - offset)
	local frontWorld = plotInfo.PlotPart.CFrame:VectorToWorldSpace(Vector3.new(frontNormal.X, 0, frontNormal.Y))
	setHandleIconRotation(wallHandleFlip, getScreenRotationForDirection(frontWorld))

	setWallHandlesVisible(true)

	local editMode = getEditMode()
	local showPointHandles = editMode == Enums.EditMode.PointMove
	local showDisconnectHandles = editMode == Enums.EditMode.DisconnectMove
	local showPartHandle = editMode == Enums.EditMode.PartMove

	Handles.SetHandleVisible(wallHandleStart, showPointHandles)
	Handles.SetHandleVisible(wallHandleEnd, showPointHandles)
	Handles.SetHandleVisible(wallHandleCenter, showPartHandle)

	local walls = getLevelWallInfos(plotInfo, level)
	local connectedAtStart = getConnectedWallsAtPoint(walls, startPoint, wallId)
	local connectedAtEnd = getConnectedWallsAtPoint(walls, endPoint, wallId)
	Handles.SetHandleVisible(wallHandleStartSolo, showDisconnectHandles and #connectedAtStart > 0)
	Handles.SetHandleVisible(wallHandleEndSolo, showDisconnectHandles and #connectedAtEnd > 0)
	Handles.SetHandleVisible(wallHandleDivide, canSplit)
end

local function updateWallHandleHover(input: any)
	if getDesignMode() ~= Enums.DesignMode.Wall or getActionType() ~= Enums.ActionType.Select then
		Handles.ClearHandleHover()
		return
	end

	Handles.CheckHover(input.Ray)
end

local function updateWallGhost(input: any)
	if not wallStart then return end
	if not input.SnapPoint or not input.PlotInfo.PlotPart then return end
	local endPoint = input.SnapPoint
	local snappedEndPoint = snapWallEndPoint(wallStart, Vector2.new(endPoint.X, endPoint.Y))
	if input.ActionHeld
	and (snappedEndPoint.X ~= wallStart.X or snappedEndPoint.Y ~= wallStart.Y) then
		wallBuildMode = "Drag"
	end
	if lastPreviewPoint and snappedEndPoint == lastPreviewPoint then return end
	lastPreviewPoint = snappedEndPoint

	ensureWallGhost(input.PlotInfo.PlotPart, wallStart, snappedEndPoint)

	local previewData = buildWallData(wallStart, snappedEndPoint)
	local validation = Formex.IsTransactionValid(input.PlotInfo.PlotData, {
		{
			PartType = Formex.PartType.Wall,
			Action = Formex.BuildAction.Add,
			Data = previewData,
		},
	})
	local valid = validation ~= nil and validation.IsValid == true
	updateGhostValidity(valid)
	updateMergePreview(input.PlotInfo, getCurrentLevel(), validation)
end

local function updateWallStartGhost(input: any)
	if not input.SnapPoint or not input.PlotInfo.PlotPart then return end
	local startPoint = input.SnapPoint
	if lastPreviewPoint and startPoint == lastPreviewPoint then return end
	lastPreviewPoint = startPoint

	ensureWallGhost(input.PlotInfo.PlotPart, startPoint, startPoint)
	updateGhostValidity(isPointInOwnedSegments(input.PlotInfo, Vector2.new(startPoint.X, startPoint.Y)))
	Highlight.ClearMergeEdgePreview()
end

local function updateWallMoveGhost(input: any)
	if not moveWallOriginal or not input.PlotInfo.PlotPart then return end
	local startPoint = moveWallOriginal.Start
	local endPoint = moveWallOriginal.End
	local newStart = startPoint
	local newEnd = endPoint

	if activeWallHandle == "Center" then
		if not input.HitPosition or not moveDragOriginLocal then return end
		local currentLocal = getLocalXZ(input.PlotInfo.PlotPart, input.HitPosition)
		local delta = currentLocal - moveDragOriginLocal
		local startRaw = Vector2.new(startPoint.X + delta.X, startPoint.Y + delta.Y)
		local endRaw = Vector2.new(endPoint.X + delta.X, endPoint.Y + delta.Y)
		newStart = toSnappedVector2int16(startRaw)
		newEnd = toSnappedVector2int16(endRaw)
	else
		if not input.SnapPoint then return end
		local rawPoint = Vector2.new(input.SnapPoint.X, input.SnapPoint.Y)
		if activeWallHandle == "Start" or activeWallHandle == "StartSolo" then
			local snapped = snapWallEndPoint(Vector2.new(endPoint.X, endPoint.Y), rawPoint)
			newStart = toSnappedVector2int16(snapped)
			newEnd = endPoint
		elseif activeWallHandle == "End" or activeWallHandle == "EndSolo" then
			local snapped = snapWallEndPoint(Vector2.new(startPoint.X, startPoint.Y), rawPoint)
			newStart = startPoint
			newEnd = toSnappedVector2int16(snapped)
		end
	end

	movePreviewStart = newStart
	movePreviewEnd = newEnd

	local updatedWalls: {[number]: WallInfo} = {}
	local function setUpdatedWall(wallId: number, startValue: Vector2int16, endValue: Vector2int16)
		local original = moveWallOriginals[wallId]
		if not original then return end
		updatedWalls[wallId] = {
			WallId = original.WallId,
			Level = original.Level,
			Start = startValue,
			End = endValue,
			Part = original.Part,
		}
	end

	setUpdatedWall(moveWallOriginal.WallId, newStart, newEnd)

	if activeWallHandle == "Center" then
		local deltaX = newStart.X - startPoint.X
		local deltaY = newStart.Y - startPoint.Y
		for _, connected in ipairs(moveWallConnections.Start) do
			local original = moveWallOriginals[connected.Wall.WallId]
			if original then
				local newPoint = Vector2int16.new(original.Start.X + deltaX, original.Start.Y + deltaY)
				if connected.EndType == "End" then
					newPoint = Vector2int16.new(original.End.X + deltaX, original.End.Y + deltaY)
				end
				local base = updatedWalls[connected.Wall.WallId] or original
				local startValue = base.Start
				local endValue = base.End
				if connected.EndType == "Start" then
					startValue = newPoint
				else
					endValue = newPoint
				end
				setUpdatedWall(connected.Wall.WallId, startValue, endValue)
			end
		end
		for _, connected in ipairs(moveWallConnections.End) do
			local original = moveWallOriginals[connected.Wall.WallId]
			if original then
				local newPoint = Vector2int16.new(original.Start.X + deltaX, original.Start.Y + deltaY)
				if connected.EndType == "End" then
					newPoint = Vector2int16.new(original.End.X + deltaX, original.End.Y + deltaY)
				end
				local base = updatedWalls[connected.Wall.WallId] or original
				local startValue = base.Start
				local endValue = base.End
				if connected.EndType == "Start" then
					startValue = newPoint
				else
					endValue = newPoint
				end
				setUpdatedWall(connected.Wall.WallId, startValue, endValue)
			end
		end
	else
		for _, connected in ipairs(moveWallConnections.Start) do
			setUpdatedWall(connected.Wall.WallId,
				connected.EndType == "Start" and newStart or connected.Wall.Start,
				connected.EndType == "End" and newStart or connected.Wall.End)
		end
		for _, connected in ipairs(moveWallConnections.End) do
			setUpdatedWall(connected.Wall.WallId,
				connected.EndType == "Start" and newEnd or connected.Wall.Start,
				connected.EndType == "End" and newEnd or connected.Wall.End)
		end
	end

	for _, wall in pairs(updatedWalls) do
		applyWallTransform(input.PlotInfo, wall)
	end
	moveWallUpdated = updatedWalls

	local wallBatch = {}
	for _, wall in pairs(updatedWalls) do
		table.insert(wallBatch, {
			WallId = wall.WallId,
			Level = wall.Level,
			Start = wall.Start,
			End = wall.End,
		})
	end

	local validation = Formex.IsTransactionValid(input.PlotInfo.PlotData, {
		{
			PartType = Formex.PartType.Wall,
			Action = Formex.BuildAction.Edit,
			Data = wallBatch,
		},
	})
	local valid = validation ~= nil and validation.IsValid == true
	updateGhostValidity(valid)
	Highlight.UpdateWallEdgePreview(input.PlotInfo, moveWallOriginal.Level, newStart, newEnd, valid)
	updateMergePreview(input.PlotInfo, moveWallOriginal.Level, validation)
end

local function finalizeWall(plotInfo: any, endPosition: Vector3)
	if not wallStart or not plotInfo.PlotPart then return end
	local endPoint = getSnappedPoint(plotInfo.PlotPart, endPosition)
	local snappedEndPoint = snapWallEndPoint(wallStart, Vector2.new(endPoint.X, endPoint.Y))
	if isZeroLength(wallStart, snappedEndPoint) then
		cancelAction()
		return
	end
	local wallData = buildWallData(wallStart, snappedEndPoint)
	local validation = Formex.IsTransactionValid(plotInfo.PlotData, {
		{
			PartType = Formex.PartType.Wall,
			Action = Formex.BuildAction.Add,
			Data = wallData,
		},
	})
	if not validation or validation.IsValid ~= true then
		updateGhostValidity(false)
		updateMergePreview(plotInfo, getCurrentLevel(), validation)
		return
	end

	local preview = createWallPreview(plotInfo.PlotPart, wallData)
	local ok, result = safeBuildWall(wallData, Formex.BuildAction.Add)
	if not ok then
		if preview then
			preview:Destroy()
		end
		cancelAction()
		return
	end
	cancelAction()

	local resultWallId = getResultWallId(result)
	if resultWallId then
		local levelIndex = getCurrentLevel()
		local ignoreIds = { [resultWallId] = true }
		splitWallsAtPoints(plotInfo, levelIndex, { wallData.Start, wallData.End }, ignoreIds)
		selectWallByIdAsync(plotInfo, levelIndex, resultWallId)
	end
end

local function finalizeWallMove(plotInfo: any)
	if not moveWallOriginal or not movePreviewStart or not movePreviewEnd then return end
	local originalWall = moveWallOriginal

	local updates = moveWallUpdated
	if not updates or next(updates) == nil then
		updates = {
			[originalWall.WallId] = {
				WallId = originalWall.WallId,
				Level = originalWall.Level,
				Start = movePreviewStart,
				End = movePreviewEnd,
				Part = originalWall.Part,
			}
		}
	end

	local wallBatch = {}
	for _, wall in pairs(updates) do
		table.insert(wallBatch, {
			WallId = wall.WallId,
			Level = wall.Level,
			Start = wall.Start,
			End = wall.End,
			Part = nil,
		})
	end

	local validation = Formex.IsTransactionValid(plotInfo.PlotData, {
		{
			PartType = Formex.PartType.Wall,
			Action = Formex.BuildAction.Edit,
			Data = wallBatch,
		},
	})
	local valid = validation ~= nil and validation.IsValid == true
	if not valid then
		updateGhostValidity(false)
		updateMergePreview(plotInfo, originalWall.Level, validation)
		cancelAction()
		return
	end

	local selectedDeleted = false
	local deletedWalls = {}
	for _, wall in pairs(updates) do
		if isZeroLength(wall.Start, wall.End) then
			if wall.WallId == originalWall.WallId then
				selectedDeleted = true
			end
			table.insert(deletedWalls, wall)
		end
	end

	if #wallBatch == 0 then
		cancelAction()
		return
	end

	local ok = safeBuildWall(wallBatch, Formex.BuildAction.Edit)
	if not ok then
		cancelAction()
		return
	end

	local splitPoints = { movePreviewStart, movePreviewEnd }
	local splitLevel = originalWall.Level
	local ignoreIds: {[number]: boolean} = {}
	for wallId in pairs(updates) do
		ignoreIds[wallId] = true
	end

	if not selectedDeleted then
		selectedWall = {
			WallId = originalWall.WallId,
			Level = originalWall.Level,
			Start = movePreviewStart,
			End = movePreviewEnd,
			Part = originalWall.Part,
		}
	end
	resetMoveState()
	setActionType(Enums.ActionType.Select)
	clearGhost()
	if selectedDeleted then
		clearSelection()
	else
		updateWallHandles(plotInfo)
	end
	notifyDesignModeChange()
	splitWallsAtPoints(plotInfo, splitLevel, splitPoints, ignoreIds)
end

local function handleWallUpdate(input: any)
	if not input.PlotInfo.PlotPart then return end
	local actionType = getActionType()
	if actionType == Enums.ActionType.Start then
		updateWallStartGhost(input)
	elseif actionType == Enums.ActionType.Step then
		updateWallGhost(input)
	elseif actionType == Enums.ActionType.Move then
		updateWallMoveGhost(input)
	elseif isGhostActive() and getGhostType() == Formex.PartType.Wall then
		clearGhost()
	end
end

function Walls.ClearSelection()
	selectedWall = nil
	Handles.ClearHandleHover()
	Handles.Clear()
	Highlight.ClearFloorEdgePreview()
	Highlight.ClearMergeEdgePreview()
	Highlight.UpdateSelectionHighlight()
end

function Walls.UpdateHandles(plotInfo: any)
	updateWallHandles(plotInfo)
	Highlight.UpdateSelectionHighlight()
end

function Walls.StartWall()
	if getActionType() ~= Enums.ActionType.Select then
		cancelAction()
	end

	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid or not plotInfo.PlotPart then return end
	setActionType(Enums.ActionType.Start)
	wallStart = nil
	wallBuildMode = nil
	lastPreviewPoint = nil
	clearGhost()
	clearSelection()
	notifyDesignModeChange()
end

function Walls.CancelAction()
	if getActionType() == Enums.ActionType.Move then
		local plotInfo = FormexClient.CurrentPlot
		if plotInfo and plotInfo.IsValid and plotInfo.PlotPart then
			for _, wall in pairs(moveWallOriginals) do
				applyWallTransform(plotInfo, wall)
			end
		end
	end

	wallStart = nil
	wallBuildMode = nil
	lastPreviewPoint = nil
	resetMoveState()
end

function Walls.HandleUpdate(input: any)
	if getActionType() == Enums.ActionType.Select then
		updateWallHandles(input.PlotInfo)
		updateWallHandleHover(input)
		if isGhostActive() and getGhostType() == Formex.PartType.Wall then
			clearGhost()
		end
	else
		handleWallUpdate(input)
	end
end

function Walls.HandlePrimaryRelease(input: any)
	local actionType = getActionType()
	if actionType == Enums.ActionType.Step and input.HitPosition then
		if wallBuildMode == "Pending" then
			wallBuildMode = "Click"
			return
		end
		finalizeWall(input.PlotInfo, input.HitPosition)
		return
	end

	if actionType == Enums.ActionType.Move then
		finalizeWallMove(input.PlotInfo)
	end
end

function Walls.HandlePrimaryClick(input: any)
	local actionType = getActionType()
	if actionType == Enums.ActionType.Select then
		local selectionType = getSelectionType()
		local selectionData = getSelectionData()
		local hadSelection = selectionType ~= Enums.SelectionType.None
		if hadSelection
			and selectionType == Enums.SelectionType.Wall
			and input.WallData
			and selectionData
			and input.WallData == selectionData then
			return
		end

		local selected = select(input)
		if selected then return end
		if hadSelection then
			clearSelection()
		else
			Walls.StartWall()
		end
		return
	end

	if actionType == Enums.ActionType.Start then
		if input.HitPosition then
			beginWallAtPosition(input.PlotInfo, input.HitPosition)
		end
	end
end

return Walls
