--!strict
--[[
FormexDesignWalls
Handles wall design actions (placement, handles, paint/dropper).
Exports:
- Init(): load shared dependencies
- ApplyPaintToTarget(target, hitPosition): boolean
- CopyPaintFromTarget(target, hitPosition): boolean
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
local Workspace = game:GetService("Workspace")
local Context = require(script.Parent:WaitForChild("FormexDesignContext"))

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
local getCurrentLevel: () -> number
local getViewSettings: () -> any
local getSelectionType: () -> string
local getSelectionPart: () -> Instance?
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
local select: (Instance) -> boolean
local getSelectionInfoFromInstance: (Instance?) -> (string?, number?, number?)
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
	getCurrentLevel = ctx.GetCurrentLevel
	getViewSettings = ctx.GetViewSettings
	getSelectionType = ctx.GetSelectionType
	getSelectionPart = ctx.GetSelectionPart
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
	getSelectionInfoFromInstance = ctx.GetSelectionInfoFromInstance
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

local function getWallFrontPart(instance: Instance?): BasePart?
	if not instance then
		return nil
	end
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		if instance.PrimaryPart then
			return instance.PrimaryPart
		end
		local frontName = Formex.Walls and Formex.Walls.FrontPartName or "Front"
		local frontPart = instance:FindFirstChild(frontName)
		if frontPart and frontPart:IsA("BasePart") then
			return frontPart
		end
		for _, child in ipairs(instance:GetChildren()) do
			if child:IsA("BasePart") then
				return child
			end
		end
	end
	return nil
end

local function getWallEndpoints(wallModel: Model): (Vector2int16, Vector2int16)
	local startValue = wallModel:GetAttribute("Start") or Vector2.new(0, 0)
	local endValue = wallModel:GetAttribute("End") or Vector2.new(0, 0)
	local startPoint = Vector2int16.new(math.round(startValue.X), math.round(startValue.Y))
	local endPoint = Vector2int16.new(math.round(endValue.X), math.round(endValue.Y))
	return startPoint, endPoint
end

local function getLevelWallInfos(plotPart: BasePart, level: number): {WallInfo}
	local results = {}
	local levelPart = plotPart:FindFirstChild(tostring(level))
	if not levelPart then
		return results
	end

	local wallsFolder = levelPart:FindFirstChild("Walls")
	if not wallsFolder then
		return results
	end

	for _, child in ipairs(wallsFolder:GetChildren()) do
		if child:IsA("Model") then
			local wallId = tonumber(child.Name)
			local frontPart = getWallFrontPart(child)
			if wallId and frontPart then
				local startPoint, endPoint = getWallEndpoints(child)
				table.insert(results, {
					WallId = wallId,
					Level = level,
					Start = startPoint,
					End = endPoint,
					Part = child,
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

local function getHandleIcon(handle: BasePart?): ImageLabel?
	if not handle then
		return nil
	end

	local billboard = handle:FindFirstChild("HandleBillboard")
	if not billboard or not billboard:IsA("BillboardGui") then
		return nil
	end

	local icon = billboard:FindFirstChild("Icon")
	if icon and icon:IsA("ImageLabel") then
		return icon
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
	if not camera then
		return 0
	end

	local right = camera.CFrame.RightVector
	local up = camera.CFrame.UpVector
	local x = direction:Dot(right)
	local y = direction:Dot(up)
	if math.abs(x) <= Constants.Epsilon and math.abs(y) <= Constants.Epsilon then
		return 0
	end
	return math.deg(math.atan2(x, y))
end

local function getModelBottomCenter(model: Model): Vector3
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	return boundsCFrame.Position - Vector3.new(0, boundsSize.Y / 2, 0)
end

local function isZeroLength(startPoint: Vector2int16, endPoint: Vector2int16): boolean
	return startPoint.X == endPoint.X and startPoint.Y == endPoint.Y
end

local function safeBuildWall(wallData: any, action: any): (boolean, any)
	local ok, result = pcall(FormexClient.BuildWall, wallData, action, getSelectionSnapshot())
	if not ok then
		warn("FormexClient.BuildWall failed:", result)
		return false, nil
	end
	return true, result
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

local function getWallBackPart(model: Model): BasePart?
	local backPartName = Formex.Walls and Formex.Walls.BackPartName or "BackSide"
	local backPart = model:FindFirstChild(backPartName)
	if backPart and backPart:IsA("BasePart") then
		return backPart
	end
	return nil
end

local function getWallModelFromInstance(instance: Instance?): Model?
	if not instance then
		return nil
	end
	if instance:IsA("Model") and instance.Parent and instance.Parent:IsA("Folder") and instance.Parent.Name == "Walls" then
		return instance
	end
	local model = instance:FindFirstAncestorOfClass("Model")
	if model and model.Parent and model.Parent:IsA("Folder") and model.Parent.Name == "Walls" then
		return model
	end
	return nil
end

local function getWallSideFromTarget(target: Instance, hitPosition: Vector3?): (Model?, WallSide?)
	local model = getWallModelFromInstance(target)
	if not model then
		return nil, nil
	end

	local backPartName = Formex.Walls and Formex.Walls.BackPartName or "BackSide"
	local backPart = model:FindFirstChild(backPartName)
	if backPart and (target == backPart or target:IsDescendantOf(backPart)) then
		return model, "Back"
	end

	local backTop = model:FindFirstChild("BackTop")
	if backTop and (target == backTop or target:IsDescendantOf(backTop)) then
		return model, "Back"
	end

	local frontTop = model:FindFirstChild("FrontTop")
	if frontTop and (target == frontTop or target:IsDescendantOf(frontTop)) then
		return model, "Front"
	end

	if hitPosition then
		local frontPart = getWallFrontPart(model)
		local backSide = getWallBackPart(model)
		if frontPart and backSide then
			local center = (frontPart.Position + backSide.Position) * 0.5
			local right = frontPart.CFrame.RightVector
			local offset = hitPosition - center
			local dot = offset:Dot(right)
			if math.abs(dot) > Constants.Epsilon then
				if dot > 0 then
					return model, "Back"
				else
					return model, "Front"
				end
			end
		end
	end

	return model, "Front"
end

local function getWallTopPart(model: Model, name: string): BasePart?
	local child = model:FindFirstChild(name)
	if child and child:IsA("BasePart") then
		return child
	end
	return nil
end

local function getWallDataFromPart(wallModel: Model, wallId: number, level: number): Formex.WallData
	local startPoint, endPoint = getWallEndpoints(wallModel)
	local frontPart = getWallFrontPart(wallModel)
	local backPart = getWallBackPart(wallModel)
	local frontTopPart = getWallTopPart(wallModel, "FrontTop")
	local backTopPart = getWallTopPart(wallModel, "BackTop")

	local height = wallModel:GetAttribute("WallHeight") or Formex.LevelHeight
	local frontSplitHeight = wallModel:GetAttribute("FrontSplitHeight") or 0
	local backSplitHeight = wallModel:GetAttribute("BackSplitHeight") or 0

	local frontTopMaterial = wallModel:GetAttribute("FrontTopMaterial") or Formex.DefaultWallMaterial
	local frontBottomMaterial = wallModel:GetAttribute("FrontBottomMaterial") or frontTopMaterial
	local backTopMaterial = wallModel:GetAttribute("BackTopMaterial") or frontTopMaterial
	local backBottomMaterial = wallModel:GetAttribute("BackBottomMaterial") or backTopMaterial

	local frontTopColor = wallModel:GetAttribute("FrontTopColor") or Color3.new(1, 1, 1)
	local frontBottomColor = wallModel:GetAttribute("FrontBottomColor") or frontTopColor
	local backTopColor = wallModel:GetAttribute("BackTopColor") or frontTopColor
	local backBottomColor = wallModel:GetAttribute("BackBottomColor") or backTopColor

	return {
		WallId = wallId,
		Level = level,
		Start = startPoint,
		End = endPoint,
		Height = height,
		FrontSplitHeight = frontSplitHeight,
		BackSplitHeight = backSplitHeight,
		FrontTopMaterial = frontTopMaterial,
		FrontBottomMaterial = frontBottomMaterial,
		BackTopMaterial = backTopMaterial,
		BackBottomMaterial = backBottomMaterial,
		FrontTopColor = frontTopColor,
		FrontBottomColor = frontBottomColor,
		BackTopColor = backTopColor,
		BackBottomColor = backBottomColor,
		Part = wallModel,
		FrontPart = frontPart,
		BackPart = backPart,
		FrontTopPart = frontTopPart,
		BackTopPart = backTopPart,
	}
end

function Walls.GetSelectedWallData(): Formex.WallData?
	local selectionPart = getSelectionPart()
	local wallModel = getWallModelFromInstance(selectionPart)
	if not wallModel then
		return nil
	end

	local level = tonumber(wallModel.Parent.Parent.Name) or getCurrentLevel()
	local wallId = tonumber(wallModel.Name) or 0
	return getWallDataFromPart(wallModel, wallId, level)
end

local function applyWallAppearance(plotInfo: any, wallModel: Model, overrides: {[string]: any})
	if not plotInfo or not plotInfo.PlotPart then
		return
	end

	local wallId = tonumber(wallModel.Name) or 0
	local level = tonumber(wallModel.Parent.Parent.Name) or getCurrentLevel()
	local current = getWallDataFromPart(wallModel, wallId, level)

	local height = current.Height
	if overrides.Height ~= nil then
		height = overrides.Height == false and nil or overrides.Height
	end

	local frontSplitHeight = current.FrontSplitHeight
	if overrides.FrontSplitHeight ~= nil then
		frontSplitHeight = overrides.FrontSplitHeight == false and 0 or overrides.FrontSplitHeight
	end

	local backSplitHeight = current.BackSplitHeight
	if overrides.BackSplitHeight ~= nil then
		backSplitHeight = overrides.BackSplitHeight == false and 0 or overrides.BackSplitHeight
	end

	local updated = {
		WallId = current.WallId,
		Level = current.Level,
		Start = current.Start,
		End = current.End,
		Height = height,
		FrontSplitHeight = frontSplitHeight,
		BackSplitHeight = backSplitHeight,
		FrontTopMaterial = overrides.FrontTopMaterial or current.FrontTopMaterial,
		FrontBottomMaterial = overrides.FrontBottomMaterial or current.FrontBottomMaterial,
		BackTopMaterial = overrides.BackTopMaterial or current.BackTopMaterial,
		BackBottomMaterial = overrides.BackBottomMaterial or current.BackBottomMaterial,
		FrontTopColor = overrides.FrontTopColor or current.FrontTopColor,
		FrontBottomColor = overrides.FrontBottomColor or current.FrontBottomColor,
		BackTopColor = overrides.BackTopColor or current.BackTopColor,
		BackBottomColor = overrides.BackBottomColor or current.BackBottomColor,
		Part = wallModel,
	}

	Formex.Walls.Edit(updated, plotInfo.PlotPart)
	local serverData = table.clone(updated)
	serverData.Part = nil
	FormexClient.BuildWall(serverData, Formex.BuildAction.Edit, getSelectionSnapshot())
end

function Walls.ApplySelectedAppearance(overrides: {[string]: any}): boolean
	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid or not plotInfo.PlotPart then
		return false
	end

	local wallModel = getWallModelFromInstance(getSelectionPart())
	if not wallModel then
		return false
	end

	applyWallAppearance(plotInfo, wallModel, overrides)
	return true
end

function Walls.ApplyPaintToTarget(target: Instance, hitPosition: Vector3?): boolean
	local wallModel, side = getWallSideFromTarget(target, hitPosition)
	if not wallModel or not side then
		return false
	end

	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid then
		return false
	end

	local paintSettings = getWallPaintSettings() :: WallPaintSettings
	local overrides = {
		Height = paintSettings.Height == nil and false or paintSettings.Height,
	}

	if side == "Front" then
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

	applyWallAppearance(plotInfo, wallModel, overrides)
	return true
end

function Walls.CopyPaintFromTarget(target: Instance, hitPosition: Vector3?): boolean
	local wallModel, side = getWallSideFromTarget(target, hitPosition)
	if not wallModel or not side then
		return false
	end

	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid or not plotInfo.PlotPart then
		return false
	end

	local wallId = tonumber(wallModel.Name) or 0
	local level = tonumber(wallModel.Parent.Parent.Name) or getCurrentLevel()
	local appearance = getWallDataFromPart(wallModel, wallId, level)
	local splitHeight = side == "Front" and appearance.FrontSplitHeight or appearance.BackSplitHeight
	local topMaterial = side == "Front" and appearance.FrontTopMaterial or appearance.BackTopMaterial
	local bottomMaterial = side == "Front" and appearance.FrontBottomMaterial or appearance.BackBottomMaterial
	local topColor = side == "Front" and appearance.FrontTopColor or appearance.BackTopColor
	local bottomColor = side == "Front" and appearance.FrontBottomColor or appearance.BackBottomColor

	updateDesignState({
		Wall = {
			Height = appearance.Height == nil and false or appearance.Height,
			SplitHeight = splitHeight == nil and 0 or splitHeight,
			TopMaterial = topMaterial,
			BottomMaterial = bottomMaterial,
			TopColor = topColor,
			BottomColor = bottomColor,
		},
	})

	return true
end

local function applyWallTransform(plotPart: BasePart, wall: WallInfo)
	if not wall.Part then
		return
	end

	local wallData = getWallDataFromPart(wall.Part, wall.WallId, wall.Level)
	wallData.Start = wall.Start
	wallData.End = wall.End
	wallData.Part = wall.Part
	Formex.Walls.Edit(wallData, plotPart)
end

local function isPointOnSegment(point: Vector2int16, startPoint: Vector2int16, endPoint: Vector2int16): boolean
	if pointsEqual(point, startPoint) or pointsEqual(point, endPoint) then
		return false
	end

	local dx = endPoint.X - startPoint.X
	local dy = endPoint.Y - startPoint.Y
	local px = point.X - startPoint.X
	local py = point.Y - startPoint.Y
	local cross = (px * dy) - (py * dx)
	if math.abs(cross) > Constants.Epsilon then
		return false
	end

	local minX = math.min(startPoint.X, endPoint.X) - Constants.Epsilon
	local maxX = math.max(startPoint.X, endPoint.X) + Constants.Epsilon
	local minY = math.min(startPoint.Y, endPoint.Y) - Constants.Epsilon
	local maxY = math.max(startPoint.Y, endPoint.Y) + Constants.Epsilon
	return point.X >= minX and point.X <= maxX and point.Y >= minY and point.Y <= maxY
end

local function splitWallAtPoint(plotInfo: any, wall: WallInfo, splitPoint: Vector2int16): boolean
	if not plotInfo.PlotPart or not wall.Part then
		return false
	end

	local baseData = getWallDataFromPart(wall.Part, wall.WallId, wall.Level)
	local wallDataA = table.clone(baseData)
	wallDataA.WallId = 0
	wallDataA.Level = wall.Level
	wallDataA.Start = wall.Start
	wallDataA.End = splitPoint
	wallDataA.Part = nil

	local wallDataB = table.clone(baseData)
	wallDataB.WallId = 0
	wallDataB.Level = wall.Level
	wallDataB.Start = splitPoint
	wallDataB.End = wall.End
	wallDataB.Part = nil

	local previewA = createWallPreview(plotInfo.PlotPart, wallDataA)
	local previewB = createWallPreview(plotInfo.PlotPart, wallDataB)

	local deleteData = {
		WallId = wall.WallId,
		Level = wall.Level,
		Start = wall.Start,
		End = wall.End,
		Part = nil,
	}
	local ok = safeBuildWall(deleteData, Formex.BuildAction.Delete)
	if not ok then
		if previewA then previewA:Destroy() end
		if previewB then previewB:Destroy() end
		return false
	end

	ok = safeBuildWall(wallDataA, Formex.BuildAction.Add)
	if not ok then
		if previewA then previewA:Destroy() end
		if previewB then previewB:Destroy() end
		return false
	end

	ok = safeBuildWall(wallDataB, Formex.BuildAction.Add)
	if not ok then
		if previewA then previewA:Destroy() end
		if previewB then previewB:Destroy() end
		return false
	end

	return true
end

local function splitWallsAtPoints(plotInfo: any, level: number, points: {Vector2int16}, ignoreIds: {[number]: boolean})
	local walls = getLevelWallInfos(plotInfo.PlotPart, level)
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
	if not plotInfo.PlotPart then
		return
	end

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

	if selectedWall.Part and selectedWall.Part.Parent then
		selectedWall.Part:Destroy()
	end
	clearSelection()
end

local function onWallFlip()
	local input = getLastInputInfo()
	if not selectedWall or not input or not input.PlotInfo or not input.PlotInfo.PlotPart then
		return
	end

	local wallModel = selectedWall.Part
	if not wallModel then
		return
	end

	local wallData = getWallDataFromPart(wallModel, selectedWall.WallId, selectedWall.Level)
	wallData.Start = selectedWall.End
	wallData.End = selectedWall.Start
	wallData.Part = nil

	FormexClient.BuildWall(wallData, Formex.BuildAction.Edit, getSelectionSnapshot())

	selectedWall.Start = wallData.Start
	selectedWall.End = wallData.End
	Walls.UpdateHandles(input.PlotInfo)
	notifyDesignModeChange()
end

local function onWallDivide()
	local input = getLastInputInfo()
	if not selectedWall or not input or not input.PlotInfo or not input.PlotInfo.PlotPart then
		return
	end

	local startPoint = selectedWall.Start
	local endPoint = selectedWall.End
	local midpoint = Vector2.new((startPoint.X + endPoint.X) / 2, (startPoint.Y + endPoint.Y) / 2)
	local snapped = toSnappedVector2int16(midpoint)
	if not isPointOnSegment(snapped, startPoint, endPoint) then
		return
	end

	local ok = splitWallAtPoint(input.PlotInfo, {
		WallId = selectedWall.WallId,
		Level = selectedWall.Level,
		Start = startPoint,
		End = endPoint,
		Part = selectedWall.Part,
	}, snapped)

	if not ok then
		cancelAction()
		return
	end

	clearSelection()
	notifyDesignModeChange()
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
	if not selectedWall or not input or not input.PlotInfo.PlotPart then
		return
	end

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

	local walls = getLevelWallInfos(input.PlotInfo.PlotPart, selectedWall.Level)
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
	or not getSelectionPart()
	or not plotInfo
	or not plotInfo.PlotPart then
		Walls.ClearSelection()
		return
	end

	local selectionPart = getSelectionPart()
	local selectionKind, partId, level = getSelectionInfoFromInstance(selectionPart)
	if not selectionKind or selectionKind ~= Enums.SelectionType.Wall or not level then
		Walls.ClearSelection()
		return
	end

	local wallModel = selectionPart
	if wallModel and wallModel:IsA("BasePart") then
		local ancestor = wallModel:FindFirstAncestorOfClass("Model")
		if ancestor then
			wallModel = ancestor
		end
	end
	if not wallModel or not wallModel:IsA("Model") then
		Walls.ClearSelection()
		return
	end
	local frontPart = getWallFrontPart(wallModel)
	if not frontPart then
		Walls.ClearSelection()
		return
	end

	local startPoint, endPoint = getWallEndpoints(wallModel)
	local wallId = partId or tonumber(wallModel.Name) or 0
	selectedWall = {
		WallId = wallId,
		Level = level,
		Start = startPoint,
		End = endPoint,
		Part = wallModel,
	}
	Highlight.UpdateWallEdgePreview(plotInfo, level, startPoint, endPoint, true)

	wallHandleStart = Handles.CreateHandle("WallHandleStart", Constants.HandleMoveColor, Formex.Icons.ResizeItem, onWallMove, "Start")
	wallHandleEnd = Handles.CreateHandle("WallHandleEnd", Constants.HandleMoveColor, Formex.Icons.ResizeItem, onWallMove, "End")
	wallHandleCenter = Handles.CreateHandle("WallHandleCenter", Constants.HandleMoveColor, Formex.Icons.MoveItem, onWallMove, "Center")
	wallHandleStartSolo = Handles.CreateHandle("WallHandleStartSolo", Constants.HandleDisconnectColor, Formex.Icons.WallDisconnect, onWallMove, "StartSolo")
	wallHandleEndSolo = Handles.CreateHandle("WallHandleEndSolo", Constants.HandleDisconnectColor, Formex.Icons.WallDisconnect, onWallMove, "EndSolo")
	wallHandleExtendStart = Handles.CreateHandle("WallHandleExtendStart", Constants.HandleAddColor, Formex.Icons.WallExtend, onWallExtendStart)
	wallHandleExtendEnd = Handles.CreateHandle("WallHandleExtendEnd", Constants.HandleAddColor, Formex.Icons.WallExtend, onWallExtendEnd)
	wallHandleDelete = Handles.CreateHandle("WallHandleDelete", Constants.HandleDeleteColor, Formex.Icons.DeleteItem, onWallDelete)
	wallHandleFlip = Handles.CreateHandle("WallHandleFlip", Constants.HandleFlipColor, Formex.Icons.DirectionIndicator, onWallFlip)
	wallHandleDivide = Handles.CreateHandle("WallHandleDivide", Constants.HandleAddColor, Formex.Icons.WallDivide, onWallDivide)

	local viewSettings = getViewSettings()
	local handleY = getWallHandleY(level, viewSettings.HandleLocation or Enums.HandleLocation.Middle)
	local function toWorld(point: Vector2)
		return plotInfo.PlotPart.CFrame:PointToWorldSpace(Vector3.new(point.X, handleY, point.Y))
	end

	local offset = getPerpOffset(startPoint, endPoint, Constants.HandleOffset)
	local extendOffset = Vector2.new(-offset.X, -offset.Y)
	local frontNormal = getPerpOffset(startPoint, endPoint, 1)
	local startPoint2 = Vector2.new(startPoint.X, startPoint.Y)
	local endPoint2 = Vector2.new(endPoint.X, endPoint.Y)
	local midPoint = Vector2.new((startPoint.X + endPoint.X) / 2, (startPoint.Y + endPoint.Y) / 2)

	wallHandleStart.Position = toWorld(startPoint2)
	wallHandleEnd.Position = toWorld(endPoint2)
	wallHandleCenter.Position = toWorld(midPoint)
	wallHandleStartSolo.Position = toWorld(startPoint2 + offset)
	wallHandleEndSolo.Position = toWorld(endPoint2 + offset)
	wallHandleExtendStart.Position = toWorld(startPoint2 + extendOffset)
	wallHandleExtendEnd.Position = toWorld(endPoint2 + extendOffset)
	local deletePosition = toWorld(Vector2.new(midPoint.X, math.min(startPoint.Y, endPoint.Y) - Constants.HandleOffset * 2))
	wallHandleDelete.Position = deletePosition - Vector3.new(0, wallHandleDelete.Size.Y / 2, 0)
	wallHandleFlip.Position = toWorld(midPoint + offset)
	wallHandleDivide.Position = toWorld(midPoint - offset)
	local frontWorld = plotInfo.PlotPart.CFrame:VectorToWorldSpace(Vector3.new(frontNormal.X, 0, frontNormal.Y))
	setHandleIconRotation(wallHandleFlip, getScreenRotationForDirection(frontWorld))

	setWallHandlesVisible(true)

	local walls = getLevelWallInfos(plotInfo.PlotPart, level)
	local connectedAtStart = getConnectedWallsAtPoint(walls, startPoint, wallId)
	local connectedAtEnd = getConnectedWallsAtPoint(walls, endPoint, wallId)
	Handles.SetHandleVisible(wallHandleStartSolo, #connectedAtStart > 0)
	Handles.SetHandleVisible(wallHandleEndSolo, #connectedAtEnd > 0)
end

local function updateWallHandleHover(input: any)
	if getDesignMode() ~= Enums.DesignMode.Wall or getActionType() ~= Enums.ActionType.Select then
		Handles.ClearHandleHover()
		return
	end

	Handles.CheckHover(input.Ray)
end

local function updateWallGhost(input: any)
	if not wallStart then
		return
	end

	if not input.SnapPoint or not input.PlotInfo.PlotPart then
		return
	end

	local endPoint = input.SnapPoint
	local snappedEndPoint = snapWallEndPoint(wallStart, Vector2.new(endPoint.X, endPoint.Y))
	if input.ActionHeld
	and (snappedEndPoint.X ~= wallStart.X or snappedEndPoint.Y ~= wallStart.Y) then
		wallBuildMode = "Drag"
	end
	if lastPreviewPoint and snappedEndPoint == lastPreviewPoint then
		return
	end
	lastPreviewPoint = snappedEndPoint

	ensureWallGhost(input.PlotInfo.PlotPart, wallStart, snappedEndPoint)

	local previewData = buildWallData(wallStart, snappedEndPoint)
	local valid = Formex.IsWallValid(input.PlotInfo :: any, previewData)
	updateGhostValidity(valid)
end

local function updateWallStartGhost(input: any)
	if not input.SnapPoint or not input.PlotInfo.PlotPart then
		return
	end

	local startPoint = input.SnapPoint
	if lastPreviewPoint and startPoint == lastPreviewPoint then
		return
	end
	lastPreviewPoint = startPoint

	ensureWallGhost(input.PlotInfo.PlotPart, startPoint, startPoint)
	updateGhostValidity(isPointInOwnedSegments(input.PlotInfo, Vector2.new(startPoint.X, startPoint.Y)))
end

local function updateWallMoveGhost(input: any)
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
		if not original then
			return
		end
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
		applyWallTransform(input.PlotInfo.PlotPart, wall)
	end
	moveWallUpdated = updatedWalls

	local previewData = buildWallData(newStart, newEnd)
	local valid = Formex.IsWallValid(input.PlotInfo :: any, previewData)
	updateGhostValidity(valid)
	Highlight.UpdateWallEdgePreview(input.PlotInfo, moveWallOriginal.Level, newStart, newEnd, valid)
end

local function finalizeWall(plotInfo: any, endPosition: Vector3)
	if not wallStart or not plotInfo.PlotPart then
		return
	end

	local endPoint = getSnappedPoint(plotInfo.PlotPart, endPosition)
	local snappedEndPoint = snapWallEndPoint(wallStart, Vector2.new(endPoint.X, endPoint.Y))
	if isZeroLength(wallStart, snappedEndPoint) then
		cancelAction()
		return
	end
	local wallData = buildWallData(wallStart, snappedEndPoint)
	if not Formex.IsWallValid(plotInfo :: any, wallData) then
		updateGhostValidity(false)
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

	if result and result.WallId then
		local ignoreIds = { [result.WallId] = true }
		splitWallsAtPoints(plotInfo, result.Level or getCurrentLevel(), { wallData.Start, wallData.End }, ignoreIds)

		local levelIndex = result.Level or getCurrentLevel()
		local plotPart = plotInfo.PlotPart
		task.spawn(function()
			local deadline = time() + 2
			while time() < deadline do
				local levelPart = plotPart:FindFirstChild(tostring(levelIndex))
				if levelPart then
					local wallsFolder = levelPart:FindFirstChild("Walls")
					if wallsFolder then
						local wallModel = wallsFolder:FindFirstChild(tostring(result.WallId))
						if wallModel and wallModel:IsA("Model") then
							select(wallModel)
							return
						end
					end
				end
				task.wait(0.05)
			end
		end)
	end
end

local function finalizeWallMove(plotInfo: any)
	if not moveWallOriginal or not movePreviewStart or not movePreviewEnd then
		return
	end

	local editData = {
		WallId = moveWallOriginal.WallId,
		Level = moveWallOriginal.Level,
		Start = movePreviewStart,
		End = movePreviewEnd,
	}

	local valid = Formex.IsWallValid(plotInfo :: any, editData)
	if not valid then
		updateGhostValidity(false)
		cancelAction()
		return
	end

	local updates = moveWallUpdated
	if not updates or next(updates) == nil then
		updates = {
			[moveWallOriginal.WallId] = {
				WallId = moveWallOriginal.WallId,
				Level = moveWallOriginal.Level,
				Start = movePreviewStart,
				End = movePreviewEnd,
				Part = moveWallOriginal.Part,
			}
		}
	end

	local selectedDeleted = false
	local deletedWalls = {}
	local wallBatch = {}
	for _, wall in pairs(updates) do
		local data = {
			WallId = wall.WallId,
			Level = wall.Level,
			Start = wall.Start,
			End = wall.End,
			Part = nil,
		}
		table.insert(wallBatch, data)

		if isZeroLength(wall.Start, wall.End) then
			if wall.WallId == moveWallOriginal.WallId then
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

	for _, wall in ipairs(deletedWalls) do
		if wall.Part and wall.Part.Parent then
			wall.Part:Destroy()
		end
	end

	local splitPoints = { movePreviewStart, movePreviewEnd }
	local splitLevel = moveWallOriginal.Level
	local ignoreIds: {[number]: boolean} = {}
	for wallId in pairs(updates) do
		ignoreIds[wallId] = true
	end

	if not selectedDeleted then
		selectedWall = {
			WallId = moveWallOriginal.WallId,
			Level = moveWallOriginal.Level,
			Start = movePreviewStart,
			End = movePreviewEnd,
			Part = moveWallOriginal.Part,
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
	if not input.PlotInfo.PlotPart then
		return
	end

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
	if not plotInfo or not plotInfo.IsValid or not plotInfo.PlotPart then
		return
	end

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
				applyWallTransform(plotInfo.PlotPart, wall)
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
		local currentSelection = getSelectionPart()
		local hadSelection = getSelectionType() ~= Enums.SelectionType.None or currentSelection ~= nil
		if hadSelection and input.Target and currentSelection then
			if input.Target == currentSelection
			or input.Target:IsDescendantOf(currentSelection)
			or currentSelection:IsDescendantOf(input.Target) then
				return
			end
		end

		local selected = input.Target and select(input.Target) or false
		if selected then
			return
		end

		if getSelectionType() ~= Enums.SelectionType.None then
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
