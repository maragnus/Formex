local Players = game:GetService("Players")
local FormexClient = require(script.Parent:WaitForChild("FormexClient"))
local Formex = FormexClient.Formex
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
    local button = FormexUI.CreateButton({
        Parent = footerFrame,
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

local function getUserInfo(userId: number): (string, string)
    local player = Players:GetPlayerByUserId(userId)
    local playerName = player and player.Name
    if not player then
        local _, resolvedName = pcall(function()
            return Players:GetNameFromUserIdAsync(userId)
        end)
        playerName = resolvedName or ("User " .. tostring(userId))
    end

    local _, playerAvatar = pcall(function()
        return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size60x60)
    end)

    return playerName, playerAvatar or "rbxassetid://0"
end


createButton("CLAIM", "Claim", "85199762467908", function()
    FormexClient.ClaimPlot()
end)

createButton("UNCLAIM", "Unclaim", "137711830774408", function()
    FormexClient.ReleasePlot()
end)

createButton("HOME", "Go Home", nil, function()
    print("Teleport Home")
end)

createButton("RENAME", "Change Name", "74166756362476", function()
    local newName = FormexUI.Dialog("RenamePlot", "Rename your plot", {}, function(dialog)
        FormexUI.CreateTextInput({
            Parent = dialog.ContentFrame,
            Label = "Plot name",
            Text = FormexClient.CurrentPlot.Name
         }, function(value) dialog.Result = value end)
    end)
    if newName then
        FormexClient.RenamePlot(newName)
    end
end)

createButton("PERMISSIONS", "Permissions", "83277863761797", function()
    if not FormexClient.CurrentPlot then return end
    local currentPlot = FormexClient.CurrentPlot

    local roleOptions = {
        { Name = "Manager", Type = "Primary" },
        { Name = "VIP", Type = "Info" },
        { Name = "Guest", Type = "Secondary" },
        { Name = "Banned", Type = "Danger" },
    }

    local function buildEntries()
        local permissions = FormexClient.GetSavePermissions()

        local entries = {}
        local seen = {}

        for userId, permission in permissions do
            local name, avatar = getUserInfo(userId)
            table.insert(entries, {
                UserId = userId,
                Name = name,
                Avatar = avatar,
                Permission = permission,
                InPermissions = true,
            })
            seen[userId] = true
        end

        for _, player in Players:GetPlayers() do
            if seen[player.UserId] then continue end
            local name, avatar = getUserInfo(player.UserId)
            table.insert(entries, {
                UserId = player.UserId,
                Name = name,
                Avatar = avatar,
                Permission = Formex.Permissions.Guest,
                InPermissions = false,
            })
        end

        table.sort(entries, function(a, b)
            if a.InPermissions ~= b.InPermissions then
                return a.InPermissions
            end
            return string.lower(a.Name) < string.lower(b.Name)
        end)

        return entries
    end

    local function choosePermission(entry, onChanged)
        local chosen = FormexUI.Dialog("Permission_" .. entry.UserId, "Set permission for " .. entry.Name, {
            Size = "Medium",
            Buttons = {
                { Label = "Cancel", Result = false, Options = { Type = "Secondary", Style = "Outline" } }
            }
        }, function(dialog)
            local roleList = Instance.new("Frame", dialog.ContentFrame)
            roleList.Name = "Roles"
            roleList.BackgroundTransparency = 1
            roleList.Size = UDim2.new(1, 0, 0, 0)
            roleList.AutomaticSize = Enum.AutomaticSize.Y
            local layout = Instance.new("UIListLayout", roleList)
            layout.FillDirection = Enum.FillDirection.Vertical
            layout.SortOrder = Enum.SortOrder.LayoutOrder
            layout.Padding = UDim.new(0, 8)

            for _, role in ipairs(roleOptions) do
                local button = FormexUI.CreateButton({
                    Parent = roleList,
                    Name = "Role_" .. role.Name,
                    Text = role.Name,
                    Type = role.Type,
                    Style = "Solid",
                }, function()
                    local success, message = FormexClient.SetSavePermission(entry.UserId, role.Name)
                    if not success then
                        warn("Failed to set permission:", message)
                        return
                    end
                    dialog.Close(role.Name)
                end)
                button.Visible = true
            end
        end)

        if chosen and onChanged then
            onChanged(chosen)
        end
    end

    FormexUI.Dialog("PlotPermissions", "Plot Permissions", {
        Size = "Large",
        Buttons = {
            { Label = "Close", Result = false, Options = { Type = "Secondary" } }
        }
    }, function(dialog)
        local refresh

        local header = FormexUI.CreateRow({
            Parent = dialog.ContentFrame,
            Name = "Header",
            FillDirection = Enum.FillDirection.Horizontal,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Gap = 8,
            HorizontalAlignment = Enum.HorizontalAlignment.Left,
            VerticalAlignment = Enum.VerticalAlignment.Top,
            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.new(1, 0, 0, 0),
        })

        local hint = FormexUI.CreateLabel({
            Parent = header,
            Text = "Select a player to update their role.",
            TextXAlignment = Enum.TextXAlignment.Left,
            FlexMode = Enum.UIFlexMode.Grow,
            AutomaticSize = Enum.AutomaticSize.Y
        })

        local refreshButton = FormexUI.CreateButton({
            Parent = header, 
            Name = "Refresh",
            Icon = "123101975679190",
            Type = "Secondary",
            Style = "Outline",
        }, function() refresh() end)
        refreshButton.Visible = true

        local listFrame = FormexUI.CreateColumn({
            Parent = dialog.ContentFrame,
            Name = "UserList",
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Gap = 8
        })

        local function refreshPermissions()
            for _, child in listFrame:GetChildren() do
                if child:IsA("GuiObject") then
                    child:Destroy()
                end
            end

            local entries = buildEntries()
            for _, entry in entries do
                local row = Instance.new("Frame", listFrame)
                row.Name = "User_" .. tostring(entry.UserId)
                row.BackgroundColor3 = Color3.fromRGB(245, 248, 255)
                row.BackgroundTransparency = 0
                row.BorderSizePixel = 0
                row.Size = UDim2.new(1, -8, 0, 74)
                local rowCorner = Instance.new("UICorner", row)
                rowCorner.CornerRadius = UDim.new(0, 12)
                local rowStroke = Instance.new("UIStroke", row)
                rowStroke.Color = Color3.fromRGB(210, 216, 235)
                rowStroke.Thickness = 1.6
                local rowPadding = Instance.new("UIPadding", row)
                rowPadding.PaddingTop = UDim.new(0, 10)
                rowPadding.PaddingBottom = UDim.new(0, 10)
                rowPadding.PaddingLeft = UDim.new(0, 12)
                rowPadding.PaddingRight = UDim.new(0, 12)

                local rowLayout = Instance.new("UIListLayout", row)
                rowLayout.FillDirection = Enum.FillDirection.Horizontal
                rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
                rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
                rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
                rowLayout.Padding = UDim.new(0, 12)

                local avatar = Instance.new("ImageLabel", row)
                avatar.Name = "Avatar"
                avatar.BackgroundTransparency = 1
                avatar.Size = UDim2.new(0, 48, 0, 48)
                avatar.Image = entry.Avatar
                avatar.ScaleType = Enum.ScaleType.Fit

                local infoFrame = Instance.new("Frame", row)
                infoFrame.Name = "Info"
                infoFrame.BackgroundTransparency = 1
                infoFrame.Size = UDim2.new(1, -220, 1, 0)
                local infoLayout = Instance.new("UIListLayout", infoFrame)
                infoLayout.FillDirection = Enum.FillDirection.Vertical
                infoLayout.SortOrder = Enum.SortOrder.LayoutOrder
                infoLayout.Padding = UDim.new(0, 6)

                local nameLabel = Instance.new("TextLabel", infoFrame)
                nameLabel.Name = "Name"
                nameLabel.BackgroundTransparency = 1
                nameLabel.Size = UDim2.new(1, 0, 0, 22)
                nameLabel.Font = Enum.Font.GothamSemibold
                nameLabel.Text = entry.Name
                nameLabel.TextXAlignment = Enum.TextXAlignment.Left
                nameLabel.TextSize = 18
                nameLabel.TextColor3 = Color3.fromRGB(40, 45, 70)

                local permissionLabel = Instance.new("TextLabel", infoFrame)
                permissionLabel.Name = "Permission"
                permissionLabel.BackgroundTransparency = 1
                permissionLabel.Size = UDim2.new(1, 0, 0, 18)
                permissionLabel.Font = Enum.Font.Gotham
                permissionLabel.Text = entry.Permission
                permissionLabel.TextXAlignment = Enum.TextXAlignment.Left
                permissionLabel.TextSize = 14
                permissionLabel.TextColor3 = Color3.fromRGB(90, 105, 140)

                local actionButton = FormexUI.CreateButton({
                    Parent = row, 
                    Name = "Change_" .. tostring(entry.UserId), 
                    Text = "Change", 
                    Type = "Primary", 
                    Style = "Outline"
                }, function()
                    choosePermission(entry, function() refresh() end)
                end)
                actionButton.Visible = entry.Permission ~= "Owner"
                actionButton.LayoutOrder = 3
                actionButton.Size = UDim2.new(0, 132, 0, 40)
            end
        end

        refresh = refreshPermissions
        refreshPermissions()
    end)
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
