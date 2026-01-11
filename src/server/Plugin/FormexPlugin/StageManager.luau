--!strict

local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local Constants = require(script.Parent:WaitForChild("Constants"))
local GridTexture = require(script.Parent:WaitForChild("GridTexture"))
local PrefabFolders = require(script.Parent:WaitForChild("PrefabFolders"))
local PrefabMetadata = require(script.Parent:WaitForChild("PrefabMetadata"))
local PrefabSizing = require(script.Parent:WaitForChild("PrefabSizing"))

local StageManager = {}

type StageInfo = {
	StageModel: Model,
	SizeGuide: BasePart?,
}

local StageParts = {
	Floor = "StageFloor",
	Back = "StageBack",
	Ceiling = "StageCeiling",
	Wall = "StageWall",
}

local function getStageModel(root: Model): Model?
	local stageFolder = PrefabFolders.GetStageRoot()
	local stageId = root:GetAttribute(Constants.Attributes.StageId)
	if stageId and stageFolder then
		for _, child in ipairs(stageFolder:GetChildren()) do
			if child:IsA("Model") and child:GetAttribute(Constants.Attributes.StageId) == stageId then
				return child
			end
		end
		local legacy = stageFolder:FindFirstChild(stageId)
		if legacy and legacy:IsA("Model") then
			legacy:SetAttribute(Constants.Attributes.StageId, stageId)
			return legacy
		end
	end
	return nil
end

local function clearStage(root: Model)
	local stage = getStageModel(root)
	if stage then
		stage:Destroy()
	end
	local legacy = root:FindFirstChild(Constants.Prefab.StageModelName)
	if legacy and legacy:IsA("Model") then
		legacy:Destroy()
	end
end

local function clearStageParts(stage: Model)
	for _, child in ipairs(stage:GetChildren()) do
		if child:IsA("BasePart") and child.Name ~= Constants.Prefab.SizeGuideName then
			child:Destroy()
		end
	end
end

local function createStagePart(stage: Model, name: string, size: Vector3, cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Air
	part.Transparency = 1
	part.Locked = true
	part.CFrame = cframe
	part.Parent = stage
	return part
end

local function buildStageParts(stage: Model, rootPivot: CFrame, objectMount: string?): BasePart?
	clearStageParts(stage)

	local stageSize = Constants.Stage.Size
	local half = stageSize / 2
	local floorThickness = Constants.Stage.FloorThickness
	local backThickness = Constants.WallThickness

	local mount = PrefabMetadata.ResolveObjectMount(objectMount)
	local useFloor = mount == "Surface" or mount == "Floor" or mount == "Wall" or mount == "Door" or mount == "Window"
	local useCeiling = mount == "Ceiling"
	local useBack = mount == "Surface" or mount == "Floor" or mount == "Ceiling" or mount == "Wall"
	local useWall = mount == "Door" or mount == "Window"

	local floorOffsetV = (mount == "Surface" or mount == "Floor" or mount == "Ceiling") and 2 or 0
	local primarySurface: BasePart? = nil

	if useFloor then
		local floor = createStagePart(
			stage,
			StageParts.Floor,
			Vector3.new(stageSize, floorThickness, stageSize),
			rootPivot * CFrame.new(0, -half, 0)
		)
		GridTexture.Apply(floor, Enum.NormalId.Top, {
			OffsetStudsU = 2,
			OffsetStudsV = floorOffsetV,
		})
		primarySurface = floor
	end

	if useCeiling then
		local ceiling = createStagePart(
			stage,
			StageParts.Ceiling,
			Vector3.new(stageSize, floorThickness, stageSize),
			rootPivot * CFrame.new(0, half, 0)
		)
		GridTexture.Apply(ceiling, Enum.NormalId.Bottom, {
			OffsetStudsU = 2,
			OffsetStudsV = 2,
		})
		primarySurface = ceiling
	end

	if useBack then
		local back = createStagePart(
			stage,
			StageParts.Back,
			Vector3.new(stageSize, stageSize, backThickness),
			rootPivot * CFrame.new(0, 0, -half)
		)
		GridTexture.Apply(back, Enum.NormalId.Front, { OffsetStudsU = 2 })
		GridTexture.Apply(back, Enum.NormalId.Back, { OffsetStudsU = 2 })
	end

	if useWall then
		local wall = createStagePart(
			stage,
			StageParts.Wall,
			Vector3.new(stageSize, stageSize, backThickness),
			rootPivot * CFrame.new(0, 0, 0)
		)
		GridTexture.Apply(wall, Enum.NormalId.Front, { OffsetStudsU = 2 })
		GridTexture.Apply(wall, Enum.NormalId.Back, { OffsetStudsU = 2 })
	end

	return primarySurface
end

local function updateSizeGuide(guide: BasePart, rootPivot: CFrame, size: Vector3)
	local stageHalf = Constants.Stage.Size / 2
	local guideCenter = rootPivot * CFrame.new(0, -stageHalf + (size.Y / 2), 0)
	guide.Size = size
	guide.CFrame = guideCenter
end

local function ensureSizeGuide(stage: Model, rootPivot: CFrame, size: Vector3): BasePart
	local guide = stage:FindFirstChild(Constants.Prefab.SizeGuideName)
	if not (guide and guide:IsA("BasePart")) then
		local created = Instance.new("Part")
		created.Name = Constants.Prefab.SizeGuideName
		created.Anchored = true
		created.CanCollide = false
		created.CanTouch = false
		created.CanQuery = false
		created.CastShadow = false
		created.Locked = true
		created.Transparency = 0.7
		created.Color = Color3.fromRGB(66, 168, 255)
		created.Material = Enum.Material.Glass
		created.Parent = stage
		guide = created
	end

	updateSizeGuide(guide :: BasePart, rootPivot, size)
	return guide :: BasePart
end

function StageManager.CreateStage(root: Model, stageIndex: number): StageInfo
	clearStage(root)

	local stageFolder = PrefabFolders.GetStageRoot()
	local stageId = root:GetAttribute(Constants.Attributes.StageId)
	if not stageId or stageId == "" then
		stageId = HttpService:GenerateGUID(false)
		root:SetAttribute(Constants.Attributes.StageId, stageId)
	end

	local stage = Instance.new("Model", stageFolder)
	stage.Name = root.Name
	stage:SetAttribute(Constants.Attributes.StageId, stageId)

	local rootPivot = root:GetPivot()
	stage:PivotTo(rootPivot)
	local attributes = PrefabMetadata.ReadAttributes(root)
	buildStageParts(stage, rootPivot, attributes.ObjectMount)

	local size = attributes.Size
	if not size or typeof(size) ~= "Vector3" then
		size = PrefabSizing.CalculatePrefabSize(root)
	end
	size = PrefabSizing.SnapSize(size, attributes.ObjectMount)
	StageManager.PositionStage(root, stageIndex)

	return {
		StageModel = stage,
		SizeGuide = nil,
	}
end

function StageManager.UpdateStageDesign(root: Model, objectMount: string?)
	local stage = getStageModel(root)
	if not stage then
		return
	end
	local rootPivot = root:GetPivot()
	stage:PivotTo(rootPivot)
	buildStageParts(stage, rootPivot, objectMount)
end

function StageManager.UpdateStageName(root: Model)
	local stage = getStageModel(root)
	if not stage then
		return
	end
	stage.Name = root.Name
end

function StageManager.PositionStage(root: Model, stageIndex: number)
	local offset = (stageIndex - 1) * (Constants.Stage.Size + Constants.Stage.Gap)
	local position = Vector3.new(offset, Constants.Stage.YOffset, 0)
	local current = root:GetPivot()
	local rotation = current - current.Position
	local target = CFrame.new(position) * rotation
	root:PivotTo(target)
	local stage = getStageModel(root)
	if stage then
		stage:PivotTo(target)
	end
end

function StageManager.LayoutStages(roots: {Model})
	for index, root in ipairs(roots) do
		StageManager.PositionStage(root, index)
	end
end

function StageManager.RefreshSizeGuide(root: Model, size: Vector3)
	local stage = getStageModel(root)
	if not stage then
		return
	end
	local guide = stage:FindFirstChild(Constants.Prefab.SizeGuideName)
	if guide and guide:IsA("BasePart") then
		local rootPivot = root:GetPivot()
		updateSizeGuide(guide, rootPivot, size)
	end
end

function StageManager.EnsureSizeGuide(root: Model, size: Vector3): BasePart?
	local stage = getStageModel(root)
	if not stage then
		return nil
	end
	local rootPivot = root:GetPivot()
	return ensureSizeGuide(stage, rootPivot, size)
end

function StageManager.RemoveStage(root: Model)
	clearStage(root)
end

function StageManager.GetStage(root: Model): Model?
	return getStageModel(root)
end

function StageManager.FocusCameraOnStage(root: Model)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local center = root:GetPivot().Position
	local offset = Vector3.new(Constants.Stage.Size * 1.25, Constants.Stage.Size * 0.75, Constants.Stage.Size * 1.25)
	camera.CFrame = CFrame.new(center + offset, center)
end

return StageManager
