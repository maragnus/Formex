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

local function getNextId(entries: {[number]: any}): number
	local maxId = 0
	for id in entries do
		if id > maxId then
			maxId = id
		end
	end
	return maxId + 1
end

local undoStacks = {} :: {[number]: {Formex.LevelArray}}
local redoStacks = {} :: {[number]: {Formex.LevelArray}}

local function getHistory(plotId: number): ({Formex.LevelArray}, {Formex.LevelArray})
	local undo = undoStacks[plotId]
	if not undo then
		undo = {}
		undoStacks[plotId] = undo
	end
	local redo = redoStacks[plotId]
	if not redo then
		redo = {}
		redoStacks[plotId] = redo
	end
	return undo, redo
end

local function pushUndo(plotId: number, snapshot: Formex.LevelArray)
	local undo, redo = getHistory(plotId)
	table.insert(undo, snapshot)
	table.clear(redo)
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

local function cloneLevelForSnapshot(snapshot: Formex.LevelArray, levels: Formex.LevelArray, levelIndex: number, partType: Formex.PartType)
	local levelData = levels[levelIndex]
	if not levelData then
		return
	end

	local levelClone = table.clone(levelData)
	if partType == Formex.PartType.Wall then
		levelClone.Walls = table.clone(levelData.Walls)
	elseif partType == Formex.PartType.Floor then
		levelClone.Floors = table.clone(levelData.Floors)
	elseif partType == Formex.PartType.Object then
		levelClone.Objects = table.clone(levelData.Objects)
	end
	snapshot[levelIndex] = levelClone
end

local function createSnapshot(levels: Formex.LevelArray, levelIndex: number, partType: Formex.PartType): Formex.LevelArray
	local snapshot = table.clone(levels)
	cloneLevelForSnapshot(snapshot, levels, levelIndex, partType)
	return snapshot
end

local function createSnapshotForLevels(levels: Formex.LevelArray, levelIndices: {number}, partType: Formex.PartType): Formex.LevelArray
	local snapshot = table.clone(levels)
	for _, levelIndex in ipairs(levelIndices) do
		cloneLevelForSnapshot(snapshot, levels, levelIndex, partType)
	end
	return snapshot
end

local function isZeroLength(startPoint: Vector2int16, endPoint: Vector2int16): boolean
	return startPoint.X == endPoint.X and startPoint.Y == endPoint.Y
end

function FormexBuild.BuildWall(player: Player, wallData: Formex.WallData | {Formex.WallData}, action: Formex.BuildAction)
	local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
	if not plotData then error("No current plot") end
	if permission ~= Formex.Permission.Manager and permission ~= Formex.Permission.Owner then
		error("Access denied")
	end
	if not wallData then error("Invalid wall data") end

	plotData.Levels = plotData.Levels or {}
	local wallList, isBatch = normalizeWallList(wallData)
	local levelsTouched = collectWallLevels(wallList)
	local snapshot = createSnapshotForLevels(plotData.Levels, levelsTouched, Formex.PartType.Wall)

	local updatedWalls = {} :: {Formex.WallData}
	local returnWalls = {} :: {Formex.WallData}
	local removedParts = {} :: {BasePart}
	local didChange = false

	if action == Formex.BuildAction.Add then
		for _, entry in ipairs(wallList) do
			if not entry.Start or not entry.End then
				error("Invalid wall data")
			end

			local levelIndex = entry.Level or 1
			local levelData = FormexSystem.EnsureLevelData(plotData, levelIndex)

			local frontMaterial = entry.FrontMaterial or Formex.DefaultWallMaterial
			local backMaterial = entry.BackMaterial or frontMaterial
			local startMaterial = entry.StartMaterial or frontMaterial
			local endMaterial = entry.EndMaterial or frontMaterial

			local newId = getNextId(levelData.Walls)
			local newWall = {
				WallId = newId,
				Level = levelIndex,
				Start = entry.Start,
				End = entry.End,
				FrontMaterial = frontMaterial,
				BackMaterial = backMaterial,
				StartMaterial = startMaterial,
				EndMaterial = endMaterial,
				Part = nil
			}
			levelData.Walls[newId] = newWall
			table.insert(updatedWalls, newWall)
			table.insert(returnWalls, {
				WallId = newId,
				Level = levelIndex,
				Start = entry.Start,
				End = entry.End,
				FrontMaterial = frontMaterial,
				BackMaterial = backMaterial,
				StartMaterial = startMaterial,
				EndMaterial = endMaterial,
				Part = nil
			})
		end

		for _, wall in ipairs(updatedWalls) do
			if not Formex.IsWallValid(plotData, wall) then
				plotData.Levels = snapshot
				error("Invalid wall placement")
			end
		end
		didChange = #updatedWalls > 0
	elseif action == Formex.BuildAction.Edit then
		for _, entry in ipairs(wallList) do
			local levelIndex = entry.Level or 1
			local levelData = plotData.Levels[levelIndex]
			if not levelData then
				plotData.Levels = snapshot
				error("Wall not found")
			end

			local existing = levelData.Walls[entry.WallId]
			if not existing then
				plotData.Levels = snapshot
				error("Wall not found")
			end
			if not entry.Start or not entry.End then
				plotData.Levels = snapshot
				error("Invalid wall data")
			end

			if isZeroLength(entry.Start, entry.End) then
				if existing.Part then
					table.insert(removedParts, existing.Part)
				end
				levelData.Walls[entry.WallId] = nil
				didChange = true
			else
				local frontMaterial = entry.FrontMaterial or existing.FrontMaterial or Formex.DefaultWallMaterial
				local backMaterial = entry.BackMaterial or existing.BackMaterial or frontMaterial
				local startMaterial = entry.StartMaterial or existing.StartMaterial or frontMaterial
				local endMaterial = entry.EndMaterial or existing.EndMaterial or frontMaterial

				local updated = {
					WallId = existing.WallId,
					Level = levelIndex,
					Start = entry.Start,
					End = entry.End,
					FrontMaterial = frontMaterial,
					BackMaterial = backMaterial,
					StartMaterial = startMaterial,
					EndMaterial = endMaterial,
					Part = existing.Part
				}
				levelData.Walls[existing.WallId] = updated
				table.insert(updatedWalls, updated)
				table.insert(returnWalls, {
					WallId = updated.WallId,
					Level = updated.Level,
					Start = updated.Start,
					End = updated.End,
					FrontMaterial = updated.FrontMaterial,
					BackMaterial = updated.BackMaterial,
					StartMaterial = updated.StartMaterial,
					EndMaterial = updated.EndMaterial,
					Part = nil
				})
				didChange = true
			end
		end

		for _, wall in ipairs(updatedWalls) do
			if not Formex.IsWallValid(plotData, wall) then
				plotData.Levels = snapshot
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
					levelData.Walls[entry.WallId] = nil
					didChange = true
				end
			end
		end
	else
		error("Invalid wall action")
	end

	if not didChange then
		return nil
	end

	if action ~= Formex.BuildAction.Delete then
		for _, part in ipairs(removedParts) do
			if part and part.Parent then
				part:Destroy()
			end
		end
	end

	local plotPart = FormexSystem.Plots[plotData.PlotId]
	if plotPart then
		for _, levelIndex in ipairs(levelsTouched) do
			FormexSystem.RenderPlot(plotData.PlotId, levelIndex, Formex.PartType.Wall)
		end
	end

	pushUndo(plotData.PlotId, snapshot)
	FormexSystem.QueueSave(plotData.PlotId)

	if action == Formex.BuildAction.Delete then
		return nil
	end

	if isBatch then
		return returnWalls
	end
	return returnWalls[1]
end

function FormexBuild.BuildFloor(player: Player, floorData: Formex.FloorData | {Formex.FloorData}, action: Formex.BuildAction)
	local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
	if not plotData then error("No current plot") end
	if permission ~= Formex.Permission.Manager and permission ~= Formex.Permission.Owner then
		error("Access denied")
	end
	if not floorData then error("Invalid floor data") end

	plotData.Levels = plotData.Levels or {}
	local floorList, isBatch = normalizeFloorList(floorData)
	local levelsTouched = collectFloorLevels(floorList)
	local snapshot = createSnapshotForLevels(plotData.Levels, levelsTouched, Formex.PartType.Floor)

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
			local newId = getNextId(levelData.Floors)

			local floorMaterial = entry.FloorMaterial or Formex.DefaultFloorMaterial
			local ceilingMaterial = entry.CeilingMaterial or floorMaterial

			local newFloor = {
				FloorId = newId,
				LevelIndex = levelIndex,
				Points = entry.Points,
				FloorMaterial = floorMaterial,
				CeilingMaterial = ceilingMaterial,
				FloorParts = {},
				CeilingParts = {},
				Model = nil,
			}

			levelData.Floors[newId] = newFloor
			table.insert(updatedFloors, newFloor)
			table.insert(returnFloors, {
				FloorId = newId,
				LevelIndex = levelIndex,
				Points = entry.Points,
				FloorMaterial = floorMaterial,
				CeilingMaterial = ceilingMaterial,
				FloorParts = {},
				CeilingParts = {},
				Model = nil,
			})
		end

		for _, floor in ipairs(updatedFloors) do
			if not Formex.IsFloorValid(plotData, floor) then
				plotData.Levels = snapshot
				error("Invalid floor placement")
			end
		end
		didChange = #updatedFloors > 0
	elseif action == Formex.BuildAction.Edit then
		for _, entry in ipairs(floorList) do
			local levelIndex = entry.LevelIndex or 1
			local levelData = plotData.Levels[levelIndex]
			if not levelData then
				plotData.Levels = snapshot
				error("Floor not found")
			end

			local existing = levelData.Floors[entry.FloorId]
			if not existing then
				plotData.Levels = snapshot
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
				local floorMaterial = entry.FloorMaterial or existing.FloorMaterial or Formex.DefaultFloorMaterial
				local ceilingMaterial = entry.CeilingMaterial or existing.CeilingMaterial or floorMaterial

				local updated = {
					FloorId = existing.FloorId,
					LevelIndex = levelIndex,
					Points = updatedPoints,
					FloorMaterial = floorMaterial,
					CeilingMaterial = ceilingMaterial,
					FloorParts = existing.FloorParts or {},
					CeilingParts = existing.CeilingParts or {},
					Model = existing.Model,
				}

				levelData.Floors[existing.FloorId] = updated
				table.insert(updatedFloors, updated)
				table.insert(returnFloors, {
					FloorId = updated.FloorId,
					LevelIndex = updated.LevelIndex,
					Points = updated.Points,
					FloorMaterial = updated.FloorMaterial,
					CeilingMaterial = updated.CeilingMaterial,
					FloorParts = {},
					CeilingParts = {},
					Model = nil,
				})
			end
		end

		didChange = didChange or #updatedFloors > 0
		for _, floor in ipairs(updatedFloors) do
			if not Formex.IsFloorValid(plotData, floor) then
				plotData.Levels = snapshot
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

	if not didChange then
		return nil
	end

	if action ~= Formex.BuildAction.Delete then
		for _, model in ipairs(removedModels) do
			if model and model.Parent then
				model:Destroy()
			end
		end
	end

	local plotPart = FormexSystem.Plots[plotData.PlotId]
	if plotPart then
		for _, levelIndex in ipairs(levelsTouched) do
			FormexSystem.RenderPlot(plotData.PlotId, levelIndex, Formex.PartType.Floor)
		end
	end

	pushUndo(plotData.PlotId, snapshot)
	FormexSystem.QueueSave(plotData.PlotId)

	if action == Formex.BuildAction.Delete then
		return nil
	end

	if isBatch then
		return returnFloors
	end
	return returnFloors[1]
end

function FormexBuild.BuildObject(player: Player, objectData: Formex.ObjectData, action: Formex.BuildAction)
    local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
    if permission ~= Formex.Permission.Manager then error("Access denied") end
    
    -- TODO
    
    FormexSystem.QueueSave(plotData.PlotId)
end

function FormexBuild.CanUndo(player: Player): boolean
	local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
	if not plotData then error("No current plot") end
	if permission ~= Formex.Permission.Manager and permission ~= Formex.Permission.Owner then
		error("Access denied")
	end

	local undo = undoStacks[plotData.PlotId]
	return undo ~= nil and #undo > 0
end

function FormexBuild.CanRedo(player: Player): boolean
	local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
	if not plotData then error("No current plot") end
	if permission ~= Formex.Permission.Manager and permission ~= Formex.Permission.Owner then
		error("Access denied")
	end

	local redo = redoStacks[plotData.PlotId]
	return redo ~= nil and #redo > 0
end

function FormexBuild.Undo(player: Player): (boolean, string?)
	local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
	if not plotData then error("No current plot") end
	if permission ~= Formex.Permission.Manager and permission ~= Formex.Permission.Owner then
		error("Access denied")
	end

	plotData.Levels = plotData.Levels or {}
	local undo, redo = getHistory(plotData.PlotId)
	if #undo == 0 then
		return false, "Nothing to undo"
	end

	local snapshot = undo[#undo]
	undo[#undo] = nil
	table.insert(redo, plotData.Levels)
	plotData.Levels = snapshot

	FormexSystem.RenderPlot(plotData.PlotId)
	FormexSystem.QueueSave(plotData.PlotId)
	return true
end

function FormexBuild.Redo(player: Player): (boolean, string?)
	local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
	if not plotData then error("No current plot") end
	if permission ~= Formex.Permission.Manager and permission ~= Formex.Permission.Owner then
		error("Access denied")
	end

	plotData.Levels = plotData.Levels or {}
	local undo, redo = getHistory(plotData.PlotId)
	if #redo == 0 then
		return false, "Nothing to redo"
	end

	local snapshot = redo[#redo]
	redo[#redo] = nil
	table.insert(undo, plotData.Levels)
	plotData.Levels = snapshot

	FormexSystem.RenderPlot(plotData.PlotId)
	FormexSystem.QueueSave(plotData.PlotId)
	return true
end

return FormexBuild
