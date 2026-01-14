local EncodingService = game:GetService("EncodingService")

local function serializeBuffer(data: buffer, length: number): string
    -- local compressed = EncodingService:CompressBuffer(data, Enum.CompressionAlgorithm.Zstd)
    return buffer.tostring(EncodingService:Base64Encode(data))
end

local function deserializeBuffer(base64: string): buffer
    local data = EncodingService:Base64Decode(buffer.fromstring(base64))
    -- return EncodingService:DecompressBuffer(data, Enum.CompressionAlgorithm.Zstd)
    return data
end

local Buffer = {}

local function clampPosition(position: number, length: number)
	if position < 0 or position > length then
		error(("Buffer position out of range: %d (length %d)"):format(position, length))
	end
end

function Buffer.new(initialSize: number?)
	local self = {}
	local buf = buffer.create(initialSize or 0)
	local position = 0
	local maxPosition = 0

	local function ensureCapacity(needed: number)
		local required = position + needed
		local length = buffer.len(buf)
		if required <= length then return end
		local newLength = math.max(required, math.max(16, length * 2))
		local newBuf = buffer.create(newLength)
		if maxPosition > 0 then
			buffer.copy(newBuf, 0, buf, 0, maxPosition)
		end
		buf = newBuf
	end

	function self:Position(): number
		return position
	end

	function self:Length(): number
		return maxPosition
	end

	function self:Seek(nextPosition: number)
		if nextPosition < 0 then
			error(("Buffer position out of range: %d"):format(nextPosition))
		end
		position = nextPosition
	end

	function self:WriteU8(value: number)
		ensureCapacity(1)
		buffer.writeu8(buf, position, value)
		position += 1
		maxPosition = math.max(maxPosition, position)
	end

	function self:WriteI8(value: number)
		ensureCapacity(1)
		buffer.writei8(buf, position, value)
		position += 1
		maxPosition = math.max(maxPosition, position)
	end

	function self:WriteU16(value: number)
		ensureCapacity(2)
		buffer.writeu16(buf, position, value)
		position += 2
		maxPosition = math.max(maxPosition, position)
	end

	function self:WriteI16(value: number)
		ensureCapacity(2)
		buffer.writei16(buf, position, value)
		position += 2
		maxPosition = math.max(maxPosition, position)
	end

	function self:WriteU32(value: number)
		ensureCapacity(4)
		buffer.writeu32(buf, position, value)
		position += 4
		maxPosition = math.max(maxPosition, position)
	end

	function self:WriteI32(value: number)
		ensureCapacity(4)
		buffer.writei32(buf, position, value)
		position += 4
		maxPosition = math.max(maxPosition, position)
	end

	function self:WriteF32(value: number)
		ensureCapacity(4)
		buffer.writef32(buf, position, value)
		position += 4
		maxPosition = math.max(maxPosition, position)
	end

	function self:WriteF64(value: number)
		ensureCapacity(8)
		buffer.writef64(buf, position, value)
		position += 8
		maxPosition = math.max(maxPosition, position)
	end

	function self:WriteStringRaw(value: string, count: number?)
		local length = count or #value
		ensureCapacity(length)
		buffer.writestring(buf, position, value, length)
		position += length
		maxPosition = math.max(maxPosition, position)
	end

	function self:WriteString(value: string)
		local length = #value
		self:WriteU16(length)
		self:WriteStringRaw(value, length)
	end

	function self:ToString(): string
		return serializeBuffer(buf, maxPosition)
	end

	function self:ToBuffer(): buffer
		return buf
	end

	return table.freeze(self)
end

function Buffer.read(data: string)
	local self = {}
	local buf = deserializeBuffer(data)
	local position = 0
	local length = buffer.len(buf)
	self.Length = length

	function self:Position(): number
		return position
	end

	function self:Remaining(): number
		return length - position
	end

	function self:Seek(nextPosition: number)
		clampPosition(nextPosition, length)
		position = nextPosition
	end

	function self:ReadU8(): number
		local value = buffer.readu8(buf, position)
		position += 1
		return value
	end

	function self:ReadI8(): number
		local value = buffer.readi8(buf, position)
		position += 1
		return value
	end

	function self:ReadU16(): number
		local value = buffer.readu16(buf, position)
		position += 2
		return value
	end

	function self:ReadI16(): number
		local value = buffer.readi16(buf, position)
		position += 2
		return value
	end

	function self:ReadU32(): number
		local value = buffer.readu32(buf, position)
		position += 4
		return value
	end

	function self:ReadI32(): number
		local value = buffer.readi32(buf, position)
		position += 4
		return value
	end

	function self:ReadF32(): number
		local value = buffer.readf32(buf, position)
		position += 4
		return value
	end

	function self:ReadF64(): number
		local value = buffer.readf64(buf, position)
		position += 8
		return value
	end

	function self:ReadStringRaw(count: number): string
		local value = buffer.readstring(buf, position, count)
		position += count
		return value
	end

	function self:ReadString(): string
		local length = self:ReadU16()
		if length == 0 then
			return ""
		end
		return self:ReadStringRaw(length)
	end

	return table.freeze(self)
end

return Buffer
