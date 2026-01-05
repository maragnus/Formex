--!strict

local Formex = require(script.Parent:FindFirstChild("FormexServer"))
local FormexSystem = require(script.Parent:FindFirstChild("FormexSystem"))

local PhysicsService = game:GetService("PhysicsService")
PhysicsService:RegisterCollisionGroup(Formex.CollisionGroup.Grid)
PhysicsService:RegisterCollisionGroup(Formex.CollisionGroup.Structure)
PhysicsService:RegisterCollisionGroup(Formex.CollisionGroup.Object)

-- Grid only collides with grid
PhysicsService:CollisionGroupSetCollidable(Formex.CollisionGroup.Grid, Formex.CollisionGroup.Grid, true)

-- Walls and objects collide with each other (ignores objects)
PhysicsService:CollisionGroupSetCollidable(Formex.CollisionGroup.Structure, Formex.CollisionGroup.Structure, true)
PhysicsService:CollisionGroupSetCollidable(Formex.CollisionGroup.Structure, "Default", true)

-- Objects collide with everything except grids
PhysicsService:CollisionGroupSetCollidable(Formex.CollisionGroup.Object, Formex.CollisionGroup.Structure, true)
PhysicsService:CollisionGroupSetCollidable(Formex.CollisionGroup.Object, Formex.CollisionGroup.Object, true)
PhysicsService:CollisionGroupSetCollidable(Formex.CollisionGroup.Object, "Default", true)

local FormexBuild = {}

local function getNextId(entries: {[number]: any}): number
	local maxId = 0
	for id in entries do
		if id > maxId then
			maxId = id
		end
	end
	return maxId + 1
end

local undoStacks = {} :: {[number]: {Formex.LevelArray}}
local redoStacks = {} :: {[number]: {Formex.LevelArray}}

local function getHistory(plotId: number): ({Formex.LevelArray}, {Formex.LevelArray})
	local undo = undoStacks[plotId]
	if not undo then
		undo = {}
		undoStacks[plotId] = undo
	end
	local redo = redoStacks[plotId]
	if not redo then
		redo = {}
		redoStacks[plotId] = redo
	end
	return undo, redo
end

local function pushUndo(plotId: number, snapshot: Formex.LevelArray)
	local undo, redo = getHistory(plotId)
	table.insert(undo, snapshot)
	table.clear(redo)
end

local function normalizeWallList(wallData: Formex.WallData | {Formex.WallData}): ({Formex.WallData}, boolean)
	local wallDataAny = wallData :: any
	if wallDataAny.WallId ~= nil or wallDataAny.Start ~= nil or wallDataAny.End ~= nil then
		return { wallData :: Formex.WallData }, false
	end

	local wallList = wallData :: {Formex.WallData}
	if #wallList == 0 then
		error("Invalid wall data")
	end
	return wallList, true
end

local function normalizeFloorList(floorData: Formex.FloorData | {Formex.FloorData}): ({Formex.FloorData}, boolean)
	local floorDataAny = floorData :: any
	if floorDataAny.FloorId ~= nil or floorDataAny.Points ~= nil then
		return { floorData :: Formex.FloorData }, false
	end

	local floorList = floorData :: {Formex.FloorData}
	if #floorList == 0 then
		error("Invalid floor data")
	end
	return floorList, true
end

local function collectFloorLevels(floors: {Formex.FloorData}): {number}
	local levels = {}
	local seen = {}
	for _, floor in ipairs(floors) do
		local levelIndex = floor.LevelIndex or 1
		if not seen[levelIndex] then
			seen[levelIndex] = true
			table.insert(levels, levelIndex)
		end
	end
	table.sort(levels)
	return levels
end

local function collectWallLevels(walls: {Formex.WallData}): {number}
	local levels = {}
	local seen = {}
	for _, wall in ipairs(walls) do
		local levelIndex = wall.Level or 1
		if not seen[levelIndex] then
			seen[levelIndex] = true
			table.insert(levels, levelIndex)
		end
	end
	table.sort(levels)
	return levels
end

local function cloneLevelForSnapshot(snapshot: Formex.LevelArray, levels: Formex.LevelArray, levelIndex: number, partType: Formex.PartType)
	local levelData = levels[levelIndex]
	if not levelData then
		return
	end

	local levelClone = table.clone(levelData)
	if partType == Formex.PartType.Wall then
		levelClone.Walls = table.clone(levelData.Walls)
	elseif partType == Formex.PartType.Floor then
		levelClone.Floors = table.clone(levelData.Floors)
	elseif partType == Formex.PartType.Object then
		levelClone.Objects = table.clone(levelData.Objects)
	end
	snapshot[levelIndex] = levelClone
end

local function createSnapshot(levels: Formex.LevelArray, levelIndex: number, partType: Formex.PartType): Formex.LevelArray
	local snapshot = table.clone(levels)
	cloneLevelForSnapshot(snapshot, levels, levelIndex, partType)
	return snapshot
end

local function createSnapshotForLevels(levels: Formex.LevelArray, levelIndices: {number}, partType: Formex.PartType): Formex.LevelArray
	local snapshot = table.clone(levels)
	for _, levelIndex in ipairs(levelIndices) do
		cloneLevelForSnapshot(snapshot, levels, levelIndex, partType)
	end
	return snapshot
end

local function isZeroLength(startPoint: Vector2int16, endPoint: Vector2int16): boolean
	return startPoint.X == endPoint.X and startPoint.Y == endPoint.Y
end

local function snapToGrid(value: number): number
	local grid = Formex.LayoutGridSize
	return math.round(value / grid) * grid
end

local function resolveWallHeight(value: number?, existing: number?): number
	if value == 0 then
		value = nil
		existing = nil
	end
	local resolved = value
	if resolved ~= nil and resolved < 0 then
		resolved = nil
	end
	if resolved == nil then
		resolved = existing
	end
	resolved = resolved or Formex.LevelHeight
	resolved = snapToGrid(resolved)
	return math.clamp(resolved, Formex.LayoutGridSize, Formex.LevelHeight)
end

local function resolveSplitHeight(height: number, value: number?, existing: number?): number?
	local resolved = value
	if resolved == nil then
		resolved = existing
	end
	if resolved == nil or resolved <= 0 then
		return nil
	end
	if height <= Formex.LayoutGridSize * 2 then
		return nil
	end
	local snapped = snapToGrid(resolved)
	local maxSplit = height - Formex.LayoutGridSize
	return math.clamp(snapped, Formex.LayoutGridSize, maxSplit)
end

local function resolveColor(value: Color3?, fallback: Color3?): Color3
	return value or fallback or Color3.new(1, 1, 1)
end

local function normalizeMaterialId(value: number?): number?
	if type(value) ~= "number" or value <= 0 then
		return nil
	end
	return value
end

local function resolveSideMaterials(entryTop: number?, entryBottom: number?, entryLegacy: number?, existingTop: number?, existingBottom: number?, existingLegacy: number?, defaultMaterial: number): (number, number)
	entryTop = normalizeMaterialId(entryTop)
	entryBottom = normalizeMaterialId(entryBottom)
	entryLegacy = normalizeMaterialId(entryLegacy)
	existingTop = normalizeMaterialId(existingTop)
	existingBottom = normalizeMaterialId(existingBottom)
	existingLegacy = normalizeMaterialId(existingLegacy)

	local base = entryLegacy or entryBottom or entryTop
	if not base then
		base = existingBottom or existingTop or existingLegacy
	end
	base = base or defaultMaterial

	local bottom = entryBottom or existingBottom or base
	local top = entryTop or existingTop or base
	return bottom, top
end

local function resolveSideColors(entryTop: Color3?, entryBottom: Color3?, existingTop: Color3?, existingBottom: Color3?, fallback: Color3?): (Color3, Color3)
	local base = entryBottom or entryTop or existingBottom or existingTop or fallback or Color3.new(1, 1, 1)
	local bottom = entryBottom or existingBottom or base
	local top = entryTop or existingTop or base
	return bottom, top
end

function FormexBuild.BuildWall(player: Player, wallData: Formex.WallData | {Formex.WallData}, action: Formex.BuildAction)
	local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
	if not plotData then error("No current plot") end
	if permission ~= Formex.Permission.Manager and permission ~= Formex.Permission.Owner then
		error("Access denied")
	end
	if not wallData then error("Invalid wall data") end

	plotData.Levels = plotData.Levels or {}
	local wallList, isBatch = normalizeWallList(wallData)
	local levelsTouched = collectWallLevels(wallList)
	local snapshot = createSnapshotForLevels(plotData.Levels, levelsTouched, Formex.PartType.Wall)

	local updatedWalls = {} :: {Formex.WallData}
	local returnWalls = {} :: {Formex.WallData}
	local removedParts = {} :: {BasePart}
	local didChange = false

	if action == Formex.BuildAction.Add then
		for _, entry in ipairs(wallList) do
			if not entry.Start or not entry.End then
				error("Invalid wall data")
			end

			local levelIndex = entry.Level or 1
			local levelData = FormexSystem.EnsureLevelData(plotData, levelIndex)

			local height = resolveWallHeight(entry.Height, nil)
			local frontSplitHeight = resolveSplitHeight(height, entry.FrontSplitHeight, nil)
			local backSplitHeight = resolveSplitHeight(height, entry.BackSplitHeight, nil)

			local frontBottomMaterial, frontTopMaterial = resolveSideMaterials(
				entry.FrontTopMaterial,
				entry.FrontBottomMaterial,
				entry.FrontMaterial,
				nil,
				nil,
				nil,
				Formex.DefaultWallMaterial
			)
			local backBottomMaterial, backTopMaterial = resolveSideMaterials(
				entry.BackTopMaterial,
				entry.BackBottomMaterial,
				entry.BackMaterial,
				nil,
				nil,
				nil,
				frontBottomMaterial
			)

			local frontBottomColor, frontTopColor = resolveSideColors(
				entry.FrontTopColor,
				entry.FrontBottomColor,
				nil,
				nil,
				nil
			)
			local backBottomColor, backTopColor = resolveSideColors(
				entry.BackTopColor,
				entry.BackBottomColor,
				nil,
				nil,
				frontBottomColor
			)

			local newId = getNextId(levelData.Walls)
			local newWall = {
				WallId = newId,
				Level = levelIndex,
				Start = entry.Start,
				End = entry.End,
				Height = height,
				FrontSplitHeight = frontSplitHeight,
				BackSplitHeight = backSplitHeight,
				FrontTopMaterial = frontTopMaterial,
				FrontBottomMaterial = frontBottomMaterial,
				BackTopMaterial = backTopMaterial,
				BackBottomMaterial = backBottomMaterial,
				FrontTopColor = frontTopColor,
				FrontBottomColor = frontBottomColor,
				BackTopColor = backTopColor,
				BackBottomColor = backBottomColor,
				Part = nil
			}
			levelData.Walls[newId] = newWall
			table.insert(updatedWalls, newWall)
			table.insert(returnWalls, {
				WallId = newId,
				Level = levelIndex,
				Start = entry.Start,
				End = entry.End,
				Height = height,
				FrontSplitHeight = frontSplitHeight,
				BackSplitHeight = backSplitHeight,
				FrontTopMaterial = frontTopMaterial,
				FrontBottomMaterial = frontBottomMaterial,
				BackTopMaterial = backTopMaterial,
				BackBottomMaterial = backBottomMaterial,
				FrontTopColor = frontTopColor,
				FrontBottomColor = frontBottomColor,
				BackTopColor = backTopColor,
				BackBottomColor = backBottomColor,
				Part = nil
			})
		end

		for _, wall in ipairs(updatedWalls) do
			if not Formex.IsWallValid(plotData, wall) then
				plotData.Levels = snapshot
				error("Invalid wall placement")
			end
		end
		didChange = #updatedWalls > 0
	elseif action == Formex.BuildAction.Edit then
		for _, entry in ipairs(wallList) do
			local levelIndex = entry.Level or 1
			local levelData = plotData.Levels[levelIndex]
			if not levelData then
				plotData.Levels = snapshot
				error("Wall not found")
			end

			local existing = levelData.Walls[entry.WallId]
			if not existing then
				plotData.Levels = snapshot
				error("Wall not found")
			end
			if not entry.Start or not entry.End then
				plotData.Levels = snapshot
				error("Invalid wall data")
			end

			if isZeroLength(entry.Start, entry.End) then
				if existing.Part then
					table.insert(removedParts, existing.Part)
				end
				levelData.Walls[entry.WallId] = nil
				didChange = true
			else
				local height = resolveWallHeight(entry.Height, existing.Height)
				local frontSplitHeight = resolveSplitHeight(height, entry.FrontSplitHeight, existing.FrontSplitHeight)
				local backSplitHeight = resolveSplitHeight(height, entry.BackSplitHeight, existing.BackSplitHeight)

				local frontBottomMaterial, frontTopMaterial = resolveSideMaterials(
					entry.FrontTopMaterial,
					entry.FrontBottomMaterial,
					entry.FrontMaterial,
					existing.FrontTopMaterial,
					existing.FrontBottomMaterial,
					existing.FrontMaterial,
					Formex.DefaultWallMaterial
				)
				local backBottomMaterial, backTopMaterial = resolveSideMaterials(
					entry.BackTopMaterial,
					entry.BackBottomMaterial,
					entry.BackMaterial,
					existing.BackTopMaterial,
					existing.BackBottomMaterial,
					existing.BackMaterial,
					frontBottomMaterial
				)

				local frontBottomColor, frontTopColor = resolveSideColors(
					entry.FrontTopColor,
					entry.FrontBottomColor,
					existing.FrontTopColor,
					existing.FrontBottomColor,
					nil
				)
				local backBottomColor, backTopColor = resolveSideColors(
					entry.BackTopColor,
					entry.BackBottomColor,
					existing.BackTopColor,
					existing.BackBottomColor,
					frontBottomColor
				)

				local updated = {
					WallId = existing.WallId,
					Level = levelIndex,
					Start = entry.Start,
					End = entry.End,
					Height = height,
					FrontSplitHeight = frontSplitHeight,
					BackSplitHeight = backSplitHeight,
					FrontTopMaterial = frontTopMaterial,
					FrontBottomMaterial = frontBottomMaterial,
					BackTopMaterial = backTopMaterial,
					BackBottomMaterial = backBottomMaterial,
					FrontTopColor = frontTopColor,
					FrontBottomColor = frontBottomColor,
					BackTopColor = backTopColor,
					BackBottomColor = backBottomColor,
					Part = existing.Part
				}
				levelData.Walls[existing.WallId] = updated
				table.insert(updatedWalls, updated)
				table.insert(returnWalls, {
					WallId = updated.WallId,
					Level = updated.Level,
					Start = updated.Start,
					End = updated.End,
					Height = updated.Height,
					FrontSplitHeight = updated.FrontSplitHeight,
					BackSplitHeight = updated.BackSplitHeight,
					FrontTopMaterial = updated.FrontTopMaterial,
					FrontBottomMaterial = updated.FrontBottomMaterial,
					BackTopMaterial = updated.BackTopMaterial,
					BackBottomMaterial = updated.BackBottomMaterial,
					FrontTopColor = updated.FrontTopColor,
					FrontBottomColor = updated.FrontBottomColor,
					BackTopColor = updated.BackTopColor,
					BackBottomColor = updated.BackBottomColor,
					Part = nil
				})
				didChange = true
			end
		end

		for _, wall in ipairs(updatedWalls) do
			if not Formex.IsWallValid(plotData, wall) then
				plotData.Levels = snapshot
				error("Invalid wall placement")
			end
		end
	elseif action == Formex.BuildAction.Delete then
		for _, entry in ipairs(wallList) do
			local levelIndex = entry.Level or 1
			local levelData = plotData.Levels[levelIndex]
			if levelData then
				local existing = levelData.Walls[entry.WallId]
				if existing then
					if existing.Part then
						existing.Part:Destroy()
					end
					levelData.Walls[entry.WallId] = nil
					didChange = true
				end
			end
		end
	else
		error("Invalid wall action")
	end

	if not didChange then
		return nil
	end

	if action ~= Formex.BuildAction.Delete then
		for _, part in ipairs(removedParts) do
			if part and part.Parent then
				part:Destroy()
			end
		end
	end

	local plotPart = FormexSystem.Plots[plotData.PlotId]
	if plotPart then
		for _, levelIndex in ipairs(levelsTouched) do
			FormexSystem.RenderPlot(plotData.PlotId, levelIndex, Formex.PartType.Wall)
		end
	end

	pushUndo(plotData.PlotId, snapshot)
	FormexSystem.QueueSave(plotData.PlotId)

	if action == Formex.BuildAction.Delete then
		return nil
	end

	if isBatch then
		return returnWalls
	end
	return returnWalls[1]
end

function FormexBuild.BuildFloor(player: Player, floorData: Formex.FloorData | {Formex.FloorData}, action: Formex.BuildAction)
	local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
	if not plotData then error("No current plot") end
	if permission ~= Formex.Permission.Manager and permission ~= Formex.Permission.Owner then
		error("Access denied")
	end
	if not floorData then error("Invalid floor data") end

	plotData.Levels = plotData.Levels or {}
	local floorList, isBatch = normalizeFloorList(floorData)
	local levelsTouched = collectFloorLevels(floorList)
	local snapshot = createSnapshotForLevels(plotData.Levels, levelsTouched, Formex.PartType.Floor)

	local updatedFloors = {} :: {Formex.FloorData}
	local returnFloors = {} :: {Formex.FloorData}
	local removedModels = {} :: {Model}
	local didChange = false

	if action == Formex.BuildAction.Add then
		for _, entry in ipairs(floorList) do
			if not entry.Points or #entry.Points < 3 then
				error("Invalid floor data")
			end

			local levelIndex = entry.LevelIndex or 1
			local levelData = FormexSystem.EnsureLevelData(plotData, levelIndex)
			local newId = getNextId(levelData.Floors)

			local floorMaterial = normalizeMaterialId(entry.FloorMaterial) or Formex.DefaultFloorMaterial
			local ceilingMaterial = normalizeMaterialId(entry.CeilingMaterial) or floorMaterial
			local foundationMaterial = normalizeMaterialId(entry.FoundationMaterial) or Formex.DefaultFoundationMaterial
			local floorColor = resolveColor(entry.FloorColor, nil)
			local ceilingColor = resolveColor(entry.CeilingColor, floorColor)
			local foundationColor = resolveColor(entry.FoundationColor, floorColor)

			local newFloor = {
				FloorId = newId,
				LevelIndex = levelIndex,
				Points = entry.Points,
				FloorMaterial = floorMaterial,
				CeilingMaterial = ceilingMaterial,
				FoundationMaterial = foundationMaterial,
				FloorColor = floorColor,
				CeilingColor = ceilingColor,
				FoundationColor = foundationColor,
				FloorParts = {},
				CeilingParts = {},
				Model = nil,
			}

			levelData.Floors[newId] = newFloor
			table.insert(updatedFloors, newFloor)
			table.insert(returnFloors, {
				FloorId = newId,
				LevelIndex = levelIndex,
				Points = entry.Points,
				FloorMaterial = floorMaterial,
				CeilingMaterial = ceilingMaterial,
				FoundationMaterial = foundationMaterial,
				FloorColor = floorColor,
				CeilingColor = ceilingColor,
				FoundationColor = foundationColor,
				FloorParts = {},
				CeilingParts = {},
				Model = nil,
			})
		end

		for _, floor in ipairs(updatedFloors) do
			if not Formex.Floors.IsValid(plotData, floor) then
				plotData.Levels = snapshot
				error("Invalid floor placement")
			end
		end
		didChange = #updatedFloors > 0
	elseif action == Formex.BuildAction.Edit then
		for _, entry in ipairs(floorList) do
			local levelIndex = entry.LevelIndex or 1
			local levelData = plotData.Levels[levelIndex]
			if not levelData then
				plotData.Levels = snapshot
				error("Floor not found")
			end

			local existing = levelData.Floors[entry.FloorId]
			if not existing then
				plotData.Levels = snapshot
				error("Floor not found")
			end

			local updatedPoints = entry.Points or existing.Points
			if not updatedPoints or #updatedPoints < 3 then
				if existing.Model then
					table.insert(removedModels, existing.Model)
				end
				levelData.Floors[entry.FloorId] = nil
				didChange = true
			else
				local floorMaterial = normalizeMaterialId(entry.FloorMaterial) or normalizeMaterialId(existing.FloorMaterial) or Formex.DefaultFloorMaterial
				local ceilingMaterial = normalizeMaterialId(entry.CeilingMaterial) or normalizeMaterialId(existing.CeilingMaterial) or floorMaterial
				local foundationMaterial = normalizeMaterialId(entry.FoundationMaterial) or normalizeMaterialId(existing.FoundationMaterial) or Formex.DefaultFoundationMaterial
				local floorColor = resolveColor(entry.FloorColor, existing.FloorColor)
				local ceilingColor = resolveColor(entry.CeilingColor, existing.CeilingColor or floorColor)
				local foundationColor = resolveColor(entry.FoundationColor, existing.FoundationColor or floorColor)

				local updated = {
					FloorId = existing.FloorId,
					LevelIndex = levelIndex,
					Points = updatedPoints,
					FloorMaterial = floorMaterial,
					CeilingMaterial = ceilingMaterial,
					FoundationMaterial = foundationMaterial,
					FloorColor = floorColor,
					CeilingColor = ceilingColor,
					FoundationColor = foundationColor,
					FloorParts = existing.FloorParts or {},
					CeilingParts = existing.CeilingParts or {},
					Model = existing.Model,
				}

				levelData.Floors[existing.FloorId] = updated
				table.insert(updatedFloors, updated)
				table.insert(returnFloors, {
					FloorId = updated.FloorId,
					LevelIndex = updated.LevelIndex,
					Points = updated.Points,
					FloorMaterial = updated.FloorMaterial,
					CeilingMaterial = updated.CeilingMaterial,
					FoundationMaterial = updated.FoundationMaterial,
					FloorColor = updated.FloorColor,
					CeilingColor = updated.CeilingColor,
					FoundationColor = updated.FoundationColor,
					FloorParts = {},
					CeilingParts = {},
					Model = nil,
				})
			end
		end

		didChange = didChange or #updatedFloors > 0
		for _, floor in ipairs(updatedFloors) do
			if not Formex.Floors.IsValid(plotData, floor) then
				plotData.Levels = snapshot
				error("Invalid floor placement")
			end
		end
	elseif action == Formex.BuildAction.Delete then
		for _, entry in ipairs(floorList) do
			local levelIndex = entry.LevelIndex or 1
			local levelData = plotData.Levels[levelIndex]
			if levelData then
				local existing = levelData.Floors[entry.FloorId]
				if existing then
					if existing.Model then
						existing.Model:Destroy()
					end
					levelData.Floors[entry.FloorId] = nil
					didChange = true
				end
			end
		end
	else
		error("Invalid floor action")
	end

	if not didChange then
		return nil
	end

	if action ~= Formex.BuildAction.Delete then
		for _, model in ipairs(removedModels) do
			if model and model.Parent then
				model:Destroy()
			end
		end
	end

	local plotPart = FormexSystem.Plots[plotData.PlotId]
	if plotPart then
		for _, levelIndex in ipairs(levelsTouched) do
			FormexSystem.RenderPlot(plotData.PlotId, levelIndex, Formex.PartType.Floor)
		end
	end

	pushUndo(plotData.PlotId, snapshot)
	FormexSystem.QueueSave(plotData.PlotId)

	if action == Formex.BuildAction.Delete then
		return nil
	end

	if isBatch then
		return returnFloors
	end
	return returnFloors[1]
end

function FormexBuild.BuildObject(player: Player, objectData: Formex.ObjectData, action: Formex.BuildAction)
    local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
    if permission ~= Formex.Permission.Manager then error("Access denied") end
    
    -- TODO
    
    FormexSystem.QueueSave(plotData.PlotId)
end

function FormexBuild.CanUndo(player: Player): boolean
	local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
	if not plotData then error("No current plot") end
	if permission ~= Formex.Permission.Manager and permission ~= Formex.Permission.Owner then
		error("Access denied")
	end

	local undo = undoStacks[plotData.PlotId]
	return undo ~= nil and #undo > 0
end

function FormexBuild.CanRedo(player: Player): boolean
	local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
	if not plotData then error("No current plot") end
	if permission ~= Formex.Permission.Manager and permission ~= Formex.Permission.Owner then
		error("Access denied")
	end

	local redo = redoStacks[plotData.PlotId]
	return redo ~= nil and #redo > 0
end

function FormexBuild.Undo(player: Player): (boolean, string?)
	local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
	if not plotData then error("No current plot") end
	if permission ~= Formex.Permission.Manager and permission ~= Formex.Permission.Owner then
		error("Access denied")
	end

	plotData.Levels = plotData.Levels or {}
	local undo, redo = getHistory(plotData.PlotId)
	if #undo == 0 then
		return false, "Nothing to undo"
	end

	local snapshot = undo[#undo]
	undo[#undo] = nil
	table.insert(redo, plotData.Levels)
	plotData.Levels = snapshot

	FormexSystem.RenderPlot(plotData.PlotId)
	FormexSystem.QueueSave(plotData.PlotId)
	return true
end

function FormexBuild.Redo(player: Player): (boolean, string?)
	local plotData, permission = FormexSystem.GetPlayerCurrentPlot(player)
	if not plotData then error("No current plot") end
	if permission ~= Formex.Permission.Manager and permission ~= Formex.Permission.Owner then
		error("Access denied")
	end

	plotData.Levels = plotData.Levels or {}
	local undo, redo = getHistory(plotData.PlotId)
	if #redo == 0 then
		return false, "Nothing to redo"
	end

	local snapshot = redo[#redo]
	redo[#redo] = nil
	table.insert(undo, plotData.Levels)
	plotData.Levels = snapshot

	FormexSystem.RenderPlot(plotData.PlotId)
	FormexSystem.QueueSave(plotData.PlotId)
	return true
end

return FormexBuild
