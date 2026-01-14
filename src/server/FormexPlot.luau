--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Formex = require(script.Parent:FindFirstChild("FormexServer"))
local FormexSystem = require(script.Parent:FindFirstChild("FormexSystem"))
local FormexBuild = require(script.Parent:FindFirstChild("FormexBuild"))

local FormexPlot = {}

function FormexPlot.ClaimPlot(player: Player, plotId: number?): (boolean, string)
    plotId = plotId or player:GetAttribute("CurrentPlotId")
    if not plotId then return false, "No plot specified" end
    return FormexSystem.AssignPlotToPlayer(player, plotId)
end

function FormexPlot.ReleasePlot(player: Player): boolean
    return FormexSystem.UnassignPlotToPlayer(player)
end

function FormexPlot.RenamePlot(player: Player, newName: string): boolean
    if not newName or newName == "" then return false, "Invalid name" end

    local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
    if not plotData then return false, "No current plot" end

    if permission ~= Formex.Permission.Owner then return false, "Permission denied" end
    if plotData.Name == newName then return false, "Name unchanged" end

    plotData.Name = newName
    FormexSystem.UpdatePlotAttributes(plotData.PlotId)
    FormexSystem.SavePlot(plotData.PlotId)

    return true
end

-- This method can throw errors because is always called via pcall
function FormexPlot.ListSaves(player: Player): {[number]: Formex.PlotSaveInfo}
    local userId = player.UserId
    local prefix = tostring(userId) .. ":"
    local keyPages = FormexSystem.PlotDataStore:ListKeysAsync(prefix, Formex.MaxSaveSlots, nil, true)
    local saves = {}

    local function addSaves(page)
        for _, keyInfo in ipairs(page:GetCurrentPage()) do
            local key = keyInfo.KeyName
            local saveId = tonumber(string.match(key, "^%d+:(%d+)$"))
            if not saveId then
                continue
            end

            local data = FormexSystem.PlotDataStore:GetAsync(key)
            if data then
                table.insert(saves, {
                    SaveId = data.SaveId or saveId,
                    Name = data.Name or ("Save " .. tostring(saveId)),
                    LastPlayed = data.LastPlayed or 0,
                })
            end
        end
    end

    addSaves(keyPages)
    while not keyPages.IsFinished do
        keyPages:AdvanceToNextPageAsync()
        addSaves(keyPages)
    end

    table.sort(saves, function(a, b)
        return (a.LastPlayed or 0) > (b.LastPlayed or 0)
    end)

    return saves
end

function FormexPlot.LoadSave(player: Player, saveId: number): boolean
    local userId = player.UserId
    return FormexSystem.LoadPlot(FormexSystem.PlayerToPlot[userId], saveId)
end

function FormexPlot.PlotLoad(player: Player, saveId: number?): (boolean, string?)
    local plotId = FormexSystem.PlayerToPlot[player.UserId]
    if not plotId or plotId == 0 then return false, "No claimed plot" end
    local plotData = FormexSystem.PlotData[plotId]
    if not plotData then return false, "Invalid plot" end
    local targetSaveId = saveId or plotData.SaveId
    if not targetSaveId or targetSaveId == 0 then return false, "No save loaded" end

    return FormexSystem.LoadPlot(plotId, targetSaveId)
end

function FormexPlot.NewSave(player: Player, startingSegment: number?): boolean
    local plotId = FormexSystem.PlayerToPlot[player.UserId]
    if not plotId or plotId == 0 then error("No claimed plot") end
    local plotData = FormexSystem.PlotData[plotId]
    if not plotData then error("Invalid plot") end
    local segmentIndex = tonumber(startingSegment)
    if segmentIndex ~= nil then
        if segmentIndex < 1 or segmentIndex > Formex.Segments.Count then return false, "Invalid starting segment." end
    end
    
    local saveId = Random.new():NextInteger(1000, 10000000)
    plotData.SaveId = saveId
    plotData.Name = player.Name .. "'s Plot"
    plotData.Permissions = plotData.Permissions or {}
    plotData.Permissions[player.UserId] = Formex.Permission.Owner
    plotData.LevelsUnlocked = 1
    plotData.SegmentsUnlocked = segmentIndex and Formex.Segments.Bit(segmentIndex) or Formex.DefaultSegmentsUnlocked
    plotData.Levels = {}
    plotData.NextId = 1

    FormexSystem.SavePlot(plotId)
    return plotData.SaveId
end

function FormexPlot.UnlockSegment(player: Player, segmentIndex: number): (boolean, string?)
    local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
    if not plotData then return false, "No current plot" end
    if plotData.SaveId == 0 then return false, "Load or create a save first." end
    if permission ~= Formex.Permission.Owner and permission ~= Formex.Permission.Manager then return false, "Permission denied" end
    local index = tonumber(segmentIndex)
    if not index or index < 1 or index > Formex.Segments.Count then return false, "Invalid segment" end
    local mask = plotData.SegmentsUnlocked or 0
    if Formex.Segments.IsUnlocked(mask, index) then return false, "Segment already unlocked" end
    mask = Formex.Segments.Unlock(mask, index)
    plotData.SegmentsUnlocked = mask

    FormexSystem.UpdatePlotAttributes(plotData.PlotId)
    FormexSystem.SavePlot(plotData.PlotId)

    return true, mask
end

function FormexPlot.SetPermission(player: Player, targetUserId: number, permission: Formex.Permission): boolean
    local plotData, playerPermission = FormexSystem.GetPlayerCurrentPlot(player)
    if not plotData then return false, "No current plot" end

    if playerPermission ~= Formex.Permission.Owner then error("Permission denied") end
    if not targetUserId or targetUserId <= 0 then return error("Invalid target") end
    if targetUserId == plotData.UserId then return error("Cannot change owner permission") end
    if not Formex.Permission[permission] then return error("Invalid permission") end

    plotData.Permissions = plotData.Permissions or {}
    if permission == Formex.Permission.Guest then
        plotData.Permissions[targetUserId] = nil
    else
        plotData.Permissions[targetUserId] = permission
    end

    FormexSystem.UpdatePlotAttributes(plotData.PlotId)
    FormexSystem.SavePlot(plotData.PlotId)

    return true
end

function FormexPlot.GetPermissions(player: Player): {[number]: Formex.Permission}
    local plotData = FormexSystem.GetPlayerCurrentPlot(player)
    if not plotData then return false, "No current plot" end

    return plotData.Permissions
end


Players.PlayerRemoving:Connect(function(player)
    local plotId = FormexSystem.PlayerToPlot[player.UserId]
    if plotId then
        FormexSystem.UnassignPlotToPlayer(player)
    end
end)

local accumulatedTime = 0
local proximityBorder = Formex.ProximityBorder
RunService.Heartbeat:Connect(function(deltaTime)
    accumulatedTime = accumulatedTime + deltaTime
    if accumulatedTime < 0.5 then return end
    accumulatedTime = 0

    -- Update CurrentPlotId for all players
    for _, player: Player in pairs(Players:GetPlayers()) do        
        if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
            continue
        end

        local currentPlotId = player:GetAttribute("CurrentPlotId") or 0
        local playerPosition = player.Character.HumanoidRootPart.Position

        local nextPlotId = currentPlotId
        if currentPlotId == 0 then
            -- Identify nearest plot
            for _, plotPart in pairs(FormexSystem.Plots) do
                local near = Formex.Plot.IsPointNear(plotPart.Position, playerPosition, proximityBorder)
                if not near then continue end

                nextPlotId = plotPart:GetAttribute("PlotId") or 0
                break
            end
        else
            -- Confirm still near current plot
            local plotPart = FormexSystem.Plots[currentPlotId]
            local near = plotPart and Formex.Plot.IsPointNear(plotPart.Position, playerPosition, proximityBorder * 1.1)
            if not near then
                nextPlotId = 0
            end
        end

        if nextPlotId ~= currentPlotId then
            FormexSystem.SetPlayerCurrentPlot(player, nextPlotId)
            FormexBuild.UpdatePlayerUndoRedoAttributes(player, nextPlotId)
        end
    end
end)

return FormexPlot
