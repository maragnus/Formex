--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FormexFolder = ReplicatedStorage:WaitForChild("Formex")
local Formex = require(FormexFolder:WaitForChild("Formex"))
Formex.Math = require(FormexFolder:WaitForChild("FormexMath"))
Formex.Plot = require(FormexFolder:WaitForChild("FormexPlot"))
Formex.Util = require(FormexFolder:WaitForChild("FormexUtil"))
Formex.Floors = require(FormexFolder:WaitForChild("FormexFloors"))
Formex.Walls = require(FormexFolder:WaitForChild("FormexWalls"))
require(FormexFolder:WaitForChild("FormexData"))

local FormexFunctions: RemoteFunction = FormexFolder:WaitForChild("FormexFunctions")

export type PlotInfo = {
    IsValid: boolean,
    PlotId: number,
    PlotPart: BasePart,
    SaveId: number,
    Name: string,
    OwnerUserId: number,
    OwnerName: string,
    IsClaimed: boolean,
    IsMine: boolean,
    MyPermission: Formex.Permission,
    LastPlayed: number?,
    LevelsUnlocked: number,
    SegmentsUnlocked: number,
    Properties: {[string]: any}
}
local EmptyPlotInfo: PlotInfo = {
    IsValid = false,
    PlotId = 0,
    PlotPart = nil,
    SaveId = 0,
    Name = "",
    OwnerUserId = 0,
    OwnerName = "",
    IsClaimed = false,
    IsMine = false,
    MyPermission = "Guest",
    LastPlayed = 0,
    LevelsUnlocked = 0,
    SegmentsUnlocked = 0,
    Properties = {} :: {[string]: any}
}

local events: BindableEvent = Instance.new("BindableEvent", workspace:WaitForChild("Formex"))
events.Name = "FormexEvents"

-- Wait until the LocalPlayer is available
local Players = game:GetService("Players")
if not Players.LocalPlayer then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
end
local localPlayer = Players.LocalPlayer

local FormexClient = {}

FormexClient.Formex = Formex
FormexClient.ClientEvents = events.Event
FormexClient.Plots = {} :: { [number]: PlotInfo }

-- local cached state
FormexClient.MyPlotId = 0
FormexClient.MyPlot = EmptyPlotInfo
FormexClient.CurrentPlotId = 0
FormexClient.CurrentPlot = EmptyPlotInfo

function FormexClient.FireEvent(eventName: string, ...)
    events:Fire(eventName, ...)
end

local function notifyPlotChange(plotId: number)
    if FormexClient.MyPlotId == plotId then
        events:Fire("MyPlotChanged", plotId)
        FormexClient.MyPlot = FormexClient.Plots[plotId] or EmptyPlotInfo
    end
    if FormexClient.CurrentPlotId == plotId then
        events:Fire("CurrentPlotChanged", plotId)
        FormexClient.CurrentPlot = FormexClient.Plots[plotId] or EmptyPlotInfo
    end
end

local permissionId = "U_" .. tostring(Players.LocalPlayer.UserId)

local function subscribeToPlot(plotPart: Part)
    -- CHECK: Wait for attribute using GetAttributeChangedSignal?
    local plotId = plotPart:GetAttribute("PlotId") or 0
   
    local ownerUserId = plotPart:GetAttribute("OwnerUserId") or 0

    local info: PlotInfo = {
        IsValid = true,
        PlotId = plotId,
        PlotPart = plotPart,
        Name = plotPart:GetAttribute("PlotName") or "Unnamed",
        OwnerUserId = ownerUserId,
        OwnerName = plotPart:GetAttribute("OwnerName") or "Unknown Player",
        SaveId = plotPart:GetAttribute("SaveId") or 0,
        MyPermission = "Guest",
        LastPlayed = plotPart:GetAttribute("LastPlayed") or 0,
        IsClaimed = ownerUserId ~= 0,
        IsMine = ownerUserId == localPlayer.UserId,
        LevelsUnlocked = plotPart:GetAttribute("LevelsUnlocked") or 0,
        SegmentsUnlocked = plotPart:GetAttribute("SegmentsUnlocked") or 0,
        CanUndo = plotPart:GetAttribute("CanUndo") or false,
        CanRedo = plotPart:GetAttribute("CanRedo") or false,
        Properties = {}
    }
    FormexClient.Plots[plotId] = info

    plotPart:GetAttributeChangedSignal("PlotName"):Connect(function()
        info.Name = plotPart:GetAttribute("PlotName") or "Unnamed"
        notifyPlotChange(plotId)
    end)

    plotPart:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
        info.OwnerUserId = plotPart:GetAttribute("OwnerUserId") or 0
        info.IsClaimed = info.OwnerUserId ~= 0
        info.IsMine = info.OwnerUserId == localPlayer.UserId
        notifyPlotChange(plotId)
    end)

    plotPart:GetAttributeChangedSignal("OwnerName"):Connect(function()
        info.OwnerName = plotPart:GetAttribute("OwnerName") or "Unknown Player"
        notifyPlotChange(plotId)
    end)

    plotPart:GetAttributeChangedSignal(permissionId):Connect(function()
        info.MyPermission = plotPart:GetAttribute(permissionId) or "Guest"
        notifyPlotChange(plotId)
    end)

    plotPart:GetAttributeChangedSignal("SaveId"):Connect(function()
        info.SaveId = plotPart:GetAttribute("SaveId") or 0
        notifyPlotChange(plotId)
    end)

    plotPart:GetAttributeChangedSignal("LastPlayed"):Connect(function()
        info.LastPlayed = plotPart:GetAttribute("LastPlayed") or 0
        notifyPlotChange(plotId)
    end)

    plotPart:GetAttributeChangedSignal("LevelsUnlocked"):Connect(function()
        info.LevelsUnlocked = plotPart:GetAttribute("LevelsUnlocked") or 0
        notifyPlotChange(plotId)
    end)

    plotPart:GetAttributeChangedSignal("SegmentsUnlocked"):Connect(function()
        info.SegmentsUnlocked = plotPart:GetAttribute("SegmentsUnlocked") or 0
        notifyPlotChange(plotId)
    end)

    plotPart:GetAttributeChangedSignal("CanUndo"):Connect(function()
        info.CanUndo = plotPart:GetAttribute("CanUndo") or false
        notifyPlotChange(plotId)
    end)

    plotPart:GetAttributeChangedSignal("CanRedo"):Connect(function()
        info.CanRedo = plotPart:GetAttribute("CanRedo") or false
        notifyPlotChange(plotId)
    end)

    notifyPlotChange(plotId)

    return info
end

function FormexClient.SetMyPlotId(plotId)
	FormexClient.MyPlotId = plotId or 0
    notifyPlotChange(plotId)
end

function FormexClient.SetCurrentPlotId(plotId)
	FormexClient.CurrentPlotId = plotId or 0
    notifyPlotChange(plotId)
end

function FormexClient.RegisterPlot(plotPart: Part)
    if plotPart:GetAttribute("PlotId") then
        local info = subscribeToPlot(plotPart)
        print("Client registered plot with PlotId:", info.PlotId)
    else 
        print("Delaying client registered plot")

        plotPart:GetAttributeChangedSignal("PlotId"):Once(function() 
            local info = subscribeToPlot(plotPart)
            print("Client registered plot with PlotId:", info.PlotId)
        end)
    end
end

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
