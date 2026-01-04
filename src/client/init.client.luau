local Players = game:GetService("Players")
require(script:WaitForChild("FormexClient"))
local PlotClient = require(script:WaitForChild("PlotClient"))

local localPlayer = Players.LocalPlayer

-- Listen for server-driven attribute changes
PlotClient.SetMyPlotId(localPlayer:GetAttribute("MyPlotId") or 0)
localPlayer:GetAttributeChangedSignal("MyPlotId"):Connect(function()
	PlotClient.SetMyPlotId(localPlayer:GetAttribute("MyPlotId") or 0)
end)

PlotClient.SetCurrentPlotId(localPlayer:GetAttribute("CurrentPlotId") or 0)
localPlayer:GetAttributeChangedSignal("CurrentPlotId"):Connect(function()
	PlotClient.SetCurrentPlotId(localPlayer:GetAttribute("CurrentPlotId") or 0)
end)

-- Register all plots
local plotCollection = workspace:WaitForChild("Formex"):WaitForChild("Plots")
for _, plotPart in ipairs(plotCollection:GetChildren()) do
    PlotClient.RegisterPlot(plotPart)
end
plotCollection.ChildAdded:Connect(function(child)
    PlotClient.RegisterPlot(child)
end)
