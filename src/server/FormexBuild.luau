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

function FormexBuild.BuildWall(player: Player, wallData: Formex.WallData, action: Formex.BuildAction)
    local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
    if not plotData then error("No current plot") end
    if permission ~= Formex.Permission.Manager and permission ~= Formex.Permission.Owner then
		error("Access denied")
	end
	if not wallData then error("Invalid wall data") end

	local levelIndex = wallData.Level or 1
	local levelData = FormexSystem.EnsureLevelData(plotData, levelIndex)

    local returnWall: Formex.WallData? = nil
    if action == Formex.BuildAction.Add then
        if not Formex.IsWallValid(plotData, wallData) then
            error("Invalid wall placement")
        end
        local frontMaterial = wallData.FrontMaterial or Formex.DefaultWallMaterial
        local backMaterial = wallData.BackMaterial or frontMaterial
        local startMaterial = wallData.StartMaterial or frontMaterial
        local endMaterial = wallData.EndMaterial or frontMaterial

        local newId = getNextId(levelData.Walls)
        local newWall = {
            WallId = newId,
            Level = levelIndex,
            Start = wallData.Start,
            End = wallData.End,
            FrontMaterial = frontMaterial,
            BackMaterial = backMaterial,
            StartMaterial = startMaterial,
            EndMaterial = endMaterial,
            Part = nil
        }
        levelData.Walls[newId] = newWall
        returnWall = {
            WallId = newId,
            Level = levelIndex,
            Start = wallData.Start,
            End = wallData.End,
            FrontMaterial = frontMaterial,
            BackMaterial = backMaterial,
            StartMaterial = startMaterial,
            EndMaterial = endMaterial,
            Part = nil
        }
    elseif action == Formex.BuildAction.Edit then
        local existing = levelData.Walls[wallData.WallId]
        if not existing then
            error("Wall not found")
        end
		if not Formex.IsWallValid(plotData, wallData) then
			error("Invalid wall placement")
		end
        local frontMaterial = wallData.FrontMaterial or existing.FrontMaterial or Formex.DefaultWallMaterial
        local backMaterial = wallData.BackMaterial or existing.BackMaterial or frontMaterial
        local startMaterial = wallData.StartMaterial or existing.StartMaterial or frontMaterial
        local endMaterial = wallData.EndMaterial or existing.EndMaterial or frontMaterial
		existing.Level = levelIndex
        existing.Start = wallData.Start
        existing.End = wallData.End
        existing.FrontMaterial = frontMaterial
        existing.BackMaterial = backMaterial
        existing.StartMaterial = startMaterial
        existing.EndMaterial = endMaterial
        returnWall = {
            WallId = existing.WallId,
            Level = levelIndex,
            Start = existing.Start,
            End = existing.End,
            FrontMaterial = existing.FrontMaterial,
            BackMaterial = existing.BackMaterial,
            StartMaterial = existing.StartMaterial,
            EndMaterial = existing.EndMaterial,
            Part = nil
        }
    elseif action == Formex.BuildAction.Delete then
        local existing = levelData.Walls[wallData.WallId]
        if existing and existing.Part then
            existing.Part:Destroy()
        end
        levelData.Walls[wallData.WallId] = nil
    end

	local plotPart = FormexSystem.Plots[plotData.PlotId]
	if plotPart then
		FormexSystem.RenderPlot(plotData.PlotId, levelIndex, Formex.PartType.Wall)
	end

    FormexSystem.QueueSave(plotData.PlotId)
    return returnWall
end

function FormexBuild.BuildFloor(player: Player, level: number, x: number, y: number, material: number, material2: number?)
    local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
    if not plotData then error("No current plot") end
    if permission ~= Formex.Permission.Manager and permission ~= Formex.Permission.Owner then
		error("Access denied")
	end

    -- TODO: is tile within an owned segment and owned level?

    local levelIndex = level or 1
    local levelData = FormexSystem.EnsureLevelData(plotData, levelIndex)
    local index = Formex.XYToIndex(x, y)
    material = material or 0

    -- TODO: handle FloorType.CW and FloorType.CCW
    levelData.Floors[index] = material > 0 and material or nil

    FormexSystem.RenderPlot(plotData.PlotId, levelIndex, Formex.PartType.Floor)

    FormexSystem.QueueSave(plotData.PlotId)
end

function FormexBuild.BuildCeiling(player: Player, level: number, x: number, y: number, material: number, material2: number?)
    local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
    if not plotData then error("No current plot") end
    if permission ~= Formex.Permission.Manager and permission ~= Formex.Permission.Owner then
        error("Access denied")
    end

    local levelIndex = level or 1
    local levelData = FormexSystem.EnsureLevelData(plotData, levelIndex)
    local index = Formex.XYToIndex(x, y)

    levelData.Ceilings[index] = material > 0 and material or nil

    FormexSystem.RenderPlot(plotData.PlotId, levelIndex, Formex.PartType.Ceiling)

    FormexSystem.QueueSave(plotData.PlotId)
end

function FormexBuild.BuildObject(player: Player, objectData: Formex.ObjectData, action: Formex.BuildAction)
    local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
    if permission ~= Formex.Permission.Manager then error("Access denied") end
    
    -- TODO
    
    FormexSystem.QueueSave(plotData.PlotId)
end

return FormexBuild
