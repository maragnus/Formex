--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FormexFolder = ReplicatedStorage:WaitForChild("Formex")
local Formex = require(FormexFolder:WaitForChild("Formex"))
local FormexServer = require(script.Parent:WaitForChild("FormexServer"))

local remoteFunctions = {
    [Formex.Functions.ClaimPlot] = function(player)
        return FormexServer.ClaimPlot(player)
    end,
    [Formex.Functions.ReleasePlot] = function(player)
        return FormexServer.ReleasePlot(player)
    end,
    [Formex.Functions.ListSaves] = function(player)
        return FormexServer.ListSaves(player)
    end,
    [Formex.Functions.LoadSave] = function(player, saveId)
        return FormexServer.LoadSave(player, saveId)
    end,
    [Formex.Functions.NewSave] = function(player)
        return FormexServer.NewSave(player)
    end,
    [Formex.Functions.SetPermission] = function(player, targetUserId, permission)
        return FormexServer.SetPermission(player, targetUserId, permission)
    end,
    [Formex.Functions.GetPermissions] = function(player)
        return FormexServer.GetPermissions(player)
    end,
}

FormexServer.Functions.OnServerInvoke = function(player, functionName, ...)
    local func = remoteFunctions[functionName]
    if func and type(func) == "function" then
        local result, message = pcall(func, player, ...)
        if result == false and type(message) == "string" then
            warn(functionName .. " failed: " .. message)
        end
        return result
    else
        warn("FormexFunctions: Unknown function invoked:", functionName)
        return nil
    end
end