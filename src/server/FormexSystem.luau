--!strict

local Formex = require(script.Parent:FindFirstChild("FormexServer"))
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")

local FormexSystem = {}

FormexSystem.Formex = Formex

FormexSystem.Plots = {} :: { [number]: BasePart } -- [plotId]: BasePart
FormexSystem.PlotData = {} :: { [number]: Formex.PlotData } -- [plotId]: Formex.PlotData
FormexSystem.PlayerToPlot = {} :: {[number]: number} -- [userId]: plotId
FormexSystem.PlotToPlayer = {} :: {[number]: number} -- [plotId]: userId

FormexSystem.PlotDataStore = DataStoreService:GetDataStore("FormexPlotData")

function FormexSystem.GetPlayerCurrentPlot(player: Player) : (Formex.PlotData?, Formex.Permission)
    local plotId = player:GetAttribute("CurrentPlotId") or 0
    if not plotId or plotId == 0 then
        return nil, nil
    end

    local plotData = FormexSystem.PlotData[plotId]
    return plotData, plotData.Permissions[player.UserId] or Formex.Permission.Guest
end

function FormexSystem.UpdatePlotAttributes(plotId: number)
    local plotPart = FormexSystem.Plots[plotId]
    local plotData = FormexSystem.PlotData[plotId]
    if not plotPart or not plotData then return end

    local userId = plotData.UserId
    local ownerPlayer = userId and userId ~= 0 and Players:GetPlayerByUserId(userId)
    local ownerName = userId and ownerPlayer and ownerPlayer.Name or ""
    local plotName = plotData.Name or (ownerPlayer and ownerName .. "'s Plot") or "Unclaimed Plot"
    local permissions = plotData.Permissions or {}

    if userId and userId ~= 0 then
        permissions[userId] = "Owner"
    end
    plotData.Permissions = permissions

    plotPart:SetAttribute("OwnerUserId", plotData.UserId or 0)
    plotPart:SetAttribute("OwnerName", ownerName)
    plotPart:SetAttribute("PlotName", plotName)
    plotPart:SetAttribute("SaveId", plotData.SaveId or 0)
    plotPart:SetAttribute("LastPlayed", plotData.LastPlayed or 0)
    plotPart:SetAttribute("LevelsUnlocked", plotData.LevelsUnlocked or 1)
    plotPart:SetAttribute("SegmentsUnlocked", plotData.SegmentsUnlocked or 0)

    -- Update permission attributes
    for permissionUserId, permission in permissions do
        plotPart:SetAttribute("U_" .. tostring(permissionUserId), permission)
    end

    -- Remove outdated permission attributes
    for key, value in plotPart:GetAttributes() do
        if string.sub(key, 1, 2) == "U_" then            
            local pid = tonumber(string.sub(key, 3))
            if pid and not permissions[pid] then
                plotPart:SetAttribute(key, nil)
            end
        end
    end
end

local function ensureFolder(parent: Instance, name: string): Folder
    local existing = parent:FindFirstChild(name)
    if existing and existing:IsA("Folder") then
        return existing
    end

    local folder = Instance.new("Folder")
    folder.Name = name
    folder.Parent = parent
    return folder
end

local function configureLevelPart(levelPart: BasePart, plotPart: BasePart, levelIndex: number)
    levelPart.Anchored = true
    levelPart.CanCollide = false
    levelPart.CanTouch = false
    levelPart.CanQuery = false
    levelPart.CastShadow = false
    levelPart.Transparency = 1
    levelPart.Material = Enum.Material.Air
    levelPart.Position = plotPart.Position + Vector3.new(0, Formex.LevelHeight * (levelIndex - 1), 0)
    levelPart.Size = Vector3.new(plotPart.Size.X, Formex.LevelHeight, plotPart.Size.Z)
end

function FormexSystem.CreateLevelPlaceholders(plotPart: BasePart)
    local totalLevels = Formex.MaxPlotSize.Levels + 1
    for levelIndex = 1, totalLevels do
        local levelPart = plotPart:FindFirstChild(tostring(levelIndex))
        if not (levelPart and levelPart:IsA("BasePart")) then
            levelPart = Instance.new("Part")
            levelPart.Name = tostring(levelIndex)
            levelPart.Parent = plotPart
        end

        configureLevelPart(levelPart, plotPart, levelIndex)

        ensureFolder(levelPart, "Floors")
        ensureFolder(levelPart, "Walls")
        ensureFolder(levelPart, "Objects")
    end
end

function FormexSystem.ClearPlot(plotPart: BasePart)
    plotPart:ClearAllChildren()
end

function FormexSystem.UnassignPlotToPlayer(player: Player)
    local userId = player.UserId
    local plotId = FormexSystem.PlayerToPlot[userId] or 0
    if plotId == 0 then return end

    FormexSystem.SavePlot(plotId)

    FormexSystem.ClearPlot(FormexSystem.Plots[plotId])

    FormexSystem.PlotToPlayer[plotId] = nil
    FormexSystem.PlayerToPlot[userId] = nil
    player:SetAttribute("MyPlotId", 0)

    local plotData = FormexSystem.PlotData[plotId]
    plotData.UserId = 0
    plotData.SaveId = 0
    plotData.Name = "Unclaimed Plot"
    plotData.LastPlayed = 0
    plotData.NextId = 1
    plotData.Levels = {}
    plotData.LevelsUnlocked = 0
    plotData.SegmentsUnlocked = 0
    plotData.Permissions = {}
    FormexSystem.UpdatePlotAttributes(plotId)

    return true
end

function FormexSystem.AssignPlotToPlayer(player: Player, plotId: number)
    if FormexSystem.PlotToPlayer[plotId] then
        return false, "Plot already claimed"
    end

    FormexSystem.UnassignPlotToPlayer(player)

    plotId = plotId or 0
    if plotId == 0 then return end

    local userId = player.UserId
    local plotName = player.Name .. "'s Plot"

    FormexSystem.PlayerToPlot[userId] = plotId
    FormexSystem.PlotToPlayer[plotId] = userId
    player:SetAttribute("MyPlotId", plotId)

    local plotData = FormexSystem.PlotData[plotId]
    plotData.UserId = player.UserId
    plotData.SaveId = 0
    plotData.Name = plotName
    plotData.LastPlayed = 0
    plotData.NextId = 1
    plotData.Levels = {}
    plotData.LevelsUnlocked = 1
    plotData.SegmentsUnlocked = 0
    plotData.Permissions = {}
    FormexSystem.UpdatePlotAttributes(plotId)

    local plotPart = FormexSystem.Plots[plotId]
    if plotPart then
        FormexSystem.CreateLevelPlaceholders(plotPart)
    end
    
    return true
end

function FormexSystem.SetPlayerCurrentPlot(player, plotId)
    plotId = plotId or 0
    player:SetAttribute("CurrentPlotId", plotId)
end

function FormexSystem.RegisterPlot(plotPart: Part)
    local plotId = #FormexSystem.Plots + 1
    FormexSystem.Plots[plotId] = plotPart
    plotPart.Transparency = 1
    plotPart.Anchored = true
    plotPart.Size = Vector3.new(Formex.MaxPlotSize.X, 1, Formex.MaxPlotSize.Z)
    plotPart.CanCollide = false
    plotPart.CanTouch = false
    plotPart.CanQuery = false
    plotPart.Material = Enum.Material.Air
    plotPart.CastShadow = false

    CollectionService:AddTag(plotPart, "FormexPlot")

    plotPart.Name = "Plot" .. tostring(plotId)
    plotPart:SetAttribute("PlotId", plotId)

    FormexSystem.PlotData[plotId] = {
        PlotId = plotId,
        UserId = 0,
        SaveId = 0,
        Name = "Unclaimed Plot",
        LastPlayed = 0,
        NextId = 1,
        Levels = {},
        LevelsUnlocked = 0,
        SegmentsUnlocked = 0,
        Permissions = {},
    }
    FormexSystem.UpdatePlotAttributes(plotId)
end

local function fixNumbericDictionary(data: {[string]: any} | nil): {[number]: any}
    if not data then return {} end
    local fixedData: {[number]: any} = {}
    for key, value in data do
        local keyNumber = tonumber(key)
        if keyNumber then
            fixedData[keyNumber] = value
        end
    end
    return fixedData
end

local function ensurePlotNextId(plotData: Formex.PlotData)
    local maxId = Formex.Serialization.GetMaxPartId(plotData.Levels)
    local desired = math.max(maxId + 1, 1)
    if not plotData.NextId or plotData.NextId < desired then
        plotData.NextId = desired
    end
end

local saveQueue = {} :: {[number]: number}

function FormexSystem.QueueSave(plotId: number)
    if not saveQueue[plotId] then
        saveQueue[plotId] = time()
    end
end

function FormexSystem.SavePlot(plotId: number)
    local plotData = FormexSystem.PlotData[plotId]
    if not plotData or plotData.SaveId == 0 then return end

    local userId = FormexSystem.PlotToPlayer[plotId] or plotData.UserId
    if not userId or userId == 0 then return end

    plotData.LastPlayed = os.time()
    plotData.LevelsUnlocked = math.max(plotData.LevelsUnlocked or 1, 1)
    local segmentsMask = plotData.SegmentsUnlocked
    if segmentsMask == nil or segmentsMask == 0 then
        segmentsMask = Formex.DefaultSegmentsUnlocked
    end
    plotData.SegmentsUnlocked = segmentsMask

    ensurePlotNextId(plotData)

    -- Ensure owner is in permissions
    plotData.Permissions[userId] = Formex.Permission.Owner

    -- Associate editors with the save data metadata
    local userMetaData = {}
    for id, permission in plotData.Permissions do
        local idNumber = tonumber(id)
        if idNumber and (permission == Formex.Permission.Manager or permission == Formex.Permission.Owner) then
            table.insert(userMetaData, idNumber)
        end
    end

    local levelData = Formex.Serialization.SerializeLevelData(plotData.Levels)

    local key = tostring(userId) .. ":" .. tostring(plotData.SaveId)
    local success, err = pcall(function()
        -- Save main plot data
        FormexSystem.PlotDataStore:SetAsync(key, {
            PlotId = plotId,
            UserId = userId,
            SaveId = plotData.SaveId,
            Name = plotData.Name,
            LastPlayed = plotData.LastPlayed,
            NextId = plotData.NextId,
            LevelsUnlocked = plotData.LevelsUnlocked or 1,
            SegmentsUnlocked = plotData.SegmentsUnlocked or 0,
            Permissions = plotData.Permissions,
        }, userMetaData)

        print("Saving " .. tostring(#levelData) .. " bytes of level data for plot", plotId)
        -- Save level data separately
        FormexSystem.PlotDataStore:SetAsync(key .. ":data",
            levelData,
            userMetaData)
    end)

    if not success then
        warn("FormexSystem.SavePlot failed for PlotId", plotId, ":", err)
        return false, err
    end

    saveQueue[plotId] = nil
    FormexSystem.UpdatePlotAttributes(plotId)

    print("Saved plot", plotId, "for user", userId)

    return true
end

function FormexSystem.LoadPlot(plotId: number, saveId: number): boolean
    if not FormexSystem.PlotData[plotId] then error("Invalid plotId") end
    if not saveId or saveId == 0 then error("Invalid save selected") end

    local userId = FormexSystem.PlotToPlayer[plotId]
    if not userId or userId == 0 then error("Plot not claimed") end

    local plotPart = FormexSystem.Plots[plotId]
    if not plotPart then error("Invalid plot") end

    local key = tostring(userId) .. ":" .. tostring(saveId)
    local saveData: Formex.PlotData = FormexSystem.PlotDataStore:GetAsync(key)
    if not saveData then error("Save not found") end

    local levelData = (FormexSystem.PlotDataStore:GetAsync(key .. ":data") or {}) :: Formex.LevelData

    local plotData = FormexSystem.PlotData[plotId]
    if not plotData then error("Invalid plot") end

    plotData.SaveId = saveData.SaveId or saveId
    plotData.Name = saveData.Name or (Players:GetNameFromUserIdAsync(userId) .. "'s Plot")
    plotData.LastPlayed = os.time()
    plotData.NextId = saveData.NextId or plotData.NextId or 1
    plotData.Levels = saveData.Levels or {}
    plotData.LevelsUnlocked = math.max(saveData.LevelsUnlocked or 1, 1)
    local segmentsUnlocked = saveData.SegmentsUnlocked
    if segmentsUnlocked == nil or segmentsUnlocked == 0 then
        segmentsUnlocked = Formex.DefaultSegmentsUnlocked
    end
    plotData.SegmentsUnlocked = segmentsUnlocked
    plotData.Permissions = fixNumbericDictionary(saveData.Permissions or {})

    if type(levelData) == "string" then
        plotData.Levels = Formex.Serialization.DeserializeLevelData(levelData)
    else
        warn("No level data found for plot", plotId, "save", saveId)
        plotData.Levels = plotData.Levels or {}
    end

    ensurePlotNextId(plotData)

    FormexSystem.UpdatePlotAttributes(plotId)

    FormexSystem.ClearPlot(plotPart)

    FormexSystem.RenderPlot(plotId)

    return true
end

function FormexSystem.EnsureLevelData(plotData: Formex.PlotData, levelIndex: number): Formex.LevelData
	plotData.Levels = plotData.Levels or {} :: {number: Formex.LevelData}
	local levelData = plotData.Levels[levelIndex]

	if not levelData then
		levelData = {
			Walls = {} :: {number: Formex.WallData},
			Floors = {} :: {[number]: Formex.FloorData},
			Objects = {} :: {number: Formex.ObjectData},
		}
		plotData.Levels[levelIndex] = levelData
	end

	return levelData
end

type RenderState = {
    PlotPart: BasePart,
    PlotData: Formex.PlotData,
    LevelIndex: number,
    LevelData: Formex.LevelData,
    LevelPart: BasePart,
    FloorFolder: Folder,
    WallFolder: Folder,
    ObjectFolder: Folder
}

local function renderFloors(data: RenderState)
    local parent = data.FloorFolder

    local floors = data.LevelData.Floors

	for _, child in parent:GetChildren() do
		local floorId = tonumber(child.Name)
		if floorId and not floors[floorId] then
			child:Destroy()
		end
	end

	for floorId, floorData in floors do
		if not floorData.Model or not floorData.Model.Parent then
			local existing = parent:FindFirstChild(tostring(floorId))
			if existing and existing:IsA("Model") then
				floorData.Model = existing
			end
		end

		floorData.LevelIndex = data.LevelIndex
		local model = Formex.Floors.Create(floorData, data.PlotPart, parent, data.PlotData)
		if model then
			model.Parent = parent
			floorData.Model = model
		end
	end
end

local function renderWalls(data: RenderState)
    local parent = data.WallFolder
    for _, child in parent:GetChildren() do
        local wallId = tonumber(child.Name)
        if wallId and not data.LevelData.Walls[wallId] then
            child:Destroy()
        end
    end

    for wallId, wallData in data.LevelData.Walls do
        local model = wallData.Part
        if not model or not model.Parent then
            wallData.Part = nil
            local newModel = Formex.Walls.Create(wallData, data.PlotPart)
            if newModel then
                newModel.Parent = parent
            end
        else
            Formex.Walls.Edit(wallData, data.PlotPart)
        end
    end
end

local function renderFurniture(data: RenderState)
    local parent = data.RenderFurniture
    for objectId, objectData in data.LevelData.Objects do
        if not objectData.Part then
            Formex.CreateObject(parent, objectData)
        else
            Formex.EditObject(objectData)
        end
    end
end

local function renderLevel(data: RenderState, levelIndex: number, filterPartType: Formex.PartType?)
    data.LevelIndex = levelIndex
    data.LevelData = FormexSystem.EnsureLevelData(data.PlotData, levelIndex)

    local levelPart = data.PlotPart:FindFirstChild(tostring(data.LevelIndex))
    if not levelPart then
        levelPart = Instance.new("Part", data.PlotPart)
        levelPart.Name = tostring(data.LevelIndex)
    
        levelPart.Anchored = true
        levelPart.CanCollide = false
        levelPart.CanTouch = false
        levelPart.CanQuery = false
        levelPart.CastShadow = false
        levelPart.Transparency = 1
        levelPart.Material = Enum.Material.Air
        -- Level part represents the entire level volume, invisible and non-collidable
        levelPart.Position = data.PlotPart.Position + Vector3.new(0, Formex.LevelHeight * (levelIndex - 1) + Formex.LevelHeight / 2, 0)
        levelPart.Size = Vector3.new(data.PlotPart.Size.X, Formex.LevelHeight, data.PlotPart.Size.Z)
    end

    data.LevelPart = levelPart :: BasePart
    data.FloorFolder = Formex.Util.EnsureFolder("Floors", levelPart)
    data.WallFolder = Formex.Util.EnsureFolder("Walls", levelPart)
    data.ObjectFolder = Formex.Util.EnsureFolder("Objects", levelPart)

    if filterPartType == "Wall" then
        renderWalls(data)
    elseif filterPartType == "Floor" or filterPartType == "Ceiling" then
        renderFloors(data)
    elseif filterPartType == "Object" then
        renderFurniture(data)
    else
        renderFloors(data)
        renderWalls(data)
        renderFurniture(data)
    end
end

function FormexSystem.RenderPlot(plotId: number, filterLevelIndex: number?, filterPartType: Formex.PartType?): Model
    local data = {
        PlotPart = FormexSystem.Plots[plotId],
        PlotData = FormexSystem.PlotData[plotId],
    }

    if filterLevelIndex then
        renderLevel(data :: RenderState, filterLevelIndex, filterPartType)
        return
    end

    for level = 1, Formex.MaxPlotSize.Levels, 1 do
        renderLevel(data, level)
    end
end

-- Ensure defaults when players join
Players.PlayerAdded:Connect(function(player)
    if player:GetAttribute("MyPlotId") == nil then
        player:SetAttribute("MyPlotId", 0)
    end
    if player:GetAttribute("CurrentPlotId") == nil then
        player:SetAttribute("CurrentPlotId", 0)
    end
    if player:GetAttribute("CanUndo") == nil then
        player:SetAttribute("CanUndo", false)
    end
    if player:GetAttribute("CanRedo") == nil then
        player:SetAttribute("CanRedo", false)
    end
end)

-- TODO every minute try and save all plots in saveQueue

return FormexSystem
