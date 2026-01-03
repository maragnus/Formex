--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FormexFolder = ReplicatedStorage:WaitForChild("Formex")
local Formex = require(FormexFolder:WaitForChild("Formex"))
local FormexSystem = require(script.Parent:WaitForChild("FormexSystem"))

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
	elseif partType == Formex.PartType.Ceiling then
		levelClone.Ceilings = table.clone(levelData.Ceilings)
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

function FormexBuild.BuildFloor(player: Player, level: number, x: number, y: number, material: number, material2: number?)
    local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
    if not plotData then error("No current plot") end
    if permission ~= Formex.Permission.Manager and permission ~= Formex.Permission.Owner then
		error("Access denied")
	end

    -- TODO: is tile within an owned segment and owned level?

	plotData.Levels = plotData.Levels or {}
    local levelIndex = level or 1
    local index = Formex.XYToIndex(x, y)
    material = material or 0
	local newMaterial = material > 0 and material or nil

	local levelData = plotData.Levels[levelIndex]
	local currentMaterial = levelData and levelData.Floors[index] or nil
	if currentMaterial == newMaterial then
		return
	end

	local snapshot = createSnapshot(plotData.Levels, levelIndex, Formex.PartType.Floor)
	levelData = levelData or FormexSystem.EnsureLevelData(plotData, levelIndex)

    -- TODO: handle FloorType.CW and FloorType.CCW
    levelData.Floors[index] = newMaterial

    FormexSystem.RenderPlot(plotData.PlotId, levelIndex, Formex.PartType.Floor)

	pushUndo(plotData.PlotId, snapshot)
    FormexSystem.QueueSave(plotData.PlotId)
end

function FormexBuild.BuildCeiling(player: Player, level: number, x: number, y: number, material: number, material2: number?)
    local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
    if not plotData then error("No current plot") end
    if permission ~= Formex.Permission.Manager and permission ~= Formex.Permission.Owner then
        error("Access denied")
    end

	plotData.Levels = plotData.Levels or {}
    local levelIndex = level or 1
    local index = Formex.XYToIndex(x, y)
	material = material or 0
	local newMaterial = material > 0 and material or nil

	local levelData = plotData.Levels[levelIndex]
	local currentMaterial = levelData and levelData.Ceilings[index] or nil
	if currentMaterial == newMaterial then
		return
	end

	local snapshot = createSnapshot(plotData.Levels, levelIndex, Formex.PartType.Ceiling)
	levelData = levelData or FormexSystem.EnsureLevelData(plotData, levelIndex)

    levelData.Ceilings[index] = newMaterial

    FormexSystem.RenderPlot(plotData.PlotId, levelIndex, Formex.PartType.Ceiling)

	pushUndo(plotData.PlotId, snapshot)
    FormexSystem.QueueSave(plotData.PlotId)
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
