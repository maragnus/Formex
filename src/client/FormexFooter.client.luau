local Players = game:GetService("Players")
local FormexClient = require(script.Parent:WaitForChild("FormexClient"))
local FormexUI = require(script.Parent:WaitForChild("FormexUI"))
local BlurController = FormexUI.BlurController

local localPlayer = Players.LocalPlayer

local screenGui: ScreenGui = FormexUI.ScreenGui

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

local function createButton(name: string, label: string, icon: string, action: any)
    local button = FormexUI.CreateButton(footerFrame, name, label, { Icon = icon }, action)
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

createButton("CLAIM", "Claim", "85199762467908", function()
    print("Do Claim")
    FormexClient.ClaimPlot()
end)

createButton("UNCLAIM", "Unclaim", "137711830774408", function()
    print("Do Unclaim")
    FormexClient.ReleasePlot()
end)

createButton("HOME", "Go Home", nil, function()
    print("Teleport Home")
end)

createButton("RENAME", "Change Name", "74166756362476", function()
    print("Change name")
end)

createButton("PERMISSIONS", "Permissions", "83277863761797", function()
    print("Change Permissions")
end)

createButton("DESIGN", "Design", "78727585562674", function()
    uiSettings.DesignMode = uiSettings.IsManager and "Furniture"
    refreshUI()
end)

createButton("EXIT_DESIGN", "Exit Design", "78727585562674", function()
    uiSettings.DesignMode = nil
    refreshUI()
end)

createButton("DESIGN_FLOOR", "Floors", "136537860205120", function()
    uiSettings.DesignMode = uiSettings.IsManager and "Furniture"
    refreshUI()
end)

createButton("DESIGN_CEILING", "Ceilings", "86944909652185", function()
    uiSettings.DesignMode = uiSettings.IsManager and "Furniture"
    refreshUI()
end)

createButton("DESIGN_WALL", "Walls", "105416010695180", function()
    uiSettings.DesignMode = uiSettings.IsManager and "Furniture"
    refreshUI()
end)

createButton("DESIGN_FURNITURE", "Furniture", "120639802680464", function()
    uiSettings.DesignMode = uiSettings.IsManager and "Furniture"
    refreshUI()
end)

createButton("DESIGN_PAINT", "Paint", "92885878760720", function()
    uiSettings.DesignMode = uiSettings.IsManager and "Paint"
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