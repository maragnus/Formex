local Players = game:GetService("Players")
local FormexClient = require(script.Parent:WaitForChild("FormexClient"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BlurController = require(script.Parent:WaitForChild("BlurController"))

local localPlayer = Players.LocalPlayer

local screenGui: ScreenGui = Instance.new("ScreenGui", localPlayer:WaitForChild("PlayerGui"))
screenGui.Name = "FormexUI"

-- Narrow bar at the bottom
local padding = UDim.new(0, 8)
local footerFrame: Frame = Instance.new("Frame", screenGui)
footerFrame.Name = "FooterFrame"
footerFrame.AnchorPoint = Vector2.new(0.5, 1)
footerFrame.Position = UDim2.new(0.5, 0, 1, 64)
footerFrame.Size = UDim2.new(1, -32, 0, 128)
footerFrame.BackgroundColor3 = Color3.fromRGB(250, 245, 255)
footerFrame.BackgroundTransparency = 0.5
local footerUICorner: UICorner = Instance.new("UICorner", footerFrame)
footerUICorner.CornerRadius = UDim.new(0, 32)
BlurController.new(footerFrame, "Rectangle")
local footerUIPadding = Instance.new("UIPadding", footerFrame)
footerUIPadding.PaddingTop = padding
footerUIPadding.PaddingBottom = UDim.new(0, padding.Offset + 64)
footerUIPadding.PaddingLeft = padding
footerUIPadding.PaddingRight = padding
local footerLayout: UIListLayout = Instance.new("UIListLayout", footerFrame)
footerLayout.FillDirection = Enum.FillDirection.Horizontal
footerLayout.Padding = UDim.new(0, 16)
footerLayout.SortOrder = Enum.SortOrder.LayoutOrder
local footerButtons = {} :: {[string]: ImageButton}

local function createButton(name: string, label: string, action: any)
    local button = Instance.new("ImageButton", footerFrame)
    button.Name = name
    button.AutoButtonColor = false
    button.BackgroundColor3 = Color3.fromRGB(252, 252, 255)
    button.ClipsDescendants = false
    button.Activated:Connect(action)
    button.Visible = false
    button.Size = UDim2.new(0, 128, 1, 0)
    local buttonCorner = Instance.new("UICorner", button)
    local buttonShadow = Instance.new("Frame", button)
    buttonShadow.Name = "Shadow"
    buttonShadow.AnchorPoint = Vector2.new(0.5, 0.5)
    buttonShadow.Position = UDim2.new(0.5, 0, 0.5, 4)
    buttonShadow.Size = UDim2.new(1, 8, 1, 12)
    buttonShadow.BackgroundTransparency = 0.85
    buttonShadow.BackgroundColor3 = Color3.new(0, 0, 0)
    buttonShadow.ZIndex = 0
    local shadowCorner = Instance.new("UICorner", buttonShadow)
    shadowCorner.CornerRadius = UDim.new(0, 12)

    buttonCorner.CornerRadius = UDim.new(0, 12)
    local stroke = Instance.new("UIStroke", button)
    stroke.Color = Color3.fromRGB(200, 200, 220)
    stroke.Thickness = 2
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

    local gradient = Instance.new("UIGradient", button)
    gradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(230, 234, 255))
    gradient.Rotation = 90

    local labelText = Instance.new("TextLabel", button)
    labelText.AnchorPoint = Vector2.new(0.5, 0.5)
    labelText.Position = UDim2.new(0.5, 0, 0.5, -2)
    labelText.Size = UDim2.new(1, -16, 1, -16)
    labelText.BackgroundTransparency = 1
    labelText.Text = label
    labelText.Font = Enum.Font.GothamBold
    labelText.TextSize = 18
    labelText.TextColor3 = Color3.fromRGB(60, 65, 90)
    labelText.ZIndex = 2
    local textStroke = Instance.new("UIStroke", labelText)
    textStroke.Thickness = 1
    textStroke.Color = Color3.fromRGB(255, 255, 255)
    textStroke.Transparency = 0.4

    footerButtons[name] = button
end

local function updateFooter(buttons: {})
    for _, button in footerButtons do
        button.Visible = false
    end

    for name, show in buttons do
        if not show then continue end
        local button = footerButtons[name]
        button.Visible = true
    end
end

local uiSettings = {
    IsHome = false,
    PlotName = "Unclaimed",
    OwnerName = "Nobody",
    HomeName = "Unclaimed",
    ShowClaim = false,
    ShowUnclaim = false,
    ShowTeleportHome = false,
    IsOwner = false,
    IsManager = false,
    IsVIP = false,
    IsGuest = false,
    DesignMode = false
}

local refreshUI

createButton("CLAIM", "Claim", function()
    print("Do Claim")
    FormexClient.ClaimPlot()
end)

createButton("UNCLAIM", "Unclaim", function()
    print("Do Unclaim")
    FormexClient.ReleasePlot()
end)

createButton("HOME", "Go Home", function()
    print("Teleport Home")
end)

createButton("RENAME", "Change Name", function()
    print("Change name")
end)

createButton("PERMISSIONS", "Permissions", function()
    print("Change Permissions")
end)

createButton("DESIGN", "Design", function()
    uiSettings.DesignMode = uiSettings.IsManager and "Furniture"
    refreshUI()
end)

createButton("EXIT_DESIGN", "Exit Design", function()
    uiSettings.DesignMode = nil
    refreshUI()
end)

createButton("DESIGN_FLOOR", "Floors", function()
    uiSettings.DesignMode = uiSettings.IsManager and "Furniture"
    refreshUI()
end)

createButton("DESIGN_CEILING", "Ceilings", function()
    uiSettings.DesignMode = uiSettings.IsManager and "Furniture"
    refreshUI()
end)

createButton("DESIGN_WALL", "Walls", function()
    uiSettings.DesignMode = uiSettings.IsManager and "Furniture"
    refreshUI()
end)

createButton("DESIGN_FURNITURE", "Furniture", function()
    uiSettings.DesignMode = uiSettings.IsManager and "Furniture"
    refreshUI()
end)

-- Listen for client events
FormexClient.ClientEvents:Connect(function(eventName)
    if eventName ~= "MyPlotChanged" then return end

    local info = FormexClient.MyPlot
    uiSettings.IsHome = FormexClient.CurrentPlotId == FormexClient.MyPlotId
    uiSettings.ShowTeleportHome = info.IsMine
    uiSettings.HomeName = info.Name

    refreshUI()
end)

FormexClient.ClientEvents:Connect(function(eventName)
    if eventName ~= "CurrentPlotChanged" then return end

    local info = FormexClient.CurrentPlot
    uiSettings.IsHome = FormexClient.CurrentPlotId == FormexClient.MyPlotId
    uiSettings.PlotName = info.Name
    uiSettings.OwnerName = info.OwnerName
    uiSettings.ShowClaim = info.IsValid and not info.IsClaimed
    uiSettings.ShowUnclaim = info.IsMine
    uiSettings.IsOwner = info.MyPermission == "Owner"
    uiSettings.IsManager = uiSettings.IsOwner or info.MyPermission == "Manager"
    uiSettings.IsVIP = uiSettings.IsManager or info.MyPermission == "VIP"
    uiSettings.IsGuest = uiSettings.IsVIP or info.MyPermission == "Guest"
    uiSettings.DesignMode = uiSettings.IsManager and uiSettings.DesignMode

    print(info)

    refreshUI()
end)

refreshUI = function()
    local buttons = {}

    buttons["CLAIM"] = uiSettings.ShowClaim
    buttons["UNCLAIM"] = not uiSettings.DesignMode and uiSettings.ShowUnclaim
    buttons["HOME"] = not uiSettings.IsHome and uiSettings.ShowTeleportHome
    buttons["RENAME"] = not uiSettings.DesignMode and uiSettings.IsOwner
    buttons["PERMISSIONS"] = not uiSettings.DesignMode and uiSettings.IsOwner
    buttons["DESIGN"] = not uiSettings.DesignMode and uiSettings.IsManager
    buttons["EXIT_DESIGN"] = uiSettings.DesignMode
    buttons["DESIGN_FLOOR"] = uiSettings.DesignMode
    buttons["DESIGN_CEILING"] = uiSettings.DesignMode
    buttons["DESIGN_WALL"] = uiSettings.DesignMode
    buttons["DESIGN_FURNITURE"] = uiSettings.DesignMode

    updateFooter(buttons)

    BlurController.updateAll();
end

refreshUI()