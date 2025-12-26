--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FormexFolder = ReplicatedStorage:WaitForChild("Formex")
local Formex = require(FormexFolder:WaitForChild("Formex"))
local FormexFunctions: RemoteFunction = FormexFolder:WaitForChild("FormexFunctions")
local FormexEvents: RemoteEvent = FormexFolder:WaitForChild("FormexEvents")

export type PlotInfo = {
    IsValid: boolean,
    PlotId: number,
    PlotPart: BasePart,
    Name: string,
    OwnerUserId: number,
    OwnerName: string,
    IsClaimed: boolean,
    IsMine: boolean,
    MyPermission: Formex.Permission,
    Properties: {[string]: any}
}
local EmptyPlotInfo: PlotInfo = {
    IsValid = false,
    PlotId = 0,
    PlotPart = nil,
    Name = "",
    OwnerUserId = 0,
    OwnerName = "",
    IsClaimed = false,
    IsMine = false,
    MyPermission = "Guest",
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

local module = {}
module.Formex = Formex
module.ClientEvents = events.Event
module.Plots = {} :: { [number]: PlotInfo }

-- local cached state
module.MyPlotId = 0
module.MyPlot = {} :: PlotInfo
module.CurrentPlotId = 0

local function notifyPlotChange(plotId: number)
    if module.MyPlotId == plotId then
        events:Fire("MyPlotChanged", plotId)
        module.MyPlot = module.Plots[plotId] or EmptyPlotInfo
    end
    if module.CurrentPlotId == plotId then
        events:Fire("CurrentPlotChanged", plotId)
        module.CurrentPlot = module.Plots[plotId] or EmptyPlotInfo
    end
end

local permissionId = "U_" .. tostring(Players.LocalPlayer.UserId)

local function subscribeToPlot(plotPart: Part)
    -- CHECK: Wait for attribute using GetAttributeChangedSignal?
    local plotId = plotPart:GetAttribute("PlotId") or 0
   
    local info: PlotInfo = {
        IsValid = true,
        PlotId = plotId,
        PlotPart = plotPart,
        Name = plotPart:GetAttribute("Name") or "Unnamed",
        OwnerUserId = plotPart:GetAttribute("OwnerUserId") or 0,
        OwnerName = plotPart:GetAttribute("OwnerName") or "Unknown Player",
        MyPermission = "Guest",
        Properties = {}
    }
    module.Plots[plotId] = info

    plotPart:GetAttributeChangedSignal("Name"):Connect(function()
        info.Name = plotPart:GetAttribute("Name") or "Unnamed"
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

    notifyPlotChange(plotId)

    return info
end

function module.SetMyPlotId(plotId)
	module.MyPlotId = plotId or 0
    notifyPlotChange(plotId)
end

function module.SetCurrentPlotId(plotId)
	module.CurrentPlotId = plotId or 0
    notifyPlotChange(plotId)
end

function module.RegisterPlot(plotPart: Part)
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

function module.ClaimPlot()
    FormexFunctions:InvokeServer(Formex.Functions.ClaimPlot)
end

function module.ReleasePlot()
    FormexFunctions:InvokeServer(Formex.Functions.ReleasePlot)
end

function module.ListSaves(): {[number]: Formex.PlotSaveInfo}
    return FormexFunctions:InvokeServer(Formex.Functions.ReleasePlot)
end

function module.LoadSave(saveId: number)
    return FormexFunctions:InvokeServer(Formex.Functions.LoadPlot, saveId)
end

function module.NewSave()
    return FormexFunctions:InvokeServer(Formex.Functions.NewPlot)
end

function module.SetSavePermission(targetUserId: number, permission: Formex.Permission)
    return FormexFunctions:InvokeServer(Formex.Functions.SetPermission, targetUserId, permission)
end

function module.GetSavePermissions(): {[number]: Formex.Permission}
    return FormexFunctions:InvokeServer(Formex.Functions.GetPermissions)
end

return module
