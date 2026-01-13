--!strict
--[[
FormexDesignRooms
Room selection and wall move handles.
]]
local Context = require(script.Parent:WaitForChild("FormexDesignContext"))

local Rooms = {}

type RoomHandle = {
	Kind: "Wall" | "Point",
	WallId: number?,
	Point: Vector2int16?,
	Handle: BasePart,
}

type MoveState = {
	Kind: "Wall" | "Point",
	WallId: number,
	LevelIndex: number,
	Start: Vector2int16,
	End: Vector2int16,
	OriginLocal: Vector2,
	Point: Vector2int16?,
	Connections: { {WallId: number, EndType: "Start" | "End"} }?,
	RoomWallSet: {[number]: boolean}?,
	RoomFloorSet: {[number]: boolean}?,
}

local FormexClient: any
local Formex: any
local Poly: any
local Handles: any
local Highlight: any
local Enums: any
local Constants: any

local getActionType: () -> string
local setActionType: (string) -> ()
local getCurrentLevel: () -> number
local getEditMode: () -> string
local getSelectionType: () -> string
local getSelectionData: () -> any?
local setRoomSelection: (any?) -> ()
local getLastInputInfo: () -> any?
local getSelectionSnapshot: () -> any?
local getLocalXZ: (BasePart, Vector3) -> Vector2
local updateGhostValidity: (boolean) -> ()
local notifyDesignModeChange: () -> ()

local roomHandles = {} :: {RoomHandle}
local lastRoomId: number? = nil
local lastRoomWallKey: string? = nil
local lastRoomEditMode: string? = nil

local activeMove: MoveState? = nil
local movePreviewStart: Vector2int16? = nil
local movePreviewEnd: Vector2int16? = nil
local movePreviewPoint: Vector2int16? = nil
local moveValid = false

local function snapToGrid(value: number): number
	return math.round(value / Formex.LayoutGridSize) * Formex.LayoutGridSize
end

local function pointsEqual(a: Vector2int16, b: Vector2int16): boolean
	return a.X == b.X and a.Y == b.Y
end

local function toSnappedPoint(point: Vector2): Vector2int16
	return Vector2int16.new(snapToGrid(point.X), snapToGrid(point.Y))
end

local function getPointKey(point: Vector2int16): string
	return tostring(point.X) .. "," .. tostring(point.Y)
end

local function buildIdSet(list: {number}?): {[number]: boolean}
	local set = {}
	if list then
		for _, id in ipairs(list) do
			set[id] = true
		end
	end
	return set
end

local function updateMergePreview(plotInfo: any, levelIndex: number, validation: any?)
	if not Highlight or not validation or not validation.MergeSegments then
		if Highlight then
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

local function clearRoomHandles()
	Handles.ClearHandleHover()
	Handles.Clear()
	roomHandles = {}
	lastRoomId = nil
	lastRoomWallKey = nil
	lastRoomEditMode = nil
end

local function setHandlesVisible(visible: boolean)
	for _, handle in ipairs(roomHandles) do
		Handles.SetHandleVisible(handle.Handle, visible)
	end
end

local function getRoomWallKey(plotInfo: any, room: any): string
	if not room or not room.Walls then
		return ""
	end
	local levelData = plotInfo and plotInfo.PlotData and plotInfo.PlotData.Levels and plotInfo.PlotData.Levels[room.LevelIndex]
	local walls = levelData and levelData.Walls
	if not walls then
		return ""
	end
	local keys = {}
	for _, wallId in ipairs(room.Walls) do
		local wall = walls[wallId]
		if wall and wall.Start and wall.End then
			table.insert(keys, string.format(
				"%d:%d,%d:%d,%d",
				wallId,
				wall.Start.X,
				wall.Start.Y,
				wall.End.X,
				wall.End.Y
			))
		end
	end
	table.sort(keys)
	return table.concat(keys, "|")
end

local function updateRoomHighlight(plotInfo: any, room: any)
	if not plotInfo or not plotInfo.PlotPart or not room or not room.Points then
		Highlight.ClearFloorEdgePreview()
		return
	end
	Highlight.UpdateFloorEdgePreview(plotInfo, room.LevelIndex, room.Points, true, 0)
end

local function getCursorLocalPoint(plotInfo: any, input: any): Vector2?
	if not plotInfo or not plotInfo.PlotPart then
		return nil
	end
	if input and input.HitPosition then
		return getLocalXZ(plotInfo.PlotPart, input.HitPosition)
	end
	if input and input.LayoutTile then
		local tileSize = Formex.LayoutGridSize
		local halfWidth = Formex.Dimensions.Width / 2
		local halfDepth = Formex.Dimensions.Depth / 2
		local centerX = input.LayoutTile.X * tileSize - halfWidth + (tileSize / 2)
		local centerY = input.LayoutTile.Y * tileSize - halfDepth + (tileSize / 2)
		return Vector2.new(centerX, centerY)
	end
	return nil
end

local function selectRoomAtPoint(plotInfo: any, levelIndex: number, point: Vector2?): any?
	if not plotInfo or not plotInfo.PlotData or not plotInfo.PlotData.Rooms or not point then
		setRoomSelection(nil)
		return nil
	end

	local selected = nil
	for _, room in pairs(plotInfo.PlotData.Rooms) do
		if room.LevelIndex == levelIndex and room.Points and #room.Points >= 3 and not room.IsExterior then
			if Poly.IsPointInsidePolygon(point, room.Points, true, Formex.EPSILON) then
				if not selected or room.Area < selected.Area then
					selected = room
				end
			end
		end
	end

	setRoomSelection(selected)
	return selected
end

local function getMoveWallData(plotInfo: any, room: any, wallId: number): (any?, Vector2int16?, Vector2int16?)
	if not room or not room.Walls then
		return nil, nil, nil
	end
	local levelData = plotInfo and plotInfo.PlotData and plotInfo.PlotData.Levels and plotInfo.PlotData.Levels[room.LevelIndex]
	local wall = levelData and levelData.Walls and levelData.Walls[wallId]
	if not wall or not wall.Start or not wall.End then
		return nil, nil, nil
	end
	return wall, wall.Start, wall.End
end

local function beginWallMove(wallId: number)
	local room = getSelectionData()
	local input = getLastInputInfo()
	if not room or not input or not input.PlotInfo or not input.PlotInfo.PlotPart or not input.HitPosition then
		return
	end

	local wall, startPoint, endPoint = getMoveWallData(input.PlotInfo, room, wallId)
	if not wall or not startPoint or not endPoint then
		return
	end

	activeMove = {
		Kind = "Wall",
		WallId = wallId,
		LevelIndex = wall.Level or room.LevelIndex,
		Start = startPoint,
		End = endPoint,
		OriginLocal = getLocalXZ(input.PlotInfo.PlotPart, input.HitPosition),
	}

	setActionType(Enums.ActionType.Move)
	setHandlesVisible(false)
	Highlight.ClearFloorEdgePreview()
	notifyDesignModeChange()
end

local function getWallConnectionsAtPoint(
	plotInfo: any,
	levelIndex: number,
	point: Vector2int16,
	wallFilter: {[number]: boolean}?
): { {WallId: number, EndType: "Start" | "End"} }
	local connections = {}
	local levelData = plotInfo and plotInfo.PlotData and plotInfo.PlotData.Levels and plotInfo.PlotData.Levels[levelIndex]
	if not levelData or not levelData.Walls then
		return connections
	end

	for wallId, wall in pairs(levelData.Walls) do
		if wallFilter and not wallFilter[wallId] then
			continue
		end
		if wall and wall.Start and wall.End then
			if pointsEqual(wall.Start, point) then
				table.insert(connections, {
					WallId = wallId,
					EndType = "Start",
				})
			elseif pointsEqual(wall.End, point) then
				table.insert(connections, {
					WallId = wallId,
					EndType = "End",
				})
			end
		end
	end

	return connections
end

local function beginPointMove(point: Vector2int16)
	local room = getSelectionData()
	local input = getLastInputInfo()
	if not room or not input or not input.PlotInfo or not input.PlotInfo.PlotPart then
		return
	end
	local editMode = getEditMode()
	local roomWallSet = nil
	local roomFloorSet = nil
	if editMode == Enums.EditMode.DisconnectMove then
		roomWallSet = buildIdSet(room.Walls)
		roomFloorSet = buildIdSet(room.Floors)
	end

	activeMove = {
		Kind = "Point",
		WallId = 0,
		LevelIndex = room.LevelIndex,
		Start = point,
		End = point,
		OriginLocal = Vector2.new(0, 0),
		Point = point,
		Connections = getWallConnectionsAtPoint(input.PlotInfo, room.LevelIndex, point, roomWallSet),
		RoomWallSet = roomWallSet,
		RoomFloorSet = roomFloorSet,
	}
	movePreviewPoint = point
	moveValid = true
	updateGhostValidity(true)

	setActionType(Enums.ActionType.Move)
	setHandlesVisible(false)
	Highlight.ClearFloorEdgePreview()
	notifyDesignModeChange()
end

local function updatePointMovePreview(plotInfo: any, input: any)
	if not activeMove or activeMove.Kind ~= "Point" or not input or not input.SnapPoint then
		return
	end

	local newPoint = input.SnapPoint
	movePreviewPoint = newPoint

	local updatedWalls = {} :: {[number]: Formex.WallData}
	local levelData = plotInfo and plotInfo.PlotData and plotInfo.PlotData.Levels and plotInfo.PlotData.Levels[activeMove.LevelIndex]
	if levelData and activeMove.Connections then
		for _, connection in ipairs(activeMove.Connections) do
			local wall = levelData.Walls and levelData.Walls[connection.WallId] or nil
			if wall and wall.Start and wall.End then
				local startPoint = wall.Start
				local endPoint = wall.End
				if connection.EndType == "Start" then
					startPoint = newPoint
				else
					endPoint = newPoint
				end
				updatedWalls[connection.WallId] = {
					WallId = connection.WallId,
					Level = wall.Level or activeMove.LevelIndex,
					Start = startPoint,
					End = endPoint,
				}
			end
		end
	end

	local valid = true
	local validation = nil
	if plotInfo and plotInfo.PlotData then
		local wallUpdates = {}
		for _, wall in pairs(updatedWalls) do
			table.insert(wallUpdates, wall)
		end
		if #wallUpdates > 0 then
			validation = Formex.IsTransactionValid(plotInfo.PlotData, {
				{
					PartType = Formex.PartType.Wall,
					Action = Formex.BuildAction.Edit,
					Data = wallUpdates,
				},
			})
			valid = validation and validation.IsValid == true
		end
	end

	moveValid = valid
	updateGhostValidity(valid)
	updateMergePreview(plotInfo, activeMove.LevelIndex, validation)

	local room = getSelectionData()
	if room and room.Points and #room.Points >= 3 then
		local previewPoints = table.clone(room.Points)
		for index, point in ipairs(previewPoints) do
			if pointsEqual(point, activeMove.Start) then
				previewPoints[index] = newPoint
			end
		end
		Highlight.UpdateFloorEdgePreview(plotInfo, activeMove.LevelIndex, previewPoints, valid, 0)
	end
end

local function updateMovePreview(plotInfo: any, input: any)
	if not activeMove then
		return
	end
	if activeMove.Kind == "Point" then
		updatePointMovePreview(plotInfo, input)
		return
	end
	if not input or not input.PlotInfo or not input.PlotInfo.PlotPart or not input.HitPosition then
		return
	end

	local localPos = getLocalXZ(input.PlotInfo.PlotPart, input.HitPosition)
	local delta = localPos - activeMove.OriginLocal

	local startPoint = activeMove.Start
	local endPoint = activeMove.End
	local dir = Vector2.new(endPoint.X - startPoint.X, endPoint.Y - startPoint.Y)
	if dir.Magnitude <= Formex.EPSILON then
		return
	end

	local normal = Vector2.new(-dir.Y, dir.X).Unit
	local offset = delta:Dot(normal)
	local shift = normal * offset

	local newStart = toSnappedPoint(Vector2.new(startPoint.X + shift.X, startPoint.Y + shift.Y))
	local newEnd = toSnappedPoint(Vector2.new(endPoint.X + shift.X, endPoint.Y + shift.Y))
	movePreviewStart = newStart
	movePreviewEnd = newEnd

	local wallUpdates = {
		{
			WallId = activeMove.WallId,
			Level = activeMove.LevelIndex,
			Start = newStart,
			End = newEnd,
		},
	}

	local levelData = plotInfo and plotInfo.PlotData and plotInfo.PlotData.Levels and plotInfo.PlotData.Levels[activeMove.LevelIndex]
	if levelData and levelData.Walls then
		for wallId, wall in pairs(levelData.Walls) do
			if wallId ~= activeMove.WallId and wall and wall.Start and wall.End then
				local startPoint = wall.Start
				local endPoint = wall.End
				local changed = false
				if pointsEqual(startPoint, activeMove.Start) then
					startPoint = newStart
					changed = true
				elseif pointsEqual(startPoint, activeMove.End) then
					startPoint = newEnd
					changed = true
				end
				if pointsEqual(endPoint, activeMove.Start) then
					endPoint = newStart
					changed = true
				elseif pointsEqual(endPoint, activeMove.End) then
					endPoint = newEnd
					changed = true
				end
				if changed then
					table.insert(wallUpdates, {
						WallId = wallId,
						Level = wall.Level or activeMove.LevelIndex,
						Start = startPoint,
						End = endPoint,
					})
				end
			end
		end
	end

	local validation = Formex.IsTransactionValid(plotInfo.PlotData, {
		{
			PartType = Formex.PartType.Wall,
			Action = Formex.BuildAction.Edit,
			Data = wallUpdates,
		},
	})
	local valid = validation and validation.IsValid == true
	moveValid = valid
	updateGhostValidity(valid)
	updateMergePreview(plotInfo, activeMove.LevelIndex, validation)
	Highlight.UpdateWallEdgePreview(plotInfo, activeMove.LevelIndex, newStart, newEnd, valid)
end

local function mergeDuplicatePoints(points: {Vector2int16}): {Vector2int16}
	local unique = {}
	local seen = {}
	for _, point in ipairs(points) do
		local key = tostring(point.X) .. "," .. tostring(point.Y)
		if not seen[key] then
			seen[key] = true
			table.insert(unique, point)
		end
	end
	return unique
end

local function buildFloorUpdates(plotInfo: any, levelIndex: number, oldStart: Vector2int16, oldEnd: Vector2int16, newStart: Vector2int16, newEnd: Vector2int16): {Formex.FloorData}
	local updates = {}
	local levelData = plotInfo and plotInfo.PlotData and plotInfo.PlotData.Levels and plotInfo.PlotData.Levels[levelIndex]
	if not levelData or not levelData.Floors then
		return updates
	end

	for floorId, floor in pairs(levelData.Floors) do
		if floor.Points and #floor.Points >= 3 then
			local changed = false
			local points = table.clone(floor.Points)
			for index, point in ipairs(points) do
				if pointsEqual(point, oldStart) then
					points[index] = newStart
					changed = true
				elseif pointsEqual(point, oldEnd) then
					points[index] = newEnd
					changed = true
				end
			end
			if changed then
				points = mergeDuplicatePoints(points)
				local floorMaterial = floor.FloorMaterial or Formex.DefaultFloorMaterial
				local ceilingMaterial = floor.CeilingMaterial or floorMaterial
				local floorColor = floor.FloorColor or Color3.new(1, 1, 1)
				local ceilingColor = floor.CeilingColor or floorColor
				local foundationColor = floor.FoundationColor or floorColor
				table.insert(updates, {
					FloorId = floorId,
					LevelIndex = levelIndex,
					Points = points,
					RaiseHeight = floor.RaiseHeight or 0,
					FloorMaterial = floorMaterial,
					CeilingMaterial = ceilingMaterial,
					FoundationMaterial = floor.FoundationMaterial or Formex.DefaultFoundationMaterial,
					FloorColor = floorColor,
					CeilingColor = ceilingColor,
					FoundationColor = foundationColor,
				})
			end
		end
	end

	return updates
end

local function buildFloorPointUpdates(
	plotInfo: any,
	levelIndex: number,
	oldPoint: Vector2int16,
	newPoint: Vector2int16,
	floorFilter: {[number]: boolean}?
): {Formex.FloorData}
	local updates = {}
	local levelData = plotInfo and plotInfo.PlotData and plotInfo.PlotData.Levels and plotInfo.PlotData.Levels[levelIndex]
	if not levelData or not levelData.Floors then
		return updates
	end

	for floorId, floor in pairs(levelData.Floors) do
		if floorFilter and not floorFilter[floorId] then
			continue
		end
		if floor.Points and #floor.Points >= 3 then
			local changed = false
			local points = table.clone(floor.Points)
			for index, point in ipairs(points) do
				if pointsEqual(point, oldPoint) then
					points[index] = newPoint
					changed = true
				end
			end
			if changed then
				points = mergeDuplicatePoints(points)
				local floorMaterial = floor.FloorMaterial or Formex.DefaultFloorMaterial
				local ceilingMaterial = floor.CeilingMaterial or floorMaterial
				local floorColor = floor.FloorColor or Color3.new(1, 1, 1)
				local ceilingColor = floor.CeilingColor or floorColor
				local foundationColor = floor.FoundationColor or floorColor
				table.insert(updates, {
					FloorId = floorId,
					LevelIndex = levelIndex,
					Points = points,
					RaiseHeight = floor.RaiseHeight or 0,
					FloorMaterial = floorMaterial,
					CeilingMaterial = ceilingMaterial,
					FoundationMaterial = floor.FoundationMaterial or Formex.DefaultFoundationMaterial,
					FloorColor = floorColor,
					CeilingColor = ceilingColor,
					FoundationColor = foundationColor,
				})
			end
		end
	end

	return updates
end

local function buildConnectedWallUpdates(plotInfo: any, levelIndex: number, movedWallId: number, oldStart: Vector2int16, oldEnd: Vector2int16, newStart: Vector2int16, newEnd: Vector2int16): {Formex.WallData}
	local updates = {}
	local levelData = plotInfo and plotInfo.PlotData and plotInfo.PlotData.Levels and plotInfo.PlotData.Levels[levelIndex]
	if not levelData or not levelData.Walls then
		return updates
	end

	for wallId, wall in pairs(levelData.Walls) do
		if wallId ~= movedWallId and wall and wall.Start and wall.End then
			local startPoint = wall.Start
			local endPoint = wall.End
			local changed = false
			if pointsEqual(startPoint, oldStart) then
				startPoint = newStart
				changed = true
			elseif pointsEqual(startPoint, oldEnd) then
				startPoint = newEnd
				changed = true
			end

			if pointsEqual(endPoint, oldStart) then
				endPoint = newStart
				changed = true
			elseif pointsEqual(endPoint, oldEnd) then
				endPoint = newEnd
				changed = true
			end

			if changed then
				table.insert(updates, {
					WallId = wallId,
					Level = wall.Level or levelIndex,
					Start = startPoint,
					End = endPoint,
				})
			end
		end
	end

	return updates
end

local function finalizeWallMove(plotInfo: any)
	if not activeMove or activeMove.Kind ~= "Wall" or not movePreviewStart or not movePreviewEnd or not plotInfo then
		return
	end

	if not moveValid then
		return
	end

	local wallUpdate = {
		WallId = activeMove.WallId,
		Level = activeMove.LevelIndex,
		Start = movePreviewStart,
		End = movePreviewEnd,
	}

	local wallUpdates = { wallUpdate }
	local connectedUpdates = buildConnectedWallUpdates(plotInfo, activeMove.LevelIndex, activeMove.WallId, activeMove.Start, activeMove.End, movePreviewStart, movePreviewEnd)
	for _, update in ipairs(connectedUpdates) do
		table.insert(wallUpdates, update)
	end

	local floorUpdates = buildFloorUpdates(plotInfo, activeMove.LevelIndex, activeMove.Start, activeMove.End, movePreviewStart, movePreviewEnd)

	local changes = {
		{
			PartType = Formex.PartType.Wall,
			Action = Formex.BuildAction.Edit,
			Data = wallUpdates,
		},
	}
	if #floorUpdates > 0 then
		table.insert(changes, {
			PartType = Formex.PartType.Floor,
			Action = Formex.BuildAction.Edit,
			Data = floorUpdates,
		})
	end

	runBuildTransaction(changes, getSelectionSnapshot())
end

local function finalizePointMove(plotInfo: any)
	if not activeMove or activeMove.Kind ~= "Point" or not movePreviewPoint or not plotInfo then
		return
	end

	if not moveValid then
		return
	end

	local levelData = plotInfo.PlotData and plotInfo.PlotData.Levels and plotInfo.PlotData.Levels[activeMove.LevelIndex]
	if not levelData then
		return
	end

	local wallUpdates = {}
	if activeMove.Connections then
		for _, connection in ipairs(activeMove.Connections) do
			local wall = levelData.Walls and levelData.Walls[connection.WallId] or nil
			if wall and wall.Start and wall.End then
				local startPoint = wall.Start
				local endPoint = wall.End
				if connection.EndType == "Start" then
					startPoint = movePreviewPoint
				else
					endPoint = movePreviewPoint
				end
				table.insert(wallUpdates, {
					WallId = connection.WallId,
					Level = wall.Level or activeMove.LevelIndex,
					Start = startPoint,
					End = endPoint,
				})
			end
		end
	end

	local floorUpdates = buildFloorPointUpdates(
		plotInfo,
		activeMove.LevelIndex,
		activeMove.Start,
		movePreviewPoint,
		activeMove.RoomFloorSet
	)
	local changes = {}

	if #wallUpdates > 0 then
		table.insert(changes, {
			PartType = Formex.PartType.Wall,
			Action = Formex.BuildAction.Edit,
			Data = wallUpdates,
		})
	end
	if #floorUpdates > 0 then
		table.insert(changes, {
			PartType = Formex.PartType.Floor,
			Action = Formex.BuildAction.Edit,
			Data = floorUpdates,
		})
	end

	if #changes > 0 then
		runBuildTransaction(changes, getSelectionSnapshot())
	end
end

local function finalizeMove(plotInfo: any)
	if not activeMove then
		return
	end
	if activeMove.Kind == "Point" then
		finalizePointMove(plotInfo)
	else
		finalizeWallMove(plotInfo)
	end
end

local function resetMoveState()
	activeMove = nil
	movePreviewStart = nil
	movePreviewEnd = nil
	movePreviewPoint = nil
	moveValid = false
	lastRoomId = nil
	lastRoomWallKey = nil
	lastRoomEditMode = nil
	updateGhostValidity(true)
	Highlight.ClearFloorEdgePreview()
	Highlight.ClearMergeEdgePreview()
end

function Rooms.Init()
	local ctx = Context.Get()
	FormexClient = ctx.FormexClient
	Formex = ctx.Formex
	Poly = Formex.Poly
	Handles = ctx.Handles
	Highlight = ctx.Highlight
	Enums = ctx.Enums
	Constants = ctx.Constants

	getActionType = ctx.GetActionType
	setActionType = ctx.SetActionType
	getCurrentLevel = ctx.GetCurrentLevel
	getEditMode = ctx.GetEditMode
	getSelectionType = ctx.GetSelectionType
	getSelectionData = ctx.GetSelectionData
	setRoomSelection = ctx.SetRoomSelection
	getLastInputInfo = ctx.GetLastInputInfo
	getSelectionSnapshot = ctx.GetSelectionSnapshot
	getLocalXZ = ctx.GetLocalXZ
	updateGhostValidity = ctx.UpdateGhostValidity
	notifyDesignModeChange = ctx.NotifyDesignModeChange
end

function Rooms.ClearSelection()
	resetMoveState()
	clearRoomHandles()
	Highlight.ClearFloorEdgePreview()
	Highlight.ClearMergeEdgePreview()
end

function Rooms.UpdateHandles(plotInfo: any)
	if getSelectionType() ~= Enums.SelectionType.Room then
		clearRoomHandles()
		Highlight.ClearFloorEdgePreview()
		Highlight.ClearMergeEdgePreview()
		return
	end

	local room = getSelectionData()
	if not room or not room.Points or not plotInfo or not plotInfo.PlotPart then
		clearRoomHandles()
		Highlight.ClearFloorEdgePreview()
		Highlight.ClearMergeEdgePreview()
		return
	end

	local wallKey = getRoomWallKey(plotInfo, room)
	local editMode = getEditMode()
	if room.RoomId == lastRoomId and wallKey == lastRoomWallKey and editMode == lastRoomEditMode then
		return
	end

	clearRoomHandles()
	updateRoomHighlight(plotInfo, room)

	local levelIndex = room.LevelIndex
	local y = Formex.LevelHeight * (levelIndex - 1)
	if editMode == Enums.EditMode.PartMove then
		local levelData = plotInfo.PlotData and plotInfo.PlotData.Levels and plotInfo.PlotData.Levels[levelIndex]
		local walls = levelData and levelData.Walls
		for _, wallId in ipairs(room.Walls or {}) do
			local wall = walls and walls[wallId] or nil
			if wall and wall.Start and wall.End then
				local handle = Handles.CreateHandle(
					"RoomWall_" .. tostring(wallId),
					Constants.HandleMoveColor,
					Formex.Icons.MoveItem,
					beginWallMove,
					wallId
				)
				local midX = (wall.Start.X + wall.End.X) / 2
				local midY = (wall.Start.Y + wall.End.Y) / 2
				handle.CFrame = plotInfo.PlotPart.CFrame * CFrame.new(midX, y, midY)
				roomHandles[#roomHandles + 1] = {
					Kind = "Wall",
					WallId = wallId,
					Handle = handle,
				}
			end
		end
	elseif editMode == Enums.EditMode.PointMove or editMode == Enums.EditMode.DisconnectMove then
		local seen = {}
		local handleColor = editMode == Enums.EditMode.DisconnectMove and Constants.HandleDisconnectColor
			or Constants.HandleMoveColor
		local handleIcon = editMode == Enums.EditMode.DisconnectMove and Formex.Icons.WallDisconnect
			or Formex.Icons.ResizeItem
		for _, point in ipairs(room.Points) do
			local key = getPointKey(point)
			if not seen[key] then
				seen[key] = true
				local handle = Handles.CreateHandle(
					"RoomPoint_" .. key,
					handleColor,
					handleIcon,
					beginPointMove,
					point
				)
				handle.CFrame = plotInfo.PlotPart.CFrame * CFrame.new(point.X, y, point.Y)
				roomHandles[#roomHandles + 1] = {
					Kind = "Point",
					Point = point,
					Handle = handle,
				}
			end
		end
	end

	lastRoomId = room.RoomId
	lastRoomWallKey = wallKey
	lastRoomEditMode = editMode
	setHandlesVisible(true)
end

function Rooms.HandleUpdate(input: any)
	if getActionType() == Enums.ActionType.Select then
		if Highlight and Highlight.UpdateRoomOverlays then
			Highlight.UpdateRoomOverlays(input.PlotInfo, getCurrentLevel())
		end
		Rooms.UpdateHandles(input.PlotInfo)
		Handles.CheckHover(input.Ray)
		return
	end

	if getActionType() == Enums.ActionType.Move then
		updateMovePreview(input.PlotInfo, input)
	end
end

function Rooms.HandlePrimaryClick(input: any): boolean
	if getActionType() ~= Enums.ActionType.Select then
		return false
	end
	local plotInfo = input and input.PlotInfo or nil
	if not plotInfo or not plotInfo.PlotPart then
		return false
	end

	local cursorPoint = getCursorLocalPoint(plotInfo, input)
	local levelIndex = getCurrentLevel()
	local selected = selectRoomAtPoint(plotInfo, levelIndex, cursorPoint)
	return selected ~= nil
end

function Rooms.HandlePrimaryRelease(input: any)
	if getActionType() == Enums.ActionType.Move then
		local plotInfo = input and input.PlotInfo or nil
		if plotInfo then
			finalizeMove(plotInfo)
		end
		resetMoveState()
		setActionType(Enums.ActionType.Select)
		Rooms.UpdateHandles(input.PlotInfo)
		notifyDesignModeChange()
	end
end

function Rooms.CancelAction()
	if getActionType() == Enums.ActionType.Move then
		resetMoveState()
		setActionType(Enums.ActionType.Select)
		local input = getLastInputInfo()
		if input and input.PlotInfo then
			Rooms.UpdateHandles(input.PlotInfo)
		end
		notifyDesignModeChange()
	end
end

return Rooms
