--!strict

local Utils = {}

function Utils.DisplayMessageBox(plugin: Plugin, title: string, message: string)
    local messageBox = plugin:CreateDockWidgetPluginGuiAsync("FormexAlertBox",
        DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, true, false, 200, 150, 150, 100))
    messageBox.Title = title

    local textLabel = Instance.new("TextLabel", messageBox)
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.Text = message

    local closeButton = Instance.new("TextButton", messageBox)
    closeButton.Size = UDim2.new(0, 100, 0, 30)
    closeButton.Position = UDim2.new(0.5, -50, 1, -40)
    closeButton.Text = "Close"
    closeButton.MouseButton1Click:Connect(function()
        messageBox.Enabled = false
        messageBox:Destroy()
    end)
end

return Utils