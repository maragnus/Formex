--!strict
--[[
FormexRooms
Room discovery and adjacency using wall geometry.
]]

local Formex = require(script.Parent)

local FormexRooms = {}

type RoomSeed = {
	LevelIndex: number,
	Points: {Vector2int16},
	EdgeWalls: {number?},
	WallIds: {[number]: boolean},
	Area: number,
	IsExterior: boolean,
}

type RoomCache = {
	WallKeysByLevel: {[number]: string},
	RoomSeedsByLevel: {[number]: {RoomSeed}},
}

local cacheByPlot = setmetatable({}, { __mode = "k" }) :: {[any]: RoomCache}

local function getCache(plotData: any): RoomCache
	local cache = cacheByPlot[plotData]
	if cache then return cache end
	cache = {
		WallKeysByLevel = {},
		RoomSeedsByLevel = {},
	}
	cacheByPlot[plotData] = cache
	return cache
end

local function getWallKey(levelData: any, segmentsUnlocked: number?): string
	if not levelData or not levelData.Walls then
		return tostring(segmentsUnlocked or 0)
	end

	local keys = {}
	for wallId, wall in pairs(levelData.Walls) do
		if wall.Start and wall.End then
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
	table.insert(keys, 1, tostring(segmentsUnlocked or 0))
	return table.concat(keys, "|")
end

local function pointsEqual(a: Vector2int16, b: Vector2int16): boolean
	return a.X == b.X and a.Y == b.Y
end

local function buildRoomPoints(face: FormexPoly.Face): ({Vector2int16}, {number?}, boolean)
	local points = {}
	local edgeWalls = {}
	local isExterior = false
	local lastPoint = nil

	for _, edge in ipairs(face.Edges) do
		local point = edge.Start
		if not lastPoint or not pointsEqual(lastPoint, point) then
			table.insert(points, point)
			table.insert(edgeWalls, edge.WallId)
			lastPoint = point
		else
			local index = #edgeWalls
			if edgeWalls[index] == nil and edge.WallId then
				edgeWalls[index] = edge.WallId
			end
		end
		if edge.IsBoundary then
			isExterior = true
		end
	end

	if #points >= 2 and pointsEqual(points[1], points[#points]) then
		table.remove(points, #points)
		table.remove(edgeWalls, #edgeWalls)
	end

	return points, edgeWalls, isExterior
end

local function getRoomSeeds(formex: any, plotData: any, levelIndex: number): {RoomSeed}
	local seeds = {}
	local faces = FormexPoly.TraceFaces(formex, plotData, levelIndex, {
		IncludeWalls = true,
		IncludeFloors = false,
		IncludeBoundary = true,
		PruneWalls = true,
	})

	local epsilon = formex.EPSILON
	for _, face in ipairs(faces) do
		local points, edgeWalls, isExterior = buildRoomPoints(face)
		if #points >= 3 then
			local sample = FormexPoly.GetFaceSamplePoint(points, epsilon)
			if sample and formex.Plot.IsPointInUnlockedSegments(sample, plotData.SegmentsUnlocked) then
				local wallIds = {}
				for _, wallId in ipairs(edgeWalls) do
					if wallId then
						wallIds[wallId] = true
					end
				end
				table.insert(seeds, {
					LevelIndex = levelIndex,
					Points = points,
					EdgeWalls = edgeWalls,
					WallIds = wallIds,
					Area = math.abs(face.Area),
					IsExterior = isExterior,
				})
			end
		end
	end

	return seeds
end

local function roomContainsPoint(formex: any, roomPoints: {Vector2int16}, point: Vector2): boolean
	return FormexPoly.IsPointInsidePolygon(point, roomPoints, true, formex.EPSILON)
end

local function floorTouchesRoom(formex: any, roomPoints: {Vector2int16}, floorPoints: {Vector2int16}): boolean
	local epsilon = formex.EPSILON
	if FormexPoly.PolygonsIntersect(roomPoints, floorPoints, epsilon) then return true end
	for _, point in ipairs(floorPoints) do
		if FormexPoly.IsPointInsidePolygon(Vector2.new(point.X, point.Y), roomPoints, true, epsilon) then return true end
	end
	for _, point in ipairs(roomPoints) do
		if FormexPoly.IsPointInsidePolygon(Vector2.new(point.X, point.Y), floorPoints, true, epsilon) then return true end
	end
	return false
end

local function buildRoomData(
	formex: any,
	plotData: any,
	levelData: any,
	roomId: number,
	seed: RoomSeed
)
	local room = {
		RoomId = roomId,
		LevelIndex = seed.LevelIndex,
		Points = table.clone(seed.Points),
		EdgeWalls = table.clone(seed.EdgeWalls),
		Walls = {},
		Floors = {},
		Objects = {},
		NeighboringRooms = {},
		Area = seed.Area,
		IsExterior = seed.IsExterior,
		IsCovered = false,
	} :: any

	local wallSet = {} :: {[number]: boolean}
	if levelData and levelData.Walls then
		for wallId in pairs(seed.WallIds) do
			local wall = levelData.Walls[wallId]
			if wall then
				table.insert(room.Walls, wallId)
				wallSet[wallId] = true
			end
		end
	end

	if levelData and levelData.Floors then
		for floorId, floor in pairs(levelData.Floors) do
			if floor.Points and #floor.Points >= 3 then
				local points = floor.Points
				if formex.Floors and formex.Floors.CleanPolygon then
					points = formex.Floors.CleanPolygon(points)
				end
				if #points >= 3 and floorTouchesRoom(formex, seed.Points, points) then
					table.insert(room.Floors, floorId)
				end
			end
		end
	end

	if levelData and levelData.Objects then
		for objectId, object in pairs(levelData.Objects) do
			local included = false
			if object.WallId and wallSet[object.WallId] then
				included = true
			elseif object.Position then
				local testPoint = Vector2.new(object.Position.X, object.Position.Z)
				included = roomContainsPoint(formex, seed.Points, testPoint)
			end
			if included then
				table.insert(room.Objects, objectId)
			end
		end
	end

	return room
end

local function findRoomAtPoint(formex: any, rooms: {any}, point: Vector2): any?
	local selected = nil
	for _, room in ipairs(rooms) do
		if roomContainsPoint(formex, room.Points, point) then
			if not selected or room.Area < selected.Area then
				selected = room
			end
		end
	end
	return selected
end

local function buildConnections(formex: any, plotData: any, roomsByLevel: {[number]: {any}})
	local connectionMap = {}
	local portalsByWall = {}

	for levelIndex, rooms in pairs(roomsByLevel) do
		local levelData = plotData.Levels[levelIndex]
		if levelData and levelData.Objects then
			for _, object in pairs(levelData.Objects) do
				if object.IsPortal and object.WallId then
					local list = portalsByWall[object.WallId]
					if not list then
						list = {}
						portalsByWall[object.WallId] = list
					end
					local objectId = tonumber(object.ObjectId) or object.ObjectId
					if objectId ~= nil then
						table.insert(list, objectId)
					end
				end
			end
		end
	end

	local function getConnection(roomA: any, roomB: any): any
		local idA = roomA.RoomId
		local idB = roomB.RoomId
		local key = idA < idB and (tostring(idA) .. ":" .. tostring(idB)) or (tostring(idB) .. ":" .. tostring(idA))
		local existing = connectionMap[key]
		if existing then return existing end
		local connection = {
			Room1 = roomA,
			Room2 = roomB,
			IsConnected = false,
			Portals = {},
		}
		connectionMap[key] = connection
		roomA.NeighboringRooms[idB] = connection
		roomB.NeighboringRooms[idA] = connection
		return connection
	end

	for levelIndex, rooms in pairs(roomsByLevel) do
		local levelData = plotData.Levels[levelIndex]
		if not levelData or not levelData.Walls then
			continue
		end
		local offset = math.max(formex.GridSize * 0.25, 0.25)
		for wallId, wall in pairs(levelData.Walls) do
			if not wall.Start or not wall.End then
				continue
			end
			local startPoint = wall.Start
			local endPoint = wall.End
			local dir = Vector2.new(endPoint.X - startPoint.X, endPoint.Y - startPoint.Y)
			if dir.Magnitude <= formex.EPSILON then
				continue
			end
			local normal = Vector2.new(-dir.Y, dir.X).Unit
			local mid = Vector2.new((startPoint.X + endPoint.X) / 2, (startPoint.Y + endPoint.Y) / 2)
			local roomLeft = findRoomAtPoint(formex, rooms, mid + normal * offset)
			local roomRight = findRoomAtPoint(formex, rooms, mid - normal * offset)

			wall.FrontRoom = roomLeft and roomLeft.RoomId or nil
			wall.BackRoom = roomRight and roomRight.RoomId or nil

			if roomLeft and roomRight and roomLeft.RoomId ~= roomRight.RoomId then
				local connection = getConnection(roomLeft, roomRight)
				local portals = portalsByWall[wallId]
				if portals then
					for _, portalId in ipairs(portals) do
						table.insert(connection.Portals, portalId)
					end
					if #portals > 0 then
						connection.IsConnected = true
					end
				end
			end
		end
	end
end

function FormexRooms.RebuildPlotRooms(formex: any, plotData: any)
	if not formex or not plotData then return end
	local cache = getCache(plotData)
	plotData.Rooms = {}

	local roomsByLevel = {} :: {[number]: {any}}
	local nextRoomId = 0
	for levelIndex = 1, formex.MaxPlotSize.Levels do
		local levelData = plotData.Levels and plotData.Levels[levelIndex] or nil
		if not levelData then
			cache.RoomSeedsByLevel[levelIndex] = {}
			cache.WallKeysByLevel[levelIndex] = getWallKey(nil, plotData.SegmentsUnlocked)
			continue
		end

		local wallKey = getWallKey(levelData, plotData.SegmentsUnlocked)
		local seeds = cache.RoomSeedsByLevel[levelIndex]
		if cache.WallKeysByLevel[levelIndex] ~= wallKey or not seeds then
			seeds = getRoomSeeds(formex, plotData, levelIndex)
			cache.RoomSeedsByLevel[levelIndex] = seeds
			cache.WallKeysByLevel[levelIndex] = wallKey
		end

		local levelRooms = {}
		for _, seed in ipairs(seeds) do
			nextRoomId += 1
			local room = buildRoomData(formex, plotData, levelData, nextRoomId, seed)
			plotData.Rooms[nextRoomId] = room
			table.insert(levelRooms, room)
		end
		roomsByLevel[levelIndex] = levelRooms
	end

	buildConnections(formex, plotData, roomsByLevel)
end

return FormexRooms
