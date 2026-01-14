--!strict
--[[
FormexTransaction
Shared transaction validation + application logic for walls/floors/objects.

Table of contents:
1) Utility + normalization helpers
2) Merge/overlap helpers
3) Object normalization + validation helpers
4) Transaction context + copy-on-write helpers
5) applyTransaction (core pipeline)
]]

local Formex = require(script.Parent)

local EPSILON = Formex.EPSILON

type BuildChange = Formex.BuildChange
type BuildChangeResult = Formex.BuildChangeResult

type WallIdEntry = { Level: number, WallId: number }
type FloorIdEntry = { Level: number, FloorId: number }
type ObjectIdEntry = { Level: number, ObjectId: number | string }
type MergedSegmentEntry = { Level: number, Start: Vector2int16, End: Vector2int16 }

type TransactionResult = {
	IsValid: boolean,
	Error: string?,
	DidChange: boolean,
	Results: {BuildChangeResult},
	LevelsTouched: {number},
	MergeSegments: {MergedSegmentEntry},
	RemovedObjects: {ObjectIdEntry},
	UpdatedWalls: {WallIdEntry},
	AddedWalls: {WallIdEntry},
	RemovedWalls: {WallIdEntry},
	UpdatedFloors: {FloorIdEntry},
	AddedFloors: {FloorIdEntry},
	RemovedFloors: {FloorIdEntry},
	UpdatedObjects: {ObjectIdEntry},
	AddedObjects: {ObjectIdEntry},
	Levels: Formex.LevelArray?,
	NextId: number?,
	Rollback: (() -> ())?,
}

type TransactionOptions = {
	Commit: boolean?,
}

type TransactionContext = {
	PlotData: Formex.PlotData,
	WorkingLevels: Formex.LevelArray,
	LevelsTouched: {number},
	HasStructureChange: boolean,
	ObjectOnly: boolean,
	OriginalLevels: Formex.LevelArray?,
	OriginalNextId: number,
	NextId: number,
	LevelCloned: {[number]: boolean},
	WallsCloned: {[number]: boolean},
	FloorsCloned: {[number]: boolean},
	ObjectsCloned: {[number]: boolean},
	LevelMissing: {[number]: boolean},
}

local collectLevelsTouched: (changes: {BuildChange}) -> ({number}, boolean, boolean)

local function toVector2(point: Vector2int16): Vector2
	return Vector2.new(point.X, point.Y)
end

local function pointsEqual(a: Vector2int16, b: Vector2int16): boolean
	return a.X == b.X and a.Y == b.Y
end

local function cross2(a: Vector2, b: Vector2): number
	return a.X * b.Y - a.Y * b.X
end

local function isZeroLength(startPoint: Vector2int16, endPoint: Vector2int16): boolean
	return startPoint.X == endPoint.X and startPoint.Y == endPoint.Y
end

local function snapToGrid(value: number, grid: number): number
	if grid <= 0 then return value end
	return math.round(value / grid) * grid
end

local function resolveWallHeight(value: number?, existing: number?): number
	if value == 0 then
		value = nil
		existing = nil
	end
	local resolved = value
	if resolved ~= nil and resolved < 0 then
		resolved = nil
	end
	if resolved == nil then
		resolved = existing
	end
	resolved = resolved or Formex.LevelHeight
	resolved = snapToGrid(resolved, Formex.LayoutGridSize)
	return math.clamp(resolved, Formex.LayoutGridSize, Formex.LevelHeight)
end

local function resolveSplitHeight(height: number, value: number?, existing: number?): number?
	local resolved = value
	if resolved == nil then
		resolved = existing
	end
	if resolved == nil or resolved <= 0 or height <= Formex.LayoutGridSize * 2 then return 0 end
	local snapped = snapToGrid(resolved, Formex.LayoutGridSize)
	local maxSplit = height - Formex.LayoutGridSize
	return math.clamp(snapped, Formex.LayoutGridSize, maxSplit)
end

local function resolveRaiseHeight(value: number?, existing: number?): number
	local resolved = value
	if resolved == nil then
		resolved = existing
	end
	resolved = resolved or 0
	if resolved < 0 then
		resolved = 0
	end
	local snapped = snapToGrid(resolved, Formex.GridSize)
	local maxHeight = Formex.LevelHeight - Formex.InterfloorHeight
	if maxHeight < 0 then
		maxHeight = 0
	end
	return math.clamp(snapped, 0, maxHeight)
end

local function resolveColor(primary: Color3?, fallback: Color3?): Color3
	return primary or fallback or Color3.new(1, 1, 1)
end

local function normalizeMaterialId(value: number?): number?
	if type(value) ~= "number" or value <= 0 then return nil end
	return value
end

local function resolveSideMaterials(entryTop: number?, entryBottom: number?, entryLegacy: number?, existingTop: number?, existingBottom: number?, existingLegacy: number?, defaultMaterial: number): (number, number)
	entryTop = normalizeMaterialId(entryTop)
	entryBottom = normalizeMaterialId(entryBottom)
	entryLegacy = normalizeMaterialId(entryLegacy)
	existingTop = normalizeMaterialId(existingTop)
	existingBottom = normalizeMaterialId(existingBottom)
	existingLegacy = normalizeMaterialId(existingLegacy)

	local base = entryLegacy or entryBottom or entryTop
	if not base then
		base = existingBottom or existingTop or existingLegacy
	end
	base = base or defaultMaterial

	local bottom = entryBottom or existingBottom or base
	local top = entryTop or existingTop or base
	return bottom, top
end

local function resolveSideColors(entryTop: Color3?, entryBottom: Color3?, existingTop: Color3?, existingBottom: Color3?, fallback: Color3?): (Color3, Color3)
	local base = entryBottom or entryTop or existingBottom or existingTop or fallback or Color3.new(1, 1, 1)
	local bottom = entryBottom or existingBottom or base
	local top = entryTop or existingTop or base
	return bottom, top
end

local function normalizeWallList(wallData: Formex.WallData | {Formex.WallData}): ({Formex.WallData}, boolean)
	local wallDataAny = wallData :: any
	if wallDataAny.WallId ~= nil or wallDataAny.Start ~= nil or wallDataAny.End ~= nil then
		return { wallData :: Formex.WallData }, false
	end

	local wallList = wallData :: {Formex.WallData}
	if #wallList == 0 then
		error("Invalid wall data")
	end
	return wallList, true
end

local function normalizeFloorList(floorData: Formex.FloorData | {Formex.FloorData}): ({Formex.FloorData}, boolean)
	local floorDataAny = floorData :: any
	if floorDataAny.FloorId ~= nil or floorDataAny.Points ~= nil then
		return { floorData :: Formex.FloorData }, false
	end

	local floorList = floorData :: {Formex.FloorData}
	if #floorList == 0 then
		error("Invalid floor data")
	end
	return floorList, true
end

local function collectWallLevels(walls: {Formex.WallData}): {number}
	local levels = {}
	local seen = {}
	for _, wall in ipairs(walls) do
		local levelIndex = wall.Level or 1
		if not seen[levelIndex] then
			seen[levelIndex] = true
			table.insert(levels, levelIndex)
		end
	end
	table.sort(levels)
	return levels
end

local function collectFloorLevels(floors: {Formex.FloorData}): {number}
	local levels = {}
	local seen = {}
	for _, floor in ipairs(floors) do
		local levelIndex = floor.LevelIndex or 1
		if not seen[levelIndex] then
			seen[levelIndex] = true
			table.insert(levels, levelIndex)
		end
	end
	table.sort(levels)
	return levels
end

local function cloneLevelShell(levelData: Formex.LevelData): Formex.LevelData
	local clone = table.clone(levelData)
	clone.Walls = levelData.Walls or {}
	clone.Floors = levelData.Floors or {}
	clone.Objects = levelData.Objects or {}
	clone.Rooms = levelData.Rooms or {}
	return clone
end

local function createTransactionContext(plotData: Formex.PlotData, changes: {BuildChange}): TransactionContext
	local levelsTouched, hasStructureChange, objectOnly = collectLevelsTouched(changes)
	local workingLevels = table.clone(plotData.Levels or {})
	local ctx: TransactionContext = {
		PlotData = plotData,
		WorkingLevels = workingLevels,
		LevelsTouched = levelsTouched,
		HasStructureChange = hasStructureChange,
		ObjectOnly = objectOnly,
		OriginalLevels = plotData.Levels,
		OriginalNextId = plotData.NextId or 1,
		NextId = plotData.NextId or 1,
		LevelCloned = {},
		WallsCloned = {},
		FloorsCloned = {},
		ObjectsCloned = {},
		LevelMissing = {},
	}

	for _, levelIndex in ipairs(levelsTouched) do
		local levelData = plotData.Levels and plotData.Levels[levelIndex]
		if levelData then
			workingLevels[levelIndex] = cloneLevelShell(levelData)
		else
			workingLevels[levelIndex] = {
				LevelIndex = levelIndex,
				Walls = {},
				Floors = {},
				Objects = {},
				Rooms = {},
			} :: any
			ctx.LevelMissing[levelIndex] = true
		end
		ctx.LevelCloned[levelIndex] = true
	end

	return ctx
end

local function ensureLevel(ctx: TransactionContext, levelIndex: number): Formex.LevelData
	local levelData = ctx.WorkingLevels[levelIndex]
	if not levelData then
		local original = ctx.OriginalLevels and ctx.OriginalLevels[levelIndex]
		if original then
			levelData = cloneLevelShell(original)
		else
			levelData = {
				LevelIndex = levelIndex,
				Walls = {},
				Floors = {},
				Objects = {},
				Rooms = {},
			} :: any
			ctx.LevelMissing[levelIndex] = true
		end
		ctx.WorkingLevels[levelIndex] = levelData
		ctx.LevelCloned[levelIndex] = true
	end
	levelData.Walls = levelData.Walls or {}
	levelData.Floors = levelData.Floors or {}
	levelData.Objects = levelData.Objects or {}
	return levelData
end

local function ensureWallsMap(ctx: TransactionContext, levelIndex: number): {[number]: Formex.WallData}
	local levelData = ensureLevel(ctx, levelIndex)
	if not ctx.WallsCloned[levelIndex] then
		levelData.Walls = table.clone(levelData.Walls or {})
		ctx.WallsCloned[levelIndex] = true
	end
	levelData.Walls = levelData.Walls or {}
	return levelData.Walls
end

local function ensureFloorsMap(ctx: TransactionContext, levelIndex: number): {[number]: Formex.FloorData}
	local levelData = ensureLevel(ctx, levelIndex)
	if not ctx.FloorsCloned[levelIndex] then
		levelData.Floors = table.clone(levelData.Floors or {})
		ctx.FloorsCloned[levelIndex] = true
	end
	levelData.Floors = levelData.Floors or {}
	return levelData.Floors
end

local function ensureObjectsMap(ctx: TransactionContext, levelIndex: number): {[number]: Formex.ObjectData}
	local levelData = ensureLevel(ctx, levelIndex)
	if not ctx.ObjectsCloned[levelIndex] then
		levelData.Objects = table.clone(levelData.Objects or {})
		ctx.ObjectsCloned[levelIndex] = true
	end
	levelData.Objects = levelData.Objects or {}
	return levelData.Objects
end

local function getOverlapLength(a: Vector2, b: Vector2, c: Vector2, d: Vector2): number
	if math.abs(b.X - a.X) >= math.abs(b.Y - a.Y) then
		local min1, max1 = math.min(a.X, b.X), math.max(a.X, b.X)
		local min2, max2 = math.min(c.X, d.X), math.max(c.X, d.X)
		return math.min(max1, max2) - math.max(min1, min2)
	else
		local min1, max1 = math.min(a.Y, b.Y), math.max(a.Y, b.Y)
		local min2, max2 = math.min(c.Y, d.Y), math.max(c.Y, d.Y)
		return math.min(max1, max2) - math.max(min1, min2)
	end
end

local function segmentsIntersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2): boolean
	local ab = b - a
	local cd = d - c
	local ac = c - a
	local ad = d - a
	local ca = a - c
	local cb = b - c

	local cross1 = cross2(ab, ac)
	local cross2Value = cross2(ab, ad)
	local cross3 = cross2(cd, ca)
	local cross4 = cross2(cd, cb)

	if math.abs(cross1) <= EPSILON and Formex.Plot.IsPointOnSegment(c, a, b) then return true end
	if math.abs(cross2Value) <= EPSILON and Formex.Plot.IsPointOnSegment(d, a, b) then return true end
	if math.abs(cross3) <= EPSILON and Formex.Plot.IsPointOnSegment(a, c, d) then return true end
	if math.abs(cross4) <= EPSILON and Formex.Plot.IsPointOnSegment(b, c, d) then return true end
	return (cross1 > 0 and cross2Value < 0 or cross1 < 0 and cross2Value > 0)
		and (cross3 > 0 and cross4 < 0 or cross3 < 0 and cross4 > 0)
end

local function isWallIntersectionDisallowed(newStart: Vector2, newEnd: Vector2, existingStart: Vector2, existingEnd: Vector2): boolean
	local newDir = newEnd - newStart
	if math.abs(cross2(newDir, existingStart - newStart)) <= EPSILON
	and math.abs(cross2(newDir, existingEnd - newStart)) <= EPSILON then
		local overlap = getOverlapLength(newStart, newEnd, existingStart, existingEnd)
		return overlap > EPSILON
	end

	if not segmentsIntersect(newStart, newEnd, existingStart, existingEnd) then return false end
	if Formex.Plot.IsPointOnSegment(newStart, existingStart, existingEnd) or Formex.Plot.IsPointOnSegment(newEnd, existingStart, existingEnd) then return false end
	return true
end

local function validateWallGeometry(plotData: Formex.PlotData, wall: Formex.WallData): boolean
	if not wall or not wall.Start or not wall.End then return false end
	local dx = wall.End.X - wall.Start.X
	local dz = wall.End.Y - wall.Start.Y
	local length = math.sqrt(dx * dx + dz * dz)
	if length <= EPSILON then return false end
	if not Formex.Plot.IsLineWithinUnlockedSegments(wall.Start, wall.End, plotData.SegmentsUnlocked) then return false end
	return true
end

local function validateWallIntersections(levelData: Formex.LevelData, wallId: number, wall: Formex.WallData): boolean
	local walls = levelData.Walls
	if not walls then return true end
	local newStart = toVector2(wall.Start)
	local newEnd = toVector2(wall.End)
	for existingId, existing in pairs(walls) do
		if existingId ~= wallId and existing and existing.Start and existing.End then
			if isWallIntersectionDisallowed(newStart, newEnd, toVector2(existing.Start), toVector2(existing.End)) then return false end
		end
	end
	return true
end

local function getSegmentKey(a: Vector2int16, b: Vector2int16): string
	local minX = math.min(a.X, b.X)
	local minY = math.min(a.Y, b.Y)
	local maxX = math.max(a.X, b.X)
	local maxY = math.max(a.Y, b.Y)
	return string.format("%d,%d|%d,%d", minX, minY, maxX, maxY)
end

local function isSegmentOnWall(segmentStart: Vector2int16, segmentEnd: Vector2int16, wallStart: Vector2int16, wallEnd: Vector2int16): boolean
	local a1 = toVector2(segmentStart)
	local a2 = toVector2(segmentEnd)
	local b1 = toVector2(wallStart)
	local b2 = toVector2(wallEnd)
	local wallDir = b2 - b1
	if wallDir.Magnitude <= EPSILON then return false end
	if math.abs(cross2(wallDir, a1 - b1)) > EPSILON then return false end
	if math.abs(cross2(wallDir, a2 - b1)) > EPSILON then return false end
	if not Formex.Plot.IsPointOnSegment(a1, b1, b2) then return false end
	if not Formex.Plot.IsPointOnSegment(a2, b1, b2) then return false end	return true
end

local function getWallDirection2(wall: Formex.WallData): Vector2
	return Vector2.new(wall.End.X - wall.Start.X, wall.End.Y - wall.Start.Y)
end

local function chooseSideCandidate(candidates: {{Wall: Formex.WallData, Height: number, HasRoom: boolean}}): Formex.WallData?
	if #candidates == 0 then return nil end
	local best: any = nil
	for _, candidate in ipairs(candidates) do
		if not best then
			best = candidate
			continue
		end
		if candidate.HasRoom ~= best.HasRoom then
			if candidate.HasRoom then
				best = candidate
			end
		elseif candidate.Height ~= best.Height then
			if candidate.Height > best.Height then
				best = candidate
			end
		else
			if (candidate.Wall.WallId or 0) < (best.Wall.WallId or 0) then
				best = candidate
			end
		end
	end

	return best.Wall
end

local function buildWallFromSide(
	wall: Formex.WallData,
	height: number,
	frontSide: "Front" | "Back",
	backSide: "Front" | "Back"
): Formex.WallData
	local resolved = {
		WallId = wall.WallId,
		Level = wall.Level,
		Start = wall.Start,
		End = wall.End,
		Height = height,
		FrontSplitHeight = frontSide == "Front" and wall.FrontSplitHeight or wall.BackSplitHeight,
		BackSplitHeight = backSide == "Front" and wall.FrontSplitHeight or wall.BackSplitHeight,
		FrontTopMaterial = frontSide == "Front" and wall.FrontTopMaterial or wall.BackTopMaterial,
		FrontBottomMaterial = frontSide == "Front" and wall.FrontBottomMaterial or wall.BackBottomMaterial,
		BackTopMaterial = backSide == "Front" and wall.FrontTopMaterial or wall.BackTopMaterial,
		BackBottomMaterial = backSide == "Front" and wall.FrontBottomMaterial or wall.BackBottomMaterial,
		FrontTopColor = frontSide == "Front" and wall.FrontTopColor or wall.BackTopColor,
		FrontBottomColor = frontSide == "Front" and wall.FrontBottomColor or wall.BackBottomColor,
		BackTopColor = backSide == "Front" and wall.FrontTopColor or wall.BackTopColor,
		BackBottomColor = backSide == "Front" and wall.FrontBottomColor or wall.BackBottomColor,
		Part = wall.Part,
		FrontBottomPart = wall.FrontBottomPart,
		BackBottomPart = wall.BackBottomPart,
		FrontTopPart = wall.FrontTopPart,
		BackTopPart = wall.BackTopPart,
		FrontRoom = nil,
		BackRoom = nil,
	} :: Formex.WallData

	resolved.FrontSplitHeight = resolveSplitHeight(height, resolved.FrontSplitHeight, nil)
	resolved.BackSplitHeight = resolveSplitHeight(height, resolved.BackSplitHeight, nil)
	return resolved
end

local function mergeWallsForLevel(
	plotData: Formex.PlotData,
	levelIndex: number,
	levelData: Formex.LevelData,
	nextId: number
): (Formex.LevelData, number, {{Level: number, Start: Vector2int16, End: Vector2int16}}, {[number]: Formex.WallData}, {WallIdEntry}, {WallIdEntry})
	local walls = levelData.Walls or {}
	local originalWalls = walls
	local mergeSegments = {}
	local updatedWalls = {}
	local addedWalls = {}

	local segments = {}
	for wallId, wall in pairs(originalWalls) do
		if wall and wall.Start and wall.End and not isZeroLength(wall.Start, wall.End) then
			table.insert(segments, {
				Start = wall.Start,
				End = wall.End,
				Kind = "Wall",
				WallId = wallId,
				IsBoundary = false,
			} :: any)
		end
	end

	if #segments == 0 then
		levelData.Walls = {}
		return levelData, nextId, mergeSegments, {}, addedWalls, updatedWalls
	end

	table.sort(segments, function(a, b)
		return (a.WallId or 0) < (b.WallId or 0)
	end)

	local splitSegments = Formex.Poly.SplitSegments(segments, EPSILON)
	local segmentEntries = {}
	for _, segment in ipairs(splitSegments) do
		local contributors = {}
		for _, wall in pairs(originalWalls) do
			if wall and wall.Start and wall.End and isSegmentOnWall(segment.Start, segment.End, wall.Start, wall.End) then
				table.insert(contributors, wall)
			end
		end
		if #contributors > 1 then
			table.insert(mergeSegments, {
				Level = levelIndex,
				Start = segment.Start,
				End = segment.End,
			})
		end
		table.insert(segmentEntries, {
			Start = segment.Start,
			End = segment.End,
			Key = getSegmentKey(segment.Start, segment.End),
			Contributors = contributors,
		})
	end

	table.sort(segmentEntries, function(a, b)
		if a.Key == b.Key then return false end
		return a.Key < b.Key
	end)

	local assignedIds = {}
	local newWalls = {} :: {[number]: Formex.WallData}

	for _, entry in ipairs(segmentEntries) do
		local contributors = entry.Contributors
		if #contributors == 0 then
			continue
		end

		table.sort(contributors, function(a, b)
			return (a.WallId or 0) < (b.WallId or 0)
		end)

		local assignedId: number? = nil
		for _, wall in ipairs(contributors) do
			local id = wall.WallId
			if id and not assignedIds[id] then
				assignedId = id
				break
			end
		end
		if not assignedId then
			assignedId = nextId
			nextId += 1
		end
		assignedIds[assignedId] = true

		local primaryWall = nil
		for _, wall in ipairs(contributors) do
			if wall.WallId == assignedId then
				primaryWall = wall
				break
			end
		end
		if not primaryWall then
			primaryWall = contributors[1]
		end

		local primaryDir = getWallDirection2(primaryWall)
		local primaryLength2 = primaryDir:Dot(primaryDir)
		local orientedStart = entry.Start
		local orientedEnd = entry.End
		if primaryLength2 > EPSILON then
			local startVec = toVector2(entry.Start)
			local endVec = toVector2(entry.End)
			local tStart = (startVec - toVector2(primaryWall.Start)):Dot(primaryDir) / primaryLength2
			local tEnd = (endVec - toVector2(primaryWall.Start)):Dot(primaryDir) / primaryLength2
			if tStart > tEnd then
				orientedStart = entry.End
				orientedEnd = entry.Start
			end
		end

		local maxHeight = Formex.LevelHeight
		if #contributors > 0 then
			maxHeight = 0
			for _, wall in ipairs(contributors) do
				local height = resolveWallHeight(wall.Height, nil)
				if height > maxHeight then
					maxHeight = height
				end
			end
		end

		local frontCandidates = {}
		local backCandidates = {}
		for _, wall in ipairs(contributors) do
			local wallHeight = resolveWallHeight(wall.Height, nil)
			local wallDir = getWallDirection2(wall)
			local sameDirection = wallDir:Dot(primaryDir) >= 0
			local frontRoom = wall.FrontRoom
			local backRoom = wall.BackRoom
			local frontSide: "Front" | "Back" = "Front"
			local backSide: "Front" | "Back" = "Back"
			if not sameDirection then
				frontRoom, backRoom = backRoom, frontRoom
				frontSide = "Back"
				backSide = "Front"
			end
			table.insert(frontCandidates, {
				Wall = wall :: any,
				Height = wallHeight,
				HasRoom = frontRoom ~= nil,
				FrontSide = frontSide,
			})
			table.insert(backCandidates, {
				Wall = wall :: any,
				Height = wallHeight,
				HasRoom = backRoom ~= nil,
				BackSide = backSide,
			})
		end

		local frontSource = chooseSideCandidate(frontCandidates)
		local backSource = chooseSideCandidate(backCandidates)
		if not frontSource then
			frontSource = primaryWall
		end
		if not backSource then
			backSource = primaryWall
		end

		local function resolveSideForSource(source: Formex.WallData, target: "Front" | "Back"): "Front" | "Back"
			for _, candidate in ipairs(frontCandidates) do
				if candidate.Wall == source then
					return candidate.FrontSide
				end
			end
			for _, candidate in ipairs(backCandidates) do
				if candidate.Wall == source then
					return candidate.BackSide
				end
			end
			return target
		end

		local frontSide = resolveSideForSource(frontSource, "Front")
		local backSide = resolveSideForSource(backSource, "Back")

		local baseWall = frontSource
		if backSource and (backSource.WallId or 0) < (baseWall.WallId or 0) then
			baseWall = backSource
		end

		local newWall = buildWallFromSide(baseWall, maxHeight, frontSide, backSide)
		newWall.WallId = assignedId
		newWall.Level = levelIndex
		newWall.Start = orientedStart
		newWall.End = orientedEnd

		if newWall.WallId ~= (baseWall.WallId or 0) then
			newWall.Part = nil
			newWall.FrontBottomPart = nil
			newWall.BackBottomPart = nil
			newWall.FrontTopPart = nil
			newWall.BackTopPart = nil
		end

		newWalls[newWall.WallId] = newWall
	end

	for wallId, newWall in pairs(newWalls) do
		local existing = originalWalls[wallId]
		if not existing then
			table.insert(addedWalls, { Level = levelIndex, WallId = newWall.WallId })
		else
			local changed = false
			if existing.Start and existing.End then
				changed = not pointsEqual(existing.Start, newWall.Start) or not pointsEqual(existing.End, newWall.End)
			else
				changed = true
			end
			changed = changed
				or (existing.Height or Formex.LevelHeight) ~= (newWall.Height or Formex.LevelHeight)
				or (existing.FrontSplitHeight or 0) ~= (newWall.FrontSplitHeight or 0)
				or (existing.BackSplitHeight or 0) ~= (newWall.BackSplitHeight or 0)
				or (existing.FrontTopMaterial or 0) ~= (newWall.FrontTopMaterial or 0)
				or (existing.FrontBottomMaterial or 0) ~= (newWall.FrontBottomMaterial or 0)
				or (existing.BackTopMaterial or 0) ~= (newWall.BackTopMaterial or 0)
				or (existing.BackBottomMaterial or 0) ~= (newWall.BackBottomMaterial or 0)
				or (existing.FrontTopColor or Color3.new(1, 1, 1)) ~= (newWall.FrontTopColor or Color3.new(1, 1, 1))
				or (existing.FrontBottomColor or Color3.new(1, 1, 1)) ~= (newWall.FrontBottomColor or Color3.new(1, 1, 1))
				or (existing.BackTopColor or Color3.new(1, 1, 1)) ~= (newWall.BackTopColor or Color3.new(1, 1, 1))
				or (existing.BackBottomColor or Color3.new(1, 1, 1)) ~= (newWall.BackBottomColor or Color3.new(1, 1, 1))
			if changed then
				table.insert(updatedWalls, { Level = levelIndex, WallId = newWall.WallId })
			end
		end
	end

	local removedWalls = {}
	for wallId, wall in pairs(originalWalls) do
		if not newWalls[wallId] then
			table.insert(removedWalls, { Level = levelIndex, WallId = wallId })
		end
	end

	levelData.Walls = newWalls
	return levelData, nextId, mergeSegments, removedWalls, addedWalls, updatedWalls
end

local function resolvePrefab(entry: Formex.ObjectData): Formex.ObjectPrefab?
	local prefabName = entry.PrefabName
	if entry.Prefab and entry.Prefab.PrefabName then
		prefabName = entry.Prefab.PrefabName
	end
	if not prefabName then return nil end
	return Formex.Objects.GetPrefab(prefabName)
end

local function ensureObjectDesign(entry: Formex.ObjectData, prefab: Formex.ObjectPrefab)
	entry.Design = entry.Design or {}
	entry.DesignColors = entry.DesignColors or {}
	Formex.Objects.EnsureDesignDefaults(entry, prefab)
end

local function getDefaultFloorSurfaceHeights(levelIndex: number): (number, number)
	local levelTop = Formex.Plot.GetLevelOffset(levelIndex)
	local thickness = levelIndex == 1 and Formex.FoundationHeight or Formex.InterfloorHeight
	return levelTop, levelTop - thickness
end

local function getFloorSurfaceHeightsAt(plotData: Formex.PlotData, levelIndex: number, position: Vector2): (number, number)
	local fallbackTop, fallbackBottom = getDefaultFloorSurfaceHeights(levelIndex)
	local floorData = Formex.Objects.GetFloorAtPosition(plotData, levelIndex, position)
	if not floorData then
		return fallbackTop, fallbackBottom
	end
	return Formex.Objects.GetFloorSurfaceY(floorData), Formex.Objects.GetCeilingSurfaceY(floorData)
end

local function normalizeObject(entry: Formex.ObjectData, prefab: Formex.ObjectPrefab, existing: Formex.ObjectData?, plotData: Formex.PlotData): Formex.ObjectData
	local levelIndex = entry.Level or (existing and existing.Level) or 1
	local position = entry.Position or (existing and existing.Position) or Vector3.new(0, 0, 0)
	local rotation = entry.Rotation or (existing and existing.Rotation) or Vector3.new(0, 0, 0)
	local wallId = entry.WallId
	if wallId == 0 then
		wallId = nil
	end
	local side = Formex.Objects.ResolveObjectSide(entry.Side or (existing and existing.Side))

	if prefab.ObjectMount == Formex.ObjectMount.Door then
		position = Vector3.new(position.X, 0, 0)
		rotation = Vector3.new(0, 0, 0)
	elseif prefab.ObjectMount == Formex.ObjectMount.Window or prefab.ObjectMount == Formex.ObjectMount.Wall then
		position = Vector3.new(position.X, position.Y, 0)
		rotation = Vector3.new(0, 0, 0)
	elseif prefab.ObjectMount == Formex.ObjectMount.Floor or prefab.ObjectMount == Formex.ObjectMount.Ceiling then
		local _, boundsSize = Formex.Objects.GetPrefabBounds(prefab, nil)
		local position2 = Vector2.new(position.X, position.Z)
		local floorHeight, ceilingHeight = getFloorSurfaceHeightsAt(plotData, levelIndex, position2)
		if prefab.ObjectMount == Formex.ObjectMount.Floor then
			position = Vector3.new(position.X, floorHeight + (boundsSize.Y / 2), position.Z)
		else
			position = Vector3.new(position.X, ceilingHeight - (boundsSize.Y / 2), position.Z)
		end
		rotation = Vector3.new(0, rotation.Y, 0)
		wallId = nil
	else
		rotation = Vector3.new(0, rotation.Y, 0)
		wallId = nil
	end

	local resolved = {
		ObjectId = existing and existing.ObjectId or entry.ObjectId,
		Level = levelIndex,
		Position = position,
		Rotation = rotation,
		Side = side,
		WallId = wallId,
		Prefab = prefab,
		PrefabName = prefab.PrefabName,
		Design = entry.Design or (existing and existing.Design) or {},
		DesignColors = entry.DesignColors or (existing and existing.DesignColors) or {},
		IsPortal = prefab.ObjectMount == Formex.ObjectMount.Door,
		Part = existing and existing.Part or nil,
		ObjectModel = existing and existing.ObjectModel or nil,
		SubtractModel = existing and existing.SubtractModel or nil,
		DesignParts = existing and existing.DesignParts or nil,
		Properties = entry.Properties or (existing and existing.Properties) or {},
	} :: Formex.ObjectData

	ensureObjectDesign(resolved, prefab)
	return resolved
end

local function isWallMount(mount: Formex.ObjectMount?): boolean
	return mount == Formex.ObjectMount.Wall or mount == Formex.ObjectMount.Door or mount == Formex.ObjectMount.Window
end

local function isObjectValid(plotData: Formex.PlotData, levelData: Formex.LevelData, entry: Formex.ObjectData, prefab: Formex.ObjectPrefab): boolean
	if not entry.Position or not entry.Rotation then return false end
	local _, boundsSize = Formex.Objects.GetPrefabBounds(prefab, nil)
	local mount = prefab.ObjectMount

	if isWallMount(mount) then
		if not entry.WallId then return false end
		local wallData = levelData.Walls and levelData.Walls[entry.WallId]
		if not wallData then return false end
		local dir, _, startLocal, length = Formex.Objects.GetWallBasis(wallData)
		if length <= EPSILON then return false end
		local minX = boundsSize.X / 2
		local maxX = length - (boundsSize.X / 2)
		if entry.Position.X < minX - EPSILON or entry.Position.X > maxX + EPSILON then return false end
		local levelIndex = wallData.Level or entry.Level or 1
		local levelOffset = Formex.Plot.GetLevelOffset(levelIndex)
		local wallHeight = wallData.Height or Formex.LevelHeight
		local wallTop = levelOffset + wallHeight
		local anchor2 = Vector2.new(startLocal.X + dir.X * entry.Position.X, startLocal.Z + dir.Z * entry.Position.X)
		local floorData = Formex.Objects.GetFloorAtPosition(plotData, levelIndex, anchor2)
		local floorHeight = floorData and Formex.Objects.GetFloorSurfaceY(floorData) or levelOffset
		local elevation = entry.Position.Y
		if mount == Formex.ObjectMount.Door then
			elevation = 0
		end
		if elevation < -EPSILON then return false end
		local bottomY = floorHeight + elevation
		local topY = bottomY + boundsSize.Y
		if topY > wallTop + EPSILON then return false end
		return true
	end

	local position2 = Vector2.new(entry.Position.X, entry.Position.Z)
	if not Formex.Plot.IsPointInUnlockedSegments(position2, plotData.SegmentsUnlocked) then return false end
	if mount == Formex.ObjectMount.Floor or mount == Formex.ObjectMount.Ceiling then
		local floorData = Formex.Objects.GetFloorAtPosition(plotData, entry.Level or 1, position2)
		if not floorData then return false end
	end
	return true
end

local function swapSide(side: Formex.ObjectSide?): Formex.ObjectSide
	if side == Formex.ObjectSide.Back then
		return Formex.ObjectSide.Front
	end
	return Formex.ObjectSide.Back
end

local function reattachObjectsToMergedWalls(levelData: Formex.LevelData, originalWalls: {[number]: Formex.WallData})
	if not levelData.Objects or not levelData.Walls then return end
	local wallList = {}
	for _, wall in pairs(levelData.Walls) do
		table.insert(wallList, wall)
	end
	table.sort(wallList, function(a, b)
		return (a.WallId or 0) < (b.WallId or 0)
	end)

	for _, object in pairs(levelData.Objects) do
		if not object.WallId then
			continue
		end

		local oldWall = originalWalls[object.WallId]
		if not oldWall or not oldWall.Start or not oldWall.End then
			object.WallId = nil
			continue
		end

		local oldDir = getWallDirection2(oldWall)
		local oldLength = oldDir.Magnitude
		if oldLength <= EPSILON then
			object.WallId = nil
			continue
		end
		local unitDir = oldDir / oldLength
		local distance = object.Position and object.Position.X or 0
		local anchor = Vector2.new(oldWall.Start.X, oldWall.Start.Y) + (unitDir * distance)

		local matchWall: Formex.WallData? = nil
		for _, wall in ipairs(wallList) do
			if wall.Start and wall.End then
				local onSegment = Formex.Plot.IsPointOnSegment(anchor, toVector2(wall.Start), toVector2(wall.End))
				if onSegment then
					matchWall = wall
					break
				end
			end
		end

		if not matchWall then
			object.WallId = nil
			continue
		end

		local newDir = getWallDirection2(matchWall)
		local newLength = newDir.Magnitude
		if newLength <= EPSILON then
			object.WallId = nil
			continue
		end
		local newUnit = newDir / newLength
		local newDistance = (anchor - toVector2(matchWall.Start)):Dot(newUnit)
		if object.Position then
			object.Position = Vector3.new(newDistance, object.Position.Y, object.Position.Z)
		end

		if newDir:Dot(oldDir) < 0 then
			object.Side = swapSide(object.Side)
		end

		object.WallId = matchWall.WallId
	end
end

collectLevelsTouched = function(changes: {BuildChange}): ({number}, boolean, boolean)
	local levelsTouchedSet = {} :: {[number]: boolean}
	local hasWallChange = false
	local hasFloorChange = false
	local objectOnly = true

	for _, change in ipairs(changes) do
		if change.PartType == Formex.PartType.Wall then
			local walls = normalizeWallList(change.Data :: any)
			local levels = collectWallLevels(walls)
			for _, levelIndex in ipairs(levels) do
				levelsTouchedSet[levelIndex] = true
			end
			hasWallChange = true
			objectOnly = false
		elseif change.PartType == Formex.PartType.Floor then
			local floors = normalizeFloorList(change.Data :: any)
			local levels = collectFloorLevels(floors)
			for _, levelIndex in ipairs(levels) do
				levelsTouchedSet[levelIndex] = true
			end
			hasFloorChange = true
			objectOnly = false
		elseif change.PartType == Formex.PartType.Object then
			local levelIndex = (change.Data :: any).Level or 1
			levelsTouchedSet[levelIndex] = true
		end
	end

	local levelsTouched = {}
	for levelIndex in pairs(levelsTouchedSet) do
		table.insert(levelsTouched, levelIndex)
	end
	table.sort(levelsTouched)

	return levelsTouched, hasWallChange or hasFloorChange, objectOnly
end

local function getObjectBoundsCenter(plotData: Formex.PlotData, levelIndex: number, objectData: Formex.ObjectData, prefab: Formex.ObjectPrefab): (Vector3, Vector3)
	local _, boundsSize = Formex.Objects.GetPrefabBounds(prefab, objectData.ObjectModel)
	local position = objectData.Position or Vector3.new(0, 0, 0)
	local mount = prefab.ObjectMount

	if isWallMount(mount) and objectData.WallId and plotData.Levels and plotData.Levels[levelIndex] then
		local wall = plotData.Levels[levelIndex].Walls[objectData.WallId]
		if wall and wall.Start and wall.End then
			local dir, right, startLocal = Formex.Objects.GetWallBasis(wall)
			local anchor2 = Vector2.new(startLocal.X + dir.X * position.X, startLocal.Z + dir.Z * position.X)
			local floorHeight, _ = getFloorSurfaceHeightsAt(plotData, levelIndex, anchor2)
			local elevation = position.Y
			if mount == Formex.ObjectMount.Door then
				elevation = 0
			end
			local centerY = floorHeight + elevation + (boundsSize.Y / 2)
			local normal = right
			if objectData.Side ~= Formex.ObjectSide.Back then
				normal = -right
			end
			local offset = 0
			if mount == Formex.ObjectMount.Wall then
				offset = (Formex.WallThickness / 2) + (boundsSize.Z / 2)
			end
			return Vector3.new(anchor2.X, centerY, anchor2.Y) + (normal * offset), boundsSize
		end
	end

	local center = position
	return center, boundsSize
end

local function collectObjectCollisions(plotData: Formex.PlotData, levelIndex: number, objects: {[number]: Formex.ObjectData})
	local function normalizeObjectId(objectId: any, objectData: Formex.ObjectData): string
		local raw = objectData.ObjectId
		if raw == nil then
			raw = objectId
		end
		local numeric = tonumber(raw)
		if numeric then
			return tostring(numeric)
		end
		return tostring(raw)
	end

	local function preferEntry(existingKeyType: string?, objectId: any, objectData: Formex.ObjectData): boolean
		if objectData.ObjectId == nil then return false end
		local desiredType = type(objectData.ObjectId)
		if desiredType ~= "number" and desiredType ~= "string" then return false end
		local keyType = type(objectId)
		if keyType == desiredType and existingKeyType ~= desiredType then return true end
		return false
	end

	local entries = {}
	local entriesById = {} :: {[string]: {KeyType: string?, Index: number}}
	for objectId, objectData in pairs(objects) do
		local prefab = objectData.Prefab or resolvePrefab(objectData)
		if prefab then
			local center, size = getObjectBoundsCenter(plotData, levelIndex, objectData, prefab)
			local entry = {
				Object = objectData,
				Prefab = prefab,
				Center = center,
				Size = size,
				IsPortal = objectData.IsPortal == true or prefab.ObjectMount == Formex.ObjectMount.Door,
			}
			local idKey = normalizeObjectId(objectId, objectData)
			local existing = entriesById[idKey]
			if existing then
				if preferEntry(existing.KeyType, objectId, objectData) then
					existing.KeyType = type(objectId)
					entries[existing.Index] = entry
				end
			else
				table.insert(entries, entry)
				entriesById[idKey] = {
					KeyType = type(objectId),
					Index = #entries,
				}
			end
		end
	end

	local removals = {} :: {[Formex.ObjectData]: boolean}
	for i = 1, #entries do
		local a = entries[i]
		if removals[a.Object] then
			continue
		end
		for j = i + 1, #entries do
			local b = entries[j]
			if removals[b.Object] then
				continue
			end
			local dx = math.abs(a.Center.X - b.Center.X)
			local dy = math.abs(a.Center.Y - b.Center.Y)
			local dz = math.abs(a.Center.Z - b.Center.Z)
			if dx <= (a.Size.X + b.Size.X) / 2 + EPSILON
				and dy <= (a.Size.Y + b.Size.Y) / 2 + EPSILON
				and dz <= (a.Size.Z + b.Size.Z) / 2 + EPSILON then
				local keepA = true
				if a.IsPortal ~= b.IsPortal then
					keepA = a.IsPortal
				else
					local idA = tonumber(a.Object.ObjectId) or math.huge
					local idB = tonumber(b.Object.ObjectId) or math.huge
					keepA = idA <= idB
				end
				if keepA then
					removals[b.Object] = true
				else
					removals[a.Object] = true
					break
				end
			end
		end
	end

	return removals
end

local function applyTransaction(plotData: Formex.PlotData, changes: {BuildChange}, options: TransactionOptions?): TransactionResult
	local results = {}
	local updatedWalls = {} :: {number}
	local addedWalls = {} :: {WallIdEntry}
	local removedWalls = {} :: {WallIdEntry}
	local updatedFloors = {} :: {FloorIdEntry}
	local addedFloors = {} :: {FloorIdEntry}
	local removedFloors = {} :: {FloorIdEntry}
	local updatedObjects = {} :: {ObjectIdEntry}
	local addedObjects = {} :: {ObjectIdEntry}
	local mergeSegments = {} :: {MergedSegmentEntry}
	local removedObjects = {} :: {ObjectIdEntry}
	local didChange = false
	local originalLevels = plotData and plotData.Levels
	local originalNextId = plotData and plotData.NextId or 1
	local function rollback()
		if not plotData then return end
		plotData.Levels = originalLevels
		plotData.NextId = originalNextId
	end

	local function invalid(message: string): TransactionResult
		if plotData and plotData.Levels ~= originalLevels then
			plotData.Levels = originalLevels
		end
		return {
			IsValid = false,
			Error = message,
			DidChange = false,
			Results = results,
			LevelsTouched = {},
			MergeSegments = mergeSegments,
			RemovedObjects = removedObjects,
			UpdatedWalls = updatedWalls,
			AddedWalls = addedWalls,
			RemovedWalls = removedWalls,
			UpdatedFloors = updatedFloors,
			AddedFloors = addedFloors,
			RemovedFloors = removedFloors,
			UpdatedObjects = updatedObjects,
			AddedObjects = addedObjects,
			Rollback = rollback,
		}
	end

	if not plotData then
		return invalid("Invalid plot data")
	end
	if not changes or #changes == 0 then
		return invalid("Invalid build transaction")
	end

	local settings = options or {}
	local ctx = createTransactionContext(plotData, changes)
	local levelsTouched = ctx.LevelsTouched
	local hasStructureChange = ctx.HasStructureChange
	local objectOnly = ctx.ObjectOnly
	local workingLevels = ctx.WorkingLevels
	local nextId = ctx.NextId
	plotData.Levels = workingLevels

	for _, change in ipairs(changes) do
		local partType = change.PartType
		local action = change.Action
		local data = change.Data
		if partType == Formex.PartType.Wall then
			local wallList, isBatch = normalizeWallList(data :: any)
			local resultIds = {}
			for _, entry in ipairs(wallList) do
				if not entry.Start or not entry.End then
					return invalid("Invalid wall data")
				end

				local levelIndex = entry.Level or 1
				local walls = ensureWallsMap(ctx, levelIndex)

				if action == Formex.BuildAction.Add then
					local height = resolveWallHeight(entry.Height, nil)
					local frontSplitHeight = resolveSplitHeight(height, entry.FrontSplitHeight, nil)
					local backSplitHeight = resolveSplitHeight(height, entry.BackSplitHeight, nil)

					local frontBottomMaterial, frontTopMaterial = resolveSideMaterials(
						entry.FrontTopMaterial,
						entry.FrontBottomMaterial,
						entry.FrontMaterial,
						nil,
						nil,
						nil,
						Formex.DefaultWallMaterial
					)
					local backBottomMaterial, backTopMaterial = resolveSideMaterials(
						entry.BackTopMaterial,
						entry.BackBottomMaterial,
						entry.BackMaterial,
						nil,
						nil,
						nil,
						frontBottomMaterial
					)

					local frontBottomColor, frontTopColor = resolveSideColors(
						entry.FrontTopColor,
						entry.FrontBottomColor,
						nil,
						nil,
						nil
					)
					local backBottomColor, backTopColor = resolveSideColors(
						entry.BackTopColor,
						entry.BackBottomColor,
						nil,
						nil,
						frontBottomColor
					)

					local newId = nextId
					nextId += 1
					local newWall = {
						WallId = newId,
						Level = levelIndex,
						Start = entry.Start,
						End = entry.End,
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
						Part = nil,
						FrontRoom = nil,
						BackRoom = nil,
					} :: Formex.WallData
					walls[newId] = newWall
					table.insert(addedWalls, { Level = levelIndex, WallId = newId })
					table.insert(resultIds, newId)
					didChange = true
				elseif action == Formex.BuildAction.Edit then
					local existing = walls[entry.WallId]
					if not existing then
						return invalid("Wall not found")
					end

					if isZeroLength(entry.Start, entry.End) then
						walls[entry.WallId] = nil
						table.insert(removedWalls, { Level = levelIndex, WallId = entry.WallId })
						table.insert(resultIds, entry.WallId)
						didChange = true
					else
						local height = resolveWallHeight(entry.Height, existing.Height)
						local frontSplitHeight = resolveSplitHeight(height, entry.FrontSplitHeight, existing.FrontSplitHeight)
						local backSplitHeight = resolveSplitHeight(height, entry.BackSplitHeight, existing.BackSplitHeight)

						local frontBottomMaterial, frontTopMaterial = resolveSideMaterials(
							entry.FrontTopMaterial,
							entry.FrontBottomMaterial,
							entry.FrontMaterial,
							existing.FrontTopMaterial,
							existing.FrontBottomMaterial,
							existing.FrontMaterial,
							Formex.DefaultWallMaterial
						)
						local backBottomMaterial, backTopMaterial = resolveSideMaterials(
							entry.BackTopMaterial,
							entry.BackBottomMaterial,
							entry.BackMaterial,
							existing.BackTopMaterial,
							existing.BackBottomMaterial,
							existing.BackMaterial,
							frontBottomMaterial
						)

						local frontBottomColor, frontTopColor = resolveSideColors(
							entry.FrontTopColor,
							entry.FrontBottomColor,
							existing.FrontTopColor,
							existing.FrontBottomColor,
							nil
						)
						local backBottomColor, backTopColor = resolveSideColors(
							entry.BackTopColor,
							entry.BackBottomColor,
							existing.BackTopColor,
							existing.BackBottomColor,
							frontBottomColor
						)

						local updated = {
							WallId = existing.WallId,
							Level = levelIndex,
							Start = entry.Start,
							End = entry.End,
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
							Part = existing.Part,
							FrontBottomPart = existing.FrontBottomPart,
							BackBottomPart = existing.BackBottomPart,
							FrontTopPart = existing.FrontTopPart,
							BackTopPart = existing.BackTopPart,
							Room = existing.Room,
						} :: Formex.WallData
						walls[existing.WallId] = updated
						table.insert(updatedWalls, { Level = levelIndex, WallId = existing.WallId })
						table.insert(resultIds, existing.WallId)
						didChange = true
					end
				elseif action == Formex.BuildAction.Delete then
					local existing = walls[entry.WallId]
					if existing then
						walls[entry.WallId] = nil
						table.insert(removedWalls, { Level = levelIndex, WallId = entry.WallId })
						table.insert(resultIds, entry.WallId)
						didChange = true
					end
				else
					return invalid("Invalid wall action")
				end
			end

			table.insert(results, {
				PartType = partType,
				Action = action,
				Result = isBatch and resultIds or resultIds[1],
			})
		elseif partType == Formex.PartType.Floor then
			local floorList, isBatch = normalizeFloorList(data :: any)
			local resultIds = {}
			for _, entry in ipairs(floorList) do
				local levelIndex = entry.LevelIndex or 1
				local floors = ensureFloorsMap(ctx, levelIndex)

				if action == Formex.BuildAction.Add then
					local newId = nextId
					nextId += 1
					local updated = {
						FloorId = newId,
						LevelIndex = levelIndex,
						Points = entry.Points,
						RaiseHeight = resolveRaiseHeight(entry.RaiseHeight, nil),
						FloorMaterial = entry.FloorMaterial,
						CeilingMaterial = entry.CeilingMaterial,
						FoundationMaterial = entry.FoundationMaterial,
						FloorColor = resolveColor(entry.FloorColor, nil),
						CeilingColor = resolveColor(entry.CeilingColor, entry.FloorColor),
						FoundationColor = resolveColor(entry.FoundationColor, entry.FloorColor),
						Model = nil,
					} :: Formex.FloorData
					floors[newId] = updated
					table.insert(addedFloors, { Level = levelIndex, FloorId = newId })
					table.insert(resultIds, newId)
					didChange = true
				elseif action == Formex.BuildAction.Edit then
					local existing = floors[entry.FloorId]
					if not existing then
						return invalid("Floor not found")
					end
					local updated = {
						FloorId = existing.FloorId,
						LevelIndex = levelIndex,
						Points = entry.Points or existing.Points,
						RaiseHeight = resolveRaiseHeight(entry.RaiseHeight, existing.RaiseHeight),
						FloorMaterial = entry.FloorMaterial or existing.FloorMaterial,
						CeilingMaterial = entry.CeilingMaterial or existing.CeilingMaterial,
						FoundationMaterial = entry.FoundationMaterial or existing.FoundationMaterial,
						FloorColor = resolveColor(entry.FloorColor, existing.FloorColor),
						CeilingColor = resolveColor(entry.CeilingColor, existing.CeilingColor),
						FoundationColor = resolveColor(entry.FoundationColor, existing.FoundationColor),
						Model = existing.Model,
						FloorPart = existing.FloorPart,
						FoundationPart = existing.FoundationPart,
						CeilingPart = existing.CeilingPart,
						FloorClientPart = existing.FloorClientPart,
						FoundationClientPart = existing.FoundationClientPart,
						CeilingClientPart = existing.CeilingClientPart,
						Room = existing.Room,
					} :: Formex.FloorData
					floors[existing.FloorId] = updated
					table.insert(updatedFloors, { Level = levelIndex, FloorId = existing.FloorId })
					table.insert(resultIds, existing.FloorId)
					didChange = true
				elseif action == Formex.BuildAction.Delete then
					local existing = floors[entry.FloorId]
					if existing then
						floors[entry.FloorId] = nil
						table.insert(removedFloors, { Level = levelIndex, FloorId = entry.FloorId })
						table.insert(resultIds, entry.FloorId)
						didChange = true
					end
				else
					return invalid("Invalid floor action")
				end
			end

			table.insert(results, {
				PartType = partType,
				Action = action,
				Result = isBatch and resultIds or resultIds[1],
			})
		elseif partType == Formex.PartType.Object then
			local levelIndex = data.Level or 1
			local objects = ensureObjectsMap(ctx, levelIndex)
			if action == Formex.BuildAction.Add then
				local prefab = resolvePrefab(data :: any)
				if not prefab then
					return invalid("Invalid object prefab")
				end
				local newId = nextId
				nextId += 1
				data.ObjectId = newId
				data.Level = levelIndex
				local resolved = normalizeObject(data :: any, prefab, nil, plotData)
				objects[newId] = resolved
				table.insert(addedObjects, { Level = levelIndex, ObjectId = newId })
				table.insert(results, {
					PartType = partType,
					Action = action,
					Result = newId,
				})
				didChange = true
			elseif action == Formex.BuildAction.Edit then
				local objectId = tonumber(data.ObjectId) or data.ObjectId
				local existing = objectId and objects[objectId]
				if not existing then
					return invalid("Object not found")
				end
				local prefab = resolvePrefab(data :: any) or existing.Prefab
				if not prefab then
					return invalid("Invalid object prefab")
				end
				local resolved = normalizeObject(data :: any, prefab, existing, plotData)
				objects[objectId] = resolved
				table.insert(updatedObjects, { Level = levelIndex, ObjectId = objectId })
				table.insert(results, {
					PartType = partType,
					Action = action,
					Result = objectId,
				})
				didChange = true
			elseif action == Formex.BuildAction.Delete then
				local objectId = tonumber(data.ObjectId) or data.ObjectId
				local existing = objectId and objects[objectId]
				if existing then
					objects[objectId] = nil
					table.insert(removedObjects, { Level = levelIndex, ObjectId = objectId })
					didChange = true
				end
				table.insert(results, {
					PartType = partType,
					Action = action,
					Result = existing and objectId or nil,
				})
			else
				return invalid("Invalid object action")
			end
		else
			return invalid("Invalid build change type")
		end
	end

	if hasStructureChange and not objectOnly then
		for _, levelIndex in ipairs(levelsTouched) do
			local levelData = workingLevels[levelIndex]
			if levelData and levelData.Walls then
				local originalWalls = table.clone(levelData.Walls)
				local mergedLevel, mergedNextId, mergeList, removedAfterMerge, addedAfterMerge, updatedAfterMerge =
					mergeWallsForLevel(plotData, levelIndex, levelData, nextId)
				workingLevels[levelIndex] = mergedLevel
				nextId = mergedNextId
				for _, segment in ipairs(mergeList) do
					table.insert(mergeSegments, segment)
				end
				for _, wall in ipairs(removedAfterMerge) do
					table.insert(removedWalls, wall)
				end
				for _, wall in ipairs(addedAfterMerge) do
					table.insert(addedWalls, wall)
				end
				for _, wall in ipairs(updatedAfterMerge) do
					table.insert(updatedWalls, wall)
				end
				reattachObjectsToMergedWalls(mergedLevel, originalWalls)
			end
		end
	end

	for _, levelIndex in ipairs(levelsTouched) do
		local levelData = workingLevels[levelIndex]
		if levelData then
			for wallId, wall in pairs(levelData.Walls) do
				if not validateWallGeometry(plotData, wall) then
					return invalid("Invalid wall placement")
				end
				if not validateWallIntersections(levelData, wallId, wall) then
					return invalid("Invalid wall placement")
				end
			end

			for _, floor in pairs(levelData.Floors) do
				if floor and floor.Points and #floor.Points >= 3 then
					if not Formex.Floors.IsValid(plotData, floor) then
						return invalid("Invalid floor placement")
					end
				end
			end

			local objects = ensureObjectsMap(ctx, levelIndex)
			for objectId, objectData in pairs(objects) do
				local prefab = objectData.Prefab or resolvePrefab(objectData)
				if prefab then
					local normalized = normalizeObject(objectData, prefab, objectData, plotData)
					objects[objectId] = normalized
					local valid = isObjectValid(plotData, levelData, normalized, prefab)
					if not valid then
						if objectOnly then
							return invalid("Invalid object placement")
						end
						objects[objectId] = nil
						table.insert(removedObjects, { Level = levelIndex, ObjectId = objectId })
					else
						objects[objectId] = normalized
					end
				else
					if objectOnly then
						return invalid("Invalid object prefab")
					end
					objects[objectId] = nil
					table.insert(removedObjects, { Level = levelIndex, ObjectId = objectId })
				end
			end

			if not settings.SkipObjectCollisions then
				local removals = collectObjectCollisions(plotData, levelIndex, objects)
				if objectOnly then
					if next(removals) ~= nil then
						for objectData in pairs(removals) do
							local id = objectData.ObjectId
							table.insert(removedObjects, { Level = levelIndex, ObjectId = id })
						end
						return invalid("Object collision")
					end
				else
					for objectData in pairs(removals) do
						local id = objectData.ObjectId
						objects[id] = nil
						table.insert(removedObjects, { Level = levelIndex, ObjectId = id })
					end
				end
			end
		end
	end

	if settings.Commit then
		plotData.Levels = workingLevels
		plotData.NextId = nextId
	else
		plotData.Levels = originalLevels
	end

	return {
		IsValid = true,
		Error = nil,
		DidChange = didChange,
		Results = results,
		LevelsTouched = levelsTouched,
		MergeSegments = mergeSegments,
		RemovedObjects = removedObjects,
		UpdatedWalls = updatedWalls,
		AddedWalls = addedWalls,
		RemovedWalls = removedWalls,
		UpdatedFloors = updatedFloors,
		AddedFloors = addedFloors,
		RemovedFloors = removedFloors,
		UpdatedObjects = updatedObjects,
		AddedObjects = addedObjects,
		Levels = workingLevels,
		NextId = nextId,
		Rollback = rollback,
	}
end

function Formex.Transaction.Apply(plotData: Formex.PlotData, changes: {BuildChange}, options: TransactionOptions?): TransactionResult
	print("Applying transaction with " .. tostring(#changes) .. " changes", changes[1])
	return applyTransaction(plotData, changes, options or {Commit = true})
end

function Formex.Transaction.Validate(plotData: Formex.PlotData, changes: {BuildChange}): TransactionResult
	return applyTransaction(plotData, changes, {Commit = false})
end

function Formex.IsTransactionValid(plotData: Formex.PlotData, changes: {BuildChange}): TransactionResult
	return Formex.Transaction.Validate(plotData, changes)
end

return Formex.Transaction
