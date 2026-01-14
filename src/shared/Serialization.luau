--!strict

local Formex = require(script.Parent)
local Buffer = require(script.Parent.Buffer)

local DATA_VERSION: number = 7
local INITIAL_BUFFER_SIZE: number = 1024
local MAX_LEVELS: number = 5

-- Rooms are transient (derived from wall geometry) and are intentionally not serialized.

local function writeMaterialId(writer, value: number?)
	writer:WriteU8(value and value > 0 and value or 0)
end

local function readMaterialId(reader): number?
	local value = reader:ReadU8()
	if value == 0 then return nil end
	return value
end

local function writeRaiseHeight(writer, value: number)
	local maxHeight = Formex.LevelHeight - Formex.InterfloorHeight
	if maxHeight < 0 then maxHeight = 0	end
	local snapped = math.round((value or 0) / Formex.GridSize) * Formex.GridSize
	local clamped = math.clamp(snapped, 0, maxHeight)
	writer:WriteU8(math.clamp(math.round(clamped), 0, 255))
end

local function readRaiseHeight(reader): number
	return reader:ReadU8()
end

local function writeColor(writer, color: Color3?)
	local resolved = color or Color3.new(1, 1, 1)
	writer:WriteU8(math.clamp(math.round(resolved.R * 255), 0, 255))
	writer:WriteU8(math.clamp(math.round(resolved.G * 255), 0, 255))
	writer:WriteU8(math.clamp(math.round(resolved.B * 255), 0, 255))
end

local function readColor(reader): Color3
	local r = reader:ReadU8()
	local g = reader:ReadU8()
	local b = reader:ReadU8()
	return Color3.fromRGB(r, g, b)
end

local function writeObjectSide(writer, side: Formex.ObjectSide?)
	if side == Formex.ObjectSide.Back then
		writer:WriteU8(2)
	elseif side == Formex.ObjectSide.Front then
		writer:WriteU8(1)
	else
		writer:WriteU8(0)
	end
end

local function readObjectSide(reader): Formex.ObjectSide?
	local value = reader:ReadU8()
	if value == 2 then
		return Formex.ObjectSide.Back
	elseif value == 1 then
		return Formex.ObjectSide.Front
	end
	return nil
end

function Formex.Serialization.GetMaxPartId(levels: Formex.LevelArray?): number
	if not levels then return 0 end
	local maxId = 0
	for _, levelData in levels do
		if levelData then
			for id in levelData.Walls do
				if id > maxId then
					maxId = id
				end
			end

			for id in levelData.Floors do
				if id > maxId then
					maxId = id
				end
			end

			for id, objectData in levelData.Objects do
				local numericId = tonumber(id)
				if not numericId and objectData then
					numericId = tonumber(objectData.ObjectId)
				end
				if numericId and numericId > maxId then
					maxId = numericId
				end
			end
		end
	end

	return maxId
end

function Formex.Serialization.SerializeLevelData(levels: Formex.LevelArray): string
	local writer = Buffer.new(INITIAL_BUFFER_SIZE)
	writer:WriteU16(DATA_VERSION)

	-- Serialize levels
	for levelIndex = 1, MAX_LEVELS do
		local levelData = levels[levelIndex] :: Formex.LevelData

		if levelData then
			writer:WriteU8(levelIndex)

			-- Walls
			for wallId, wall in levelData.Walls do
				writer:WriteU16(wallId)
				writer:WriteI16(wall.Start.X)
				writer:WriteI16(wall.Start.Y)
				writer:WriteI16(wall.End.X)
				writer:WriteI16(wall.End.Y)
				writer:WriteU8(wall.Height and math.round(wall.Height) or 0)
				writer:WriteU8(wall.FrontSplitHeight and math.round(wall.FrontSplitHeight) or 0)
				writer:WriteU8(wall.BackSplitHeight and math.round(wall.BackSplitHeight) or 0)
				writeMaterialId(writer, wall.FrontTopMaterial)
				writeMaterialId(writer, wall.FrontBottomMaterial)
				writeMaterialId(writer, wall.BackTopMaterial)
				writeMaterialId(writer, wall.BackBottomMaterial)
				writeColor(writer, wall.FrontTopColor)
				writeColor(writer, wall.FrontBottomColor)
				writeColor(writer, wall.BackTopColor)
				writeColor(writer, wall.BackBottomColor)
			end
			writer:WriteU16(0)

			-- Floors
			for floorId, floor in levelData.Floors do
				local points = Formex.Floors.CleanPolygon(floor.Points or {})
				writer:WriteU16(floorId)
				writeMaterialId(writer, floor.FloorMaterial)
				writeMaterialId(writer, floor.CeilingMaterial)
				writeMaterialId(writer, floor.FoundationMaterial)
				writeColor(writer, floor.FloorColor)
				writeColor(writer, floor.CeilingColor)
				writeColor(writer, floor.FoundationColor)
				writeRaiseHeight(writer, floor.RaiseHeight)
				writer:WriteU8(#points)
				for _, point in ipairs(points) do
					writer:WriteI8(point.X)
					writer:WriteI8(point.Y)
				end
			end
			writer:WriteU16(0)

			-- Objects
			for objectId, object in levelData.Objects do
				writer:WriteU16(objectId)
				writer:WriteString(object.PrefabName or "")
				writer:WriteF32(object.Position.X)
				writer:WriteF32(object.Position.Y)
				writer:WriteF32(object.Position.Z)
				writer:WriteF32(object.Rotation.X)
				writer:WriteF32(object.Rotation.Y)
				writer:WriteF32(object.Rotation.Z)
				writer:WriteU16(object.WallId or 0)
				writeObjectSide(writer, object.Side)
				for designIndex, materialId in object.Design do
					writer:WriteU16(designIndex)
					writer:WriteU16(materialId)
					local color = object.DesignColors and object.DesignColors[designIndex] or nil
					writeColor(writer, color)
				end
				writer:WriteU16(0)
			end
			writer:WriteU16(0)

		else
			writer:WriteU8(0) -- levelIndex
			writer:WriteU16(0) -- walls terminator
			writer:WriteU16(0) -- floors terminator
			writer:WriteU16(0) -- objects terminator
		end
	end

	return writer:ToString()
end

local function deserializeLevelDataV7(reader): Formex.LevelArray
	local result = {} :: Formex.LevelArray

	for i = 1, Formex.MaxPlotSize.Levels do
		local levelData: Formex.LevelData = {
			Walls = {},
			Floors = {},
			Objects = {},
		}

		local levelIndex = reader:ReadU8()
		if levelIndex ~= 0 then
			result[levelIndex] = levelData
		end

		-- Walls
		while true do
			local wallId = reader:ReadU16()
			if wallId == 0 then break end

			local wall: Formex.WallData = {
				WallId = wallId,
				Level = levelIndex,
				Start = Vector2int16.new(reader:ReadI16(), reader:ReadI16()),
				End = Vector2int16.new(reader:ReadI16(), reader:ReadI16()),
				Height = reader:ReadU8(),
				FrontSplitHeight = reader:ReadU8(),
				BackSplitHeight = reader:ReadU8(),
				FrontTopMaterial = readMaterialId(reader),
				FrontBottomMaterial = readMaterialId(reader),
				BackTopMaterial = readMaterialId(reader),
				BackBottomMaterial = readMaterialId(reader),
				FrontTopColor = readColor(reader),
				FrontBottomColor = readColor(reader),
				BackTopColor = readColor(reader),
				BackBottomColor = readColor(reader),
			} :: Formex.WallData
			levelData.Walls[wallId] = wall
		end

		-- Floors
		while true do
			local floorId = reader:ReadU16()
			if floorId == 0 then break end
			local floorMaterial = readMaterialId(reader)
			local ceilingMaterial = readMaterialId(reader)
			local foundationMaterial = readMaterialId(reader)
			local floorColor = readColor(reader)
			local ceilingColor = readColor(reader)
			local foundationColor = readColor(reader)
			local raiseHeight = readRaiseHeight(reader)
			local pointCount = reader:ReadU8()
			local points = {}
			for _ = 1, pointCount do
				table.insert(points, Vector2int16.new(reader:ReadI8(), reader:ReadI8()))
			end
			levelData.Floors[floorId] = {
				FloorId = floorId,
				LevelIndex = levelIndex,
				Points = points,
				RaiseHeight = raiseHeight,
				FloorMaterial = floorMaterial,
				CeilingMaterial = ceilingMaterial,
				FoundationMaterial = foundationMaterial,
				FloorColor = floorColor,
				CeilingColor = ceilingColor,
				FoundationColor = foundationColor,
			} :: Formex.FloorData
		end

		-- Objects
		while true do
			local objectId = reader:ReadU16()
			if objectId == 0 then break end
			local prefabName = reader:ReadString()
			local prefab = Formex.Objects.GetPrefab(prefabName)
			local obj = {
				ObjectId = objectId,
				Level = levelIndex,
				PrefabName = prefabName,
				Position = Vector3.new(reader:ReadF32(), reader:ReadF32(), reader:ReadF32()),
				Rotation = Vector3.new(reader:ReadF32(), reader:ReadF32(), reader:ReadF32()),
				WallId = reader:ReadU16(),
				Side = readObjectSide(reader) or Formex.ObjectSide.Front,
				Design = {},
				DesignColors = {},
				Properties = {},
				IsPortal = prefab and prefab.ObjectMount == Formex.ObjectMount.Door or false,
				Prefab = prefab,
			} :: Formex.ObjectData
			if obj.WallId == 0 then
				obj.WallId = nil
			end

			while true do
				local designIndex = reader:ReadU16()
				if designIndex == 0 then break end
				local materialId = reader:ReadU16()
				local color = readColor(reader)
				obj.Design[designIndex] = materialId
				obj.DesignColors[designIndex] = color
			end

			levelData.Objects[objectId] = obj
		end
	end

	return result
end

function Formex.Serialization.DeserializeLevelData(dataString: string): Formex.LevelArray
	local reader = Buffer.read(dataString)
	local version = reader:ReadU16()

	if version < 7 then
		error("Unsupported legacy data version: " .. tostring(version))
	elseif version == 7 then
		return deserializeLevelDataV7(reader)
	else
		error("Unsupported future data version: " .. tostring(version))
	end
end

return Formex.Serialization
