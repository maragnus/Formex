--!strict

local Players = game:GetService("Players")
local FormexClient = require(script.Parent:WaitForChild("FormexClient"))
local Formex = FormexClient.Formex
local FormexUI = require(script.Parent:WaitForChild("FormexUI"))

local FormexPrompts = {}

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

function FormexPrompts.PlotLoad()
    local saves = FormexClient.GetSaves() or {}
    local currentSaveId = FormexClient.CurrentPlot.SaveId or 0
    local rng = Random.new()

    table.sort(saves, function(a, b)
        return (a.LastPlayed or 0) > (b.LastPlayed or 0)
    end)

    local function formatTimestamp(timestamp: number?): string
        if not timestamp or timestamp == 0 then return "Never played" end
        return "Last played " .. os.date("%x %X", timestamp)
    end

    local newSaveButton: GuiButton? = nil

    local function updateNewSaveVisibility()
        if newSaveButton then
            newSaveButton.Visible = #saves < Formex.MaxSaveSlots
        end
    end

    local function removeSaveFromList(saveId: number)
        for index, entry in ipairs(saves) do
            if entry.SaveId == saveId then
                table.remove(saves, index)
                break
            end
        end
        updateNewSaveVisibility()
    end

    local function confirmDelete(save)
        local saveName = save.Name ~= nil and tostring(save.Name) or ("Save " .. tostring(save.SaveId))
        local proceed = FormexUI.Alert(
            "Delete plot",
            "Are you sure you want to delete \"" .. saveName .. "\"?",
            FormexUI.ButtonType.Danger,
            FormexUI.AlertType.YesNo
        )
        if proceed ~= true then
            return false
        end

        local targetNumber = rng:NextInteger(1, 9)
        local numbers = { targetNumber }
        while #numbers < 4 do
            local candidate = rng:NextInteger(1, 9)
            local unique = true
            for _, value in ipairs(numbers) do
                if value == candidate then
                    unique = false
                    break
                end
            end
            if unique then
                table.insert(numbers, candidate)
            end
        end

        for index = #numbers, 2, -1 do
            local swapIndex = rng:NextInteger(1, index)
            numbers[index], numbers[swapIndex] = numbers[swapIndex], numbers[index]
        end

        local confirmation = FormexUI.Dialog({
            Name = "DeletePlotConfirm" .. tostring(save.SaveId),
            Title = "Double check",
            Size = "Small",
            Buttons = {
                { Text = "Cancel", Result = false, Type = FormexUI.ButtonType.Secondary, Style = FormexUI.ButtonStyle.Outline }
            }
        }, function(dialog)
            FormexUI.CreateLabel({
                Parent = dialog.ContentFrame,
                Text = string.format("Click %d to delete \"%s\". This cannot be undone.", targetNumber, saveName),
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Top,
                TextWrapped = true,
                AutomaticSize = Enum.AutomaticSize.Y,
                Size = UDim2.new(1, 0, 0, 0),
            })

            local numberRow = FormexUI.CreateRow({
                Parent = dialog.ContentFrame,
                Name = "ConfirmNumbers",
                AutomaticSize = Enum.AutomaticSize.Y,
                Size = UDim2.new(1, 0, 0, 0),
                Gap = 8,
                HorizontalAlignment = Enum.HorizontalAlignment.Left,
                VerticalAlignment = Enum.VerticalAlignment.Top,
            })

            for _, value in ipairs(numbers) do
                local button = FormexUI.CreateButton({
                    Parent = numberRow,
                    Name = "Number_" .. tostring(value),
                    Text = tostring(value),
                    Type = value == targetNumber and FormexUI.ButtonType.Danger or FormexUI.ButtonType.Secondary,
                    Style = "Solid",
                    Size = UDim2.new(0, 64, 0, 44),
                }, function()
                    dialog.Close(value == targetNumber)
                end)
                button.Visible = true
            end
        end)

        return confirmation == true
    end

    FormexUI.Dialog({
        Name = "LoadSaveDialog",
        Title = "Load a save",
        Size = "Medium",
        CanClose = true,
        AutoSize = true,
    }, function(dialog)
        local list = FormexUI.CreateColumn({
            Parent = dialog.ContentFrame,
            Name = "Saves",
            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.new(1, 0, 0, 0),
            Gap = 10,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
        })

        if #saves == 0 then
            FormexUI.CreateLabel({
                Parent = list,
                Text = "No saves yet. Create a new save slot to start building.",
                TextXAlignment = Enum.TextXAlignment.Center,
                Size = UDim2.new(1, -12, 0, 48),
                TextSize = 16,
                TextColor3 = Color3.fromRGB(70, 80, 110)
            })
        end

        for _, save in ipairs(saves) do
            local isCurrentSave = currentSaveId ~= 0 and save.SaveId == currentSaveId

            local row = Instance.new("Frame", list)
            row.Name = "Save_" .. tostring(save.SaveId or "Unknown")
            row.BackgroundColor3 = Color3.fromRGB(245, 248, 255)
            row.BackgroundTransparency = 0
            row.Size = UDim2.new(1, -6, 0, 76)
            local corner = Instance.new("UICorner", row)
            corner.CornerRadius = UDim.new(0, 12)
            local padding = Instance.new("UIPadding", row)
            padding.PaddingTop = UDim.new(0, 10)
            padding.PaddingBottom = UDim.new(0, 10)
            padding.PaddingLeft = UDim.new(0, 12)
            padding.PaddingRight = UDim.new(0, 12)
            local layout = Instance.new("UIListLayout", row)
            layout.FillDirection = Enum.FillDirection.Horizontal
            layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
            layout.VerticalAlignment = Enum.VerticalAlignment.Center
            layout.SortOrder = Enum.SortOrder.LayoutOrder
            layout.Padding = UDim.new(0, 12)

            local info = Instance.new("Frame", row)
            info.Name = "Info"
            info.BackgroundTransparency = 1
            info.Size = UDim2.new(1, -220, 1, 0)
            local infoLayout = Instance.new("UIListLayout", info)
            infoLayout.FillDirection = Enum.FillDirection.Vertical
            infoLayout.SortOrder = Enum.SortOrder.LayoutOrder
            infoLayout.Padding = UDim.new(0, 6)

            local nameLabel = Instance.new("TextLabel", info)
            nameLabel.Name = "Name"
            nameLabel.BackgroundTransparency = 1
            nameLabel.Size = UDim2.new(1, 0, 0, 24)
            nameLabel.Font = Enum.Font.GothamSemibold
            nameLabel.Text = save.Name ~= nil and tostring(save.Name) or ("Save " .. tostring(save.SaveId))
            nameLabel.TextSize = 18
            nameLabel.TextXAlignment = Enum.TextXAlignment.Left
            nameLabel.TextColor3 = Color3.fromRGB(45, 50, 80)

            local detailsLabel = Instance.new("TextLabel", info)
            detailsLabel.Name = "Details"
            detailsLabel.BackgroundTransparency = 1
            detailsLabel.Size = UDim2.new(1, 0, 0, 18)
            detailsLabel.Font = Enum.Font.Gotham
            detailsLabel.Text = formatTimestamp(save.LastPlayed)
            detailsLabel.TextSize = 14
            detailsLabel.TextXAlignment = Enum.TextXAlignment.Left
            detailsLabel.TextColor3 = Color3.fromRGB(90, 105, 140)

            local actions = Instance.new("Frame", row)
            actions.Name = "Actions"
            actions.BackgroundTransparency = 1
            actions.Size = UDim2.new(0, 200, 1, 0)
            actions.LayoutOrder = 3
            local actionsLayout = Instance.new("UIListLayout", actions)
            actionsLayout.FillDirection = Enum.FillDirection.Horizontal
            actionsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
            actionsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
            actionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
            actionsLayout.Padding = UDim.new(0, 8)

            if isCurrentSave then
                local refreshButton = FormexUI.CreateButton({
                    Parent = actions,
                    Name = "Refresh_" .. tostring(save.SaveId),
                    Icon = Formex.Icons.Refresh,
                    Text = "Refresh",
                    Type = "Primary",
                    Style = "Solid",
                    Size = UDim2.new(0, 108, 0, 44),
                }, function()
                    local success, message = FormexClient.PlotLoad(save.SaveId)
                    if success == false then
                        warn("Failed to refresh save:", message)
                        return
                    end
                    dialog.Close(save.SaveId)
                end)
                refreshButton.Visible = true
            else
                local loadButton = FormexUI.CreateButton({
                    Parent = actions,
                    Name = "Load_" .. tostring(save.SaveId),
                    Icon = Formex.Icons.PlotLoad,
                    Type = "Primary",
                    Style = "Solid",
                    Size = UDim2.new(0, 44, 0, 44),
                }, function()
                    local success, message = FormexClient.PlotLoad(save.SaveId)
                    if success == false then
                        warn("Failed to load save:", message)
                        return
                    end
                    dialog.Close(save.SaveId)
                end)
                loadButton.Visible = true
                loadButton.LayoutOrder = 1

                local deleteButton = FormexUI.CreateButton({
                    Parent = actions,
                    Name = "Delete_" .. tostring(save.SaveId),
                    Icon = Formex.Icons.DeleteItem,
                    Type = "Danger",
                    Style = FormexUI.ButtonStyle.Outline,
                    Size = UDim2.new(0, 44, 0, 44),
                }, function()
                    local confirmed = confirmDelete(save)
                    if not confirmed then
                        return
                    end

                    local success, message = FormexClient.DeletePlot(save.SaveId)
                    if success == false then
                        FormexUI.Alert(
                            "Delete failed",
                            message or "Could not delete this plot. Please try again.",
                            FormexUI.ButtonType.Warn,
                            FormexUI.AlertType.OkOnly
                        )
                        return
                    end

                    removeSaveFromList(save.SaveId)
                    row:Destroy()
                end)
                deleteButton.Visible = true
                deleteButton.LayoutOrder = 2
            end
        end

        newSaveButton = FormexUI.CreateButton({
            Parent = dialog.ContentFrame,
            Name = "NewSave",
            Text = "Create new save",
            Type = "Success",
            Style = "Solid"
        }, function()
            local saveId, message = FormexClient.NewSave()
            if saveId == false then
                warn("Failed to create save:", message)
                return
            end
            dialog.Close(saveId or true)
        end)
        newSaveButton.Visible = #saves < Formex.MaxSaveSlots
        newSaveButton.Size = UDim2.new(1, -6, 0, 44)
    end)
end

function FormexPrompts.PlotRename()
    local newName = FormexUI.Dialog({
        Name = "RenamePlotDialog",
        Title = "Rename your plot",
        Buttons = {
            { Text = "OK", Result = nil, Type = FormexUI.ButtonType.Primary },
            { Text = "Cancel", Result = false, Type = FormexUI.ButtonType.Secondary, Style = FormexUI.ButtonStyle.Outline }
        }
    }, function(dialog)
        FormexUI.CreateTextInput({
            Parent = dialog.ContentFrame,
            Label = "Plot name",
            Text = FormexClient.CurrentPlot.Name
         }, function(value) dialog.Result = value end)
    end)
    if newName then
        FormexClient.RenamePlot(newName)
    end
end

function FormexPrompts.PlotPermissions()
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
                Permission = Formex.Permission.Guest,
                InPermissions = false,
            })
        end

        table.sort(entries, function(a, b)
            if a.InPermissions ~= b.InPermissions then return a.InPermissions end
            return string.lower(a.Name) < string.lower(b.Name)
        end)

        return entries
    end

    local function choosePermission(entry, onChanged)
        local chosen = FormexUI.Dialog({
            Name = "Permission" .. entry.UserId .. "Dialog",
            Title = "Set permission for " .. entry.Name,
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

    FormexUI.Dialog({
        Name = "PlotPermissionsDialog",
        Title = "Plot Permissions",
        Size = "Large",
        Scrolling = Enum.ScrollingDirection.Y,
        Buttons = {
            { Text = "Done", Type = FormexUI.ButtonType.Primary },
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
end

return FormexPrompts
