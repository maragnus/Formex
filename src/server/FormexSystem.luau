--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")

local FormexFolder = ReplicatedStorage:WaitForChild("Formex")
local Formex = require(FormexFolder:WaitForChild("Formex"))

local FormexSystem = {}

FormexSystem.Formex = Formex

FormexSystem.Plots = {} :: { [number]: BasePart } -- [plotId]: BasePart
FormexSystem.PlotData = {} :: { [number]: Formex.PlotData } -- [plotId]: Formex.PlotData
FormexSystem.PlayerToPlot = {} :: {[number]: number} -- [userId]: plotId
FormexSystem.PlotToPlayer = {} :: {[number]: number} -- [plotId]: userId

FormexSystem.PlotDataStore = DataStoreService:GetDataStore("FormexPlotData")

function FormexSystem.GetPlayerCurrentPlot(player: Player) : (Formex.PlotData?, Formex.Permission)
    local plotId = player:GetAttribute("CurrentPlotId") or 0
    if not plotId or plotId == 0 then
        return nil, nil
    end

    local plotData = FormexSystem.PlotData[plotId]
    return plotData, plotData.Permissions[player.UserId] or Formex.Permissions.Guest
end

function FormexSystem.UpdatePlotAttributes(plotId: number)
    local plotPart = FormexSystem.Plots[plotId]
    local plotData = FormexSystem.PlotData[plotId]
    if not plotPart or not plotData then return end

    local userId = plotData.UserId
    local ownerPlayer = userId and userId ~= 0 and Players:GetPlayerByUserId(userId)
    local ownerName = userId and ownerPlayer and ownerPlayer.Name or ""
    local plotName = plotData.Name or (ownerPlayer and ownerName .. "'s Plot") or "Unclaimed Plot"
    local permissions = plotData.Permissions or {}

    if userId and userId ~= 0 then
        permissions[userId] = "Owner"
    end
    plotData.Permissions = permissions

    plotPart:SetAttribute("OwnerUserId", plotData.UserId or 0)
    plotPart:SetAttribute("OwnerName", ownerName)
    plotPart:SetAttribute("PlotName", plotName)
    plotPart:SetAttribute("SaveId", plotData.SaveId or 0)
    plotPart:SetAttribute("LastPlayed", plotData.LastPlayed or 0)
    plotPart:SetAttribute("LevelsUnlocked", plotData.LevelsUnlocked or 1)
    plotPart:SetAttribute("SegmentsUnlocked", plotData.SegmentsUnlocked or 0)

    -- Update permission attributes
    for permissionUserId, permission in permissions do
        plotPart:SetAttribute("U_" .. tostring(permissionUserId), permission)
    end

    -- Remove outdated permission attributes
    for key, value in plotPart:GetAttributes() do
        if string.sub(key, 1, 2) == "U_" then            
            local pid = tonumber(string.sub(key, 3))
            if pid and not permissions[pid] then
                plotPart:SetAttribute(key, nil)
            end
        end
    end
end

function FormexSystem.ClearPlot(plotPart: BasePart)
    plotPart:ClearAllChildren()
end

function FormexSystem.UnassignPlotToPlayer(player: Player)
    local userId = player.UserId
    local plotId = FormexSystem.PlayerToPlot[userId] or 0
    if plotId == 0 then return end

    print(player.Name .. " unclaims plot " .. tostring(plotId))

    FormexSystem.SavePlot(plotId)

    FormexSystem.ClearPlot(FormexSystem.Plots[plotId])

    FormexSystem.PlotToPlayer[plotId] = nil
    FormexSystem.PlayerToPlot[userId] = nil
    player:SetAttribute("MyPlotId", 0)

    local plotData = FormexSystem.PlotData[plotId]
    plotData.UserId = 0
    plotData.SaveId = 0
    plotData.Name = "Unclaimed Plot"
    plotData.LastPlayed = 0
    plotData.Levels = {}
    plotData.LevelsUnlocked = 0
    plotData.SegmentsUnlocked = 0
    plotData.Permissions = {}
    FormexSystem.UpdatePlotAttributes(plotId)

    return true
end

function FormexSystem.AssignPlotToPlayer(player: Player, plotId: number)
    if FormexSystem.PlotToPlayer[plotId] then
        return false, "Plot already claimed"
    end

    FormexSystem.UnassignPlotToPlayer(player)

    plotId = plotId or 0
    if plotId == 0 then return end

    print(player.Name .. " claims plot " .. tostring(plotId))

    local userId = player.UserId
    local plotName = player.Name .. "'s Plot"

    FormexSystem.PlayerToPlot[userId] = plotId
    FormexSystem.PlotToPlayer[plotId] = userId
    player:SetAttribute("MyPlotId", plotId)

    local plotData = FormexSystem.PlotData[plotId]
    plotData.UserId = player.UserId
    plotData.SaveId = 0
    plotData.Name = plotName
    plotData.LastPlayed = 0
    plotData.Levels = {}
    plotData.LevelsUnlocked = 1
    plotData.SegmentsUnlocked = 0
    plotData.Permissions = {}
    FormexSystem.UpdatePlotAttributes(plotId)
    
    return true
end

function FormexSystem.SetPlayerCurrentPlot(player, plotId)
    plotId = plotId or 0
    player:SetAttribute("CurrentPlotId", plotId)
end

function FormexSystem.RegisterPlot(plotPart: Part)
    local plotId = #FormexSystem.Plots + 1
    FormexSystem.Plots[plotId] = plotPart

    CollectionService:AddTag(plotPart, "FormexPlot")

    plotPart.Name = "Plot" .. tostring(plotId)
    plotPart:SetAttribute("PlotId", plotId)

    FormexSystem.PlotData[plotId] = {
        PlotId = plotId,
        UserId = 0,
        SaveId = 0,
        Name = "Unclaimed Plot",
        LastPlayed = 0,
        Levels = {},
        LevelsUnlocked = 0,
        SegmentsUnlocked = 0,
        Permissions = {},
    }
    FormexSystem.UpdatePlotAttributes(plotId)

    print("Registering plot with PlotId:", plotId)
end

local saveQueue = {} :: {[number]: number}

function FormexSystem.QueueSave(plotId: number)
    if not saveQueue[plotId] then
        saveQueue[plotId] = time()
    end
end

function FormexSystem.SavePlot(plotId: number)
    local plotData = FormexSystem.PlotData[plotId]
    if not plotData or plotData.SaveId == 0 then return end

    local userId = FormexSystem.PlotToPlayer[plotId] or plotData.UserId
    if not userId or userId == 0 then return end

    plotData.LastPlayed = os.time()
    plotData.LevelsUnlocked = math.max(plotData.LevelsUnlocked or 1, 1)
    local segmentsMask = plotData.SegmentsUnlocked
    if segmentsMask == nil then
        segmentsMask = Formex.Segments.Bit(Formex.Segments.DefaultIndex)
    end
    plotData.SegmentsUnlocked = segmentsMask

    local key = tostring(userId) .. ":" .. tostring(plotData.SaveId)
    local success, err = pcall(function()        
        FormexSystem.PlotDataStore:SetAsync(key, {
            PlotId = plotId,
            UserId = userId,
            SaveId = plotData.SaveId,
            Name = plotData.Name,
            LastPlayed = plotData.LastPlayed,
            Levels = plotData.Levels,
            LevelsUnlocked = plotData.LevelsUnlocked or 1,
            SegmentsUnlocked = plotData.SegmentsUnlocked or 0,
            Permissions = plotData.Permissions,
        })
    end)

    if not success then
        warn("FormexServer.SavePlot failed for PlotId", plotId, ":", err)
        return false, err
    end

    saveQueue[plotId] = nil
    FormexSystem.UpdatePlotAttributes(plotId)

    return true
end

-- Ensure defaults when players join
Players.PlayerAdded:Connect(function(player)
    if player:GetAttribute("MyPlotId") == nil then
        player:SetAttribute("MyPlotId", 0)
    end
    if player:GetAttribute("CurrentPlotId") == nil then
        player:SetAttribute("CurrentPlotId", 0)
    end
end)

-- TODO every minute try and save all plots in saveQueue

return FormexSystem