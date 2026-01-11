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

function Utils.ConfirmMessageBox(plugin: Plugin, title: string, message: string, onConfirm: () -> ())
    local messageBox = plugin:CreateDockWidgetPluginGuiAsync("FormexConfirmBox",
        DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, true, false, 240, 160, 200, 120))
    messageBox.Title = title

    local textLabel = Instance.new("TextLabel", messageBox)
    textLabel.Size = UDim2.new(1, -16, 1, -60)
    textLabel.Position = UDim2.new(0, 8, 0, 8)
    textLabel.TextWrapped = true
    textLabel.Text = message

    local cancelButton = Instance.new("TextButton", messageBox)
    cancelButton.Size = UDim2.new(0, 100, 0, 30)
    cancelButton.Position = UDim2.new(0.5, -110, 1, -40)
    cancelButton.Text = "Cancel"

    local confirmButton = Instance.new("TextButton", messageBox)
    confirmButton.Size = UDim2.new(0, 100, 0, 30)
    confirmButton.Position = UDim2.new(0.5, 10, 1, -40)
    confirmButton.Text = "Delete"

    local function cleanup()
        messageBox.Enabled = false
        messageBox:Destroy()
    end

    cancelButton.MouseButton1Click:Connect(function()
        cleanup()
    end)

    confirmButton.MouseButton1Click:Connect(function()
        cleanup()
        onConfirm()
    end)
end

return Utils
