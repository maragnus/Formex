--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FormexFolder = ReplicatedStorage:WaitForChild("Formex")
local Formex = require(FormexFolder:WaitForChild("Formex"))

export type RenderData = {
    PlotPart: BasePart,
    PlotData: Formex.PlotData,
    LevelIndex: number,
    LevelData: Formex.LevelData,
    LevelPart: BasePart,
}

local module = {}

function module.RenderPlot(plotPart: BasePart, plotData: Formex.PlotData): Model
    local data = {
        PlotPart = plotPart,
        PlotData = plotData,
    }

    for index, _ in ipairs(plotData.Levels) do
        module.RenderLevel(data, index)
    end
end

function module.ClearPlot(plotPart: BasePart)
    plotPart:ClearAllChildren()
end

function module.RenderLevel(data: RenderData, levelIndex: number)
    data.LevelIndex = levelIndex
    data.LevelData = data.PlotData.Levels[levelIndex]
    local levelPart = data:WaitForChild("Level_" .. tostring(data.LevelIndex))
    if (levelPart == nil) then
        levelPart = Instance.new("Part", data.PlotPart)
        levelPart.Name = "Level_" .. tostring(data.LevelIndex)
        levelPart.Anchored = true
        levelPart.Position = data.PlotPart.Position + Vector3.new(0, Formex.LevelHeight * (levelIndex - 1), 0)
        levelPart.Size = Vector3.new(Formex.GridSize * Formex.SegmentSize.X, Formex.LevelHeight, Formex.GridSize * Formex.SegmentSize.Y)
    end

    module.RenderFloor(data)
    module.RenderWalls(data)
    module.RenderFurniture(data)
end

function module.RenderFloor(data: RenderData)

end

function module.RenderWalls(data: RenderData)

end

function module.RenderFurniture(data: RenderData)

end

return module