--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local FormexFolder = ReplicatedStorage:WaitForChild("Formex")
local Formex = require(FormexFolder:WaitForChild("Formex"))
local FormexBuild = require(script.Parent:WaitForChild("FormexBuild"))

local plotDataStore: DataStore = DataStoreService:GetDataStore("FormexPlotData")

local FormexFunctions: RemoteFunction = Instance.new("RemoteFunction", FormexFolder)
FormexFunctions.Name = "FormexFunctions"

local FormexEvents: RemoteEvent = Instance.new("RemoteEvent", FormexFolder)
FormexEvents.Name = "FormexEvents"

local module = {}
module.Formex = Formex

module.Plots = {} :: { [number]: BasePart } -- [plotId]: BasePart
module.PlotData = {} :: { [number]: Formex.PlotData } -- [plotId]: Formex.PlotData
module.PlayerToPlot = {} :: {[number]: number} -- [userId]: plotId
module.PlotToPlayer = {} :: {[number]: number} -- [plotId]: userId
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

local function getPlayerCurrentPlot(player: Player) : (Formex.PlotData?, Formex.Permission)
    local plotId = player:GetAttribute("CurrentPlotId") or 0
    if not plotId or plotId == 0 then
        return nil, nil
    end

    local plotData = module.PlotData[plotId]
    return plotData, plotData.Permissions[player.UserId] or Formex.Permissions.Guest
end

function module.UnassignPlotToPlayer(player: Player)
    local userId = player.UserId
    local plotId = module.PlayerToPlot[userId] or 0
    if plotId == 0 then return end

    print(player.Name .. " unclaims plot " .. tostring(plotId))

    module.SavePlot(plotId)

    FormexBuild.ClearPlot(module.Plots[plotId])

    module.PlotToPlayer[plotId] = nil
    module.PlayerToPlot[userId] = nil
    player:SetAttribute("MyPlotId", 0)

    local plotData = module.PlotData[plotId]
    plotData.UserId = 0
    plotData.SaveId = 0
    plotData.Name = "Unclaimed Plot"
    plotData.LastPlayed = 0
    plotData.Levels = {}
    plotData.Permissions = {}
    updatePlotAttributes(plotId)

    return true
end

function module.AssignPlotToPlayer(player: Player, plotId: number)
    if module.PlotToPlayer[plotId] then
        return false, "Plot already claimed"
    end

    module.UnassignPlotToPlayer(player)

    plotId = plotId or 0
    if plotId == 0 then return end

    print(player.Name .. " claims plot " .. tostring(plotId))

    local userId = player.UserId
    local plotName = player.Name .. "'s Plot"

    module.PlayerToPlot[userId] = plotId
    module.PlotToPlayer[plotId] = userId
    player:SetAttribute("MyPlotId", plotId)

    local plotData = module.PlotData[plotId]
    plotData.UserId = player.UserId
    plotData.SaveId = 0
    plotData.Name = plotName
    plotData.LastPlayed = 0
    plotData.Levels = {}
    plotData.Permissions = {}
    updatePlotAttributes(plotId)
    
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
        PlotId = plotId,
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

function module.ClaimPlot(player: Player, plotId: number?): (boolean, string)
    plotId = plotId or player:GetAttribute("CurrentPlotId")
    if not plotId then return false, "No plot specified" end
    return module.AssignPlotToPlayer(player, plotId)
end

function module.ReleasePlot(player: Player): boolean
    return module.UnassignPlotToPlayer(player)
end

function module.RenamePlot(player: Player, newName: string): boolean
    if not newName or newName == "" then return false, "Invalid name" end

    local plotData, permission = getPlayerCurrentPlot(player)
    if not plotData then return false, "No current plot" end

    if permission ~= Formex.Permissions.Owner then return false, "Permission denied" end
    if plotData.Name == newName then return false, "Name unchanged" end

    plotData.Name = newName
    updatePlotAttributes(plotData.PlotId)
    module.SavePlot(plotData.PlotId)

    return true
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

    updatePlotAttributes(plotId)

    return true
end

-- This method can throw errors because is always called via pcall
function module.ListSaves(player: Player): {[number]: Formex.PlotSaveInfo}
    local userId = player.UserId
    local prefix = tostring(userId) .. ":"
    local keyPages = plotDataStore:ListKeysAsync(prefix, Formex.MaxSaveSlots, nil, true)
    local saves = {}

    local function addSaves(page)
        for _, keyInfo in ipairs(page:GetCurrentPage()) do
            local key = keyInfo.KeyName
            local saveId = tonumber(string.match(key, "^%d+:(%d+)$"))
            if not saveId then
                continue
            end

            local data = plotDataStore:GetAsync(key)
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

function module.LoadSave(player: Player, saveId: number): boolean
    if not saveId or saveId == 0 then error("Invalid save selected") end

    local userId = player.UserId
    local plotId = module.PlayerToPlot[userId]
    if not plotId or plotId == 0 then error("No claimed plot") end

    local plotPart = module.Plots[plotId]
    if not plotPart then error("Invalid plot") end

    local key = tostring(userId) .. ":" .. tostring(saveId)
    local saveData: Formex.PlotData = plotDataStore:GetAsync(key)
    if not saveData then error("Save not found") end

    local plotData = module.PlotData[plotId]
    if not plotData then error("Invalid plot") end

    plotData.SaveId = saveData.SaveId or saveId
    plotData.Name = saveData.Name or (player.Name .. "'s Plot")
    plotData.LastPlayed = os.time()
    plotData.Levels = saveData.Levels or {}
    plotData.LevelsUnlocked = saveData.LevelsUnlocked or 1
    plotData.SegmentsUnlocked = saveData.SegmentsUnlocked or 0
    plotData.Permissions = saveData.Permissions or {}
    updatePlotAttributes(plotId)

    FormexBuild.ClearPlot(plotPart)
    FormexBuild.RenderPlot(plotPart, module.PlotData[plotId])

    module.SavePlot(plotId)

    return true
end

function module.NewSave(player: Player): boolean
    local plotId = module.PlayerToPlot[player.UserId]
    if not plotId or plotId == 0 then error("No claimed plot") end
    local plotData = module.PlotData[plotId]
    if not plotData then error("Invalid plot") end
    
    local saveId = Random.new():NextInteger(1000, 10000000)
    plotData.SaveId = saveId
    plotData.Name = player.Name .. "'s Plot"
    plotData.Permissions[player.UserId] = Formex.Permissions.Owner
    plotData.LevelsUnlocked = 1
    plotData.SegmentsUnlocked = 0
    plotData.Levels = {}

    module.SavePlot(plotId)
    return plotData.SaveId
end

function module.SetPermission(player: Player, targetUserId: number, permission: Formex.Permission): boolean
    local plotData, playerPermission = getPlayerCurrentPlot(player)
    if not plotData then return false, "No current plot" end

    if playerPermission ~= Formex.Permissions.Owner then error("Permission denied") end
    if not targetUserId or targetUserId <= 0 then return error("Invalid target") end
    if targetUserId == plotData.UserId then return error("Cannot change owner permission") end
    if not Formex.Permissions[permission] then return error("Invalid permission") end

    plotData.Permissions = plotData.Permissions or {}
    if permission == Formex.Permissions.Guest then
        plotData.Permissions[targetUserId] = nil
    else
        plotData.Permissions[targetUserId] = permission
    end

    updatePlotAttributes(plotData.PlotId)
    module.SavePlot(plotData.PlotId)

    return true
end

function module.GetPermissions(player: Player): {[number]: Formex.Permission}
    local plotData = getPlayerCurrentPlot(player)
    if not plotData then return false, "No current plot" end

    return plotData.Permissions
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
