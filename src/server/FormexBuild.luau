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

export type RenderState = {
    PlotPart: BasePart,
    PlotData: Formex.PlotData,
    LevelIndex: number,
    LevelData: Formex.LevelData,
    LevelPart: BasePart,
    FloorFolder: Folder,
    WallFolder: Folder,
    ObjectFolder: Folder
}

local FormexBuild = {}

local function ensureLevelData(plotData: Formex.PlotData, levelIndex: number): Formex.LevelData
	plotData.Levels = plotData.Levels or {} :: {number: Formex.LevelData}
	local levelData = plotData.Levels[levelIndex]

	if not levelData then
		levelData = {
			Walls = {} :: {number: Formex.WallData},
			Floors = {} :: {[number]: number},
			Ceilings = {} :: {[number]: number},
			Objects = {} :: {number: Formex.ObjectData},
		}
		plotData.Levels[levelIndex] = levelData
	end

	return levelData
end

local function getNextId(entries: {[number]: any}): number
	local maxId = 0
	for id in entries do
		if id > maxId then
			maxId = id
		end
	end
	return maxId + 1
end

function FormexBuild.RenderPlot(plotPart: BasePart, plotData: Formex.PlotData, filterLevelIndex: number?, filterPartType: Formex.PartType?): Model
    local data = {
        PlotPart = plotPart,
        PlotData = plotData,
    }

    if filterLevelIndex then
        FormexBuild.RenderLevel(data :: RenderState, filterLevelIndex, filterPartType)
        return
    end

    for level = 1, Formex.MaxPlotSize.Levels, 1 do
        FormexBuild.RenderLevel(data, level)
    end
end

function FormexBuild.RenderLevel(data: RenderState, levelIndex: number, filterPartType: Formex.PartType?)
    data.LevelIndex = levelIndex
    data.LevelData = ensureLevelData(data.PlotData, levelIndex)

    local levelPart = data.PlotPart:FindFirstChild(tostring(data.LevelIndex))
    if not levelPart then
        levelPart = Instance.new("Part", data.PlotPart)
        levelPart.Name = tostring(data.LevelIndex)
    
        levelPart.Anchored = true
        levelPart.CanCollide = false
        levelPart.CanTouch = false
        levelPart.CanQuery = false
        levelPart.CastShadow = false
        levelPart.Transparency = 1
        levelPart.Material = Enum.Material.Air
        -- Level part represents the entire level volume, invisible and non-collidable
        levelPart.Position = data.PlotPart.Position + Vector3.new(0, Formex.LevelHeight * (levelIndex - 1) + Formex.LevelHeight / 2, 0)
        levelPart.Size = Vector3.new(data.PlotPart.Size.X, Formex.LevelHeight, data.PlotPart.Size.Z)
    end

    data.LevelPart = levelPart :: BasePart
    data.FloorFolder = Formex.EnsureFolder("Floors", levelPart)
    data.WallFolder = Formex.EnsureFolder("Walls", levelPart)
    data.ObjectFolder = Formex.EnsureFolder("Objects", levelPart)

    if filterPartType == "Wall" then
        FormexBuild.RenderWalls(data)
    elseif filterPartType == "Floor" or filterPartType == "Ceiling" then
        FormexBuild.RenderFloorCeiling(data)
    elseif filterPartType == "Object" then
        FormexBuild.RenderFurniture(data)
    else
        FormexBuild.RenderFloorCeiling(data)
        FormexBuild.RenderWalls(data)
        FormexBuild.RenderFurniture(data)
    end
end

function FormexBuild.RenderFloorCeiling(data: RenderState)
    local parent = data.FloorFolder
    local tiles: {[number]: boolean} = {}

    for index: number, _ in data.LevelData.Floors do
        tiles[index] = true
    end

    for index: number, _ in data.LevelData.Ceilings do
        tiles[index] = true
    end

    for _, child in parent:GetChildren() do
        local index = tonumber(child.Name)
        if index and not tiles[index] then
            child:Destroy()
        end
    end

    local floorData = {
        FloorId = 0,
        LevelIndex = data.LevelIndex,
        Type = Formex.FloorType.Square,
    } :: Formex.FloorData

    for index in tiles do
        local floorMaterial = data.LevelData.Floors[index]
        local ceilingMaterial = data.LevelData.Ceilings[index]
        if not floorMaterial and not ceilingMaterial then
            continue
        end

        floorData.FloorId = index
        floorData.Tile = Formex.IndexToXY(index)
        floorData.Type = Formex.FloorType.Square
        floorData.FloorMaterial = floorMaterial
        floorData.CeilingMaterial = ceilingMaterial
        floorData.Part = parent:FindFirstChild(tostring(index)) :: Part

        Formex.UpdateFloor(data.PlotPart, floorData, floorData.Part)

        if false then
            local part = parent:FindFirstChild(tostring(index)) :: Part?
            local height = data.LevelIndex == 1 and Formex.FoundationHeight or Formex.InterfloorHeight
            local x, y = 0, 0
            local floorTexture: Texture
            local ceilingTexture: Texture
            if not part then
                part = Instance.new("Part") :: Part
                part.Name = tostring(index)
                part.Anchored = true
                part.Parent = parent

                floorTexture = Instance.new("Texture")
                floorTexture.Face = Enum.NormalId.Top
                floorTexture.Name = "Floor"
                floorTexture.Parent = part

                ceilingTexture = Instance.new("Texture")
                ceilingTexture.Face = Enum.NormalId.Bottom
                ceilingTexture.Name = "Ceiling"
                ceilingTexture.Parent = part
            else
                floorTexture = part:FindFirstChild("Floor") :: Texture
                ceilingTexture = part:FindFirstChild("Ceiling") :: Texture
                if not (floorTexture and floorTexture:IsA("Texture")) then
                    floorTexture = Instance.new("Texture")
                    floorTexture.Face = Enum.NormalId.Top
                    floorTexture.Name = "Floor"
                    floorTexture.Parent = part
                end
                if not (ceilingTexture and ceilingTexture:IsA("Texture")) then
                    ceilingTexture = Instance.new("Texture")
                    ceilingTexture.Face = Enum.NormalId.Bottom
                    ceilingTexture.Name = "Ceiling"
                    ceilingTexture.Parent = part
                end
            end

            local tileSize = Formex.LayoutGridSize
            local plotSize = data.PlotPart.Size
            local xOffset = (x + 0.5) * tileSize - (plotSize.X / 2)
            local zOffset = (y + 0.5) * tileSize - (plotSize.Z / 2)
            local levelTop = (plotSize.Y / 2) + (Formex.LevelHeight * (data.LevelIndex - 1))
            local centerY = levelTop - (height / 2)

            part.Size = Vector3.new(tileSize, height, tileSize)
            part.CFrame = data.PlotPart.CFrame * CFrame.new(xOffset, centerY, zOffset)

            Formex.UpdateTexture(part, floorTexture, floorMaterial or 0)
            Formex.UpdateTexture(part, ceilingTexture, ceilingMaterial or 0)
        end
    end
end

function FormexBuild.RenderWalls(data: RenderState)
    local parent = data.WallFolder
    for wallId, wallData in data.LevelData.Walls do
        if not wallData.Part then
            local part = Formex.CreateWall(wallData, data.PlotPart)
            if part then
                part.Parent = parent
            end
        else
            Formex.EditWall(wallData)
        end
    end
end

function FormexBuild.RenderFurniture(data: RenderState)
    local parent = data.RenderFurniture
    for objectId, objectData in data.LevelData.Objects do
        if not objectData.Part then
            Formex.CreateObject(parent, objectData)
        else
            Formex.EditObject(objectData)
        end
    end
end

function FormexBuild.BuildWall(player: Player, wallData: Formex.WallData, action: Formex.BuildAction)
    local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
    if not plotData then error("No current plot") end
    if permission ~= Formex.Permission.Manager and permission ~= Formex.Permission.Owner then
		error("Access denied")
	end
	if not wallData then error("Invalid wall data") end

	local levelIndex = wallData.Level or 1
	local levelData = ensureLevelData(plotData, levelIndex)

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
		FormexBuild.RenderLevel({
			PlotPart = plotPart,
			PlotData = plotData,
		} :: RenderState, levelIndex)
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
    local levelData = ensureLevelData(plotData, levelIndex)
    local index = Formex.XYToIndex(x, y)
    material = material or 0

    -- TODO: handle FloorType.CW and FloorType.CCW
    levelData.Floors[index] = material > 0 and material or nil

    FormexBuild.RenderPlot(FormexSystem.Plots[plotData.PlotId] :: BasePart, plotData, levelIndex, Formex.PartType.Floor)

    FormexSystem.QueueSave(plotData.PlotId)
end

function FormexBuild.BuildCeiling(player: Player, level: number, x: number, y: number, material: number, material2: number?)
    local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
    if not plotData then error("No current plot") end
    if permission ~= Formex.Permission.Manager and permission ~= Formex.Permission.Owner then
        error("Access denied")
    end

    local levelIndex = level or 1
    local levelData = ensureLevelData(plotData, levelIndex)
    local index = Formex.XYToIndex(x, y)

    levelData.Ceilings[index] = material > 0 and material or nil

    FormexBuild.RenderPlot(FormexSystem.Plots[plotData.PlotId] :: BasePart, plotData, levelIndex, Formex.PartType.Ceiling)

    FormexSystem.QueueSave(plotData.PlotId)
end

function FormexBuild.BuildObject(player: Player, objectData: Formex.ObjectData, action: Formex.BuildAction)
    local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
    if permission ~= Formex.Permission.Manager then error("Access denied") end
    
    -- TODO
    
    FormexSystem.QueueSave(plotData.PlotId)
end

return FormexBuild
