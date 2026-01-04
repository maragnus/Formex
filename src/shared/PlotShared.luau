--!strict

local Formex = require(script.Parent:WaitForChild("Formex"))

local PlotShared = {}

export type PlotInfo = {
	IsValid: boolean,
	Id: number,
	PlotId: number,
	Part: BasePart?,
	PlotPart: BasePart?,
	SaveId: number,
	Name: string,
	OwnerUserId: number,
	OwnerName: string,
	IsClaimed: boolean,
	IsMine: boolean,
	MyPermission: Formex.Permission,
	LastPlayed: number,
	LevelsUnlocked: number,
	SegmentsUnlocked: number,
	CanUndo: boolean,
	CanRedo: boolean,
	Properties: {[string]: any},
	OnPlotChanged: BindableEvent,
}

local function createPlotChangedEvent(parent: Instance?): BindableEvent
	local event = Instance.new("BindableEvent")	
	if parent then
		event.Parent = parent
	end
	return event
end

function PlotShared.CreateEmptyPlot(parent: Instance?): PlotInfo
	return {
		IsValid = false,
		Id = 0,
		PlotId = 0,
		Part = nil,
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
		CanUndo = false,
		CanRedo = false,
		Properties = {},
		OnPlotChanged = createPlotChangedEvent(parent),
	}
end

local function updateOwnership(plot: PlotInfo, ownerUserId: number, ownerName: string, localUserId: number?)
	plot.OwnerUserId = ownerUserId
	plot.OwnerName = ownerName
	plot.IsClaimed = ownerUserId ~= 0
	plot.IsMine = localUserId ~= nil and ownerUserId == localUserId
end

function PlotShared.ApplyPlotAttributes(plotPart: BasePart, plot: PlotInfo, localUserId: number?)
	plot.PlotId = plotPart:GetAttribute("PlotId") or plot.PlotId
	plot.Id = plot.PlotId
	plot.Name = plotPart:GetAttribute("PlotName") or "Unnamed"
	local ownerUserId = plotPart:GetAttribute("OwnerUserId") or 0
	local ownerName = plotPart:GetAttribute("OwnerName") or "Unknown Player"
	updateOwnership(plot, ownerUserId, ownerName, localUserId)
	plot.SaveId = plotPart:GetAttribute("SaveId") or 0
	plot.LastPlayed = plotPart:GetAttribute("LastPlayed") or 0
	plot.LevelsUnlocked = plotPart:GetAttribute("LevelsUnlocked") or 0
	plot.SegmentsUnlocked = plotPart:GetAttribute("SegmentsUnlocked") or 0
	plot.CanUndo = plotPart:GetAttribute("CanUndo") or false
	plot.CanRedo = plotPart:GetAttribute("CanRedo") or false

	if localUserId ~= nil then
		local permissionId = "U_" .. tostring(localUserId)
		plot.MyPermission = plotPart:GetAttribute(permissionId) or "Guest"
	end
end

function PlotShared.CreatePlot(plotPart: BasePart, localUserId: number?, parent: Instance?): PlotInfo
	local plot = PlotShared.CreateEmptyPlot(parent)
	plot.IsValid = true
	plot.Part = plotPart
	plot.PlotPart = plotPart
	PlotShared.ApplyPlotAttributes(plotPart, plot, localUserId)
	plot.Id = plot.PlotId
	return plot
end

export type PlotAttributeOptions = {
	LocalUserId: number?,
	OnPlotChanged: ((plot: PlotInfo) -> ())?,
}

function PlotShared.BindPlotAttributes(plotPart: BasePart, plot: PlotInfo, options: PlotAttributeOptions)
	local localUserId = options.LocalUserId
	local onPlotChanged = options.OnPlotChanged

	local function notifyChange()
		plot.OnPlotChanged:Fire()
		if onPlotChanged then
			onPlotChanged(plot)
		end
	end

	plotPart:GetAttributeChangedSignal("PlotName"):Connect(function()
		plot.Name = plotPart:GetAttribute("PlotName") or "Unnamed"
		notifyChange()
	end)

	plotPart:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
		local ownerUserId = plotPart:GetAttribute("OwnerUserId") or 0
		local ownerName = plotPart:GetAttribute("OwnerName") or plot.OwnerName
		updateOwnership(plot, ownerUserId, ownerName, localUserId)
		notifyChange()
	end)

	plotPart:GetAttributeChangedSignal("OwnerName"):Connect(function()
		plot.OwnerName = plotPart:GetAttribute("OwnerName") or "Unknown Player"
		notifyChange()
	end)

	plotPart:GetAttributeChangedSignal("SaveId"):Connect(function()
		plot.SaveId = plotPart:GetAttribute("SaveId") or 0
		notifyChange()
	end)

	plotPart:GetAttributeChangedSignal("LastPlayed"):Connect(function()
		plot.LastPlayed = plotPart:GetAttribute("LastPlayed") or 0
		notifyChange()
	end)

	plotPart:GetAttributeChangedSignal("LevelsUnlocked"):Connect(function()
		plot.LevelsUnlocked = plotPart:GetAttribute("LevelsUnlocked") or 0
		notifyChange()
	end)

	plotPart:GetAttributeChangedSignal("SegmentsUnlocked"):Connect(function()
		plot.SegmentsUnlocked = plotPart:GetAttribute("SegmentsUnlocked") or 0
		notifyChange()
	end)

	plotPart:GetAttributeChangedSignal("CanUndo"):Connect(function()
		plot.CanUndo = plotPart:GetAttribute("CanUndo") or false
		notifyChange()
	end)

	plotPart:GetAttributeChangedSignal("CanRedo"):Connect(function()
		plot.CanRedo = plotPart:GetAttribute("CanRedo") or false
		notifyChange()
	end)

	if localUserId ~= nil then
		local permissionId = "U_" .. tostring(localUserId)
		plotPart:GetAttributeChangedSignal(permissionId):Connect(function()
			plot.MyPermission = plotPart:GetAttribute(permissionId) or "Guest"
			notifyChange()
		end)
	end
end

return PlotShared
