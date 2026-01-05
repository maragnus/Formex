--!strict

local Formex = require(script.Parent:FindFirstChild("Formex"))
Formex.Math = require(script.Parent:FindFirstChild("FormexMath"))

local EPSILON = Formex.EPSILON

Formex.Walls = {}

local BACK_PART_NAME = "BackSide"
Formex.Walls.BackPartName = BACK_PART_NAME

local function ensureBackPart(frontPart: BasePart): BasePart
	local existing = frontPart:FindFirstChild(BACK_PART_NAME)
	if existing and existing:IsA("BasePart") then
		return existing
	end

	local backPart = Instance.new("Part")
	backPart.Name = BACK_PART_NAME
	backPart.Parent = frontPart
	return backPart
end

local function cross2(a: Vector2, b: Vector2): number
	return a.X * b.Y - a.Y * b.X
end

local function segmentsIntersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2): boolean
	local ab = b - a
	local cd = d - c
	local ac = c - a
	local ad = d - a
	local ca = a - c
	local cb = b - c

	local cross1 = cross2(ab, ac)
	local cross2Value = cross2(ab, ad)
	local cross3 = cross2(cd, ca)
	local cross4 = cross2(cd, cb)

	if math.abs(cross1) <= EPSILON and Formex.Plot.IsPointOnSegment(c, a, b) then
		return true
	end
	if math.abs(cross2Value) <= EPSILON and Formex.Plot.IsPointOnSegment(d, a, b) then
		return true
	end
	if math.abs(cross3) <= EPSILON and Formex.Plot.IsPointOnSegment(a, c, d) then
		return true
	end
	if math.abs(cross4) <= EPSILON and Formex.Plot.IsPointOnSegment(b, c, d) then
		return true
	end

	return (cross1 > 0 and cross2Value < 0 or cross1 < 0 and cross2Value > 0)
		and (cross3 > 0 and cross4 < 0 or cross3 < 0 and cross4 > 0)
end

local function getOverlapLength(a: Vector2, b: Vector2, c: Vector2, d: Vector2): number
	if math.abs(b.X - a.X) >= math.abs(b.Y - a.Y) then
		local min1, max1 = math.min(a.X, b.X), math.max(a.X, b.X)
		local min2, max2 = math.min(c.X, d.X), math.max(c.X, d.X)
		return math.min(max1, max2) - math.max(min1, min2)
	else
		local min1, max1 = math.min(a.Y, b.Y), math.max(a.Y, b.Y)
		local min2, max2 = math.min(c.Y, d.Y), math.max(c.Y, d.Y)
		return math.min(max1, max2) - math.max(min1, min2)
	end
end

local function isWallIntersectionDisallowed(newStart: Vector2, newEnd: Vector2, existingStart: Vector2, existingEnd: Vector2): boolean
	local newDir = newEnd - newStart
	if math.abs(cross2(newDir, existingStart - newStart)) <= EPSILON
	and math.abs(cross2(newDir, existingEnd - newStart)) <= EPSILON then
		local overlap = getOverlapLength(newStart, newEnd, existingStart, existingEnd)
		if overlap > EPSILON then
			return true
		end
		if Formex.Plot.IsPointOnSegment(newStart, existingStart, existingEnd) or Formex.Plot.IsPointOnSegment(newEnd, existingStart, existingEnd) then
			return false
		end
		return true
	end

	if not segmentsIntersect(newStart, newEnd, existingStart, existingEnd) then
		return false
	end

	if Formex.Plot.IsPointOnSegment(newStart, existingStart, existingEnd) or Formex.Plot.IsPointOnSegment(newEnd, existingStart, existingEnd) then
		return false
	end

	return true
end

function Formex.IsWallValid(plot: Formex.PlotData, wall: Formex.WallData)
	if not wall or not wall.Start or not wall.End then
		return false
	end

	local dx = wall.End.X - wall.Start.X
	local dz = wall.End.Y - wall.Start.Y
	local length = math.sqrt(dx * dx + dz * dz)
	if length <= EPSILON then
		return false
	end

	if not Formex.Plot.IsLineWithinUnlockedSegments(wall.Start, wall.End, plot.SegmentsUnlocked) then
		return false
	end

	local levelIndex = wall.Level or 1
	local levels = (plot :: any).Levels
	if levels and levels[levelIndex] then
		local walls = levels[levelIndex].Walls
		if walls then
			for wallId, existing in walls do
				if wallId ~= wall.WallId and existing and existing.Start and existing.End then
					if isWallIntersectionDisallowed(wall.Start, wall.End, existing.Start, existing.End) then
						return false
					end
				end
			end
		end
	end

	return true
end

function Formex.Walls.Create(wall: Formex.WallData, plotPart: BasePart?): Part
	local part = Instance.new("Part")
	part.Name = tostring(wall.WallId)
	part.Anchored = true
	part.CollisionGroup = Formex.CollisionGroup.Structure
	wall.Part = part
	Formex.Walls.Edit(wall, plotPart)
	return part
end

function Formex.Walls.Edit(wall: Formex.WallData, plotPart: BasePart?)
	local part = wall.Part
	if not part or not plotPart then return end
	local backPart = ensureBackPart(part)
	wall.BackPart = backPart

	local height = Formex.SegmentSize.Height
	local levelIndex = wall.Level or 1
	local startPoint = wall.Start
	local endPoint = wall.End
	local dx = endPoint.X - startPoint.X
	local dz = endPoint.Y - startPoint.Y
	local length = math.max(math.sqrt(dx * dx + dz * dz), 1)

	local levelOffset = Formex.Plot.GetLevelOffset(levelIndex)
	local midLocal = Vector3.new((startPoint.X + endPoint.X) / 2, levelOffset + height / 2, (startPoint.Y + endPoint.Y) / 2)
	local worldMid = plotPart.CFrame:PointToWorldSpace(midLocal)

	local dirLocal = Vector3.new(dx, 0, dz)
	if dirLocal.Magnitude <= EPSILON then
		dirLocal = Vector3.new(0, 0, 1)
	end
	local worldDir = plotPart.CFrame:VectorToWorldSpace(dirLocal)

	local wallThickness = Formex.WallThickness
	local sideThickness = wallThickness / 2
	local sideOffset = wallThickness / 4

	local wallCFrame = CFrame.lookAt(worldMid, worldMid + worldDir)
	part.Size = Vector3.new(sideThickness, height, length)
	part.CFrame = wallCFrame * CFrame.new(-sideOffset, 0, 0)
	part.Transparency = 0 -- Disable invisibility in case it was set

	backPart.Size = Vector3.new(sideThickness, height, length)
	backPart.CFrame = wallCFrame * CFrame.new(sideOffset, 0, 0)
	backPart.Anchored = part.Anchored
	backPart.CollisionGroup = part.CollisionGroup
	backPart.CanCollide = part.CanCollide
	backPart.CanTouch = part.CanTouch
	backPart.CanQuery = part.CanQuery
	backPart.CastShadow = part.CastShadow
	backPart.Transparency = part.Transparency

	local frontMaterial = wall.FrontMaterial or Formex.DefaultWallMaterial
	local backMaterial = wall.BackMaterial or frontMaterial
	local startMaterial = wall.StartMaterial or frontMaterial
	local endMaterial = wall.EndMaterial or frontMaterial

    local ensureTexture = Formex.Util.EnsureTexture
	local frontTexture = ensureTexture(part, "Front", Enum.NormalId.Left)
	local startTexture = ensureTexture(part, "Start", Enum.NormalId.Back)
	local endTexture = ensureTexture(part, "End", Enum.NormalId.Front)
	local topTexture = ensureTexture(part, "Top", Enum.NormalId.Top)

	Formex.UpdateTexture(part, frontTexture, frontMaterial)
	Formex.UpdateTexture(part, startTexture, startMaterial)
	Formex.UpdateTexture(part, endTexture, endMaterial)
	Formex.UpdateTexture(part, topTexture, Formex.WallTopMaterial)

	local legacyBackTexture = part:FindFirstChild("Back")
	if legacyBackTexture and legacyBackTexture:IsA("Texture") then
		legacyBackTexture.Face = Enum.NormalId.Right
		Formex.UpdateTexture(part, legacyBackTexture, backMaterial)
	end

	local backTexture = ensureTexture(backPart, "Back", Enum.NormalId.Right)
	local backStartTexture = ensureTexture(backPart, "Start", Enum.NormalId.Back)
	local backEndTexture = ensureTexture(backPart, "End", Enum.NormalId.Front)
	local backTopTexture = ensureTexture(backPart, "Top", Enum.NormalId.Top)

	Formex.UpdateTexture(backPart, backTexture, backMaterial)
	Formex.UpdateTexture(backPart, backStartTexture, startMaterial)
	Formex.UpdateTexture(backPart, backEndTexture, endMaterial)
	Formex.UpdateTexture(backPart, backTopTexture, Formex.WallTopMaterial)
end

function Formex.Walls.Divide(wall: Formex.WallData, distance: number): {Formex.WallData}
	-- TODO returns two new walls split at `distance` from `wall.Start`
end

return Formex.Walls
