--!strict

local Formex = require(script.Parent:FindFirstChild("Formex"))
Formex.Math = require(script.Parent:FindFirstChild("FormexMath"))

local EPSILON = Formex.EPSILON

Formex.Plot = {}

function Formex.Segments.GetRowColumn(index: number): (number, number)
	if index < 1 or index > Formex.Segments.Count then
		error("Segment index out of range: " .. tostring(index))
	end

	local row = math.ceil(index / Formex.Segments.GridWidth)
	local column = ((index - 1) % Formex.Segments.GridWidth) + 1
	return row, column
end

function Formex.Segments.GetIndex(row: number, column: number): number
	if row < 1 or row > Formex.Segments.GridHeight or column < 1 or column > Formex.Segments.GridWidth then
		error("Segment row/column out of range: " .. tostring(row) .. "," .. tostring(column))
	end

	return (row - 1) * Formex.Segments.GridWidth + column
end

function Formex.Segments.Bit(index: number): number
	if index < 1 or index > Formex.Segments.Count then
		error("Segment index out of range: " .. tostring(index))
	end

	return bit32.lshift(1, index - 1)
end

function Formex.Segments.IsUnlocked(mask: number?, index: number): boolean
	return bit32.band(mask or 0, Formex.Segments.Bit(index)) ~= 0
end

function Formex.Segments.Unlock(mask: number?, index: number): number
	return bit32.bor(mask or 0, Formex.Segments.Bit(index))
end

function Formex.Segments.CountUnlocked(mask: number?): number
	local unlocked = 0
	for index = 1, Formex.Segments.Count do
		if Formex.Segments.IsUnlocked(mask, index) then
			unlocked += 1
		end
	end
	return unlocked
end

function Formex.Segments.GetAllUnlocked(mask: number?): {number}
	local unlocked = {}
	for index = 1, Formex.Segments.Count do
		if Formex.Segments.IsUnlocked(mask, index) then
			table.insert(unlocked, index)
		end
	end
	return unlocked
end

function Formex.Segments.GetBounds(plotPart: BasePart, segmentIndex: number, levelsUnlocked: number?): Formex.SegmentBounds
	local row, column = Formex.Segments.GetRowColumn(segmentIndex)
	local xOffset = (column - (Formex.Segments.GridWidth + 1) / 2) * Formex.SegmentSize.Width
	local zOffset = (row - (Formex.Segments.GridHeight + 1) / 2) * Formex.SegmentSize.Depth
	local height = math.max(1, levelsUnlocked or 1) * Formex.LevelHeight

	local segmentCFrame = plotPart.CFrame * CFrame.new(xOffset, 0, zOffset)
	local size = Vector3.new(Formex.SegmentSize.Width, height, Formex.SegmentSize.Depth)

	return {
		Index = segmentIndex,
		Row = row,
		Column = column,
		CFrame = segmentCFrame,
		Position = segmentCFrame.Position,
		Size = size,
		Extents = size / 2,
	}
end

function Formex.Plot.IsPointNear(plotCenter: Vector3, position: Vector3, border: number): boolean
	local plotDimensions = Formex.Dimensions
	local plotWidth = plotDimensions.Width
	local plotDepth = plotDimensions.Depth
	local plotHeight = plotDimensions.Height

	local xDiff = math.abs(position.X - plotCenter.X)
	local yDiff = math.abs(position.Y - plotCenter.Y)
	local zDiff = math.abs(position.Z - plotCenter.Z)

	return xDiff <= (plotWidth / 2 + border) and yDiff <= (plotHeight / 2 + border) and zDiff <= (plotDepth / 2 + border)
end

function Formex.Plot.GetLevelOffset(level: number): number
	return (math.max(level, 1) - 1) * Formex.SegmentSize.Height
end

local function cross2(a: Vector2, b: Vector2): number
	return a.X * b.Y - a.Y * b.X
end

function Formex.Plot.IsPointOnSegment(point: Vector2, startPoint: Vector2, endPoint: Vector2): boolean
	if math.abs(cross2(endPoint - startPoint, point - startPoint)) > EPSILON then
		return false
	end
	local minX = math.min(startPoint.X, endPoint.X) - EPSILON
	local maxX = math.max(startPoint.X, endPoint.X) + EPSILON
	local minY = math.min(startPoint.Y, endPoint.Y) - EPSILON
	local maxY = math.max(startPoint.Y, endPoint.Y) + EPSILON
	return point.X >= minX and point.X <= maxX and point.Y >= minY and point.Y <= maxY
end


local function getSegmentCenter(index: number): (number, number)
	local row, column = Formex.Segments.GetRowColumn(index)
	local xOffset = (column - (Formex.Segments.GridWidth + 1) / 2) * Formex.SegmentSize.Width
	local zOffset = (row - (Formex.Segments.GridHeight + 1) / 2) * Formex.SegmentSize.Depth
	return xOffset, zOffset
end

local function isPointInUnlockedSegments(point: Vector2, mask: number?): boolean
	if not mask or mask == 0 then
		return false
	end

	local halfWidth = Formex.SegmentSize.Width / 2
	local halfDepth = Formex.SegmentSize.Depth / 2

	for index = 1, Formex.Segments.Count do
		if Formex.Segments.IsUnlocked(mask, index) then
			local centerX, centerZ = getSegmentCenter(index)
			if math.abs(point.X - centerX) <= halfWidth + EPSILON
			and math.abs(point.Y - centerZ) <= halfDepth + EPSILON then
				return true
			end
		end
	end

	return false
end

Formex.Plot.IsPointInUnlockedSegments = isPointInUnlockedSegments

function Formex.Plot.IsLineWithinUnlockedSegments(startPoint: Vector2 | Vector2int16, endPoint: Vector2 | Vector2int16, mask: number?): boolean
	if not isPointInUnlockedSegments(startPoint, mask) or not isPointInUnlockedSegments(endPoint, mask) then
		return false
	end

	if typeof(startPoint) ~= "Vector2" or typeof(endPoint) ~= "Vector2" then
		startPoint = Vector2.new(startPoint.X, startPoint.Y)
		endPoint = Vector2.new(endPoint.X, endPoint.Y)
	end

	local direction: Vector2 = endPoint - startPoint
	local length = direction.Magnitude
	if length <= EPSILON then return false end

	local step = math.max(Formex.GridSize, 1)
	local steps = math.floor(length / step)
	local unit = direction / length

	for i = 1, steps do
		local point = startPoint + unit * (i * step)
		if not isPointInUnlockedSegments(point, mask) then
			return false
		end
	end

	return true
end

return Formex.Plot