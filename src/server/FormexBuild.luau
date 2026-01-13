--!strict

local Formex = require(script.Parent:FindFirstChild("FormexServer"))
local FormexSystem = require(script.Parent:FindFirstChild("FormexSystem"))

local PhysicsService = game:GetService("PhysicsService")
PhysicsService:RegisterCollisionGroup(Formex.CollisionGroup.Grid)
PhysicsService:RegisterCollisionGroup(Formex.CollisionGroup.Structure)
PhysicsService:RegisterCollisionGroup(Formex.CollisionGroup.Object)

-- Grid only collides with grid
PhysicsService:CollisionGroupSetCollidable(Formex.CollisionGroup.Grid, Formex.CollisionGroup.Grid, true)

-- Walls and objects collide with each other (ignores objects)
PhysicsService:CollisionGroupSetCollidable(Formex.CollisionGroup.Structure, Formex.CollisionGroup.Structure, true)
PhysicsService:CollisionGroupSetCollidable(Formex.CollisionGroup.Structure, "Default", true)

-- Objects collide with everything except grids
PhysicsService:CollisionGroupSetCollidable(Formex.CollisionGroup.Object, Formex.CollisionGroup.Structure, true)
PhysicsService:CollisionGroupSetCollidable(Formex.CollisionGroup.Object, Formex.CollisionGroup.Object, true)
PhysicsService:CollisionGroupSetCollidable(Formex.CollisionGroup.Object, "Default", true)

local FormexBuild = {}

local function takeNextId(plotData: Formex.PlotData): number
	local nextId = plotData.NextId
	if not nextId or nextId < 1 then
		nextId = 1
	end
	plotData.NextId = nextId + 1
	return nextId
end

type HistoryTransaction = {
	Levels: Formex.LevelArray,
	Selection: Formex.SelectionSnapshot?,
}

type HistoryState = {
	Undo: {HistoryTransaction},
	Redo: {HistoryTransaction},
}

type WallIdEntry = {
	Level: number,
	WallId: number,
}

type ObjectIdEntry = {
	Level: number,
	ObjectId: number | string,
}

type TransactionResult = {
	LevelsTouched: {number}?,
	UpdatedWalls: {WallIdEntry}?,
	AddedWalls: {WallIdEntry}?,
	AddedObjects: {ObjectIdEntry}?,
	UpdatedObjects: {ObjectIdEntry}?,
	RemovedObjects: {ObjectIdEntry}?,
}

local historyByPlot = {} :: {[number]: {[number]: HistoryState}}

local function getHistory(plotId: number, userId: number): HistoryState
	local plotHistory = historyByPlot[plotId]
	if not plotHistory then
		plotHistory = {}
		historyByPlot[plotId] = plotHistory
	end

	local history = plotHistory[userId]
	if not history then
		history = {
			Undo = {},
			Redo = {},
		}
		plotHistory[userId] = history
	end

	return history
end

local function getHistoryIfExists(plotId: number, userId: number): HistoryState?
	local plotHistory = historyByPlot[plotId]
	if not plotHistory then
		return nil
	end
	return plotHistory[userId]
end

local function pushUndo(plotId: number, userId: number, snapshot: Formex.LevelArray, selection: Formex.SelectionSnapshot?)
	local history = getHistory(plotId, userId)
	table.insert(history.Undo, {
		Levels = snapshot,
		Selection = selection,
	})
	if #history.Undo > Formex.MaxUndoQueueSize then
		table.remove(history.Undo, 1)
	end
	table.clear(history.Redo)
end

local function updatePlayerUndoRedoAttributes(player: Player, plotId: number?)
	if not player then
		return
	end

	if not plotId or plotId == 0 then
		player:SetAttribute("CanUndo", false)
		player:SetAttribute("CanRedo", false)
		return
	end

	local history = getHistoryIfExists(plotId, player.UserId)
	local canUndo = history ~= nil and #history.Undo > 0
	local canRedo = history ~= nil and #history.Redo > 0
	player:SetAttribute("CanUndo", canUndo)
	player:SetAttribute("CanRedo", canRedo)
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

local function cloneLevelForSnapshot(snapshot: Formex.LevelArray, levels: Formex.LevelArray, levelIndex: number)
	local levelData = levels[levelIndex]
	if not levelData then
		return
	end

	local levelClone = table.clone(levelData)
	levelClone.Walls = table.clone(levelData.Walls)
	levelClone.Floors = table.clone(levelData.Floors)
	levelClone.Objects = table.clone(levelData.Objects)
	snapshot[levelIndex] = levelClone
end

local function createSnapshot(levels: Formex.LevelArray, levelIndex: number): Formex.LevelArray
	local snapshot = table.clone(levels)
	cloneLevelForSnapshot(snapshot, levels, levelIndex)
	return snapshot
end

local function createSnapshotForLevels(levels: Formex.LevelArray, levelIndices: {number}): Formex.LevelArray
	local snapshot = table.clone(levels)
	for _, levelIndex in ipairs(levelIndices) do
		cloneLevelForSnapshot(snapshot, levels, levelIndex)
	end
	return snapshot
end

local function isZeroLength(startPoint: Vector2int16, endPoint: Vector2int16): boolean
	return startPoint.X == endPoint.X and startPoint.Y == endPoint.Y
end

local function snapToGrid(value: number): number
	local grid = Formex.LayoutGridSize
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
	resolved = snapToGrid(resolved)
	return math.clamp(resolved, Formex.LayoutGridSize, Formex.LevelHeight)
end

local function resolveSplitHeight(height: number, value: number?, existing: number?): number?
	local resolved = value
	if resolved == nil then
		resolved = existing
	end
	if resolved == nil or resolved <= 0 or height <= Formex.LayoutGridSize * 2 then
		return 0
	end
	local snapped = snapToGrid(resolved)
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
	local snapped = math.round(resolved / Formex.GridSize) * Formex.GridSize
	local maxHeight = Formex.LevelHeight - Formex.InterfloorHeight
	if maxHeight < 0 then
		maxHeight = 0
	end
	return math.clamp(snapped, 0, maxHeight)
end

local function resolveColor(value: Color3?, fallback: Color3?): Color3
	return value or fallback or Color3.new(1, 1, 1)
end

local function normalizeMaterialId(value: number?): number?
	if type(value) ~= "number" or value <= 0 then
		return nil
	end
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

local function isWallMount(mount: Formex.ObjectMount?): boolean
	return mount == Formex.MountType.Wall or mount == Formex.MountType.Door or mount == Formex.MountType.Window
end

local function isDoorWindowMount(mount: Formex.ObjectMount?): boolean
	return mount == Formex.MountType.Door or mount == Formex.MountType.Window
end

local function rebuildWallModels(
	plotData: Formex.PlotData,
	rebuildWalls: {{Level: number, WallId: number}},
	removedParts: {BasePart}
)
	local seen = {} :: {[string]: boolean}
	for _, entry in ipairs(rebuildWalls) do
		local key = tostring(entry.Level) .. ":" .. tostring(entry.WallId)
		if seen[key] then
			continue
		end
		seen[key] = true

		local levelData = plotData.Levels and plotData.Levels[entry.Level]
		local wallData = levelData and levelData.Walls and levelData.Walls[entry.WallId]
		if wallData and wallData.Part then
			table.insert(removedParts, wallData.Part)
			wallData.Part = nil
		end
	end
end

local function syncWallMountedObjects(
	plotData: Formex.PlotData,
	plotPart: BasePart?,
	movedWalls: {{Old: Formex.WallData, New: Formex.WallData}},
	removedParts: {BasePart}
): {[number]: boolean}
	local rebuildLevels = {} :: {[number]: boolean}
	for _, moved in ipairs(movedWalls) do
		local levelIndex = moved.New.Level or moved.Old.Level or 1
		local levelData = plotData.Levels[levelIndex]
		if not levelData or not levelData.Objects then
			continue
		end

		local wallId = moved.New.WallId
		local hasDoorWindow = false

		for _, objectData in pairs(levelData.Objects) do
			if objectData.WallId == wallId then
				local prefab = objectData.Prefab or (objectData.PrefabName and Formex.Objects.GetPrefab(objectData.PrefabName))
				if prefab then
					objectData.Prefab = prefab
					if isWallMount(prefab.ObjectMount) then
						local position = objectData.Position or Vector3.new(0, 0, 0)
						local newY = position.Y
						if prefab.ObjectMount == Formex.MountType.Door then
							newY = 0
						end
						if position.Z ~= 0 or newY ~= position.Y then
							objectData.Position = Vector3.new(position.X, newY, 0)
						end
						if plotPart then
							Formex.Objects.EditObject(objectData, plotPart, plotData)
						end
						if prefab.ObjectMount == Formex.MountType.Door or prefab.ObjectMount == Formex.MountType.Window then
							hasDoorWindow = true
						end
					end
				end
			end
		end

		if hasDoorWindow then
			local wallData = levelData.Walls[wallId]
			if wallData and wallData.Part then
				table.insert(removedParts, wallData.Part)
				wallData.Part = nil
			end
			rebuildLevels[levelIndex] = true
		end
	end
	return rebuildLevels
end

local function applyWallChanges(plotData: Formex.PlotData, wallData: Formex.WallData | {Formex.WallData}, action: Formex.BuildAction, snapshot: Formex.LevelArray?): any
	plotData.Levels = plotData.Levels or {}
	local wallList, isBatch = normalizeWallList(wallData)
	local levelsTouched = collectWallLevels(wallList)
	local resolvedSnapshot = snapshot or createSnapshotForLevels(plotData.Levels, levelsTouched)

	local updatedWalls = {} :: {Formex.WallData}
	local returnWalls = {} :: {Formex.WallData}
	local movedWalls = {} :: {{Old: Formex.WallData, New: Formex.WallData}}
	local removedParts = {} :: {BasePart}
	local removedWallIds = {} :: {[number]: {[number]: boolean}}
	local didChange = false

	if action == Formex.BuildAction.Add then
		for _, entry in ipairs(wallList) do
			if not entry.Start or not entry.End then
				error("Invalid wall data")
			end

			local levelIndex = entry.Level or 1
			local levelData = FormexSystem.EnsureLevelData(plotData, levelIndex)

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

			local newId = takeNextId(plotData)
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
				Part = nil
			}
			levelData.Walls[newId] = newWall
			table.insert(updatedWalls, newWall)
			table.insert(returnWalls, {
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
				Part = nil
			})
		end

		for _, wall in ipairs(updatedWalls) do
			if not Formex.IsWallValid(plotData, wall) then
				plotData.Levels = resolvedSnapshot
				error("Invalid wall placement")
			end
		end
		didChange = #updatedWalls > 0
	elseif action == Formex.BuildAction.Edit then
		for _, entry in ipairs(wallList) do
			local levelIndex = entry.Level or 1
			local levelData = plotData.Levels[levelIndex]
			if not levelData then
				plotData.Levels = resolvedSnapshot
				error("Wall not found")
			end

			local existing = levelData.Walls[entry.WallId]
			if not existing then
				plotData.Levels = resolvedSnapshot
				error("Wall not found")
			end
			if not entry.Start or not entry.End then
				plotData.Levels = resolvedSnapshot
				error("Invalid wall data")
			end

			if isZeroLength(entry.Start, entry.End) then
				if existing.Part then
					table.insert(removedParts, existing.Part)
				end
				removedWallIds[levelIndex] = removedWallIds[levelIndex] or {}
				removedWallIds[levelIndex][existing.WallId] = true
				levelData.Walls[entry.WallId] = nil
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
					Part = existing.Part
				}
				levelData.Walls[existing.WallId] = updated
				if existing.Start.X ~= entry.Start.X
					or existing.Start.Y ~= entry.Start.Y
					or existing.End.X ~= entry.End.X
					or existing.End.Y ~= entry.End.Y then
					table.insert(movedWalls, {
						Old = existing,
						New = updated,
					})
				end
				table.insert(updatedWalls, updated)
				table.insert(returnWalls, {
					WallId = updated.WallId,
					Level = updated.Level,
					Start = updated.Start,
					End = updated.End,
					Height = updated.Height,
					FrontSplitHeight = updated.FrontSplitHeight,
					BackSplitHeight = updated.BackSplitHeight,
					FrontTopMaterial = updated.FrontTopMaterial,
					FrontBottomMaterial = updated.FrontBottomMaterial,
					BackTopMaterial = updated.BackTopMaterial,
					BackBottomMaterial = updated.BackBottomMaterial,
					FrontTopColor = updated.FrontTopColor,
					FrontBottomColor = updated.FrontBottomColor,
					BackTopColor = updated.BackTopColor,
					BackBottomColor = updated.BackBottomColor,
					Part = nil
				})
				didChange = true
			end
		end

		for _, wall in ipairs(updatedWalls) do
			if not Formex.IsWallValid(plotData, wall) then
				plotData.Levels = resolvedSnapshot
				error("Invalid wall placement")
			end
		end
	elseif action == Formex.BuildAction.Delete then
		for _, entry in ipairs(wallList) do
			local levelIndex = entry.Level or 1
			local levelData = plotData.Levels[levelIndex]
			if levelData then
				local existing = levelData.Walls[entry.WallId]
				if existing then
					if existing.Part then
						existing.Part:Destroy()
					end
					removedWallIds[levelIndex] = removedWallIds[levelIndex] or {}
					removedWallIds[levelIndex][existing.WallId] = true
					levelData.Walls[entry.WallId] = nil
					didChange = true
				end
			end
		end
	else
		error("Invalid wall action")
	end

	for levelIndex, wallIds in pairs(removedWallIds) do
		local levelData = plotData.Levels[levelIndex]
		if levelData and levelData.Objects then
			for objectId, object in pairs(levelData.Objects) do
				if object.WallId and wallIds[object.WallId] then
					local prefab = object.Prefab or (object.PrefabName and Formex.Objects.GetPrefab(object.PrefabName))
					if prefab and (prefab.ObjectMount == Formex.MountType.Wall
						or prefab.ObjectMount == Formex.MountType.Door
						or prefab.ObjectMount == Formex.MountType.Window) then
						if object.Part then
							object.Part:Destroy()
						end
						levelData.Objects[objectId] = nil
					end
				end
			end
		end
	end

	return {
		DidChange = didChange,
		IsBatch = isBatch,
		ReturnList = returnWalls,
		ReturnSingle = returnWalls[1],
		LevelsTouched = levelsTouched,
		RemovedParts = removedParts,
		RemovedWallIds = removedWallIds,
		RenderWallsLevels = levelsTouched,
		RenderObjectsLevels = levelsTouched,
		MovedWalls = movedWalls,
		Snapshot = resolvedSnapshot,
	}
end

function FormexBuild.BuildWall(player: Player, wallData: Formex.WallData | {Formex.WallData}, action: Formex.BuildAction, selection: Formex.SelectionSnapshot?)
	local results = FormexBuild.BuildTransaction(player, {
		{
			PartType = Formex.PartType.Wall,
			Action = action,
			Data = wallData,
		},
	}, selection)
	if not results then
		return nil
	end
	local changeResult = results[1]
	return changeResult and changeResult.Result or nil
end

local function applyFloorChanges(plotData: Formex.PlotData, floorData: Formex.FloorData | {Formex.FloorData}, action: Formex.BuildAction, snapshot: Formex.LevelArray?): any
	plotData.Levels = plotData.Levels or {}
	local floorList, isBatch = normalizeFloorList(floorData)
	local levelsTouched = collectFloorLevels(floorList)
	local resolvedSnapshot = snapshot or createSnapshotForLevels(plotData.Levels, levelsTouched)

	local updatedFloors = {} :: {Formex.FloorData}
	local returnFloors = {} :: {Formex.FloorData}
	local removedModels = {} :: {Model}
	local didChange = false

	if action == Formex.BuildAction.Add then
		for _, entry in ipairs(floorList) do
			if not entry.Points or #entry.Points < 3 then
				error("Invalid floor data")
			end

			local levelIndex = entry.LevelIndex or 1
			local levelData = FormexSystem.EnsureLevelData(plotData, levelIndex)
			local newId = takeNextId(plotData)

			local floorMaterial = normalizeMaterialId(entry.FloorMaterial) or Formex.DefaultFloorMaterial
			local ceilingMaterial = normalizeMaterialId(entry.CeilingMaterial) or floorMaterial
			local foundationMaterial = normalizeMaterialId(entry.FoundationMaterial) or Formex.DefaultFoundationMaterial
			local floorColor = resolveColor(entry.FloorColor, nil)
			local ceilingColor = resolveColor(entry.CeilingColor, floorColor)
			local foundationColor = resolveColor(entry.FoundationColor, floorColor)
			local raiseHeight = resolveRaiseHeight(entry.RaiseHeight, nil)

			local newFloor = {
				FloorId = newId,
				LevelIndex = levelIndex,
				Points = entry.Points,
				RaiseHeight = raiseHeight,
				FloorMaterial = floorMaterial,
				CeilingMaterial = ceilingMaterial,
				FoundationMaterial = foundationMaterial,
				FloorColor = floorColor,
				CeilingColor = ceilingColor,
				FoundationColor = foundationColor,
				Model = nil,
			}

			levelData.Floors[newId] = newFloor
			table.insert(updatedFloors, newFloor)
			table.insert(returnFloors, {
				FloorId = newId,
				LevelIndex = levelIndex,
				Points = entry.Points,
				RaiseHeight = raiseHeight,
				FloorMaterial = floorMaterial,
				CeilingMaterial = ceilingMaterial,
				FoundationMaterial = foundationMaterial,
				FloorColor = floorColor,
				CeilingColor = ceilingColor,
				FoundationColor = foundationColor,
				Model = nil,
			})
		end

		for _, floor in ipairs(updatedFloors) do
			if not Formex.Floors.IsValid(plotData, floor) then
				plotData.Levels = resolvedSnapshot
				error("Invalid floor placement")
			end
		end
		didChange = #updatedFloors > 0
	elseif action == Formex.BuildAction.Edit then
		for _, entry in ipairs(floorList) do
			local levelIndex = entry.LevelIndex or 1
			local levelData = plotData.Levels[levelIndex]
			if not levelData then
				plotData.Levels = resolvedSnapshot
				error("Floor not found")
			end

			local existing = levelData.Floors[entry.FloorId]
			if not existing then
				plotData.Levels = resolvedSnapshot
				error("Floor not found")
			end

			local updatedPoints = entry.Points or existing.Points
			if not updatedPoints or #updatedPoints < 3 then
				if existing.Model then
					table.insert(removedModels, existing.Model)
				end
				levelData.Floors[entry.FloorId] = nil
				didChange = true
			else
				local floorMaterial = normalizeMaterialId(entry.FloorMaterial) or normalizeMaterialId(existing.FloorMaterial) or Formex.DefaultFloorMaterial
				local ceilingMaterial = normalizeMaterialId(entry.CeilingMaterial) or normalizeMaterialId(existing.CeilingMaterial) or floorMaterial
				local foundationMaterial = normalizeMaterialId(entry.FoundationMaterial) or normalizeMaterialId(existing.FoundationMaterial) or Formex.DefaultFoundationMaterial
				local floorColor = resolveColor(entry.FloorColor, existing.FloorColor)
				local ceilingColor = resolveColor(entry.CeilingColor, existing.CeilingColor or floorColor)
				local foundationColor = resolveColor(entry.FoundationColor, existing.FoundationColor or floorColor)
				local raiseHeight = resolveRaiseHeight(entry.RaiseHeight, existing.RaiseHeight)

				local updated = {
					FloorId = existing.FloorId,
					LevelIndex = levelIndex,
					Points = updatedPoints,
					RaiseHeight = raiseHeight,
					FloorMaterial = floorMaterial,
					CeilingMaterial = ceilingMaterial,
					FoundationMaterial = foundationMaterial,
					FloorColor = floorColor,
					CeilingColor = ceilingColor,
					FoundationColor = foundationColor,
					Model = existing.Model,
				}

				levelData.Floors[existing.FloorId] = updated
				table.insert(updatedFloors, updated)
				table.insert(returnFloors, {
					FloorId = updated.FloorId,
					LevelIndex = updated.LevelIndex,
					Points = updated.Points,
					RaiseHeight = updated.RaiseHeight,
					FloorMaterial = updated.FloorMaterial,
					CeilingMaterial = updated.CeilingMaterial,
					FoundationMaterial = updated.FoundationMaterial,
					FloorColor = updated.FloorColor,
					CeilingColor = updated.CeilingColor,
					FoundationColor = updated.FoundationColor,
					Model = nil,
				})
			end
		end

		didChange = didChange or #updatedFloors > 0
		for _, floor in ipairs(updatedFloors) do
			if not Formex.Floors.IsValid(plotData, floor) then
				plotData.Levels = resolvedSnapshot
				error("Invalid floor placement")
			end
		end
	elseif action == Formex.BuildAction.Delete then
		for _, entry in ipairs(floorList) do
			local levelIndex = entry.LevelIndex or 1
			local levelData = plotData.Levels[levelIndex]
			if levelData then
				local existing = levelData.Floors[entry.FloorId]
				if existing then
					if existing.Model then
						existing.Model:Destroy()
					end
					levelData.Floors[entry.FloorId] = nil
					didChange = true
				end
			end
		end
	else
		error("Invalid floor action")
	end

	return {
		DidChange = didChange,
		IsBatch = isBatch,
		ReturnList = returnFloors,
		ReturnSingle = returnFloors[1],
		LevelsTouched = levelsTouched,
		RemovedModels = removedModels,
		RenderFloorsLevels = levelsTouched,
		RenderObjectsLevels = levelsTouched,
		Snapshot = resolvedSnapshot,
	}
end

function FormexBuild.BuildFloor(player: Player, floorData: Formex.FloorData | {Formex.FloorData}, action: Formex.BuildAction, selection: Formex.SelectionSnapshot?)
	local results = FormexBuild.BuildTransaction(player, {
		{
			PartType = Formex.PartType.Floor,
			Action = action,
			Data = floorData,
		},
	}, selection)
	if not results then
		return nil
	end
	local changeResult = results[1]
	return changeResult and changeResult.Result or nil
end

local function applyObjectChanges(plotData: Formex.PlotData, objectData: Formex.ObjectData, action: Formex.BuildAction, snapshot: Formex.LevelArray?): any
	plotData.Levels = plotData.Levels or {}
	local levelIndex = objectData.Level or 1
	local resolvedSnapshot = snapshot or createSnapshot(plotData.Levels, levelIndex)
	local levelData = FormexSystem.EnsureLevelData(plotData, levelIndex)

	local function resolvePrefab(entry: Formex.ObjectData): Formex.ObjectPrefab
		local prefabName = entry.PrefabName
		if entry.Prefab and entry.Prefab.PrefabName then
			prefabName = entry.Prefab.PrefabName
		end
		local prefab = prefabName and Formex.Objects.GetPrefab(prefabName)
		if not prefab then
			error("Invalid object prefab")
		end
		return prefab
	end

	local function ensureDesign(entry: Formex.ObjectData, prefab: Formex.ObjectPrefab)
		entry.Design = entry.Design or {}
		entry.DesignColors = entry.DesignColors or {}
		Formex.Objects.EnsureDesignDefaults(entry, prefab)
	end

	local function getDefaultFloorSurfaceHeights(levelIndex: number): (number, number)
		local levelTop = Formex.Plot.GetLevelOffset(levelIndex)
		local thickness = levelIndex == 1 and Formex.FoundationHeight or Formex.InterfloorHeight
		return levelTop, levelTop - thickness
	end

	local function getFloorSurfaceHeightsAt(position: Vector2, levelIndex: number): (number, number)
		local fallbackTop, fallbackBottom = getDefaultFloorSurfaceHeights(levelIndex)
		local floorData = Formex.Objects.GetFloorAtPosition(plotData, levelIndex, position)
		if not floorData then
			return fallbackTop, fallbackBottom
		end
		return Formex.Objects.GetFloorSurfaceY(floorData), Formex.Objects.GetCeilingSurfaceY(floorData)
	end

	local function normalizeObject(entry: Formex.ObjectData, prefab: Formex.ObjectPrefab, existing: Formex.ObjectData?): Formex.ObjectData
		local position = entry.Position or (existing and existing.Position) or Vector3.new(0, 0, 0)
		local rotation = entry.Rotation or (existing and existing.Rotation) or Vector3.new(0, 0, 0)
		local wallId = entry.WallId
		if wallId == 0 then
			wallId = nil
		end
		local side = Formex.Objects.ResolveObjectSide(entry.Side or (existing and existing.Side))

		if prefab.ObjectMount == Formex.MountType.Door then
			position = Vector3.new(position.X, 0, 0)
			rotation = Vector3.new(0, 0, 0)
		elseif prefab.ObjectMount == Formex.MountType.Window or prefab.ObjectMount == Formex.MountType.Wall then
			position = Vector3.new(position.X, position.Y, 0)
			rotation = Vector3.new(0, 0, 0)
		elseif prefab.ObjectMount == Formex.MountType.Floor or prefab.ObjectMount == Formex.MountType.Ceiling then
			local _, boundsSize = Formex.Objects.GetPrefabBounds(prefab, nil)
			local position2 = Vector2.new(position.X, position.Z)
			local floorHeight, ceilingHeight = getFloorSurfaceHeightsAt(position2, levelIndex)
			if prefab.ObjectMount == Formex.MountType.Floor then
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
			IsPortal = prefab.ObjectMount == Formex.MountType.Door,
			Part = existing and existing.Part or nil,
		} :: Formex.ObjectData

		ensureDesign(resolved, prefab)
		return resolved
	end

	local function isWallMount(mount: Formex.ObjectMount): boolean
		return mount == Formex.MountType.Wall or mount == Formex.MountType.Door or mount == Formex.MountType.Window
	end

	local function isObjectValid(entry: Formex.ObjectData, prefab: Formex.ObjectPrefab): boolean
		if not entry.Position or not entry.Rotation then
			return false
		end
		local _, boundsSize = Formex.Objects.GetPrefabBounds(prefab, nil)
		local plot = plotData
		local mount = prefab.ObjectMount

		if isWallMount(mount) then
			if not entry.WallId then
				return false
			end
			local wallData = levelData.Walls[entry.WallId]
			if not wallData then
				return false
			end
			local dir, _, startLocal, length = Formex.Objects.GetWallBasis(wallData)
			if length <= Formex.EPSILON then
				return false
			end
			local minX = boundsSize.X / 2
			local maxX = length - (boundsSize.X / 2)
			if entry.Position.X < minX - Formex.EPSILON or entry.Position.X > maxX + Formex.EPSILON then
				return false
			end
			local levelIndex = wallData.Level or entry.Level or 1
			local levelOffset = Formex.Plot.GetLevelOffset(levelIndex)
			local wallHeight = wallData.Height or Formex.LevelHeight
			local wallTop = levelOffset + wallHeight
			local anchor2 = Vector2.new(startLocal.X + dir.X * entry.Position.X, startLocal.Z + dir.Z * entry.Position.X)
			local floorData = Formex.Objects.GetFloorAtPosition(plot, levelIndex, anchor2)
			local floorHeight = floorData and Formex.Objects.GetFloorSurfaceY(floorData) or levelOffset
			local elevation = entry.Position.Y
			if mount == Formex.MountType.Door then
				elevation = 0
			end
			if elevation < -Formex.EPSILON then
				return false
			end
			local bottomY = floorHeight + elevation
			local topY = bottomY + boundsSize.Y
			if topY > wallTop + Formex.EPSILON then
				return false
			end
			return true
		end

		local position2 = Vector2.new(entry.Position.X, entry.Position.Z)
		if not Formex.Plot.IsPointInUnlockedSegments(position2, plot.SegmentsUnlocked) then
			return false
		end
		if mount == Formex.MountType.Floor or mount == Formex.MountType.Ceiling then
			local floorData = Formex.Objects.GetFloorAtPosition(plot, entry.Level or 1, position2)
			if not floorData then
				return false
			end
		end
		return true
	end

	local didChange = false
	local updatedObject: Formex.ObjectData? = nil
	local rebuildWalls = {} :: {{Level: number, WallId: number}}

	local function markRebuildWall(wallId: number?)
		if wallId then
			table.insert(rebuildWalls, { Level = levelIndex, WallId = wallId })
		end
	end

	if action == Formex.BuildAction.Add then
		local prefab = resolvePrefab(objectData)
		local newId = takeNextId(plotData)
		objectData.ObjectId = newId
		objectData.Level = levelIndex
		local resolved = normalizeObject(objectData, prefab, nil)
		if not isObjectValid(resolved, prefab) then
			plotData.Levels = resolvedSnapshot
			error("Invalid object placement")
		end
		levelData.Objects[newId] = resolved
		if isDoorWindowMount(prefab.ObjectMount) then
			markRebuildWall(resolved.WallId)
		end
		didChange = true
		updatedObject = resolved
	elseif action == Formex.BuildAction.Edit then
		local objectId = tonumber(objectData.ObjectId) or objectData.ObjectId
		local existing = objectId and levelData.Objects[objectId]
		if not existing then
			plotData.Levels = resolvedSnapshot
			error("Object not found")
		end
		local legacyKey = existing.ObjectId
		if legacyKey ~= nil and legacyKey ~= objectId then
			levelData.Objects[legacyKey] = nil
		end
		local prefab = resolvePrefab(objectData)
		local resolved = normalizeObject(objectData, prefab, existing)
		if not isObjectValid(resolved, prefab) then
			plotData.Levels = resolvedSnapshot
			error("Invalid object placement")
		end
		levelData.Objects[objectId] = resolved
		if isDoorWindowMount(prefab.ObjectMount) then
			markRebuildWall(existing.WallId)
			markRebuildWall(resolved.WallId)
		end
		didChange = true
		updatedObject = resolved
	elseif action == Formex.BuildAction.Delete then
		local objectId = tonumber(objectData.ObjectId) or objectData.ObjectId
		local existing = objectId and levelData.Objects[objectId]
		if existing then
			local legacyKey = existing.ObjectId
			if legacyKey ~= nil and legacyKey ~= objectId then
				levelData.Objects[legacyKey] = nil
			end
			local prefab = existing.Prefab or (existing.PrefabName and Formex.Objects.GetPrefab(existing.PrefabName))
			if prefab and isDoorWindowMount(prefab.ObjectMount) then
				markRebuildWall(existing.WallId)
			end
			if existing.Part then
				existing.Part:Destroy()
			end
			levelData.Objects[objectId] = nil
			didChange = true
		end
	else
		error("Invalid object action")
	end

	local shouldRenderWalls = (updatedObject and updatedObject.Prefab and isWallMount(updatedObject.Prefab.ObjectMount)) or #rebuildWalls > 0

	return {
		DidChange = didChange,
		ReturnSingle = updatedObject,
		LevelsTouched = { levelIndex },
		RenderObjectsLevels = { levelIndex },
		RenderWallsLevels = shouldRenderWalls and { levelIndex } or {},
		RebuildWalls = rebuildWalls,
		Snapshot = resolvedSnapshot,
	}
end

function FormexBuild.BuildObject(player: Player, objectData: Formex.ObjectData, action: Formex.BuildAction, selection: Formex.SelectionSnapshot?)
	local results = FormexBuild.BuildTransaction(player, {
		{
			PartType = Formex.PartType.Object,
			Action = action,
			Data = objectData,
		},
	}, selection)
	if not results then
		return nil
	end
	local changeResult = results[1]
	return changeResult and changeResult.Result or nil
end

local function mergeLevelSet(target: {[number]: boolean}, levels: {number}?)
	if not levels then
		return
	end
	for _, levelIndex in ipairs(levels) do
		target[levelIndex] = true
	end
end

local function toSortedLevelList(levelSet: {[number]: boolean}): {number}
	local levels = {}
	for levelIndex in pairs(levelSet) do
		table.insert(levels, levelIndex)
	end
	table.sort(levels)
	return levels
end

local function shouldCarveObject(objectData: Formex.ObjectData?): boolean
	if not objectData then
		return false
	end
	local prefab = objectData.Prefab
	if not prefab and objectData.PrefabName then
		prefab = Formex.Objects.GetPrefab(objectData.PrefabName)
	end
	if not prefab then
		return false
	end
	return prefab.ObjectMount == Formex.MountType.Door or prefab.ObjectMount == Formex.MountType.Window
end

local function resolveObjectFromLevels(levels: Formex.LevelArray?, levelIndex: number, objectId: number | string): Formex.ObjectData?
	local levelData = levels and levels[levelIndex]
	if not levelData or not levelData.Objects then
		return nil
	end
	local objectData = levelData.Objects[objectId]
	if not objectData and type(objectId) == "string" then
		local numericId = tonumber(objectId)
		if numericId then
			objectData = levelData.Objects[numericId]
		end
	elseif not objectData and type(objectId) == "number" then
		objectData = levelData.Objects[tostring(objectId)]
	end
	return objectData
end

local function buildCarveWallIds(
	plotData: Formex.PlotData,
	snapshotLevels: Formex.LevelArray?,
	result: TransactionResult,
	levelsTouched: {number}
): {[number]: {[number]: boolean}}
	local carveWallIdsByLevel: {[number]: {[number]: boolean}} = {}
	for _, levelIndex in ipairs(levelsTouched) do
		carveWallIdsByLevel[levelIndex] = {}
	end

	local function addWall(levelIndex: number?, wallId: number?)
		if not levelIndex or not wallId then
			return
		end
		local wallSet = carveWallIdsByLevel[levelIndex]
		if not wallSet then
			wallSet = {}
			carveWallIdsByLevel[levelIndex] = wallSet
		end
		wallSet[wallId] = true
	end

	local function addWallForObject(levels: Formex.LevelArray?, levelIndex: number, objectId: number | string)
		local objectData = resolveObjectFromLevels(levels, levelIndex, objectId)
		if not objectData or not objectData.WallId then
			return
		end
		if not shouldCarveObject(objectData) then
			return
		end
		addWall(levelIndex, objectData.WallId)
	end

	for _, entry in ipairs(result.UpdatedWalls or {}) do
		addWall(entry.Level, entry.WallId)
	end
	for _, entry in ipairs(result.AddedWalls or {}) do
		addWall(entry.Level, entry.WallId)
	end

	for _, entry in ipairs(result.AddedObjects or {}) do
		addWallForObject(plotData.Levels, entry.Level, entry.ObjectId)
	end
	for _, entry in ipairs(result.UpdatedObjects or {}) do
		addWallForObject(plotData.Levels, entry.Level, entry.ObjectId)
		addWallForObject(snapshotLevels, entry.Level, entry.ObjectId)
	end
	for _, entry in ipairs(result.RemovedObjects or {}) do
		addWallForObject(snapshotLevels, entry.Level, entry.ObjectId)
	end

	return carveWallIdsByLevel
end

local function renderPlotChanges(
	plotData: Formex.PlotData,
	snapshotLevels: Formex.LevelArray?,
	result: TransactionResult?,
	levelsTouched: {number}?
)
	local plotPart = FormexSystem.Plots[plotData.PlotId]
	if not plotPart then
		return
	end

	if result and levelsTouched then
		local levelsToRender = result.LevelsTouched or levelsTouched
		local carveWallIdsByLevel = buildCarveWallIds(plotData, snapshotLevels, result, levelsToRender)
		for _, levelIndex in ipairs(levelsToRender) do
			FormexSystem.RenderPlot(plotData.PlotId, levelIndex, nil, carveWallIdsByLevel)
		end
		return
	end

	FormexSystem.RenderPlot(plotData.PlotId)
	FormexSystem.RefreshWallCarves(plotData.PlotId)
end

function FormexBuild.BuildTransaction(player: Player, changes: {Formex.BuildChange}, selection: Formex.SelectionSnapshot?)
	local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
	if not plotData then
		return nil, "No current plot"
	end
	if permission ~= Formex.Permission.Manager and permission ~= Formex.Permission.Owner then
		return nil, "Access denied"
	end
	if not changes or #changes == 0 then
		return nil, "Invalid build transaction"
	end

	plotData.Levels = plotData.Levels or {}

	local validation = Formex.IsTransactionValid(plotData, changes)
	if not validation or validation.IsValid ~= true then
		return nil, (validation and validation.Error) or "Invalid build transaction"
	end

	local levelsTouched = validation.LevelsTouched or {}
	local snapshot = createSnapshotForLevels(plotData.Levels, levelsTouched)
	local result = Formex.Transaction.Apply(plotData, changes)

	if not result or not result.DidChange then
		return nil, "No changes"
	end

	renderPlotChanges(plotData, snapshot, result, levelsTouched)

	pushUndo(plotData.PlotId, player.UserId, snapshot, selection)
	updatePlayerUndoRedoAttributes(player, plotData.PlotId)
	FormexSystem.QueueSave(plotData.PlotId)

	return result.Results
end

function FormexBuild.CanUndo(player: Player): boolean
	local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
	if not plotData then error("No current plot") end
	if permission ~= Formex.Permission.Manager and permission ~= Formex.Permission.Owner then
		error("Access denied")
	end

	local history = getHistoryIfExists(plotData.PlotId, player.UserId)
	return history ~= nil and #history.Undo > 0
end

function FormexBuild.CanRedo(player: Player): boolean
	local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
	if not plotData then error("No current plot") end
	if permission ~= Formex.Permission.Manager and permission ~= Formex.Permission.Owner then
		error("Access denied")
	end

	local history = getHistoryIfExists(plotData.PlotId, player.UserId)
	return history ~= nil and #history.Redo > 0
end

function FormexBuild.Undo(player: Player, selection: Formex.SelectionSnapshot?): (boolean, string?, Formex.SelectionSnapshot?)
	local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
	if not plotData then error("No current plot") end
	if permission ~= Formex.Permission.Manager and permission ~= Formex.Permission.Owner then
		error("Access denied")
	end

	plotData.Levels = plotData.Levels or {}
	local history = getHistoryIfExists(plotData.PlotId, player.UserId)
	if not history or #history.Undo == 0 then
		return false, "Nothing to undo"
	end

	local transaction = history.Undo[#history.Undo]
	history.Undo[#history.Undo] = nil
	table.insert(history.Redo, {
		Levels = plotData.Levels,
		Selection = selection,
	})
	plotData.Levels = transaction.Levels

	renderPlotChanges(plotData, nil, nil, nil)
	FormexSystem.QueueSave(plotData.PlotId)
	updatePlayerUndoRedoAttributes(player, plotData.PlotId)
	return true, nil, transaction.Selection
end

function FormexBuild.Redo(player: Player, selection: Formex.SelectionSnapshot?): (boolean, string?, Formex.SelectionSnapshot?)
	local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
	if not plotData then error("No current plot") end
	if permission ~= Formex.Permission.Manager and permission ~= Formex.Permission.Owner then
		error("Access denied")
	end

	plotData.Levels = plotData.Levels or {}
	local history = getHistoryIfExists(plotData.PlotId, player.UserId)
	if not history or #history.Redo == 0 then
		return false, "Nothing to redo"
	end

	local transaction = history.Redo[#history.Redo]
	history.Redo[#history.Redo] = nil
	table.insert(history.Undo, {
		Levels = plotData.Levels,
		Selection = selection,
	})
	if #history.Undo > Formex.MaxUndoQueueSize then
		table.remove(history.Undo, 1)
	end
	plotData.Levels = transaction.Levels

	renderPlotChanges(plotData, nil, nil, nil)
	FormexSystem.QueueSave(plotData.PlotId)
	updatePlayerUndoRedoAttributes(player, plotData.PlotId)
	return true, nil, transaction.Selection
end

function FormexBuild.UpdatePlayerUndoRedoAttributes(player: Player, plotId: number?)
	updatePlayerUndoRedoAttributes(player, plotId)
end

return FormexBuild
