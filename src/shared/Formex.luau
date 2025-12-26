--!strict

--    ___
--   / __\__  _ __ _ __ ___   _____  __
--  / _\/ _ \| '__| '_ ` _ \ / _ \ \/ /
-- / / | (_) | |  | | | | | |  __/>  <
-- \/   \___/|_|  |_| |_| |_|\___/_/\_\
-- Formex by NexArc Solutions <roblox@nexarc.dev>

-- Type constants

export type SurfaceType = "Square" | "Sliced"
export type Permission = "Guest" | "Banned" | "VIP" | "Manager" | "Owner"

-- Client shared represenation
export type PlotSaveInfo = {
	Name: string,
	Properties: {[string]: any}
}

-- Stored representation
export type PlotData = {
	PlotId: number,
	UserId: number,
	SaveId: number,
	Name: string,
	LastPlayed: number,
	Levels: {[number]: LevelData},
	Permissions: {[number]: Permission},
}

export type LevelData = {
	Walls: {[number]: WallData},
	Segments: {[number]: boolean},
	Objects: {[number]: ObjectData},
}

export type WallData = {
	X1: number,
	Y1: number,
	X2: number,
	Y2: number,
	FrontMaterial: string,
	BackMaterial: string
}

export type FloorData = {
	FloorType: SurfaceType,
	FloorMaterial: string,
	CeilingType: SurfaceType,
	CeilingMaterial: string
}

export type ObjectData = {
	ObjectId: string,
	Position: Vector3,
	Rotation: Vector3,
	Design: {[number]: string},
	Properties: {[string]: any}
}

-- Module constants

local module = {}

module.Permissions = {
	Banned = "Banned",
	Guest = "Guest",
	VIP = "VIP",
	Manager = "Manager",
	Owner = "Owner"
} :: { Permission: Permission }

module.LevelHeight = 10 -- studs
module.GridSize = 2 -- studs
module.MaxSaveSlots = 3
module.ProximityBorder = 25 -- studs

-- Upgrade segment size
module.SegmentSize = {
	Width = 64, -- studs
	Depth = 64, -- studs
	Height = 10 -- studs
}
module.MaxPlotSize = {
	Width = 3, -- segments
	Height = 3, -- segments
	Levels = 4 -- segments
}
module.Dimensions = {
	Width = module.SegmentSize.Width * module.MaxPlotSize.Width, -- studs
	Depth = module.SegmentSize.Depth * module.MaxPlotSize.Height, -- studs
	Height = module.LevelHeight * module.MaxPlotSize.Levels -- studs
}

module.Functions = {
	ClaimPlot = "ClaimPlot",
	ReleasePlot = "ReleasePlot",
	RenamePlot = "RenamePlot",
	ListSaves = "ListSaves",
	LoadSave = "LoadSave",
	NewSave = "NewSave",
	GetPermissions = "GetPermissions",
	SetPermission = "SetPermission"
}

function module.IsNearPlot(plotCenter: Vector3, position: Vector3, border: number): boolean
	local plotDimensions = module.Dimensions
	local plotWidth = plotDimensions.Width
	local plotDepth = plotDimensions.Depth
	local plotHeight = plotDimensions.Height

	local xDiff = math.abs(position.X - plotCenter.X)
	local yDiff = math.abs(position.Y - plotCenter.Y)
	local zDiff = math.abs(position.Z - plotCenter.Z)

	return xDiff <= (plotWidth / 2 + border) and yDiff <= (plotHeight / 2 + border) and zDiff <= (plotDepth / 2 + border)
end

return module
