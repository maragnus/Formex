--!strict

local Formex = require(script.Parent)

local EPSILON = Formex.EPSILON

local function ensureChildPart(parent: Instance, name: string, allowCreate: boolean): BasePart?
	-- TODO: Refactor to use WallData part references
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("BasePart") then return existing end
	if not allowCreate then return nil end
	local part = Instance.new("Part", parent)
	part.Name = name
	part.Anchored = true
	return part
end

local function ensureFrontPart(model: Model, allowCreate: boolean): BasePart?
	return ensureChildPart(model, Formex.WallPart.FrontBottom, allowCreate)
end

local function ensureBackPart(model: Model, allowCreate: boolean): BasePart?
	local existing = model:FindFirstChild(Formex.WallPart.BackBottom)
	if existing and existing:IsA("BasePart") then
		return existing
	end

	local legacy = model:FindFirstChild("Back")
	if legacy and legacy:IsA("BasePart") then
		legacy.Name = Formex.WallPart.BackBottom
		return legacy
	end

	if not allowCreate then
		return nil
	end

	return ensureChildPart(model, Formex.WallPart.BackBottom, true)
end

local function clearTextures(part: Instance)
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Texture") then
			child:Destroy()
		end
	end
end

local function snapToGrid(value: number): number
	local grid = Formex.GridSize
	return math.round(value / grid) * grid
end

local function resolveWallHeight(value: number?): number
	local resolved = value
	if resolved ~= nil and resolved <= 0 then
		resolved = nil
	end
	resolved = resolved or Formex.LevelHeight
	resolved = snapToGrid(resolved)
	return math.clamp(resolved, Formex.GridSize, Formex.LevelHeight)
end

local function resolveSplitHeight(height: number, value: number?): number?
	if value == nil or value <= Formex.GridSize or height <= Formex.GridSize * 2 then return 0 end
	local snapped = snapToGrid(value)
	local maxSplit = height - Formex.GridSize
	return math.clamp(snapped, Formex.GridSize, maxSplit)
end

local function resolveColor(primary: Color3?, fallback: Color3?): Color3
	return primary or fallback or Color3.new(1, 1, 1)
end

local function normalizeMaterialId(value: number?): number?
	if type(value) ~= "number" or value <= 0 then return nil end
	return value
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

	if math.abs(cross1) <= EPSILON and Formex.Plot.IsPointOnSegment(c, a, b) then return true end
	if math.abs(cross2Value) <= EPSILON and Formex.Plot.IsPointOnSegment(d, a, b) then return true end
	if math.abs(cross3) <= EPSILON and Formex.Plot.IsPointOnSegment(a, c, d) then return true end
	if math.abs(cross4) <= EPSILON and Formex.Plot.IsPointOnSegment(b, c, d) then return true end
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
		return overlap > EPSILON
	end

	if not segmentsIntersect(newStart, newEnd, existingStart, existingEnd) then return false end
	if Formex.Plot.IsPointOnSegment(newStart, existingStart, existingEnd) or Formex.Plot.IsPointOnSegment(newEnd, existingStart, existingEnd) then return false end
	return true
end

Formex.Walls.IsValid = function(plot: Formex.PlotData, wall: Formex.WallData): boolean
	if not wall or not wall.Start or not wall.End then return false end
	local dx = wall.End.X - wall.Start.X
	local dz = wall.End.Y - wall.Start.Y
	local length = math.sqrt(dx * dx + dz * dz)
	if length <= EPSILON then return false end
	if not Formex.Plot.IsLineWithinUnlockedSegments(wall.Start, wall.End, plot.SegmentsUnlocked) then return false end
	local levelIndex = wall.Level or 1
	local levels = plot.Levels
	if levels and levels[levelIndex] then
		local walls = levels[levelIndex].Walls
		if walls then
			for wallId, existing in walls do
				if wallId ~= wall.WallId and existing and existing.Start and existing.End then
					if isWallIntersectionDisallowed(wall.Start, wall.End, existing.Start, existing.End) then return false end
				end
			end
		end
	end

	return true
end

Formex.Walls.Create = function(wall: Formex.WallData, plotPart: BasePart?): Model
	local model = Instance.new("Model")
	model.Name = tostring(wall.WallId)
	local frontPart = ensureFrontPart(model, true)
	frontPart.Anchored = true
	frontPart.CollisionGroup = Formex.CollisionGroup.Structure
	model.PrimaryPart = frontPart
	wall.Part = model
	Formex.Walls.Edit(wall, plotPart)
	return model
end

Formex.Walls.Edit = function(wall: Formex.WallData, plotPart: BasePart?, allowCreateParts: boolean?)
	local model = wall.Part
	if not model or not plotPart then return end
	model.Name = tostring(wall.WallId)
	local allowCreate = allowCreateParts ~= false
	local frontPart = ensureFrontPart(model, allowCreate)
	local backPart = ensureBackPart(model, allowCreate)
	if not frontPart or not backPart then return end
	frontPart.Name = Formex.WallPart.FrontBottom
	backPart.Name = Formex.WallPart.BackBottom
	model.PrimaryPart = frontPart
	wall.FrontBottomPart = frontPart
	wall.BackBottomPart = backPart

	local height = resolveWallHeight(wall.Height)
	local frontSplitHeight = resolveSplitHeight(height, wall.FrontSplitHeight)
	local backSplitHeight = resolveSplitHeight(height, wall.BackSplitHeight)
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
	frontPart.Transparency = 0 -- Disable invisibility in case it was set

	local frontBottomMaterial = normalizeMaterialId(wall.FrontBottomMaterial)
		or normalizeMaterialId(wall.FrontTopMaterial)
		or normalizeMaterialId(wall.FrontMaterial)
		or Formex.DefaultWallMaterial
	local frontTopMaterial = normalizeMaterialId(wall.FrontTopMaterial) or frontBottomMaterial
	local backBottomMaterial = normalizeMaterialId(wall.BackBottomMaterial)
		or normalizeMaterialId(wall.BackTopMaterial)
		or normalizeMaterialId(wall.BackMaterial)
		or frontBottomMaterial
	local backTopMaterial = normalizeMaterialId(wall.BackTopMaterial) or backBottomMaterial

	local frontBottomColor = resolveColor(wall.FrontBottomColor, wall.FrontTopColor)
	local frontTopColor = resolveColor(wall.FrontTopColor, frontBottomColor)
	local backBottomColor = resolveColor(wall.BackBottomColor, wall.BackTopColor)
	local backTopColor = resolveColor(wall.BackTopColor, backBottomColor)

	model:SetAttribute("Start", Vector2.new(startPoint.X, startPoint.Y))
	model:SetAttribute("End", Vector2.new(endPoint.X, endPoint.Y))
	model:SetAttribute("WallHeight", height)
	model:SetAttribute("FrontSplitHeight", frontSplitHeight)
	model:SetAttribute("BackSplitHeight", backSplitHeight)
	model:SetAttribute("FrontTopMaterial", frontTopMaterial)
	model:SetAttribute("FrontBottomMaterial", frontBottomMaterial)
	model:SetAttribute("BackTopMaterial", backTopMaterial)
	model:SetAttribute("BackBottomMaterial", backBottomMaterial)
	model:SetAttribute("FrontTopColor", frontTopColor)
	model:SetAttribute("FrontBottomColor", frontBottomColor)
	model:SetAttribute("BackTopColor", backTopColor)
	model:SetAttribute("BackBottomColor", backBottomColor)

	clearTextures(frontPart)
	clearTextures(backPart)

	local function applySegment(target: BasePart, segmentHeight: number, segmentCenterY: number, offsetX: number)
		target.Size = Vector3.new(sideThickness, segmentHeight, length)
		target.CFrame = wallCFrame * CFrame.new(offsetX, segmentCenterY - (levelOffset + height / 2), 0)
		target.Anchored = true
		target.CollisionGroup = frontPart.CollisionGroup
		target.CanCollide = frontPart.CanCollide
		target.CanTouch = frontPart.CanTouch
		target.CanQuery = frontPart.CanQuery
		target.CastShadow = frontPart.CastShadow
		target.Transparency = frontPart.Transparency
	end

	local function applySide(splitHeight: number?, bottomPart: BasePart, topName: string, offsetX: number, bottomMaterial: number, topMaterial: number, bottomColor: Color3, topColor: Color3): BasePart?
		local topPart: BasePart? = nil
		local hasSplit = splitHeight ~= nil and splitHeight > 0
		if hasSplit then
			topPart = ensureChildPart(model, topName, allowCreate)
			if topPart then
				clearTextures(topPart)
			end
		elseif allowCreate then
			local existing = model:FindFirstChild(topName)
			if existing and existing:IsA("BasePart") then
				existing:Destroy()
			end
		end

		if hasSplit then
			local bottomHeight = splitHeight
			local topHeight = height - splitHeight
			applySegment(bottomPart, bottomHeight, levelOffset + (bottomHeight / 2), offsetX)
			if topPart then
				applySegment(topPart, topHeight, levelOffset + splitHeight + (topHeight / 2), offsetX)
			end
			Formex.Util.ApplyMaterial(bottomPart, bottomMaterial, bottomColor)
			if topPart then
				Formex.Util.ApplyMaterial(topPart, topMaterial, topColor)
			end
		else
			applySegment(bottomPart, height, levelOffset + (height / 2), offsetX)
			Formex.Util.ApplyMaterial(bottomPart, topMaterial, topColor)
		end

		return topPart
	end

	wall.FrontTopPart = applySide(frontSplitHeight, frontPart, Formex.WallPart.FrontTop, -sideOffset, frontBottomMaterial, frontTopMaterial, frontBottomColor, frontTopColor)
	wall.BackTopPart = applySide(backSplitHeight, backPart, Formex.WallPart.BackTop, sideOffset, backBottomMaterial, backTopMaterial, backBottomColor, backTopColor)
end

Formex.Walls.Divide = function(wall: Formex.WallData, distance: number): {Formex.WallData}
	-- TODO returns two new walls split at `distance` from `wall.Start`, snapped to LayoutGridSize
	return {wall}
end

return Formex.Walls
