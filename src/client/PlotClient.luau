--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local FormexFolder = ReplicatedStorage:WaitForChild("Formex")
local Plot = require(FormexFolder:WaitForChild("Plot"))
local PlotShared = require(FormexFolder:WaitForChild("PlotShared"))
local FormexFunctions: RemoteFunction = FormexFolder:WaitForChild("FormexFunctions")

if not Players.LocalPlayer then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
end
local localPlayer = Players.LocalPlayer

local PlotClient = {}

export type PlotInfo = PlotShared.PlotInfo

local emptyPlot = Plot.Attach(PlotShared.CreateEmptyPlot(), nil)

PlotClient.Plots = {} :: {[number]: PlotInfo}
PlotClient.MyPlotId = 0
PlotClient.MyPlot = emptyPlot
PlotClient.CurrentPlotId = 0
PlotClient.CurrentPlot = emptyPlot

local events: BindableEvent? = nil

local function fireEvent(eventName: string, ...)
	if events then
		events:Fire(eventName, ...)
	end
end

local function notifyPlotChange(plotId: number)
	if PlotClient.MyPlotId == plotId then
		PlotClient.MyPlot = PlotClient.Plots[plotId] or emptyPlot
		fireEvent("MyPlotChanged", plotId)
	end
	if PlotClient.CurrentPlotId == plotId then
		PlotClient.CurrentPlot = PlotClient.Plots[plotId] or emptyPlot
		fireEvent("CurrentPlotChanged", plotId)
	end
end

local function invokePlot(plot: PlotInfo, action: string, ...)
	return FormexFunctions:InvokeServer(plot.Id, action, ...)
end

local function subscribeToPlot(plotPart: BasePart)
	local plot = Plot.Attach(PlotShared.CreatePlot(plotPart, localPlayer.UserId), {
		Invoke = invokePlot,
	})
	PlotClient.Plots[plot.PlotId] = plot
	PlotShared.BindPlotAttributes(plotPart, plot, {
		LocalUserId = localPlayer.UserId,
		OnPlotChanged = function()
			notifyPlotChange(plot.PlotId)
		end,
	})

	notifyPlotChange(plot.PlotId)

	return plot
end

function PlotClient.SetEventEmitter(eventEmitter: BindableEvent)
	events = eventEmitter
end

function PlotClient.SetMyPlotId(plotId: number?)
	PlotClient.MyPlotId = plotId or 0
	notifyPlotChange(PlotClient.MyPlotId)
end

function PlotClient.SetCurrentPlotId(plotId: number?)
	PlotClient.CurrentPlotId = plotId or 0
	notifyPlotChange(PlotClient.CurrentPlotId)
end

function PlotClient.RegisterPlot(plotPart: BasePart)
	if plotPart:GetAttribute("PlotId") then
		local info = subscribeToPlot(plotPart)
		print("Client registered plot with PlotId:", info.PlotId)
		return
	end

	print("Delaying client registered plot")
	plotPart:GetAttributeChangedSignal("PlotId"):Once(function()
		local info = subscribeToPlot(plotPart)
		print("Client registered plot with PlotId:", info.PlotId)
	end)
end

return PlotClient
