--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FormexFolder = ReplicatedStorage:WaitForChild("Formex")
local Formex = require(FormexFolder:WaitForChild("Formex"))
local FormexSystem = require(script.Parent:WaitForChild("FormexSystem"))

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

function FormexBuild.RenderPlot(plotPart: BasePart, plotData: Formex.PlotData): Model
    local data = {
        PlotPart = plotPart,
        PlotData = plotData,
    }

    for index, _ in ipairs(plotData.Levels) do
        FormexBuild.RenderLevel(data, index)
    end
end


function FormexBuild.RenderLevel(data: RenderState, levelIndex: number)
    data.LevelIndex = levelIndex
    data.LevelData = data.PlotData.Levels[levelIndex]
    local levelPart = data.PlotPart:WaitForChild(tostring(data.LevelIndex))
    if levelPart ~= nil then
        data.LevelPart = levelPart
        data.FloorFolder = levelPart.Floors
        data.WallFolder = levelPart.Walls
        data.ObjectFolder = levelPart.Objects
    else
        levelPart = Instance.new("Part", data.PlotPart)
        levelPart.Name = tostring(data.LevelIndex)
        levelPart.Anchored = true
        levelPart.Position = data.PlotPart.Position + Vector3.new(0, Formex.LevelHeight * (levelIndex - 1), 0)
        levelPart.Size = Vector3.new(Formex.GridSize * Formex.SegmentSize.X, Formex.LevelHeight, Formex.GridSize * Formex.SegmentSize.Y)

        data.LevelPart = levelPart
        data.FloorFolder = Instance.new("Folder", levelPart)
        data.FloorFolder.Name = "Floors"
        data.WallFolder = Instance.new("Folder", levelPart)
        data.WallFolder.Name = "Walls"
        data.ObjectFolder = Instance.new("Folder", levelPart)
        data.ObjectFolder.Name = "Objects"
    end

    FormexBuild.RenderFloor(data)
    FormexBuild.RenderWalls(data)
    FormexBuild.RenderFurniture(data)
end

function FormexBuild.RenderFloor(data: RenderState)
    local parent = data.FloorFolder
    for floorId, floorData in data.LevelData.Floors do
        if not floorData.Part then
            Formex.CreateFloor(parent, floorData)
        else
            Formex.EditFloor(floorData)
        end
    end
end

function FormexBuild.RenderWalls(data: RenderState)
    local parent = data.WallFolder
    for wallId, wallData in data.LevelData.Walls do
        if not wallData.Part then
            Formex.CreateWall(parent, wallData)
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
    if permission ~= Formex.Permissions.Manager then error("Access denied") end

    -- TODO

    FormexSystem.QueueSave(plotData.PlotId)
end

function FormexBuild.BuildFloor(player: Player, floorData: Formex.FloorData, action: Formex.BuildAction)
    local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
    if permission ~= Formex.Permissions.Manager then error("Access denied") end
    
    -- TODO

    FormexSystem.QueueSave(plotData.PlotId)
end

function FormexBuild.BuildObject(player: Player, objectData: Formex.ObjectData, action: Formex.BuildAction)
    local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
    if permission ~= Formex.Permissions.Manager then error("Access denied") end
    
    -- TODO
    
    FormexSystem.QueueSave(plotData.PlotId)
end

return FormexBuild