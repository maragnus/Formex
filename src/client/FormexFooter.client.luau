local Players = game:GetService("Players")
local FormexClient = require(script.Parent:WaitForChild("FormexClient"))
local Formex = FormexClient.Formex
local FormexUI = require(script.Parent:WaitForChild("FormexUI"))
local FormexDialogs = require(script.Parent:WaitForChild("FormexDialogs"))
local BlurController = FormexUI.BlurController

local screenGui: ScreenGui = FormexUI.ScreenGui

local footerContainer = FormexUI.Footer(screenGui)

local footerButtons = {} :: {[string]: ImageButton}

local function createButton(name: string, label: string?, icon: string, action: any)
    local button = FormexUI.CreateButton({
        Parent = footerContainer,
        Name = name,
        Text = label, 
        Icon = icon 
    }, action)
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
    PlotName = "Unclaimed",
    OwnerName = "Nobody",
    HomeName = "Unclaimed",
    ShowLoad = false,
    ShowClaim = false,
    ShowUnclaim = false,
    HasHome = false,
    IsHome = false,
    IsLoaded = false,
    IsOwner = false,
    IsManager = false,
    IsVIP = false,
    IsGuest = false,
    DesignMode = false
}

local refreshUI

createButton("CLAIM", "Claim", "85199762467908", function()
    if FormexClient.ClaimPlot() then
        FormexDialogs.PlotLoad()
    end
end)

createButton("UNCLAIM", "Unclaim", "137711830774408", function()
    FormexClient.ReleasePlot()
end)

createButton("LOAD", "Load Save", nil, function()
    FormexDialogs.PlotLoad()
end)

createButton("HOME", "Go Home", nil, function()
    print("Teleport Home")
end)

createButton("RENAME", "Rename", "74166756362476", function()
    FormexDialogs.PlotRename()
end)

createButton("PERMISSIONS", "Permissions", "83277863761797", function()
    FormexDialogs.PlotPermissions()
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
    if eventName ~= "MyPlotChanged" and eventName ~= "CurrentPlotChanged" then return end

    uiSettings.HasHome = FormexClient.MyPlotId ~= 0
    uiSettings.IsHome = uiSettings.HasHome and FormexClient.CurrentPlotId == FormexClient.MyPlotId

    local myPlot = FormexClient.MyPlot
    uiSettings.HomeName = myPlot.Name

    local plot = FormexClient.CurrentPlot
    uiSettings.IsLoaded = plot.SaveId and plot.SaveId ~= 0
    uiSettings.PlotName = plot.Name
    uiSettings.OwnerName = plot.OwnerName
    uiSettings.ShowClaim = plot.IsValid and not plot.IsClaimed
    uiSettings.ShowUnclaim = plot.IsMine
    uiSettings.IsOwner = plot.MyPermission == "Owner"
    uiSettings.IsManager = uiSettings.IsOwner or plot.MyPermission == "Manager"
    uiSettings.IsVIP = uiSettings.IsManager or plot.MyPermission == "VIP"
    uiSettings.IsGuest = uiSettings.IsVIP or plot.MyPermission == "Guest"
    uiSettings.DesignMode = uiSettings.IsLoaded and uiSettings.IsManager and uiSettings.DesignMode

    refreshUI()
end)

refreshUI = function()
    local buttons = {}

    buttons["CLAIM"] = uiSettings.ShowClaim
    buttons["UNCLAIM"] = not uiSettings.DesignMode and uiSettings.ShowUnclaim
    buttons["LOAD"] = uiSettings.IsHome
    buttons["HOME"] = not uiSettings.IsHome and uiSettings.HasHome
    buttons["RENAME"] = uiSettings.IsLoaded and not uiSettings.DesignMode and uiSettings.IsOwner
    buttons["PERMISSIONS"] = uiSettings.IsLoaded and not uiSettings.DesignMode and uiSettings.IsOwner
    buttons["DESIGN"] = uiSettings.IsLoaded and not uiSettings.DesignMode and uiSettings.IsManager
    buttons["EXIT_DESIGN"] = uiSettings.DesignMode
    buttons["DESIGN_FLOOR"] = uiSettings.DesignMode
    buttons["DESIGN_CEILING"] = uiSettings.DesignMode
    buttons["DESIGN_WALL"] = uiSettings.DesignMode
    buttons["DESIGN_FURNITURE"] = uiSettings.DesignMode

    updateFooter(buttons)

    BlurController.updateAll();
end

refreshUI()
