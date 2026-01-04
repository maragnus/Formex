--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FormexFolder = ReplicatedStorage:WaitForChild("Formex")
local Plot = require(FormexFolder:WaitForChild("Plot"))
local PlotShared = require(FormexFolder:WaitForChild("PlotShared"))

local PlotServer = {}

export type PlotInfo = PlotShared.PlotInfo

local emptyPlot = Plot.Attach(PlotShared.CreateEmptyPlot(), nil)

PlotServer.Plots = {} :: {[number]: PlotInfo}
PlotServer.CurrentPlot = {} :: {[number]: PlotInfo}

function PlotServer.RegisterPlot(plotPart: BasePart): PlotInfo
	local plot = Plot.Attach(PlotShared.CreatePlot(plotPart, nil), nil)
	PlotServer.Plots[plot.PlotId] = plot
	PlotShared.BindPlotAttributes(plotPart, plot, {
		LocalUserId = nil,
	})
	return plot
end

function PlotServer.SetPlayerCurrentPlot(player: Player, plotId: number)
	PlotServer.CurrentPlot[player.UserId] = PlotServer.Plots[plotId] or emptyPlot
end

function PlotServer.GetPlayerCurrentPlot(player: Player): PlotInfo
	return PlotServer.CurrentPlot[player.UserId] or emptyPlot
end

function PlotServer.GetPlot(plotId: number): PlotInfo
	return PlotServer.Plots[plotId] or emptyPlot
end

return PlotServer
