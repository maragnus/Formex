--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FormexFolder = ReplicatedStorage:WaitForChild("Formex")
local Formex = require(FormexFolder:WaitForChild("Formex"))
Formex.Math = require(FormexFolder:WaitForChild("FormexMath"))
Formex.Plot = require(FormexFolder:WaitForChild("FormexPlot"))
Formex.Util = require(FormexFolder:WaitForChild("FormexUtil"))
Formex.Floors = require(FormexFolder:WaitForChild("FormexFloors"))
Formex.Walls = require(FormexFolder:WaitForChild("FormexWalls"))
Formex.Objects = require(FormexFolder:WaitForChild("FormexObjects"))
Formex.Poly = require(FormexFolder:WaitForChild("FormexPoly"))
Formex.Rooms = require(FormexFolder:WaitForChild("FormexRooms"))
Formex.Transaction = require(FormexFolder:WaitForChild("FormexTransaction"))
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
    Properties: {[string]: any},
    CanUndo: boolean,
    CanRedo: boolean,
    PlotData: Formex.PlotData
}
local EmptyPlotData: Formex.PlotData = {
    PlotId = 0,
    UserId = 0,
    SaveId = 0,
    Name = "",
    LastPlayed = 0,
    NextId = 1,
    FoundationMaterial = Formex.DefaultFoundationMaterial,
    Levels = {},
    Rooms = {},
    LevelsUnlocked = 0,
    SegmentsUnlocked = 0,
    Permissions = {},
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
    Properties = {} :: {[string]: any},
    PlotData = EmptyPlotData,
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

type ModelSubscription = {
    Connections: {RBXScriptConnection},
}

type FloorSubscription = {
    Connections: {RBXScriptConnection},
    PointsKey: string,
    RaiseHeight: number,
}

type LevelSubscription = {
    Connections: {RBXScriptConnection},
    Folders: {[string]: {RBXScriptConnection}},
}

type PlotSubscription = {
    PlotPart: BasePart,
    Info: PlotInfo,
    Data: Formex.PlotData,
    Connections: {RBXScriptConnection},
    Levels: {[BasePart]: LevelSubscription},
    Walls: {[Model]: ModelSubscription},
    Floors: {[Model]: FloorSubscription},
    Objects: {[Model]: ModelSubscription},
}

local plotSubscriptions = {} :: {[BasePart]: PlotSubscription}

type PredictionState = {
	PlotInfo: PlotInfo,
	PlotState: PlotSubscription,
	LevelsTouched: {number},
	OriginalLevels: {[number]: Formex.LevelData?},
	OriginalLevelMissing: {[number]: boolean},
	UsedLevelSwap: boolean,
	SnapshotWalls: {[number]: {[number]: Formex.WallData}},
	SnapshotFloors: {[number]: {[number]: Formex.FloorData}},
	SnapshotObjects: {[number]: {[number]: Formex.ObjectData}},
	RemovedWalls: {[number]: {[number]: Formex.WallData}},
	RemovedFloors: {[number]: {[number]: Formex.FloorData}},
	RemovedObjects: {[number]: {[number]: Formex.ObjectData}},
	HiddenParts: {[BasePart]: {Transparency: number, CanCollide: boolean, CanQuery: boolean, CanTouch: boolean}},
	CreatedModels: {Instance},
	RemovedPredictionModels: {Model},
	PredictedModels: {[string]: Model},
	OriginalNextId: number?,
}

local predictedModelsByType = {
	Wall = {} :: {[string]: Model},
	Floor = {} :: {[string]: Model},
	Object = {} :: {[string]: Model},
}
local predictionIdCounter = 0

local defaultColor = Color3.new(1, 1, 1)
local meshClientSuffix = " (Client)"

local floorAppearanceAttributeNames = {
    "FloorMaterial",
    "CeilingMaterial",
    "FoundationMaterial",
    "FloorColor",
    "CeilingColor",
    "FoundationColor",
}

local floorGeometryAttributeNames = {
    "Points",
    "RaiseHeight",
}

local floorAppearanceAttributes = {} :: {[string]: boolean}
for _, name in ipairs(floorAppearanceAttributeNames) do
    floorAppearanceAttributes[name] = true
end

local floorGeometryAttributes = {} :: {[string]: boolean}
for _, name in ipairs(floorGeometryAttributeNames) do
    floorGeometryAttributes[name] = true
end

local function getPredictionKey(levelIndex: number, partId: number | string): string
	return tostring(levelIndex) .. ":" .. tostring(partId)
end

local function isPredictionModel(model: Instance?): boolean
	if not model or not model:IsA("Model") then
		return false
	end
	return model:GetAttribute("IsPrediction") == true
end

local function reconcilePredictedModel(kind: "Wall" | "Floor" | "Object", levelIndex: number, partId: number | string, incoming: Model)
	local map = predictedModelsByType[kind]
	if not map then
		return
	end
	local key = getPredictionKey(levelIndex, partId)
	local predicted = map[key]
	if predicted and predicted ~= incoming then
		map[key] = nil
		if predicted.Parent then
			predicted:Destroy()
		end
	end
end

local function registerPredictedModel(state: PredictionState, kind: "Wall" | "Floor" | "Object", levelIndex: number, partId: number | string, model: Model)
	local map = predictedModelsByType[kind]
	if not map then
		return
	end
	local key = getPredictionKey(levelIndex, partId)
	map[key] = model
	state.PredictedModels[kind .. ":" .. key] = model
end

local function getPlotState(plotInfo: PlotInfo?): PlotSubscription?
	if not plotInfo or not plotInfo.PlotPart then
		return nil
	end
	return plotSubscriptions[plotInfo.PlotPart]
end

local function getLevelPart(plotPart: BasePart?, levelIndex: number): BasePart?
	if not plotPart then
		return nil
	end
	local levelPart = plotPart:FindFirstChild(tostring(levelIndex))
	if levelPart and levelPart:IsA("BasePart") then
		return levelPart
	end
	return nil
end

local function getLevelFolder(plotPart: BasePart?, levelIndex: number, name: string): Folder?
	local levelPart = getLevelPart(plotPart, levelIndex)
	if not levelPart then
		return nil
	end
	local folder = levelPart:FindFirstChild(name)
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

local function cloneWallData(wall: Formex.WallData): Formex.WallData
	return table.clone(wall)
end

local function cloneFloorData(floor: Formex.FloorData): Formex.FloorData
	local clone = table.clone(floor)
	if floor.Points then
		clone.Points = table.clone(floor.Points)
	end
	return clone
end

local function cloneObjectData(objectData: Formex.ObjectData): Formex.ObjectData
	local clone = table.clone(objectData)
	if objectData.Design then
		clone.Design = table.clone(objectData.Design)
	end
	if objectData.DesignColors then
		clone.DesignColors = table.clone(objectData.DesignColors)
	end
	if objectData.Properties then
		clone.Properties = table.clone(objectData.Properties)
	end
	return clone
end

local function capturePredictionSnapshot(plotData: Formex.PlotData, levelsTouched: {number})
	local snapshotWalls = {} :: {[number]: {[number]: Formex.WallData}}
	local snapshotFloors = {} :: {[number]: {[number]: Formex.FloorData}}
	local snapshotObjects = {} :: {[number]: {[number]: Formex.ObjectData}}
	for _, levelIndex in ipairs(levelsTouched) do
		local levelData = plotData.Levels and plotData.Levels[levelIndex]
		if levelData then
			local walls = {}
			for wallId, wall in pairs(levelData.Walls or {}) do
				walls[wallId] = cloneWallData(wall)
			end
			snapshotWalls[levelIndex] = walls

			local floors = {}
			for floorId, floor in pairs(levelData.Floors or {}) do
				floors[floorId] = cloneFloorData(floor)
			end
			snapshotFloors[levelIndex] = floors

			local objects = {}
			for objectId, objectData in pairs(levelData.Objects or {}) do
				objects[objectId] = cloneObjectData(objectData)
			end
			snapshotObjects[levelIndex] = objects
		end
	end
	return snapshotWalls, snapshotFloors, snapshotObjects
end

local function setModelHidden(state: PredictionState, model: Model, hidden: boolean)
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			if hidden then
				if not state.HiddenParts[child] then
					state.HiddenParts[child] = {
						Transparency = child.Transparency,
						CanCollide = child.CanCollide,
						CanQuery = child.CanQuery,
						CanTouch = child.CanTouch,
					}
				end
				child.Transparency = 1
				child.CanCollide = false
				child.CanQuery = false
				child.CanTouch = false
			else
				local original = state.HiddenParts[child]
				if original then
					child.Transparency = original.Transparency
					child.CanCollide = original.CanCollide
					child.CanQuery = original.CanQuery
					child.CanTouch = original.CanTouch
					state.HiddenParts[child] = nil
				end
			end
		end
	end
end

local function restoreHiddenParts(state: PredictionState)
	for part, original in pairs(state.HiddenParts) do
		if part and part.Parent then
			part.Transparency = original.Transparency
			part.CanCollide = original.CanCollide
			part.CanQuery = original.CanQuery
			part.CanTouch = original.CanTouch
		end
	end
	table.clear(state.HiddenParts)
end

local function findWallModel(plotInfo: PlotInfo, levelIndex: number, wallId: number): Model?
	local levelData = plotInfo.PlotData.Levels and plotInfo.PlotData.Levels[levelIndex]
	local wallData = levelData and levelData.Walls and levelData.Walls[wallId]
	if wallData and wallData.Part and wallData.Part:IsA("Model") then
		return wallData.Part
	end
	local folder = getLevelFolder(plotInfo.PlotPart, levelIndex, "Walls")
	if folder then
		local model = folder:FindFirstChild(tostring(wallId))
		if model and model:IsA("Model") then
			return model
		end
	end
	return nil
end

local function findFloorModel(plotInfo: PlotInfo, levelIndex: number, floorId: number): Model?
	local levelData = plotInfo.PlotData.Levels and plotInfo.PlotData.Levels[levelIndex]
	local floorData = levelData and levelData.Floors and levelData.Floors[floorId]
	if floorData and floorData.Model and floorData.Model:IsA("Model") then
		return floorData.Model
	end
	local folder = getLevelFolder(plotInfo.PlotPart, levelIndex, "Floors")
	if folder then
		local model = folder:FindFirstChild(tostring(floorId))
		if model and model:IsA("Model") then
			return model
		end
	end
	return nil
end

local function findObjectModel(plotInfo: PlotInfo, levelIndex: number, objectId: number | string): Model?
	local levelData = plotInfo.PlotData.Levels and plotInfo.PlotData.Levels[levelIndex]
	local objectData = levelData and levelData.Objects and levelData.Objects[objectId]
	if objectData and objectData.Part and objectData.Part:IsA("Model") then
		return objectData.Part
	end
	local folder = getLevelFolder(plotInfo.PlotPart, levelIndex, "Objects")
	if folder then
		local model = folder:FindFirstChild(tostring(objectId))
		if model and model:IsA("Model") then
			return model
		end
	end
	return nil
end

local function applyPrediction(plotInfo: PlotInfo, validation: any): PredictionState?
	local plotState = getPlotState(plotInfo)
	if not plotState then
		return nil
	end

	local plotData = plotState.Data
	local levelsTouched = validation.LevelsTouched or {}
	local snapshotWalls, snapshotFloors, snapshotObjects = capturePredictionSnapshot(plotData, levelsTouched)

	local state: PredictionState = {
		PlotInfo = plotInfo,
		PlotState = plotState,
		LevelsTouched = levelsTouched,
		SnapshotWalls = snapshotWalls,
		SnapshotFloors = snapshotFloors,
		SnapshotObjects = snapshotObjects,
		OriginalLevels = {},
		OriginalLevelMissing = {},
		UsedLevelSwap = false,
		RemovedWalls = {},
		RemovedFloors = {},
		RemovedObjects = {},
		HiddenParts = {},
		CreatedModels = {},
		RemovedPredictionModels = {},
		PredictedModels = {},
		OriginalNextId = plotData.NextId,
	}

	if validation.NextId then
		plotData.NextId = validation.NextId
	end

	if validation.Levels then
		plotData.Levels = plotData.Levels or {}
		for _, levelIndex in ipairs(levelsTouched) do
			local originalLevel = plotData.Levels[levelIndex]
			if originalLevel == nil then
				state.OriginalLevelMissing[levelIndex] = true
			else
				state.OriginalLevels[levelIndex] = originalLevel
			end
			local validatedLevel = validation.Levels[levelIndex]
			if validatedLevel then
				plotData.Levels[levelIndex] = validatedLevel
			end
		end
		state.UsedLevelSwap = true
	end

	local plotPart = plotInfo.PlotPart

	local function getValidatedWall(levelIndex: number, wallId: number): Formex.WallData?
		local levelData = validation.Levels and validation.Levels[levelIndex]
		return levelData and levelData.Walls and levelData.Walls[wallId] or nil
	end

	local function getValidatedFloor(levelIndex: number, floorId: number): Formex.FloorData?
		local levelData = validation.Levels and validation.Levels[levelIndex]
		return levelData and levelData.Floors and levelData.Floors[floorId] or nil
	end

	local function getValidatedObject(levelIndex: number, objectId: number | string): Formex.ObjectData?
		local levelData = validation.Levels and validation.Levels[levelIndex]
		return levelData and levelData.Objects and levelData.Objects[objectId] or nil
	end

	for _, entry in ipairs(validation.UpdatedWalls or {}) do
		local levelIndex = entry.Level
		local wallId = entry.WallId
		local wall = getValidatedWall(levelIndex, wallId)
		if wall then
			local model = wall.Part or findWallModel(plotInfo, levelIndex, wallId)
			if model then
				wall.Part = model
				Formex.Walls.Edit(wall, plotPart, false)
			end
		end
	end

	for _, entry in ipairs(validation.AddedWalls or {}) do
		local levelIndex = entry.Level
		local wallId = entry.WallId
		local wall = getValidatedWall(levelIndex, wallId)
		if wall then
			local folder = getLevelFolder(plotPart, levelIndex, "Walls")
			if folder then
				local model = Formex.Walls.Create(wall, plotPart)
				if model then
					model:SetAttribute("IsPrediction", true)
					model.Parent = folder
					table.insert(state.CreatedModels, model)
					registerPredictedModel(state, "Wall", levelIndex, wallId, model)
				end
			end
		end
	end

	for _, entry in ipairs(validation.RemovedWalls or {}) do
		local levelIndex = entry.Level
		local wallId = entry.WallId
		local model = findWallModel(plotInfo, levelIndex, wallId)
		if model then
			setModelHidden(state, model, true)
			if isPredictionModel(model) then
				table.insert(state.RemovedPredictionModels, model)
			end
		end
		local levelData = plotData.Levels and plotData.Levels[levelIndex]
		if levelData and levelData.Walls and levelData.Walls[wallId] then
			state.RemovedWalls[levelIndex] = state.RemovedWalls[levelIndex] or {}
			state.RemovedWalls[levelIndex][wallId] = levelData.Walls[wallId]
			levelData.Walls[wallId] = nil
		end
	end

	for _, entry in ipairs(validation.UpdatedFloors or {}) do
		local levelIndex = entry.Level
		local floorId = entry.FloorId
		local floor = getValidatedFloor(levelIndex, floorId)
		if floor then
			local model = floor.Model or findFloorModel(plotInfo, levelIndex, floorId)
			if model then
				floor.Model = model
				Formex.Floors.Edit(floor, plotPart, nil, plotData)
			end
		end
	end

	for _, entry in ipairs(validation.AddedFloors or {}) do
		local levelIndex = entry.Level
		local floorId = entry.FloorId
		local floor = getValidatedFloor(levelIndex, floorId)
		if floor then
			local folder = getLevelFolder(plotPart, levelIndex, "Floors")
			if folder then
				local model = Formex.Floors.Create(floor, plotPart, folder, plotData)
				if model then
					model:SetAttribute("IsPrediction", true)
					table.insert(state.CreatedModels, model)
					registerPredictedModel(state, "Floor", levelIndex, floorId, model)
				end
			end
		end
	end

	for _, entry in ipairs(validation.RemovedFloors or {}) do
		local levelIndex = entry.Level
		local floorId = entry.FloorId
		local model = findFloorModel(plotInfo, levelIndex, floorId)
		if model then
			setModelHidden(state, model, true)
			if isPredictionModel(model) then
				table.insert(state.RemovedPredictionModels, model)
			end
		end
		local levelData = plotData.Levels and plotData.Levels[levelIndex]
		if levelData and levelData.Floors and levelData.Floors[floorId] then
			state.RemovedFloors[levelIndex] = state.RemovedFloors[levelIndex] or {}
			state.RemovedFloors[levelIndex][floorId] = levelData.Floors[floorId]
			levelData.Floors[floorId] = nil
		end
	end

	for _, entry in ipairs(validation.UpdatedObjects or {}) do
		local levelIndex = entry.Level
		local objectId = entry.ObjectId
		local objectData = getValidatedObject(levelIndex, objectId)
		if objectData then
			local model = objectData.Part or findObjectModel(plotInfo, levelIndex, objectId)
			if model then
				objectData.Part = model
				Formex.Objects.EditObject(objectData, plotPart, plotData)
			end
		end
	end

	for _, entry in ipairs(validation.AddedObjects or {}) do
		local levelIndex = entry.Level
		local objectId = entry.ObjectId
		local objectData = getValidatedObject(levelIndex, objectId)
		if objectData then
			local folder = getLevelFolder(plotPart, levelIndex, "Objects")
			if folder then
				local model = Formex.Objects.CreateObject(folder, objectData, plotPart, plotData)
				if model then
					model:SetAttribute("IsPrediction", true)
					table.insert(state.CreatedModels, model)
					registerPredictedModel(state, "Object", levelIndex, objectId, model)
				end
			end
		end
	end

	for _, entry in ipairs(validation.RemovedObjects or {}) do
		local levelIndex = entry.Level
		local objectId = entry.ObjectId
		local model = findObjectModel(plotInfo, levelIndex, objectId)
		if model then
			setModelHidden(state, model, true)
			if isPredictionModel(model) then
				table.insert(state.RemovedPredictionModels, model)
			end
		end
		local levelData = plotData.Levels and plotData.Levels[levelIndex]
		if levelData and levelData.Objects and levelData.Objects[objectId] then
			state.RemovedObjects[levelIndex] = state.RemovedObjects[levelIndex] or {}
			state.RemovedObjects[levelIndex][objectId] = levelData.Objects[objectId]
			levelData.Objects[objectId] = nil
		end
	end

	for _, levelIndex in ipairs(levelsTouched) do
		local levelData = plotData.Levels and plotData.Levels[levelIndex]
		local validatedLevel = validation.Levels and validation.Levels[levelIndex]
		if levelData and levelData.Objects and validatedLevel and validatedLevel.Objects then
			for objectId, objectData in pairs(validatedLevel.Objects) do
				local current = levelData.Objects[objectId]
				if current and current.Part then
					objectData.Part = current.Part
					objectData.ObjectModel = current.ObjectModel
					objectData.SubtractModel = current.SubtractModel
					objectData.DesignParts = current.DesignParts
					Formex.Objects.EditObject(objectData, plotPart, plotData)
				end
			end
		end
	end

	if Formex.Rooms and Formex.Rooms.RebuildPlotRooms then
		Formex.Rooms.RebuildPlotRooms(Formex, plotData)
	end

	return state
end

local function nextPredictionId(): number
	predictionIdCounter -= 1
	return predictionIdCounter
end

local function buildPredictionIdMap(entries: {any}?, key: string): {[any]: number}
	local map = {}
	if not entries then
		return map
	end
	for _, entry in ipairs(entries) do
		local value = entry[key]
		if value ~= nil and map[value] == nil then
			map[value] = nextPredictionId()
		end
	end
	return map
end

local function remapEntryIds(entries: {any}?, key: string, map: {[any]: number})
	if not entries or not map then
		return
	end
	for _, entry in ipairs(entries) do
		local value = entry[key]
		local remapped = value and map[value]
		if remapped ~= nil then
			entry[key] = remapped
		end
	end
end

local function remapIdList(ids: {any}?, map: {[any]: number})
	if not ids or not map then
		return
	end
	for index, value in ipairs(ids) do
		local remapped = map[value]
		if remapped ~= nil then
			ids[index] = remapped
		end
	end
end

local function remapLevelWalls(levelData: Formex.LevelData, wallMap: {[any]: number}?)
	if wallMap and levelData.Walls then
		local remappedWalls = {}
		for wallId, wallData in pairs(levelData.Walls) do
			local newId = wallMap[wallId] or wallId
			if newId ~= wallId then
				wallData.WallId = newId
			end
			remappedWalls[newId] = wallData
		end
		levelData.Walls = remappedWalls
	end

	if wallMap and levelData.Floors then
		for _, floorData in pairs(levelData.Floors) do
			if floorData.ConnectedWalls then
				remapIdList(floorData.ConnectedWalls, wallMap)
			end
		end
	end

	if wallMap and levelData.Objects then
		for _, objectData in pairs(levelData.Objects) do
			if objectData.WallId then
				local newId = wallMap[objectData.WallId]
				if newId ~= nil then
					objectData.WallId = newId
				end
			end
		end
	end

end

local function remapLevelFloors(levelData: Formex.LevelData, floorMap: {[any]: number}?)
	if not floorMap or not levelData.Floors then
		return
	end
	local remappedFloors = {}
	for floorId, floorData in pairs(levelData.Floors) do
		local newId = floorMap[floorId] or floorId
		if newId ~= floorId then
			floorData.FloorId = newId
		end
		remappedFloors[newId] = floorData
	end
	levelData.Floors = remappedFloors

	for _, floorData in pairs(levelData.Floors) do
		if floorData.ConnectedFloors then
			remapIdList(floorData.ConnectedFloors, floorMap)
		end
	end
end

local function remapLevelObjects(levelData: Formex.LevelData, objectMap: {[any]: number}?)
	if not objectMap or not levelData.Objects then
		return
	end
	local remappedObjects = {}
	for objectId, objectData in pairs(levelData.Objects) do
		local newId = objectMap[objectId] or objectId
		if newId ~= objectId then
			objectData.ObjectId = newId
		end
		remappedObjects[newId] = objectData
	end
	levelData.Objects = remappedObjects
end

local function remapResultIds(resultValue: any, map: {[any]: number}?)
	if not map then
		return resultValue
	end
	if type(resultValue) == "table" then
		for index, value in ipairs(resultValue) do
			local remapped = map[value]
			if remapped ~= nil then
				resultValue[index] = remapped
			end
		end
		return resultValue
	end
	local remapped = map[resultValue]
	if remapped ~= nil then
		return remapped
	end
	return resultValue
end

local function remapPredictionValidation(validation: any)
	if not validation then
		return
	end

	local wallMap = buildPredictionIdMap(validation.AddedWalls, "WallId")
	local floorMap = buildPredictionIdMap(validation.AddedFloors, "FloorId")
	local objectMap = buildPredictionIdMap(validation.AddedObjects, "ObjectId")

	remapEntryIds(validation.AddedWalls, "WallId", wallMap)
	remapEntryIds(validation.UpdatedWalls, "WallId", wallMap)
	remapEntryIds(validation.RemovedWalls, "WallId", wallMap)

	remapEntryIds(validation.AddedFloors, "FloorId", floorMap)
	remapEntryIds(validation.UpdatedFloors, "FloorId", floorMap)
	remapEntryIds(validation.RemovedFloors, "FloorId", floorMap)

	remapEntryIds(validation.AddedObjects, "ObjectId", objectMap)
	remapEntryIds(validation.UpdatedObjects, "ObjectId", objectMap)
	remapEntryIds(validation.RemovedObjects, "ObjectId", objectMap)

	if validation.Levels then
		for _, levelData in pairs(validation.Levels) do
			if levelData then
				remapLevelWalls(levelData, wallMap)
				remapLevelFloors(levelData, floorMap)
				remapLevelObjects(levelData, objectMap)
			end
		end
	end

	if validation.Results then
		for _, result in ipairs(validation.Results) do
			if result.PartType == Formex.PartType.Wall then
				result.Result = remapResultIds(result.Result, wallMap)
			elseif result.PartType == Formex.PartType.Floor then
				result.Result = remapResultIds(result.Result, floorMap)
			elseif result.PartType == Formex.PartType.Object then
				result.Result = remapResultIds(result.Result, objectMap)
			end
		end
	end
end

local function normalizeChangeEntries(partType: Formex.PartType, data: any): {any}
	if type(data) ~= "table" then
		return {}
	end
	if partType == Formex.PartType.Wall then
		if data.WallId ~= nil or data.Start ~= nil or data.End ~= nil then
			return { data }
		end
	elseif partType == Formex.PartType.Floor then
		if data.FloorId ~= nil or data.Points ~= nil then
			return { data }
		end
	elseif partType == Formex.PartType.Object then
		if data.ObjectId ~= nil or data.Prefab ~= nil or data.Position ~= nil then
			return { data }
		end
	end
	return data
end

local function normalizeResultIds(resultValue: any): {any}
	if type(resultValue) == "table" then
		local ids = {}
		for _, value in ipairs(resultValue) do
			table.insert(ids, value)
		end
		return ids
	end
	if resultValue ~= nil then
		return { resultValue }
	end
	return {}
end

local function updatePredictedId(plotInfo: PlotInfo, partType: Formex.PartType, levelIndex: number, predictedId: any, serverId: any)
	if predictedId == nil or serverId == nil or predictedId == serverId then
		return
	end

	local map = predictedModelsByType[partType]
	if map then
		local predictedKey = getPredictionKey(levelIndex, predictedId)
		local serverKey = getPredictionKey(levelIndex, serverId)
		local model = map[predictedKey]
		if model then
			map[predictedKey] = nil
			map[serverKey] = model
			model.Name = tostring(serverId)
		end
	end

	local plotData = plotInfo.PlotData
	local levelData = plotData.Levels and plotData.Levels[levelIndex]
	if not levelData then
		return
	end

	local predictedKeyId = tonumber(predictedId) or predictedId
	local serverKeyId = tonumber(serverId) or serverId

	if partType == Formex.PartType.Wall then
		local walls = levelData.Walls
		local wallData = walls and walls[predictedKeyId]
		if wallData and walls then
			walls[predictedKeyId] = nil
			wallData.WallId = serverKeyId
			wallData.Level = levelIndex
			walls[serverKeyId] = wallData
		end
	elseif partType == Formex.PartType.Floor then
		local floors = levelData.Floors
		local floorData = floors and floors[predictedKeyId]
		if floorData and floors then
			floors[predictedKeyId] = nil
			floorData.FloorId = serverKeyId
			floorData.LevelIndex = levelIndex
			floors[serverKeyId] = floorData
		end
	elseif partType == Formex.PartType.Object then
		local objects = levelData.Objects
		local objectData = objects and objects[predictedKeyId]
		if objectData and objects then
			objects[predictedKeyId] = nil
			objectData.ObjectId = serverKeyId
			objectData.Level = levelIndex
			objects[serverKeyId] = objectData
		end
	end
end

local function reconcilePredictionResults(plotInfo: PlotInfo, validation: any, changes: {Formex.BuildChange}, results: {Formex.BuildChangeResult})
	if not validation or not validation.Results then
		return
	end

	local maxServerId: number? = nil
	for index, serverResult in ipairs(results) do
		local predictedResult = validation.Results[index]
		local change = changes[index]
		if predictedResult and change then
			local action = predictedResult.Action or change.Action
			local partType = predictedResult.PartType or change.PartType
			if action == Formex.BuildAction.Add and serverResult.Action == Formex.BuildAction.Add and partType then
				local entries = normalizeChangeEntries(partType, change.Data)
				local predictedIds = normalizeResultIds(predictedResult.Result)
				local serverIds = normalizeResultIds(serverResult.Result)
				local count = math.min(#entries, #predictedIds, #serverIds)
				for i = 1, count do
					local entry = entries[i]
					local levelIndex = (entry and (entry.LevelIndex or entry.Level)) or 1
					updatePredictedId(plotInfo, partType, levelIndex, predictedIds[i], serverIds[i])
					local numericId = tonumber(serverIds[i])
					if numericId then
						if not maxServerId or numericId > maxServerId then
							maxServerId = numericId
						end
					end
				end
			end
		end
	end

	if maxServerId then
		local plotData = plotInfo.PlotData
		if type(plotData.NextId) == "number" and plotData.NextId <= maxServerId then
			plotData.NextId = maxServerId + 1
		end
	end
end

local function finalizePrediction(state: PredictionState?)
	if not state then
		return
	end
	if not state.RemovedPredictionModels or #state.RemovedPredictionModels == 0 then
		return
	end

	local removedSet = {} :: {[Model]: boolean}
	for _, model in ipairs(state.RemovedPredictionModels) do
		if model then
			removedSet[model] = true
		end
	end

	for _, model in ipairs(state.RemovedPredictionModels) do
		if model and model.Parent then
			model:Destroy()
		end
	end

	for _, map in pairs(predictedModelsByType) do
		for key, entry in pairs(map) do
			if removedSet[entry] then
				map[key] = nil
			end
		end
	end
end

local function rollbackPrediction(state: PredictionState?)
	if not state then
		return
	end
	local plotInfo = state.PlotInfo
	local plotData = plotInfo.PlotData
	local plotPart = plotInfo.PlotPart

	if state.OriginalNextId then
		plotData.NextId = state.OriginalNextId
	end

	if state.UsedLevelSwap then
		plotData.Levels = plotData.Levels or {}
		for _, levelIndex in ipairs(state.LevelsTouched or {}) do
			if state.OriginalLevelMissing[levelIndex] then
				plotData.Levels[levelIndex] = nil
			else
				local originalLevel = state.OriginalLevels[levelIndex]
				if originalLevel then
					plotData.Levels[levelIndex] = originalLevel
				end
			end
		end
	else
		for levelIndex, walls in pairs(state.RemovedWalls) do
			local levelData = plotData.Levels and plotData.Levels[levelIndex]
			if levelData then
				levelData.Walls = levelData.Walls or {}
				for wallId, wallData in pairs(walls) do
					levelData.Walls[wallId] = wallData
				end
			end
		end

		for levelIndex, floors in pairs(state.RemovedFloors) do
			local levelData = plotData.Levels and plotData.Levels[levelIndex]
			if levelData then
				levelData.Floors = levelData.Floors or {}
				for floorId, floorData in pairs(floors) do
					levelData.Floors[floorId] = floorData
				end
			end
		end

		for levelIndex, objects in pairs(state.RemovedObjects) do
			local levelData = plotData.Levels and plotData.Levels[levelIndex]
			if levelData then
				levelData.Objects = levelData.Objects or {}
				for objectId, objectData in pairs(objects) do
					levelData.Objects[objectId] = objectData
				end
			end
		end
	end

	restoreHiddenParts(state)

	for _, model in ipairs(state.CreatedModels) do
		if model and model.Parent then
			model:Destroy()
		end
	end

	for _, model in pairs(state.PredictedModels) do
		for kind, map in pairs(predictedModelsByType) do
			for key, entry in pairs(map) do
				if entry == model then
					map[key] = nil
				end
			end
		end
	end

	for _, walls in pairs(state.SnapshotWalls) do
		for _, wallData in pairs(walls) do
			if wallData.Part then
				Formex.Walls.Edit(wallData, plotPart, false)
			end
		end
	end

	for _, floors in pairs(state.SnapshotFloors) do
		for _, floorData in pairs(floors) do
			if floorData.Model then
				Formex.Floors.Edit(floorData, plotPart, nil, plotData)
			end
		end
	end

	for _, objects in pairs(state.SnapshotObjects) do
		for _, objectData in pairs(objects) do
			if objectData.Part then
				Formex.Objects.EditObject(objectData, plotPart, plotData)
			end
		end
	end

	if Formex.Rooms and Formex.Rooms.RebuildPlotRooms then
		Formex.Rooms.RebuildPlotRooms(Formex, plotData)
	end
end

local function notifyPlotPartChanged(plotState: PlotSubscription, partType: Formex.PartType, levelIndex: number, partId: number?, model: Instance?, changeType: string)
    if Formex.Rooms and Formex.Rooms.RebuildPlotRooms then
        Formex.Rooms.RebuildPlotRooms(Formex, plotState.Data)
    end
    FormexClient.FireEvent("PlotPartChanged", plotState.Data.PlotId, partType, levelIndex, partId, model, changeType)
end

local function ensureLevelData(plotData: Formex.PlotData, levelIndex: number, levelPart: BasePart?): Formex.LevelData
    plotData.Levels = plotData.Levels or {}
    local levelData = plotData.Levels[levelIndex]
    if not levelData then
        levelData = {
            Walls = {},
            Floors = {},
            Objects = {},
            Part = levelPart,
        }
        plotData.Levels[levelIndex] = levelData
    elseif levelPart then
        levelData.Part = levelPart
    end
    return levelData
end

local function getChildPart(model: Model, name: string): BasePart?
    local part = model:FindFirstChild(name)
    if part and part:IsA("BasePart") then
        return part
    end
    return nil
end

local function refreshWallParts(wallData: Formex.WallData, model: Model)
    local frontName = Formex.Walls and Formex.Walls.FrontPartName or "Front"
    local backName = Formex.Walls and Formex.Walls.BackPartName or "BackSide"
    wallData.FrontPart = getChildPart(model, frontName)
    wallData.BackPart = getChildPart(model, backName)
    wallData.FrontTopPart = getChildPart(model, "FrontTop")
    wallData.BackTopPart = getChildPart(model, "BackTop")
end

local function refreshFloorParts(floorData: Formex.FloorData, model: Model)
    floorData.FloorPart = getChildPart(model, "Floor")
    floorData.FoundationPart = getChildPart(model, "Foundation")
    floorData.CeilingPart = getChildPart(model, "Ceiling")
    floorData.FloorClientPart = getChildPart(model, "Floor" .. meshClientSuffix)
    floorData.FoundationClientPart = getChildPart(model, "Foundation" .. meshClientSuffix)
    floorData.CeilingClientPart = getChildPart(model, "Ceiling" .. meshClientSuffix)
end

local function refreshObjectParts(objectData: Formex.ObjectData, model: Model)
    local objectModel = model:FindFirstChild("Object")
    objectData.ObjectModel = objectModel and objectModel:IsA("Model") and objectModel or nil
    local subtractModel = model:FindFirstChild("Subtract")
    objectData.SubtractModel = subtractModel and subtractModel:IsA("Model") and subtractModel or nil
end

local function refreshWallData(wallData: Formex.WallData, model: Model, levelIndex: number)
    local startValue = model:GetAttribute("Start") or Vector2.new(0, 0)
    local endValue = model:GetAttribute("End") or Vector2.new(0, 0)
    wallData.WallId = wallData.WallId or (tonumber(model.Name) or 0)
    wallData.Level = levelIndex
    wallData.Start = Vector2int16.new(math.round(startValue.X), math.round(startValue.Y))
    wallData.End = Vector2int16.new(math.round(endValue.X), math.round(endValue.Y))
    wallData.Height = model:GetAttribute("WallHeight") or Formex.LevelHeight
    wallData.FrontSplitHeight = model:GetAttribute("FrontSplitHeight") or 0
    wallData.BackSplitHeight = model:GetAttribute("BackSplitHeight") or 0

    local frontTopMaterial = model:GetAttribute("FrontTopMaterial") or Formex.DefaultWallMaterial
    wallData.FrontTopMaterial = frontTopMaterial
    wallData.FrontBottomMaterial = model:GetAttribute("FrontBottomMaterial") or frontTopMaterial

    local backTopMaterial = model:GetAttribute("BackTopMaterial") or frontTopMaterial
    wallData.BackTopMaterial = backTopMaterial
    wallData.BackBottomMaterial = model:GetAttribute("BackBottomMaterial") or backTopMaterial

    local frontTopColor = model:GetAttribute("FrontTopColor") or defaultColor
    wallData.FrontTopColor = frontTopColor
    wallData.FrontBottomColor = model:GetAttribute("FrontBottomColor") or frontTopColor

    local backTopColor = model:GetAttribute("BackTopColor") or frontTopColor
    wallData.BackTopColor = backTopColor
    wallData.BackBottomColor = model:GetAttribute("BackBottomColor") or backTopColor

    wallData.Part = model
    refreshWallParts(wallData, model)
end

local function refreshFloorData(floorData: Formex.FloorData, model: Model, levelIndex: number)
    floorData.FloorId = floorData.FloorId or (tonumber(model.Name) or 0)
    floorData.LevelIndex = levelIndex
    floorData.Points = Formex.DecodeFloorPoints(model:GetAttribute("Points"))
    floorData.RaiseHeight = model:GetAttribute("RaiseHeight") or 0

    local floorMaterial = model:GetAttribute("FloorMaterial") or Formex.DefaultFloorMaterial
    floorData.FloorMaterial = floorMaterial
    floorData.CeilingMaterial = model:GetAttribute("CeilingMaterial") or floorMaterial
    floorData.FoundationMaterial = model:GetAttribute("FoundationMaterial") or Formex.DefaultFoundationMaterial

    local floorColor = model:GetAttribute("FloorColor") or defaultColor
    floorData.FloorColor = floorColor
    floorData.CeilingColor = model:GetAttribute("CeilingColor") or floorColor
    floorData.FoundationColor = model:GetAttribute("FoundationColor") or floorColor

    floorData.Model = model
    refreshFloorParts(floorData, model)
end

local function refreshObjectData(objectData: Formex.ObjectData, model: Model, levelIndex: number)
    objectData.ObjectId = objectData.ObjectId or model.Name
    objectData.Level = levelIndex
    objectData.Position = model:GetAttribute("Position") or objectData.Position or Vector3.new(0, 0, 0)
    objectData.Rotation = model:GetAttribute("Rotation") or objectData.Rotation or Vector3.new(0, 0, 0)
    objectData.Side = model:GetAttribute("Side") or objectData.Side or Formex.ObjectSide.Front
    objectData.WallId = model:GetAttribute("WallId")
    objectData.IsPortal = model:GetAttribute("IsPortal") == true
    objectData.PrefabName = model:GetAttribute("PrefabName") or objectData.PrefabName
    if objectData.PrefabName and objectData.PrefabName ~= "" then
        objectData.Prefab = Formex.Objects.GetPrefab(objectData.PrefabName)
    end
    local encodedDesign = model:GetAttribute("Design")
    if encodedDesign then
        local design, colors = Formex.Objects.DecodeDesign(encodedDesign)
        objectData.Design = design
        objectData.DesignColors = colors
    elseif not objectData.Design then
        objectData.Design = {}
        objectData.DesignColors = {}
    end
    objectData.Part = model
    objectData.Design = objectData.Design or {}
    objectData.DesignColors = objectData.DesignColors or {}
    objectData.Properties = objectData.Properties or {}
    refreshObjectParts(objectData, model)
end

local function disconnectConnections(connections: {RBXScriptConnection})
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
end

local function subscribeWallModel(plotState: PlotSubscription, levelIndex: number, model: Model)
    if plotState.Walls[model] then return end

    local wallId = tonumber(model.Name)
    if not wallId then return end
    if not isPredictionModel(model) then
        reconcilePredictedModel("Wall", levelIndex, wallId, model)
    end

    local levelData = ensureLevelData(plotState.Data, levelIndex, nil)
    local wallData = levelData.Walls[wallId] or {
        WallId = wallId,
        Level = levelIndex,
        Start = Vector2int16.new(0, 0),
        End = Vector2int16.new(0, 0),
    } :: Formex.WallData
    levelData.Walls[wallId] = wallData
    refreshWallData(wallData, model, levelIndex)

    local subscription: ModelSubscription = {
        Connections = {},
    }
    plotState.Walls[model] = subscription

    table.insert(subscription.Connections, model.AttributeChanged:Connect(function()
        refreshWallData(wallData, model, levelIndex)
        notifyPlotPartChanged(plotState, Formex.PartType.Wall, levelIndex, wallId, model, "Attribute")
    end))

    table.insert(subscription.Connections, model.ChildAdded:Connect(function(child)
        if child:IsA("BasePart") then
            refreshWallParts(wallData, model)
            notifyPlotPartChanged(plotState, Formex.PartType.Wall, levelIndex, wallId, model, "Parts")
        end
    end))

    table.insert(subscription.Connections, model.ChildRemoved:Connect(function(child)
        if child:IsA("BasePart") then
            refreshWallParts(wallData, model)
            notifyPlotPartChanged(plotState, Formex.PartType.Wall, levelIndex, wallId, model, "Parts")
        end
    end))

    notifyPlotPartChanged(plotState, Formex.PartType.Wall, levelIndex, wallId, model, "Added")
end

local function unsubscribeWallModel(plotState: PlotSubscription, levelIndex: number, model: Model)
    local subscription = plotState.Walls[model]
    if not subscription then
        return
    end

    disconnectConnections(subscription.Connections)
    plotState.Walls[model] = nil

    local wallId = tonumber(model.Name)
    local levelData = plotState.Data.Levels[levelIndex]
    if levelData and wallId then
        levelData.Walls[wallId] = nil
    end

    notifyPlotPartChanged(plotState, Formex.PartType.Wall, levelIndex, wallId, model, "Removed")
end

local function subscribeFloorModel(plotState: PlotSubscription, levelIndex: number, model: Model)
    if plotState.Floors[model] then return end

    local floorId = tonumber(model.Name)
    if not floorId then return end
    if not isPredictionModel(model) then
        reconcilePredictedModel("Floor", levelIndex, floorId, model)
    end

    local levelData = ensureLevelData(plotState.Data, levelIndex, nil)
    local floorData = levelData.Floors[floorId] or {
        FloorId = floorId,
        LevelIndex = levelIndex,
        Points = {},
        RaiseHeight = 0,
    } :: Formex.FloorData
    levelData.Floors[floorId] = floorData

    local subscription: FloorSubscription = {
        Connections = {},
        PointsKey = model:GetAttribute("Points") or "",
        RaiseHeight = model:GetAttribute("RaiseHeight") or 0,
    }
    plotState.Floors[model] = subscription

    local function markFloorDebug(key: string, value: any)
        model:SetAttribute(key, value)
    end

    local function hasClientMeshes(): boolean
        return getChildPart(model, "Floor" .. meshClientSuffix) ~= nil
            or getChildPart(model, "Foundation" .. meshClientSuffix) ~= nil
            or getChildPart(model, "Ceiling" .. meshClientSuffix) ~= nil
    end

    local function ensureClientMeshes(reason: string)
        if hasClientMeshes() then
            return
        end
        if not floorData.Points or #floorData.Points < 3 then
            markFloorDebug("ClientMeshEnsureLast", "SkippedNoPoints:" .. reason)
            return
        end
        local ensureCount = (model:GetAttribute("ClientMeshEnsureCount") or 0) + 1
        markFloorDebug("ClientMeshEnsureCount", ensureCount)
        markFloorDebug("ClientMeshEnsureLast", reason)
        markFloorDebug("ClientMeshEnsurePointsKey", model:GetAttribute("Points") or "")
        markFloorDebug("ClientMeshEnsureRaiseHeight", model:GetAttribute("RaiseHeight") or 0)
        markFloorDebug("ClientMeshEnsureAt", os.clock())
        Formex.Floors.RenderClientMeshes(model, plotState.PlotPart)
        refreshFloorParts(floorData, model)
    end

    local function refreshGeometry()
        local pointsKey = model:GetAttribute("Points") or ""
        local raiseHeight = model:GetAttribute("RaiseHeight") or 0
        if pointsKey == subscription.PointsKey and raiseHeight == subscription.RaiseHeight then
            ensureClientMeshes("GeometryUnchanged")
            return
        end
        subscription.PointsKey = pointsKey
        subscription.RaiseHeight = raiseHeight
        markFloorDebug("ClientMeshLastGeometryChange", os.clock())
        Formex.Floors.RenderClientMeshes(model, plotState.PlotPart)
        refreshFloorParts(floorData, model)
    end

    local function refreshAppearance()
        Formex.Floors.ApplyClientMaterials(model)
        refreshFloorParts(floorData, model)
    end

    local function refreshData()
        refreshFloorData(floorData, model, levelIndex)
    end

    refreshData()
    markFloorDebug("ClientFloorSubscribed", true)
    markFloorDebug("ClientFloorSubscribedAt", os.clock())
    Formex.Floors.RenderClientMeshes(model, plotState.PlotPart)
    refreshAppearance()
    refreshData()
    subscription.PointsKey = model:GetAttribute("Points") or ""
    subscription.RaiseHeight = model:GetAttribute("RaiseHeight") or 0
    ensureClientMeshes("InitialSubscribe")

    table.insert(subscription.Connections, model.AttributeChanged:Connect(function(attributeName)
        refreshData()
        if floorGeometryAttributes[attributeName] then
            refreshGeometry()
        elseif floorAppearanceAttributes[attributeName] then
            refreshAppearance()
        end
        notifyPlotPartChanged(plotState, Formex.PartType.Floor, levelIndex, floorId, model, "Attribute")
    end))

    table.insert(subscription.Connections, model.ChildAdded:Connect(function(child)
        if child:IsA("BasePart") then
            refreshFloorParts(floorData, model)
            notifyPlotPartChanged(plotState, Formex.PartType.Floor, levelIndex, floorId, model, "Parts")
        end
    end))

    table.insert(subscription.Connections, model.ChildRemoved:Connect(function(child)
        if child:IsA("BasePart") then
            refreshFloorParts(floorData, model)
            notifyPlotPartChanged(plotState, Formex.PartType.Floor, levelIndex, floorId, model, "Parts")
        end
    end))

    notifyPlotPartChanged(plotState, Formex.PartType.Floor, levelIndex, floorId, model, "Added")
end

local function unsubscribeFloorModel(plotState: PlotSubscription, levelIndex: number, model: Model)
    local subscription = plotState.Floors[model]
    if not subscription then
        return
    end

    disconnectConnections(subscription.Connections)
    plotState.Floors[model] = nil

    local floorId = tonumber(model.Name)
    local levelData = plotState.Data.Levels[levelIndex]
    if levelData and floorId then
        levelData.Floors[floorId] = nil
    end

    Formex.Floors.DestroyClientMeshes(model)
    notifyPlotPartChanged(plotState, Formex.PartType.Floor, levelIndex, floorId, model, "Removed")
end

local function subscribeObjectModel(plotState: PlotSubscription, levelIndex: number, model: Model)
    if plotState.Objects[model] then
        return
    end

    local levelData = ensureLevelData(plotState.Data, levelIndex, nil)
    local objectKey = tonumber(model.Name) or 0
    if not isPredictionModel(model) then
        reconcilePredictedModel("Object", levelIndex, objectKey, model)
    end
    local objectData = levelData.Objects[objectKey] or {
        ObjectId = model.Name,
        Level = levelIndex,
        Position = Vector3.new(0, 0, 0),
        Rotation = Vector3.new(0, 0, 0),
        Side = Formex.ObjectSide.Front,
        Design = {},
        Properties = {},
    } :: Formex.ObjectData
    levelData.Objects[objectKey] = objectData
    refreshObjectData(objectData, model, levelIndex)

    local subscription: ModelSubscription = {
        Connections = {},
    }
    plotState.Objects[model] = subscription

    table.insert(subscription.Connections, model.AttributeChanged:Connect(function()
        refreshObjectData(objectData, model, levelIndex)
        notifyPlotPartChanged(plotState, Formex.PartType.Object, levelIndex, objectKey, model, "Attribute")
    end))

    table.insert(subscription.Connections, model.ChildAdded:Connect(function()
        refreshObjectParts(objectData, model)
        notifyPlotPartChanged(plotState, Formex.PartType.Object, levelIndex, objectKey, model, "Parts")
    end))

    table.insert(subscription.Connections, model.ChildRemoved:Connect(function()
        refreshObjectParts(objectData, model)
        notifyPlotPartChanged(plotState, Formex.PartType.Object, levelIndex, objectKey, model, "Parts")
    end))

    notifyPlotPartChanged(plotState, Formex.PartType.Object, levelIndex, objectKey, model, "Added")
end

local function unsubscribeObjectModel(plotState: PlotSubscription, levelIndex: number, model: Model)
    local subscription = plotState.Objects[model]
    if not subscription then
        return
    end

    disconnectConnections(subscription.Connections)
    plotState.Objects[model] = nil

    local levelData = plotState.Data.Levels[levelIndex]
    if levelData then
        local objectKey = tonumber(model.Name) or 0
        levelData.Objects[objectKey] = nil
    end

    notifyPlotPartChanged(plotState, Formex.PartType.Object, levelIndex, tonumber(model.Name) or 0, model, "Removed")
end

local function watchModelFolder(plotState: PlotSubscription, levelIndex: number, folder: Folder, kind: string)
    local function addModel(model: Model)
        if kind == "Walls" then
            subscribeWallModel(plotState, levelIndex, model)
        elseif kind == "Floors" then
            subscribeFloorModel(plotState, levelIndex, model)
        elseif kind == "Objects" then
            subscribeObjectModel(plotState, levelIndex, model)
        end
    end

    local function removeModel(model: Model)
        if kind == "Walls" then
            unsubscribeWallModel(plotState, levelIndex, model)
        elseif kind == "Floors" then
            unsubscribeFloorModel(plotState, levelIndex, model)
        elseif kind == "Objects" then
            unsubscribeObjectModel(plotState, levelIndex, model)
        end
    end

    local connections = {
        folder.ChildAdded:Connect(function(child)
            if child:IsA("Model") then
                addModel(child)
            end
        end),
        folder.ChildRemoved:Connect(function(child)
            if child:IsA("Model") then
                removeModel(child)
            end
        end),
    }

    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Model") then
            addModel(child)
        end
    end

    return connections
end

local function watchLevelPart(plotState: PlotSubscription, levelPart: BasePart)
    if plotState.Levels[levelPart] then
        return
    end

    local levelIndex = tonumber(levelPart.Name)
    if not levelIndex then
        return
    end

    ensureLevelData(plotState.Data, levelIndex, levelPart)

    local levelSubscription: LevelSubscription = {
        Connections = {},
        Folders = {},
    }
    plotState.Levels[levelPart] = levelSubscription

    local function attachFolder(folder: Instance)
        if not folder:IsA("Folder") then return end

        local name = folder.Name
        if levelSubscription.Folders[name] then return end

        levelSubscription.Folders[name] = watchModelFolder(plotState, levelIndex, folder, name)
    end

    local function detachFolder(folder: Instance)
        if not folder:IsA("Folder") then
            return
        end

        local name = folder.Name
        local connections = levelSubscription.Folders[name]
        if connections then
            disconnectConnections(connections)
            levelSubscription.Folders[name] = nil
        end

        for _, child in ipairs(folder:GetChildren()) do
            if child:IsA("Model") then
                if name == "Walls" then
                    unsubscribeWallModel(plotState, levelIndex, child)
                elseif name == "Floors" then
                    unsubscribeFloorModel(plotState, levelIndex, child)
                elseif name == "Objects" then
                    unsubscribeObjectModel(plotState, levelIndex, child)
                end
            end
        end
    end

    table.insert(levelSubscription.Connections, levelPart.ChildAdded:Connect(attachFolder))
    table.insert(levelSubscription.Connections, levelPart.ChildRemoved:Connect(detachFolder))

    for _, child in ipairs(levelPart:GetChildren()) do
        attachFolder(child)
    end
end

local function unwatchLevelPart(plotState: PlotSubscription, levelPart: BasePart)
    local levelSubscription = plotState.Levels[levelPart]
    if not levelSubscription then return end

    local levelIndex = tonumber(levelPart.Name) or 0
    for _, child in ipairs(levelPart:GetChildren()) do
        if child:IsA("Folder") then
            if child.Name == "Walls" then
                for _, model in ipairs(child:GetChildren()) do
                    if model:IsA("Model") then
                        unsubscribeWallModel(plotState, levelIndex, model)
                    end
                end
            elseif child.Name == "Floors" then
                for _, model in ipairs(child:GetChildren()) do
                    if model:IsA("Model") then
                        unsubscribeFloorModel(plotState, levelIndex, model)
                    end
                end
            elseif child.Name == "Objects" then
                for _, model in ipairs(child:GetChildren()) do
                    if model:IsA("Model") then
                        unsubscribeObjectModel(plotState, levelIndex, model)
                    end
                end
            end
        end
    end

    for _, connections in pairs(levelSubscription.Folders) do
        disconnectConnections(connections)
    end
    disconnectConnections(levelSubscription.Connections)
    plotState.Levels[levelPart] = nil

    plotState.Data.Levels[levelIndex] = nil
end

local function watchPlotStructure(plotState: PlotSubscription)
    local plotPart = plotState.PlotPart

    table.insert(plotState.Connections, plotPart.ChildAdded:Connect(function(child)
        if child:IsA("BasePart") then
            watchLevelPart(plotState, child)
        end
    end))

    table.insert(plotState.Connections, plotPart.ChildRemoved:Connect(function(child)
        if child:IsA("BasePart") then
            unwatchLevelPart(plotState, child)
        end
    end))
    
    for _, child in ipairs(plotPart:GetChildren()) do
        if child:IsA("BasePart") then
            watchLevelPart(plotState, child)
        end
    end
end

local function subscribeToPlot(plotPart: Part)
    local existing = plotSubscriptions[plotPart]
    if existing then
        return existing.Info
    end

    local plotId = plotPart:GetAttribute("PlotId") or 0

    local ownerUserId = plotPart:GetAttribute("OwnerUserId") or 0
    local plotName = plotPart:GetAttribute("PlotName") or "Unnamed"
    local ownerName = plotPart:GetAttribute("OwnerName") or "Unknown Player"
    local saveId = plotPart:GetAttribute("SaveId") or 0
    local lastPlayed = plotPart:GetAttribute("LastPlayed") or 0
    local levelsUnlocked = plotPart:GetAttribute("LevelsUnlocked") or 0
    local segmentsUnlocked = plotPart:GetAttribute("SegmentsUnlocked") or 0
    local myPermission = plotPart:GetAttribute(permissionId) or "Guest"

    local permissions = {}
    for key, value in plotPart:GetAttributes() do
        if string.sub(key, 1, 2) == "U_" then
            local id = tonumber(string.sub(key, 3))
            if id then
                permissions[id] = value
            end
        end
    end

    local plotData: Formex.PlotData = {
        PlotId = plotId,
        UserId = ownerUserId,
        SaveId = saveId,
        Name = plotName,
        LastPlayed = lastPlayed,
        NextId = 1,
        FoundationMaterial = Formex.DefaultFoundationMaterial,
        Levels = {},
        Rooms = {},
        LevelsUnlocked = levelsUnlocked,
        SegmentsUnlocked = segmentsUnlocked,
        Permissions = permissions,
    }

    local info: PlotInfo = {
        IsValid = true,
        PlotId = plotId,
        PlotPart = plotPart,
        Name = plotName,
        OwnerUserId = ownerUserId,
        OwnerName = ownerName,
        SaveId = saveId,
        MyPermission = myPermission,
        LastPlayed = lastPlayed,
        IsClaimed = ownerUserId ~= 0,
        IsMine = ownerUserId == localPlayer.UserId,
        LevelsUnlocked = levelsUnlocked,
        SegmentsUnlocked = segmentsUnlocked,
        CanUndo = plotPart:GetAttribute("CanUndo") or false,
        CanRedo = plotPart:GetAttribute("CanRedo") or false,
        Properties = {},
        PlotData = plotData,
    }
    FormexClient.Plots[plotId] = info

    local plotState: PlotSubscription = {
        PlotPart = plotPart,
        Info = info,
        Data = plotData,
        Connections = {},
        Levels = {},
        Walls = {},
        Floors = {},
        Objects = {},
    }
    plotSubscriptions[plotPart] = plotState

    table.insert(plotState.Connections, plotPart:GetAttributeChangedSignal("PlotName"):Connect(function()
        local value = plotPart:GetAttribute("PlotName") or "Unnamed"
        info.Name = value
        plotData.Name = value
        notifyPlotChange(plotId)
    end))

    table.insert(plotState.Connections, plotPart:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
        local value = plotPart:GetAttribute("OwnerUserId") or 0
        info.OwnerUserId = value
        info.IsClaimed = value ~= 0
        info.IsMine = value == localPlayer.UserId
        plotData.UserId = value
        notifyPlotChange(plotId)
    end))

    table.insert(plotState.Connections, plotPart:GetAttributeChangedSignal("OwnerName"):Connect(function()
        info.OwnerName = plotPart:GetAttribute("OwnerName") or "Unknown Player"
        notifyPlotChange(plotId)
    end))

    table.insert(plotState.Connections, plotPart:GetAttributeChangedSignal("SaveId"):Connect(function()
        local value = plotPart:GetAttribute("SaveId") or 0
        info.SaveId = value
        plotData.SaveId = value
        notifyPlotChange(plotId)
    end))

    table.insert(plotState.Connections, plotPart:GetAttributeChangedSignal("LastPlayed"):Connect(function()
        local value = plotPart:GetAttribute("LastPlayed") or 0
        info.LastPlayed = value
        plotData.LastPlayed = value
        notifyPlotChange(plotId)
    end))

    table.insert(plotState.Connections, plotPart:GetAttributeChangedSignal("LevelsUnlocked"):Connect(function()
        local value = plotPart:GetAttribute("LevelsUnlocked") or 0
        info.LevelsUnlocked = value
        plotData.LevelsUnlocked = value
        notifyPlotChange(plotId)
    end))

    table.insert(plotState.Connections, plotPart:GetAttributeChangedSignal("SegmentsUnlocked"):Connect(function()
        local value = plotPart:GetAttribute("SegmentsUnlocked") or 0
        info.SegmentsUnlocked = value
        plotData.SegmentsUnlocked = value
        if Formex.Rooms and Formex.Rooms.RebuildPlotRooms then
            Formex.Rooms.RebuildPlotRooms(Formex, plotData)
        end
        notifyPlotChange(plotId)
    end))

    table.insert(plotState.Connections, plotPart:GetAttributeChangedSignal("CanUndo"):Connect(function()
        info.CanUndo = plotPart:GetAttribute("CanUndo") or false
        notifyPlotChange(plotId)
    end))

    table.insert(plotState.Connections, plotPart:GetAttributeChangedSignal("CanRedo"):Connect(function()
        info.CanRedo = plotPart:GetAttribute("CanRedo") or false
        notifyPlotChange(plotId)
    end))

    table.insert(plotState.Connections, plotPart.AttributeChanged:Connect(function(attributeName)
        if string.sub(attributeName, 1, 2) ~= "U_" then
            return
        end
        local id = tonumber(string.sub(attributeName, 3))
        if not id then
            return
        end
        local value = plotPart:GetAttribute(attributeName)
        if value == nil then
            plotData.Permissions[id] = nil
        else
            plotData.Permissions[id] = value
        end
        if attributeName == permissionId then
            info.MyPermission = value or "Guest"
            notifyPlotChange(plotId)
        end
    end))

    watchPlotStructure(plotState)
    if Formex.Rooms and Formex.Rooms.RebuildPlotRooms then
        Formex.Rooms.RebuildPlotRooms(Formex, plotData)
    end
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

function FormexClient.PlotLoad(saveId: number?)
    local result, message = FormexFunctions:InvokeServer(Formex.Function.PlotLoad, saveId)
    if result == false then
        warn("PlotLoad failed:", message)
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

function FormexClient.BuildTransaction(changes: {Formex.BuildChange}, selection: Formex.SelectionSnapshot?): {Formex.BuildChangeResult}?
	local plotInfo = FormexClient.CurrentPlot
	if not plotInfo or not plotInfo.IsValid then
		return nil
	end
	if not changes or #changes == 0 then
		return nil
	end

	local validation = Formex.IsTransactionValid(plotInfo.PlotData, changes)
	if not validation or validation.IsValid ~= true then
		return nil
	end

	remapPredictionValidation(validation)
	local prediction = applyPrediction(plotInfo, validation)
	local results, _message = FormexFunctions:InvokeServer(Formex.Function.BuildTransaction, changes, selection)
	if not results then
		warn("BuildTransaction rolling back prediction due to server rejection")
		rollbackPrediction(prediction)
		return nil
	end
	reconcilePredictionResults(plotInfo, validation, changes, results)
	finalizePrediction(prediction)

	return results
end

function FormexClient.CanUndo(): boolean
    return FormexFunctions:InvokeServer(Formex.Function.CanUndo)
end

function FormexClient.CanRedo(): boolean
    return FormexFunctions:InvokeServer(Formex.Function.CanRedo)
end

function FormexClient.Undo(selection: Formex.SelectionSnapshot?): (boolean, string?, Formex.SelectionSnapshot?)
    local result, message, undoSelection = FormexFunctions:InvokeServer(Formex.Function.Undo, selection)
    if result == false then
        warn("Undo failed:", message)
    end
    return result, message, undoSelection
end

function FormexClient.Redo(selection: Formex.SelectionSnapshot?): (boolean, string?, Formex.SelectionSnapshot?)
    local result, message, redoSelection = FormexFunctions:InvokeServer(Formex.Function.Redo, selection)
    if result == false then
        warn("Redo failed:", message)
    end
    return result, message, redoSelection
end


return FormexClient
