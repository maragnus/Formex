--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FormexFolder = ReplicatedStorage:WaitForChild("Formex")
local Formex = require(FormexFolder:WaitForChild("Formex"))
local FormexUI = require(script.Parent:WaitForChild("FormexUI"))
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
    local result, message = FormexFunctions:InvokeServer(Formex.Functions.ClaimPlot, plotId)
    if result == false then
        warn("ClaimPlot failed:", message)
    end
    return result
end

function FormexClient.ReleasePlot()
    local result, message = FormexFunctions:InvokeServer(Formex.Functions.ReleasePlot)
    if result == false then
        warn("ReleasePlot failed:", message)
    end
    return result
end

function FormexClient.UnlockSegment(segmentIndex: number)
    local result, message = FormexFunctions:InvokeServer(Formex.Functions.UnlockSegment, segmentIndex)
    if result == false then
        warn("UnlockSegment failed:", message)
    end
    return result, message
end

function FormexClient.RenamePlot(newName: string)
    local result, message = FormexFunctions:InvokeServer(Formex.Functions.RenamePlot, newName)
    if result == false then
        warn("RenamePlot failed:", message)
    end
    return result
end

function FormexClient.GetSaves(): {[number]: Formex.PlotSaveInfo}
    local result, message = FormexFunctions:InvokeServer(Formex.Functions.ListSaves)
    if result == false then
        warn("ListSaves failed:", message)
        return {}
    end
    return result or {}
end

function FormexClient.LoadSave(saveId: number)
    local result, message = FormexFunctions:InvokeServer(Formex.Functions.LoadSave, saveId)
    if result == false then
        warn("LoadSave failed:", message)
    end
    return result, message
end

function FormexClient.NewSave(startingSegment: number?)
    local result, message = FormexFunctions:InvokeServer(Formex.Functions.NewSave, startingSegment)
    if result == false then
        warn("NewSave failed:", message)
    end
    return result, message
end

function FormexClient.SetSavePermission(targetUserId: number, permission: Formex.Permission): (boolean, string?)
    return FormexFunctions:InvokeServer(Formex.Functions.SetPermission, targetUserId, permission)
end

function FormexClient.GetSavePermissions(): {[number]: Formex.Permission}
    return FormexFunctions:InvokeServer(Formex.Functions.GetPermissions)
end

function FormexClient.BuildWall(wall: Formex.WallData, action: Formex.BuildAction): Formex.WallData
    return FormexFunctions:InvokeServer(Formex.Functions.BuildWall)
end

function FormexClient.BuildFloor(wall: Formex.FloorData, action: Formex.BuildAction): Formex.FloorData
    return FormexFunctions:InvokeServer(Formex.Functions.BuildFloor)
end

function FormexClient.BuildObject(wall: Formex.ObjectData, action: Formex.BuildAction): Formex.ObjectData
    return FormexFunctions:InvokeServer(Formex.Functions.BuildObject)
end


return FormexClient
