local Players = game:GetService("Players")
local FormexClient = require(script:WaitForChild("FormexClient"))

local localPlayer = Players.LocalPlayer

-- Listen for server-driven attribute changes
FormexClient.SetMyPlotId(localPlayer:GetAttribute("MyPlotId") or 0)
localPlayer:GetAttributeChangedSignal("MyPlotId"):Connect(function()
	FormexClient.SetMyPlotId(localPlayer:GetAttribute("MyPlotId") or 0)
end)

FormexClient.SetCurrentPlotId(localPlayer:GetAttribute("CurrentPlotId") or 0)
localPlayer:GetAttributeChangedSignal("CurrentPlotId"):Connect(function()
	FormexClient.SetCurrentPlotId(localPlayer:GetAttribute("CurrentPlotId") or 0)
end)

-- Register all plots
local plotCollection = workspace:WaitForChild("Formex"):WaitForChild("Plots")
for _, plotPart in ipairs(plotCollection:GetChildren()) do
    FormexClient.RegisterPlot(plotPart)
end
plotCollection.ChildAdded:Connect(function(child)
    FormexClient.RegisterPlot(child)
end)

-- Example event handlers
local eventHandlers = {
    MyPlotChanged = function(newPlotId)
        -- print("MyPlotId changed to:", newPlotId)
    end,
    CurrentPlotChanged = function(newPlotId)
        -- print("CurrentPlotId changed to:", newPlotId)
    end,
}

-- Listen for client events
FormexClient.ClientEvents:Connect(function(eventName, ...)
    local eventHandler = eventHandlers[eventName]
    if eventHandler then
        eventHandlers[eventName](...)
    end
end)