--!strict

local Formex = require(script.Parent:FindFirstChild("Formex"))

local DATA_VERSION: number = 2
local INITIAL_BUFFER_SIZE: number = 1024
local MAX_LEVELS: number = 5

local Buffer = require(script.Parent.Buffer)

local FormexSerialization = {}

function FormexSerialization.SerializeLevelData(levels: LevelArray): string
	local writer = Buffer.new(INITIAL_BUFFER_SIZE)
	writer:WriteU16(DATA_VERSION)

	-- Serialize levels
	for levelIndex = 1, MAX_LEVELS do
		local levelData = levels[levelIndex] :: LevelData

		if levelData then
			writer:WriteU8(levelIndex)

			-- Walls
			for wallId, wall in levelData.Walls do
				writer:WriteU16(wallId)
				writer:WriteI16(wall.Start.X)
				writer:WriteI16(wall.Start.Y)
				writer:WriteI16(wall.End.X)
				writer:WriteI16(wall.End.Y)
				writer:WriteU8(wall.FrontMaterial or 0)
				writer:WriteU8(wall.BackMaterial or 0)
				writer:WriteU8(wall.StartMaterial or 0)
				writer:WriteU8(wall.EndMaterial or 0)
			end
			writer:WriteU16(0)

			-- Floors
			for floorId, floor in levelData.Floors do
				local points = floor.Points or {}
				writer:WriteU16(floorId)
				writer:WriteU8(floor.FloorMaterial or 0)
				writer:WriteU8(floor.CeilingMaterial or 0)
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
				writer:WriteF32(object.Position.X)
				writer:WriteF32(object.Position.Y)
				writer:WriteF32(object.Position.Z)
				writer:WriteF32(object.Rotation.X)
				writer:WriteF32(object.Rotation.Y)
				writer:WriteF32(object.Rotation.Z)
				writer:WriteU16(object.WallId or 0)
				for designIndex, value in object.Design do
					writer:WriteU16(designIndex)
					writer:WriteString(value)
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

local function deserializeLevelDataV1(reader): LevelArray
	local result = {} :: LevelArray

	for i = 1, Formex.MaxPlotSize.Levels do
		local levelData: LevelData = {
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

			local wall: WallData = {
				WallId = wallId,
				Level = levelIndex,
				Start = Vector2int16.new(reader:ReadI16(), reader:ReadI16()),
				End = Vector2int16.new(reader:ReadI16(), reader:ReadI16()),
				FrontMaterial = reader:ReadU8(),
				BackMaterial = reader:ReadU8(),
				StartMaterial = reader:ReadU8(),
				EndMaterial = reader:ReadU8(),
			}
			levelData.Walls[wallId] = wall
		end

		local legacyFloors = {}
		while true do
			local index = reader:ReadU16()
			if index == 0 then break end
			legacyFloors[index] = reader:ReadU8()
		end

		local legacyCeilings = {}
		while true do
			local index = reader:ReadU16()
			if index == 0 then break end
			legacyCeilings[index] = reader:ReadU8()
		end

		for index, floorMaterial in legacyFloors do
			local ceilingMaterial = legacyCeilings[index] or floorMaterial
			local tile = Formex.IndexToXY(index)
			local tileSize = Formex.LayoutGridSize
			local x0 = tile.X * tileSize - (Formex.Dimensions.Width / 2)
			local z0 = tile.Y * tileSize - (Formex.Dimensions.Depth / 2)
			levelData.Floors[index] = {
				FloorId = index,
				LevelIndex = levelIndex,
				Points = {
					Vector2int16.new(x0, z0),
					Vector2int16.new(x0 + tileSize, z0),
					Vector2int16.new(x0 + tileSize, z0 + tileSize),
					Vector2int16.new(x0, z0 + tileSize),
				},
				FloorMaterial = floorMaterial,
				CeilingMaterial = ceilingMaterial,
				FloorParts = {},
				CeilingParts = {},
			}
		end
		for index, ceilingMaterial in legacyCeilings do
			if not legacyFloors[index] then
				local tile = Formex.IndexToXY(index)
				local tileSize = Formex.LayoutGridSize
				local x0 = tile.X * tileSize - (Formex.Dimensions.Width / 2)
				local z0 = tile.Y * tileSize - (Formex.Dimensions.Depth / 2)
				levelData.Floors[index] = {
					FloorId = index,
					LevelIndex = levelIndex,
					Points = {
						Vector2int16.new(x0, z0),
						Vector2int16.new(x0 + tileSize, z0),
						Vector2int16.new(x0 + tileSize, z0 + tileSize),
						Vector2int16.new(x0, z0 + tileSize),
					},
					FloorMaterial = ceilingMaterial,
					CeilingMaterial = ceilingMaterial,
					FloorParts = {},
					CeilingParts = {},
				}
			end
		end

		-- Objects
		while true do
			local objectId = reader:ReadU16()
			if objectId == 0 then break end
			local obj = {
				ObjectId = tostring(objectId),
				Level = levelIndex,
				Position = Vector3.new(reader:ReadF32(), reader:ReadF32(), reader:ReadF32()),
				Rotation = Vector3.new(reader:ReadF32(), reader:ReadF32(), reader:ReadF32()),
				WallId = reader:ReadU16(),
				Design = {},
				Properties = {},
			}

			while true do
				local designIndex = reader:ReadU16()
				if designIndex == 0 then break end
				obj.Design[designIndex] = reader:ReadString()
			end

			levelData.Objects[objectId] = obj
		end
	end

	return result
end

local function deserializeLevelDataV2(reader): LevelArray
	local result = {} :: LevelArray

	for i = 1, Formex.MaxPlotSize.Levels do
		local levelData: LevelData = {
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

			local wall: WallData = {
				WallId = wallId,
				Level = levelIndex,
				Start = Vector2int16.new(reader:ReadI16(), reader:ReadI16()),
				End = Vector2int16.new(reader:ReadI16(), reader:ReadI16()),
				FrontMaterial = reader:ReadU8(),
				BackMaterial = reader:ReadU8(),
				StartMaterial = reader:ReadU8(),
				EndMaterial = reader:ReadU8(),
			}
			levelData.Walls[wallId] = wall
		end

		while true do
			local floorId = reader:ReadU16()
			if floorId == 0 then break end
			local floorMaterial = reader:ReadU8()
			local ceilingMaterial = reader:ReadU8()
			local pointCount = reader:ReadU8()
			local points = {}
			for _ = 1, pointCount do
				table.insert(points, Vector2int16.new(reader:ReadI8(), reader:ReadI8()))
			end
			levelData.Floors[floorId] = {
				FloorId = floorId,
				LevelIndex = levelIndex,
				Points = points,
				FloorMaterial = floorMaterial,
				CeilingMaterial = ceilingMaterial,
				FloorParts = {},
				CeilingParts = {},
			}
		end

		-- Objects
		while true do
			local objectId = reader:ReadU16()
			if objectId == 0 then break end
			local obj = {
				ObjectId = tostring(objectId),
				Level = levelIndex,
				Position = Vector3.new(reader:ReadF32(), reader:ReadF32(), reader:ReadF32()),
				Rotation = Vector3.new(reader:ReadF32(), reader:ReadF32(), reader:ReadF32()),
				WallId = reader:ReadU16(),
				Design = {},
				Properties = {},
			}

			while true do
				local designIndex = reader:ReadU16()
				if designIndex == 0 then break end
				obj.Design[designIndex] = reader:ReadString()
			end

			levelData.Objects[objectId] = obj
		end
	end

	return result
end

function FormexSerialization.DeserializeLevelData(dataString: string): LevelArray
	local reader = Buffer.read(dataString)
	local version = reader:ReadU16()

	if version == 1 then
		return deserializeLevelDataV1(reader)
	elseif version == 2 then
		return deserializeLevelDataV2(reader)
	else
		error("Unsupported data version: " .. tostring(version))
	end
end

return FormexSerialization