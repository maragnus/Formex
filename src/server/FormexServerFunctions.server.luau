--!strict

local DEBUG = true

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FormexFolder = ReplicatedStorage:WaitForChild("Formex")
local Formex = require(FormexFolder:WaitForChild("Formex"))
local FormexPlot = require(script.Parent:WaitForChild("FormexPlot"))
local FormexBuild = require(script.Parent:WaitForChild("FormexBuild"))

local FormexFunctions: RemoteFunction = Instance.new("RemoteFunction", FormexFolder)
FormexFunctions.Name = "FormexFunctions"

local remoteFunctions = {
    [Formex.Functions.ClaimPlot] = function(player)
        return FormexPlot.ClaimPlot(player)
    end,
    [Formex.Functions.ReleasePlot] = function(player)
        return FormexPlot.ReleasePlot(player)
    end,
    [Formex.Functions.RenamePlot] = function(player, newName)
        return FormexPlot.RenamePlot(player, newName)
    end,
    [Formex.Functions.ListSaves] = function(player)
        return FormexPlot.ListSaves(player)
    end,
    [Formex.Functions.LoadSave] = function(player, saveId)
        return FormexPlot.LoadSave(player, saveId)
    end,
    [Formex.Functions.NewSave] = function(player, startingSegment)
        return FormexPlot.NewSave(player, startingSegment)
    end,
    [Formex.Functions.SetPermission] = function(player, targetUserId, permission)
        return FormexPlot.SetPermission(player, targetUserId, permission)
    end,
    [Formex.Functions.GetPermissions] = function(player)
        return FormexPlot.GetPermissions(player)
    end,
    [Formex.Functions.UnlockSegment] = function(player, segmentIndex)
        return FormexPlot.UnlockSegment(player, segmentIndex)
    end,
    [Formex.Functions.BuildWall] = function(player, wallData, action)
        return FormexBuild.BuildWall(player, wallData, action)
    end,
    [Formex.Functions.BuildFloor] = function(player, floorData, action)
        return FormexBuild.BuildFloor(player, floorData, action)
    end,
    [Formex.Functions.BuildObject] = function(player, objectData, action)
        return FormexBuild.BuildObjet(player, objectData, action)
    end,
}

FormexFunctions.OnServerInvoke = function(player, functionName, ...)
    warn(player.Name .. " called " .. functionName)
    local func = remoteFunctions[functionName]
    if func and type(func) == "function" then
        if DEBUG then
            return func(player, ...)
        else
            local success, result = pcall(func, player, ...)
            if not success then
                warn(functionName .. " failed:", result)
                return false, result
            end
            return result
        end
    else
        warn("FormexFunctions: Unknown function invoked:", functionName)
        return nil
    end
end
