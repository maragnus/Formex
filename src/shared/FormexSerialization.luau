--!strict

local Formex = require(script.Parent:FindFirstChild("Formex"))

local DATA_VERSION: number = 3
local INITIAL_BUFFER_SIZE: number = 1024
local MAX_LEVELS: number = 5

local Buffer = require(script.Parent.Buffer)

local FormexSerialization = {}

local function writeMaterialId(writer, value: number?)
	writer:WriteU8(value and value > 0 and value or 0)
end

local function readMaterialId(reader): number?
	local value = reader:ReadU8()
	if value == 0 then
		return nil
	end
	return value
end

local function writeOptionalU8(writer, value: number?)
	writer:WriteU8(value and value > 0 and value or 0)
end

local function readOptionalU8(reader): number?
	local value = reader:ReadU8()
	if value == 0 then
		return nil
	end
	return value
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

function FormexSerialization.SerializeLevelData(levels: Formex.LevelArray): string
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
				writeOptionalU8(writer, wall.Height and math.round(wall.Height) or nil)
				writeOptionalU8(writer, wall.FrontSplitHeight and math.round(wall.FrontSplitHeight) or nil)
				writeOptionalU8(writer, wall.BackSplitHeight and math.round(wall.BackSplitHeight) or nil)
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
				local points = floor.Points or {}
				writer:WriteU16(floorId)
				writeMaterialId(writer, floor.FloorMaterial)
				writeMaterialId(writer, floor.CeilingMaterial)
				writeMaterialId(writer, floor.FoundationMaterial)
				writeColor(writer, floor.FloorColor)
				writeColor(writer, floor.CeilingColor)
				writeColor(writer, floor.FoundationColor)
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

local function deserializeLevelDataV1(reader): Formex.LevelArray
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

			local startPoint = Vector2int16.new(reader:ReadI16(), reader:ReadI16())
			local endPoint = Vector2int16.new(reader:ReadI16(), reader:ReadI16())
			local frontMaterial = readMaterialId(reader)
			local backMaterial = readMaterialId(reader)
			reader:ReadU8() -- legacy start material
			reader:ReadU8() -- legacy end material

			local resolvedFront = frontMaterial or Formex.DefaultWallMaterial
			local resolvedBack = backMaterial or resolvedFront
			local wall: Formex.WallData = {
				WallId = wallId,
				Level = levelIndex,
				Start = startPoint,
				End = endPoint,
				FrontTopMaterial = resolvedFront,
				FrontBottomMaterial = resolvedFront,
				BackTopMaterial = resolvedBack,
				BackBottomMaterial = resolvedBack,
				FrontTopColor = Color3.new(1, 1, 1),
				FrontBottomColor = Color3.new(1, 1, 1),
				BackTopColor = Color3.new(1, 1, 1),
				BackBottomColor = Color3.new(1, 1, 1),
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
				FloorMaterial = floorMaterial ~= 0 and floorMaterial or nil,
				CeilingMaterial = ceilingMaterial ~= 0 and ceilingMaterial or nil,
				FoundationMaterial = Formex.DefaultFoundationMaterial,
				FloorColor = Color3.new(1, 1, 1),
				CeilingColor = Color3.new(1, 1, 1),
				FoundationColor = Color3.new(1, 1, 1),
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
					FloorMaterial = ceilingMaterial ~= 0 and ceilingMaterial or nil,
					CeilingMaterial = ceilingMaterial ~= 0 and ceilingMaterial or nil,
					FoundationMaterial = Formex.DefaultFoundationMaterial,
					FloorColor = Color3.new(1, 1, 1),
					CeilingColor = Color3.new(1, 1, 1),
					FoundationColor = Color3.new(1, 1, 1),
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

local function deserializeLevelDataV2(reader): Formex.LevelArray
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

			local startPoint = Vector2int16.new(reader:ReadI16(), reader:ReadI16())
			local endPoint = Vector2int16.new(reader:ReadI16(), reader:ReadI16())
			local frontMaterial = readMaterialId(reader)
			local backMaterial = readMaterialId(reader)
			reader:ReadU8() -- legacy start material
			reader:ReadU8() -- legacy end material

			local resolvedFront = frontMaterial or Formex.DefaultWallMaterial
			local resolvedBack = backMaterial or resolvedFront
			local wall: Formex.WallData = {
				WallId = wallId,
				Level = levelIndex,
				Start = startPoint,
				End = endPoint,
				FrontTopMaterial = resolvedFront,
				FrontBottomMaterial = resolvedFront,
				BackTopMaterial = resolvedBack,
				BackBottomMaterial = resolvedBack,
				FrontTopColor = Color3.new(1, 1, 1),
				FrontBottomColor = Color3.new(1, 1, 1),
				BackTopColor = Color3.new(1, 1, 1),
				BackBottomColor = Color3.new(1, 1, 1),
			}
			levelData.Walls[wallId] = wall
		end

		while true do
			local floorId = reader:ReadU16()
			if floorId == 0 then break end
			local floorMaterial = readMaterialId(reader)
			local ceilingMaterial = readMaterialId(reader)
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
				FoundationMaterial = Formex.DefaultFoundationMaterial,
				FloorColor = Color3.new(1, 1, 1),
				CeilingColor = Color3.new(1, 1, 1),
				FoundationColor = Color3.new(1, 1, 1),
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

local function deserializeLevelDataV3(reader): Formex.LevelArray
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
				Height = readOptionalU8(reader),
				FrontSplitHeight = readOptionalU8(reader),
				BackSplitHeight = readOptionalU8(reader),
				FrontTopMaterial = readMaterialId(reader),
				FrontBottomMaterial = readMaterialId(reader),
				BackTopMaterial = readMaterialId(reader),
				BackBottomMaterial = readMaterialId(reader),
				FrontTopColor = readColor(reader),
				FrontBottomColor = readColor(reader),
				BackTopColor = readColor(reader),
				BackBottomColor = readColor(reader),
			}
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
				FoundationMaterial = foundationMaterial,
				FloorColor = floorColor,
				CeilingColor = ceilingColor,
				FoundationColor = foundationColor,
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

function FormexSerialization.DeserializeLevelData(dataString: string): Formex.LevelArray
	local reader = Buffer.read(dataString)
	local version = reader:ReadU16()

	if version == 1 then
		return deserializeLevelDataV1(reader)
	elseif version == 2 then
		return deserializeLevelDataV2(reader)
	elseif version == 3 then
		return deserializeLevelDataV3(reader)
	else
		error("Unsupported data version: " .. tostring(version))
	end
end

return FormexSerialization
