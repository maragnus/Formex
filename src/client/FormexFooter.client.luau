if true then return end -- disable file

local Players = game:GetService("Players")
local FormexClient = require(script.Parent:WaitForChild("FormexClient"))
local Formex = FormexClient.Formex
local FormexUI = require(script.Parent:WaitForChild("FormexUI"))
local FormexPrompts = require(script.Parent:WaitForChild("FormexPrompts"))
local FormexDesign = require(script.Parent:WaitForChild("FormexDesign"))
local BlurController = FormexUI.BlurController

local screenGui: ScreenGui = FormexUI.ScreenGui

local function setHandlesBusy(active: boolean)
	if FormexDesign.Handles and FormexDesign.Handles.SetBusy then
		FormexDesign.Handles.SetBusy(active)
	end
end

local function buildWall(wallData: any, action: any): any
	setHandlesBusy(true)
	local results = FormexClient.BuildTransaction({
		{
			PartType = Formex.PartType.Wall,
			Action = action,
			Data = wallData,
		},
	}, nil)
	setHandlesBusy(false)
	if not results then return nil end
	local changeResult = results[1]
	return changeResult and changeResult.Result or nil
end

local footerContainer = FormexUI.Footer(screenGui)

local footerButtons = {} :: {[string]: ImageButton}
local floorMaterialButtonIds = {} :: {number}

local function createButton(name: string, label: string?, icon: string, action: any)
    local button = FormexUI.CreateButton({
        Parent = footerContainer,
        Name = name,
        Text = label,
        Icon = icon
    }, function()
        footerContainer.Active = false
        footerContainer.Interactable = false
        action()
        footerContainer.Interactable = true
        footerContainer.Active = true
    end)
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
    IsNew = false,
}

local refreshUI

local function canDesign(): boolean
    return uiSettings.IsLoaded and uiSettings.IsManager
end

local function setDesignMode(mode)
    if mode == FormexDesign.DesignMode.Play or canDesign() then
        FormexDesign.UpdateDesignState({ Mode = mode })
    end
end

local function isFloorMaterial(materialInfo: Formex.MaterialInfo): boolean
    local categories = materialInfo.Categories
    if not categories then return false end
    return table.find(categories, "Floor") ~= nil
end

createButton("Claim", "Claim", "85199762467908", function()
    if FormexClient.ClaimPlot() then
        FormexPrompts.PlotLoad()
    end
end)

createButton("Unclaim", "Unclaim", "137711830774408", function()
    FormexClient.ReleasePlot()
end)

createButton("Load", "Load Save", nil, function()
    FormexPrompts.PlotLoad()
end)

createButton("Home", "Go Home", nil, function()
    print("Teleport Home")
    FormexUI.Alert("Teleport", "You can't teleport because it hasn't been implemented yet. You should die.", FormexUI.ButtonType.Danger, FormexUI.AlertType.RetryCancel)
end)

createButton("Rename", "Rename", "74166756362476", function()
    FormexPrompts.PlotRename()
end)

createButton("Permissions", "Permissions", "83277863761797", function()
    FormexPrompts.PlotPermissions()
end)

createButton("Design", "Design", "78727585562674", function()
    setDesignMode(FormexDesign.DesignMode.Design)
end)

createButton("ExitDesign", "Exit Design", "78727585562674", function()
    setDesignMode(FormexDesign.DesignMode.Play)
end)

createButton("AddExpansions", "Expansions", "88488799504419", function()
    setDesignMode(FormexDesign.DesignMode.Expand)
end)

createButton("EditWalls", "Walls", "105416010695180", function()
    setDesignMode(FormexDesign.DesignMode.Wall)
end)

createButton("EditFloors", "Floors", "136537860205120", function()
    setDesignMode(FormexDesign.DesignMode.Floor)
end)

createButton("EditObjects", "Objects", "120639802680464", function()
    setDesignMode(FormexDesign.DesignMode.Object)
end)

createButton("Paint", "Paint", "92885878760720", function()
    FormexDesign.UpdateDesignState({ SubMode = FormexDesign.DesignSubMode.Paint })
end)

createButton("Back", "Back", nil, function()
    setDesignMode(FormexDesign.DesignMode.Design)
end)

createButton("Add", "Add", "88488799504419", function()
    local mode = FormexDesign.GetDesignState().Mode
    if mode == FormexDesign.DesignMode.Wall then
        FormexDesign.StartWall()
    elseif mode == FormexDesign.DesignMode.Floor then
        FormexDesign.StartFloor()
    end
end)

createButton("Delete", "Delete", nil, function()
    local mode = FormexDesign.GetDesignState().Mode
    if mode == FormexDesign.DesignMode.Floor then
        FormexDesign.UpdateDesignState({ Floor = { FloorMaterial = 0 } })
        return
    end

    local selectionType, partId, level = FormexDesign.GetSelectionInfo()
    if not partId or not level then return end
    if selectionType == FormexDesign.SelectionType.Wall then
        buildWall({
            WallId = partId,
            Level = level,
            Start = Vector2.new(0, 0),
            End = Vector2.new(0, 0),
            FrontMaterial = Formex.DefaultWallMaterial,
            BackMaterial = Formex.DefaultWallMaterial,
            Part = nil
        }, Formex.BuildAction.Delete)
        FormexDesign.ClearSelection()
    end
end)

createButton("Cancel", "Cancel", nil, function()
    FormexDesign.CancelAction()
end)

for materialId, materialInfo in ipairs(Formex.Materials) do
    if isFloorMaterial(materialInfo) then
        table.insert(floorMaterialButtonIds, materialId)
        createButton("FloorMaterial_" .. tostring(materialId), materialInfo.Name, nil, function()
            FormexDesign.UpdateDesignState({ Floor = { FloorMaterial = materialId } })
        end)
    end
end

-- Listen for client events
FormexClient.ClientEvents:Connect(function(eventName)
    if eventName ~= "MyPlotChanged" and eventName ~= "CurrentPlotChanged" and eventName ~= "DesignStateChanged" then return end

    uiSettings.HasHome = FormexClient.MyPlotId ~= 0
    uiSettings.IsHome = uiSettings.HasHome and FormexClient.CurrentPlotId == FormexClient.MyPlotId

    local myPlot = FormexClient.MyPlot
    uiSettings.HomeName = myPlot.Name

    local plot = FormexClient.CurrentPlot
    uiSettings.IsLoaded = plot.SaveId and plot.SaveId ~= 0
    uiSettings.IsNew = uiSettings.IsLoaded and Formex.Segments.CountUnlocked(plot.SegmentsUnlocked) == 0
    uiSettings.PlotName = plot.Name
    uiSettings.OwnerName = plot.OwnerName
    uiSettings.ShowClaim = plot.IsValid and not plot.IsClaimed
    uiSettings.ShowUnclaim = plot.IsMine
    uiSettings.IsOwner = plot.MyPermission == "Owner"
    uiSettings.IsManager = uiSettings.IsOwner or plot.MyPermission == "Manager"
    uiSettings.IsVIP = uiSettings.IsManager or plot.MyPermission == "VIP"
    uiSettings.IsGuest = uiSettings.IsVIP or plot.MyPermission == "Guest"

    refreshUI()
end)

refreshUI = function()
    local buttons = {}
    local designState = FormexDesign.GetDesignState()
    local designMode = designState.Mode
    local actionType = designState.ActionType
    local selectionType = designState.SelectionType

    local canEdit = uiSettings.IsLoaded and uiSettings.IsManager
    local inDesign = designMode ~= FormexDesign.DesignMode.Play
    if inDesign and not canEdit then
        FormexDesign.SetDesignMode(FormexDesign.DesignMode.Play)
        return
    end

    local inDesignMenu = designMode == FormexDesign.DesignMode.Design
    local inWallMode = designMode == FormexDesign.DesignMode.Wall
    local inFloorMode = designMode == FormexDesign.DesignMode.Floor
    local inObjectMode = designMode == FormexDesign.DesignMode.Object
    local inExpandMode = designMode == FormexDesign.DesignMode.Expand
    local inPaintMode = designState.SubMode == FormexDesign.DesignSubMode.Paint
    local isSelectAction = actionType == FormexDesign.ActionType.Select

    buttons["Claim"] = uiSettings.ShowClaim
    buttons["Unclaim"] = not inDesign and uiSettings.ShowUnclaim
    buttons["Load"] = uiSettings.IsHome and not inDesign
    buttons["Home"] = not uiSettings.IsHome and uiSettings.HasHome
    buttons["Rename"] = uiSettings.IsLoaded and not inDesign and uiSettings.IsOwner
    buttons["Permissions"] = uiSettings.IsLoaded and not inDesign and uiSettings.IsOwner
    buttons["Design"] = uiSettings.IsLoaded and uiSettings.IsManager and not inDesign

    if inDesignMenu then
        buttons["ExitDesign"] = true
        buttons["AddExpansions"] = true
        buttons["EditWalls"] = not uiSettings.IsNew
        buttons["EditFloors"] = not uiSettings.IsNew
        buttons["EditObjects"] = not uiSettings.IsNew
        buttons["Paint"] = not uiSettings.IsNew
    elseif inWallMode then
        if isSelectAction then
            buttons["Back"] = true
            buttons["Add"] = true
            buttons["Delete"] = selectionType ~= FormexDesign.SelectionType.None
        else
            buttons["Cancel"] = true
        end
    elseif inFloorMode then
        buttons["Back"] = true
        buttons["Delete"] = true
        for _, materialId in ipairs(floorMaterialButtonIds) do
            buttons["FloorMaterial_" .. tostring(materialId)] = true
        end
    elseif inObjectMode then
        if isSelectAction then
            buttons["Back"] = true
            buttons["Add"] = true
            buttons["Delete"] = selectionType ~= FormexDesign.SelectionType.None
        else
            buttons["Cancel"] = true
        end
    elseif inExpandMode or inPaintMode then
        buttons["Back"] = true
    end

    updateFooter(buttons)

    BlurController.updateAll();
end

refreshUI()
