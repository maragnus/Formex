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
    [Formex.Function.ClaimPlot] = function(player)
        return FormexPlot.ClaimPlot(player)
    end,
    [Formex.Function.ReleasePlot] = function(player)
        return FormexPlot.ReleasePlot(player)
    end,
    [Formex.Function.RenamePlot] = function(player, newName)
        return FormexPlot.RenamePlot(player, newName)
    end,
    [Formex.Function.ListSaves] = function(player)
        return FormexPlot.ListSaves(player)
    end,
    [Formex.Function.LoadSave] = function(player, saveId)
        return FormexPlot.LoadSave(player, saveId)
    end,
    [Formex.Function.NewSave] = function(player, startingSegment)
        return FormexPlot.NewSave(player, startingSegment)
    end,
    [Formex.Function.SetPermission] = function(player, targetUserId, permission)
        return FormexPlot.SetPermission(player, targetUserId, permission)
    end,
    [Formex.Function.GetPermissions] = function(player)
        return FormexPlot.GetPermissions(player)
    end,
    [Formex.Function.UnlockSegment] = function(player, segmentIndex)
        return FormexPlot.UnlockSegment(player, segmentIndex)
    end,
    [Formex.Function.BuildWall] = function(player, wallData, action)
        return FormexBuild.BuildWall(player, wallData, action)
    end,
    [Formex.Function.BuildFloor] = function(player, level, x, y, material, material2)
        return FormexBuild.BuildFloor(player, level, x, y, material, material2)
    end,
    [Formex.Function.BuildCeiling] = function(player, level, x, y, material, material2)
        return FormexBuild.BuildCeiling(player, level, x, y, material, material2)
    end,
    [Formex.Function.BuildObject] = function(player, objectData, action)
        return FormexBuild.BuildObject(player, objectData, action)
    end,
    [Formex.Function.CanUndo] = function(player)
        return FormexBuild.CanUndo(player)
    end,
    [Formex.Function.CanRedo] = function(player)
        return FormexBuild.CanRedo(player)
    end,
    [Formex.Function.Undo] = function(player)
        return FormexBuild.Undo(player)
    end,
    [Formex.Function.Redo] = function(player)
        return FormexBuild.Redo(player)
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
