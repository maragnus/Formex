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

local function notifyPlotPartChanged(plotState: PlotSubscription, partType: Formex.PartType, levelIndex: number, partId: number?, model: Instance?, changeType: string)
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

function FormexClient.BuildWall(wall: Formex.WallData | {Formex.WallData}, action: Formex.BuildAction, selection: Formex.SelectionSnapshot?): Formex.WallData | {Formex.WallData}
    return FormexFunctions:InvokeServer(Formex.Function.BuildWall, wall, action, selection)
end

function FormexClient.BuildFloor(floor: Formex.FloorData | {Formex.FloorData}, action: Formex.BuildAction, selection: Formex.SelectionSnapshot?): Formex.FloorData | {Formex.FloorData}
    return FormexFunctions:InvokeServer(Formex.Function.BuildFloor, floor, action, selection)
end

function FormexClient.BuildObject(wall: Formex.ObjectData, action: Formex.BuildAction, selection: Formex.SelectionSnapshot?): Formex.ObjectData
    return FormexFunctions:InvokeServer(Formex.Function.BuildObject, wall, action, selection)
end

function FormexClient.BuildTransaction(changes: {Formex.BuildChange}, selection: Formex.SelectionSnapshot?): {Formex.BuildChangeResult}?
    return FormexFunctions:InvokeServer(Formex.Function.BuildTransaction, changes, selection)
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
