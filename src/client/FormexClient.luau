--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FormexFolder = ReplicatedStorage:WaitForChild("Formex")
local Formex = require(FormexFolder:WaitForChild("Formex"))
local PlotClient = require(script.Parent:WaitForChild("PlotClient"))
Formex.Math = require(FormexFolder:WaitForChild("FormexMath"))
Formex.Plot = require(FormexFolder:WaitForChild("FormexPlot"))
Formex.Util = require(FormexFolder:WaitForChild("FormexUtil"))
Formex.Floors = require(FormexFolder:WaitForChild("FormexFloors"))
Formex.Walls = require(FormexFolder:WaitForChild("FormexWalls"))
require(FormexFolder:WaitForChild("FormexData"))

local FormexFunctions: RemoteFunction = FormexFolder:WaitForChild("FormexFunctions")

local events: BindableEvent = Instance.new("BindableEvent", workspace:WaitForChild("Formex"))
events.Name = "FormexEvents"

local FormexClient = {}

FormexClient.Formex = Formex
FormexClient.ClientEvents = events.Event

function FormexClient.FireEvent(eventName: string, ...)
    events:Fire(eventName, ...)
end

PlotClient.SetEventEmitter(events)

function FormexClient.ClaimPlot(plotId: number?) : boolean
    local result, message = FormexFunctions:InvokeServer(Formex.Function.ClaimPlot, plotId)
    if result == false then
        warn("ClaimPlot failed:", message)
    end
    return result
end

function FormexClient.ReleasePlot()
    local result, message = FormexFunctions:InvokeServer(Formex.Function.ReleasePlot)
    if result == false then
        warn("ReleasePlot failed:", message)
    end
    return result
end

function FormexClient.UnlockSegment(segmentIndex: number)
    local result, message = FormexFunctions:InvokeServer(Formex.Function.UnlockSegment, segmentIndex)
    if result == false then
        warn("UnlockSegment failed:", message)
    end
    return result, message
end

function FormexClient.RenamePlot(newName: string)
    local result, message = FormexFunctions:InvokeServer(Formex.Function.RenamePlot, newName)
    if result == false then
        warn("RenamePlot failed:", message)
    end
    return result
end

function FormexClient.GetSaves(): {[number]: Formex.PlotSaveInfo}
    local result, message = FormexFunctions:InvokeServer(Formex.Function.ListSaves)
    if result == false then
        warn("ListSaves failed:", message)
        return {}
    end
    return result or {}
end

function FormexClient.LoadSave(saveId: number)
    local result, message = FormexFunctions:InvokeServer(Formex.Function.LoadSave, saveId)
    if result == false then
        warn("LoadSave failed:", message)
    end
    return result, message
end

function FormexClient.NewSave(startingSegment: number?)
    local result, message = FormexFunctions:InvokeServer(Formex.Function.NewSave, startingSegment)
    if result == false then
        warn("NewSave failed:", message)
    end
    return result, message
end

function FormexClient.SetSavePermission(targetUserId: number, permission: Formex.Permission): (boolean, string?)
    return FormexFunctions:InvokeServer(Formex.Function.SetPermission, targetUserId, permission)
end

function FormexClient.GetSavePermissions(): {[number]: Formex.Permission}
    return FormexFunctions:InvokeServer(Formex.Function.GetPermissions)
end

function FormexClient.BuildWall(wall: Formex.WallData | {Formex.WallData}, action: Formex.BuildAction): Formex.WallData | {Formex.WallData}
    return FormexFunctions:InvokeServer(Formex.Function.BuildWall, wall, action)
end

function FormexClient.BuildFloor(floor: Formex.FloorData | {Formex.FloorData}, action: Formex.BuildAction): Formex.FloorData | {Formex.FloorData}
    return FormexFunctions:InvokeServer(Formex.Function.BuildFloor, floor, action)
end

function FormexClient.BuildObject(wall: Formex.ObjectData, action: Formex.BuildAction): Formex.ObjectData
    return FormexFunctions:InvokeServer(Formex.Function.BuildObject, wall, action)
end

function FormexClient.CanUndo(): boolean
    return FormexFunctions:InvokeServer(Formex.Function.CanUndo)
end

function FormexClient.CanRedo(): boolean
    return FormexFunctions:InvokeServer(Formex.Function.CanRedo)
end

function FormexClient.Undo(): (boolean, string?)
    local result, message = FormexFunctions:InvokeServer(Formex.Function.Undo)
    if result == false then
        warn("Undo failed:", message)
    end
    return result, message
end

function FormexClient.Redo(): (boolean, string?)
    local result, message = FormexFunctions:InvokeServer(Formex.Function.Redo)
    if result == false then
        warn("Redo failed:", message)
    end
    return result, message
end


return FormexClient
