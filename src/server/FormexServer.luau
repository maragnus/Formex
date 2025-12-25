--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local FormexFolder = ReplicatedStorage:WaitForChild("Formex")
local Formex = require(FormexFolder:WaitForChild("Formex"))
local FormexBuild = require(script.Parent:WaitForChild("FormexBuild"))

local plotDataStore = DataStoreService:GetDataStore("FormexPlotData")

local FormexFunctions: RemoteFunction = Instance.new("RemoteFunction")
FormexFunctions.Name = "FormexFunctions"
FormexFunctions.Parent = FormexFolder

local FormexEvents: RemoteEvent = Instance.new("RemoteEvent")
FormexEvents.Name = "FormexEvents"
FormexEvents.Parent = FormexFolder

local module = {}
module.Formex = Formex

local plots: { [number]: BasePart } = {}
local activePlotData: { [number]: Formex.PlotData } = {}
local playerToPlot: {[number]: number} = {}
local plotToPlayer: {[number]: number} = {}

module.Plots = plots -- [plotId]: BasePart
module.PlotData = activePlotData -- [plotId]: Formex.PlotData
module.PlayerToPlot = playerToPlot -- [userId]: plotId
module.PlotToPlayer = plotToPlayer -- [plotId]: userId
module.Functions = FormexFunctions
module.Events = FormexEvents

local function deepClone(original)
    local clone = table.clone(original)
    for key, value in original do
        if type(value) == "table" then
            clone[key] = deepClone(value)
        end
    end
    return clone
end

local function updatePlotAttributes(plotId: number)
    local plotPart = module.Plots[plotId]
    local plotData = module.PlotData[plotId]
    local userId = plotData.UserId
    local ownerPlayer = userId and Players:GetPlayerByUserId(userId)
    local ownerName = userId and ownerPlayer and ownerPlayer.Name or ""
    local plotName = plotData.Name or (ownerPlayer and ownerName .. "'s Plot") or "Unclaimed Plot"
    local permissions = plotData.Permissions or {}

    plotPart:SetAttribute("OwnerUserId", plotData.UserId or 0)
    plotPart:SetAttribute("OwnerName", ownerName)
    plotPart:SetAttribute("PlotName", plotName)

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

function module.UnassignPlotToPlayer(player: Player)
    local userId = player.UserId
    local plotId = module.PlayerToPlot[userId] or 0
    if plotId == 0 then return end

    module.SavePlot(plotId)

    FormexBuild.ClearPlot(module.Plots[plotId])

    module.PlotToPlayer[plotId] = nil
    module.PlayerToPlot[userId] = nil
    player:SetAttribute("MyPlotId", 0)

    updatePlotAttributes(plotId)

    local plotData = module.PlotData[plotId]
    plotData.UserId = 0
    plotData.SaveId = 0
    plotData.Name = "Unclaimed Plot"
    plotData.LastPlayed = 0
    plotData.Levels = {}
    plotData.Permissions = {}

    return true
end

function module.AssignPlotToPlayer(player: Player, plotId: number)
    if module.PlotToPlayer[plotId] then
        return false, "Plot already claimed"
    end

    module.UnassignPlotToPlayer(player)

    plotId = plotId or 0
    if plotId == 0 then return end

    local userId = player.UserId
    local plotName = player.Name .. "'s Plot"

    module.PlayerToPlot[userId] = plotId
    module.PlotToPlayer[plotId] = userId
    player:SetAttribute("MyPlotId", plotId)

    updatePlotAttributes(plotId)

    local plotData = module.PlotData[plotId]
    plotData.UserId = player
    plotData.SaveId = 0
    plotData.Name = plotName
    plotData.LastPlayed = 0
    plotData.Levels = {}
    plotData.Permissions = {}
    
    return true
end

local function setPlayerCurrentPlot(player, plotId)
    plotId = plotId or 0
    player:SetAttribute("CurrentPlotId", plotId)
end

function module.RegisterPlot(plotPart: Part)
    local plotId = #module.Plots + 1
    module.Plots[plotId] = plotPart

    CollectionService:AddTag(plotPart, "FormexPlot")

    plotPart.Name = "Plot" .. tostring(plotId)
    plotPart:SetAttribute("PlotId", plotId)

    module.PlotData[plotId] = {
        UserId = 0,
        SaveId = 0,
        Name = "Unclaimed Plot",
        LastPlayed = 0,
        Levels = {},
        Permissions = {},
    }
    updatePlotAttributes(plotId)

    print("Registering plot with PlotId:", plotId)
end

function module.SavePlot(plotId: number)
    local plotData = module.PlotData[plotId]
    if not plotData or plotData.SaveId == 0 then return end

    local userId = module.PlotToPlayer[plotId] or plotData.UserId
    if not userId or userId == 0 then return end

    plotData.LastPlayed = os.time()

    local key = tostring(userId) .. ":" .. tostring(plotData.SaveId)
    local success, err = pcall(function()        
        plotDataStore:SetAsync(key, {
            UserId = userId,
            SaveId = plotData.SaveId,
            Name = plotData.Name,
            LastPlayed = plotData.LastPlayed,
            Levels = plotData.Levels,
            Permissions = plotData.Permissions,
        })
    end)

    if not success then
        warn("FormexServer.SavePlot failed for PlotId", plotId, ":", err)
        return false, err
    end

    return true
end

function module.ClaimPlot(player: Player, plotId: number?): boolean
    plotId = plotId or player:GetAttribute("CurrentPlotId")
    if not plotId then return false, "No plot specified" end
    return module.AssignPlotToPlayer(player, plotId)
end

function module.ReleasePlot(player: Player): boolean
    return module.UnassignPlotToPlayer(player)
end

function module.ListSaves(player: Player): {[number]: Formex.PlotSaveInfo}
    -- TODO implement
end

function module.LoadSave(player: Player, saveId: number): boolean
    -- TODO implement
end

function module.NewSave(player: Player): boolean
    -- TODO implement
end

function module.SetPermission(player: Player, targetUserId: number, permission: Formex.Permission): boolean
    -- TODO implement
end

function module.GetPermissions(player: Player): {[number]: Formex.Permission}
    -- TODO implement
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

Players.PlayerRemoving:Connect(function(player)
    local plotId = module.PlayerToPlot[player.UserId]
    if plotId then
        module.UnassignPlotToPlayer(player)
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

        if currentPlotId == 0 then
            -- Identify nearest plot
            for _, plotPart in pairs(module.Plots) do
                local near = Formex.IsNearPlot(plotPart.Position, playerPosition, proximityBorder)
                if not near then continue end

                setPlayerCurrentPlot(player, plotPart:GetAttribute("PlotId") or 0)
                break
            end
        else
            -- Confirm still near current plot
            local plotPart = module.Plots[currentPlotId]
            local near = Formex.IsNearPlot(plotPart.Position, playerPosition, proximityBorder * 1.1)
            if not near then
                setPlayerCurrentPlot(player, 0)
            end
        end
    end
end)

return module
