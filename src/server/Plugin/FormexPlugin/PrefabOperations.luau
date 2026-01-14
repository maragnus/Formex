--!strict

local Workspace = game:GetService("Workspace")

local Constants = require(script.Parent:WaitForChild("Constants"))
local PrefabCatalog = require(script.Parent:WaitForChild("PrefabCatalog"))
local PrefabFolders = require(script.Parent:WaitForChild("PrefabFolders"))
local PrefabMetadata = require(script.Parent:WaitForChild("PrefabMetadata"))
local PrefabSizing = require(script.Parent:WaitForChild("PrefabSizing"))
local PluginUtils = require(script.Parent:WaitForChild("PluginUtils"))
local StageManager = require(script.Parent:WaitForChild("StageManager"))

local PrefabOperations = {}
local guidePreviewTokens = setmetatable({}, { __mode = "k" })

type PrefabEditData = {
	PrefabPath: string?,
	DisplayName: string?,
	IconAssetId: number?,
	ObjectMount: string?,
	Size: Vector3?,
	Categories: string?,
}

local function ensureSubtractModel(root: Model)
	local subtract = root:FindFirstChild(Constants.Prefab.SubtractModelName)	
	if subtract and subtract:IsA("Model") then
		-- Force a primary part
		if subtract.PrimaryPart == nil then
			local primary = subtract:FindFirstChildWhichIsA("BasePart", true)
			if primary then
				subtract.PrimaryPart = primary
			end
		end
		return subtract
	end
	
	local created = Instance.new("Model")
	created.Name = Constants.Prefab.SubtractModelName
	created.Parent = root
	return created
end

local function isDoorWindow(mount: string?): boolean
	return mount == "Door" or mount == "Window"
end

local function setSubtractVisibility(root: Model, visible: boolean)
	local subtract = root:FindFirstChild(Constants.Prefab.SubtractModelName)
	if not (subtract and subtract:IsA("Model")) then return end	for _, child in ipairs(subtract:GetDescendants()) do
		if child:IsA("BasePart") then
			child.Transparency = visible and 0.35 or 1
			child.CanCollide = false
			child.CanTouch = false
			child.CanQuery = false
			child.CastShadow = false
		end
	end
end

local function hasSubtractParts(subtract: Model): boolean
	for _, child in ipairs(subtract:GetDescendants()) do
		if child:IsA("BasePart") then return true end	end
	return false
end

local function ensureSubtractPart(root: Model, subtract: Model)
	if hasSubtractParts(subtract) then return end
	local prefabModel = PrefabMetadata.GetPrefabModel(root)
	local target = prefabModel or root
	local boundsCFrame, boundsSize = target:GetBoundingBox()

	local part = Instance.new("Part", subtract)
	part.Name = "SubtractBounds"
	part.Size = Vector3.new(boundsSize.X, boundsSize.Y, boundsSize.Z + 4)
	part.CFrame = boundsCFrame
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Glass
	part.Transparency = 0.35
	part.Color = Color3.fromRGB(255, 170, 94)
	subtract.PrimaryPart = part
end

local function isSubtractVisible(subtract: Model): boolean
	for _, child in ipairs(subtract:GetDescendants()) do
		if child:IsA("BasePart") and child.Transparency < 0.99 then return true end	end
	return false
end

local function sanitizeName(rootFolder: Instance, baseName: string): string
	local candidate = baseName
	local suffix = 1
	while rootFolder:FindFirstChild(candidate) do
		candidate = string.format("%s_%d", baseName, suffix)
		suffix += 1
	end
	return candidate
end

local function getWorldBounds(model: Model): (Vector3, Vector3)
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local half = boundsSize * 0.5
	return boundsCFrame.Position - half, boundsCFrame.Position + half
end

local function shiftModel(model: Model, offset: Vector3)
	local pivot = model:GetPivot()
	model:PivotTo(pivot + offset)
end

local function getPrefabBounds(root: Model): (CFrame, Vector3)
	local prefabModel = PrefabMetadata.GetPrefabModel(root)
	local target = prefabModel or root
	return target:GetBoundingBox()
end

local function alignGuideToBounds(guide: BasePart, boundsCFrame: CFrame, boundsSize: Vector3)
	guide.Size = boundsSize
	guide.CFrame = boundsCFrame
end

local function sanitizePrefabTransforms(root: Model)
	-- Do nothing for now; placeholder for future transform sanitization logic.
end

function PrefabOperations.SanitizePrefab(root: Model)
	sanitizePrefabTransforms(root)
end

local function ensureModelBase(root: Model)
	local prefabModel = PrefabMetadata.GetPrefabModel(root)
	if not prefabModel or prefabModel.PrimaryPart then return end
	local existing = prefabModel:FindFirstChild("ModelBase")
	if existing and existing:IsA("BasePart") then
		prefabModel.PrimaryPart = existing
		return
	end

	local boundsCFrame, boundsSize = prefabModel:GetBoundingBox()
	local base = Instance.new("Part", prefabModel)
	base.Name = "ModelBase"
	base.Anchored = true
	base.CanCollide = false
	base.CanTouch = false
	base.CanQuery = false
	base.CastShadow = false
	base.Transparency = 1
	base.Locked = true
	base.Size = Vector3.new(boundsSize.X, 0.001, boundsSize.Z)
	local minY = boundsCFrame.Position.Y - (boundsSize.Y / 2)
	base.CFrame = CFrame.new(boundsCFrame.Position.X, minY + 0.0005, boundsCFrame.Position.Z)
	prefabModel.PrimaryPart = base
end

local function getSizeGuide(root: Model): BasePart?
	local stage = StageManager.GetStage(root)
	if not stage then return nil end	local guide = stage:FindFirstChild(Constants.Prefab.SizeGuideName)
	if guide and guide:IsA("BasePart") then return guide end	return nil
end

local function ensureSizeGuide(root: Model): BasePart?
	local attributes = PrefabMetadata.ReadAttributes(root)
	local size = attributes.Size
	if not size or typeof(size) ~= "Vector3" then
		size = PrefabSizing.CalculatePrefabSize(root)
		size = PrefabSizing.SnapSize(size, attributes.ObjectMount)
		PrefabMetadata.ApplyAttributes(root, { Size = size })
	end
	return StageManager.EnsureSizeGuide(root, size)
end

local function previewSizeGuide(root: Model, duration: number, boundsCFrame: CFrame?, boundsSize: Vector3?)
	local token = (guidePreviewTokens[root] or 0) + 1
	guidePreviewTokens[root] = token
	local guide = ensureSizeGuide(root)
	if guide and boundsCFrame and boundsSize then
		alignGuideToBounds(guide, boundsCFrame, boundsSize)
	end
	task.delay(duration, function()
		if guidePreviewTokens[root] == token then
			local guide = getSizeGuide(root)
			if guide then
				guide:Destroy()
			end
		end
	end)
end

local function wrapAsPrefab(instance: Instance, workspaceRoot: Folder): Model
	local rootName = instance.Name
	if instance:IsA("Model") then
		rootName = instance.Name
	end
	rootName = sanitizeName(workspaceRoot, rootName)

	local originalPivot: CFrame? = nil
	if instance:IsA("PVInstance") then
		originalPivot = instance:GetPivot()
	end

	local root = Instance.new("Model")
	root.Name = rootName
	root.Parent = workspaceRoot
	if originalPivot then
		root:PivotTo(originalPivot)
	end

	local prefabModel: Model
	if instance:IsA("Model") then
		prefabModel = instance
		prefabModel.Name = Constants.Prefab.PrefabModelName
		prefabModel.Parent = root
		if originalPivot then
			prefabModel:PivotTo(originalPivot)
		else
			prefabModel:PivotTo(root:GetPivot())
		end
	else
		prefabModel = Instance.new("Model")
		prefabModel.Name = Constants.Prefab.PrefabModelName
		prefabModel.Parent = root
		instance.Parent = prefabModel
		if originalPivot then
			instance:PivotTo(originalPivot)
			prefabModel:PivotTo(originalPivot)
		else
			prefabModel:PivotTo(root:GetPivot())
		end
	end

	PrefabMetadata.ApplyAttributes(root, {
		DisplayName = root.Name,
		IconAssetId = 0,
		ObjectMount = "Floor",
		Categories = "",
	})

	local size = PrefabSizing.CalculatePrefabSize(root)
	size = PrefabSizing.SnapSize(size, "Floor")
	PrefabMetadata.ApplyAttributes(root, { Size = size })

	return root
end

local function ensurePrefabRoot(instance: Instance, workspaceRoot: Folder): Model?
	if not instance:IsDescendantOf(Workspace) then return nil end	if instance:IsA("Model") and PrefabCatalog.IsPrefabRoot(instance) then
		if not instance:IsDescendantOf(workspaceRoot) then
			instance.Parent = workspaceRoot
		end
		return instance
	end

	local ancestor = PluginUtils.FindAncestor(instance, function(target)
		return target:IsA("Model") and PrefabCatalog.IsPrefabRoot(target)
	end, workspaceRoot)
	if ancestor and ancestor:IsA("Model") then return ancestor end
	if not instance:IsDescendantOf(workspaceRoot) and not instance:IsDescendantOf(workspaceRoot.Parent) then
		return wrapAsPrefab(instance, workspaceRoot)
	end

	if instance:IsA("Model") then
		return wrapAsPrefab(instance, workspaceRoot)
	end

	return wrapAsPrefab(instance, workspaceRoot)
end

function PrefabOperations.SyncSubtractState(root: Model)
	local attributes = PrefabMetadata.ReadAttributes(root)
	if not isDoorWindow(attributes.ObjectMount) then
		setSubtractVisibility(root, false)
	end
end

function PrefabOperations.PrepareSelection(selection: {Instance}): {Model}
	local workspaceRoot = PrefabFolders.GetWorkspaceRoot()
	local roots = {}
	for _, instance in ipairs(PluginUtils.GetUniqueSelectionRoots(selection)) do
		local root = ensurePrefabRoot(instance, workspaceRoot)
		if root then
			sanitizePrefabTransforms(root)
			ensureModelBase(root)
			table.insert(roots, root)
		end
	end

	for index, root in ipairs(roots) do
		StageManager.CreateStage(root, index)
		PrefabOperations.SyncSubtractState(root)
	end
	StageManager.LayoutStages(roots)
	if roots[1] then
		StageManager.FocusCameraOnStage(roots[1])
	end
	return roots
end

function PrefabOperations.UpdatePrefab(root: Model, data: PrefabEditData)
	sanitizePrefabTransforms(root)
	local attributes = PrefabMetadata.ReadAttributes(root)
	local previousMount = attributes.ObjectMount
	if data.PrefabPath and data.PrefabPath ~= "" then
		local workspaceRoot = PrefabFolders.GetWorkspaceRoot()
		local parts = PluginUtils.SplitPath(data.PrefabPath)
		local name = parts[#parts] or root.Name
		table.remove(parts, #parts)
		local parentFolder = PrefabFolders.EnsurePath(workspaceRoot, parts)
		local existing = parentFolder:FindFirstChild(name)
		if existing and existing ~= root then
			name = sanitizeName(parentFolder, name)
		end
		root.Name = name
		root.Parent = parentFolder
	end

	local mount = data.ObjectMount or attributes.ObjectMount
	local nextSize = data.Size or attributes.Size
	if nextSize then
		data.Size = PrefabSizing.SnapSize(nextSize, mount)
	end

	PrefabMetadata.ApplyAttributes(root, data)
	PrefabOperations.SyncSubtractState(root)
	StageManager.UpdateStageName(root)

	if data.Size then
		StageManager.RefreshSizeGuide(root, data.Size)
	end

	if data.ObjectMount and PrefabMetadata.ResolveObjectMount(data.ObjectMount) ~= previousMount then
		StageManager.UpdateStageDesign(root, data.ObjectMount)
		PrefabOperations.AutoPosition(root)
	end
end

function PrefabOperations.AutoPosition(root: Model): boolean
	sanitizePrefabTransforms(root)
	if not StageManager.GetStage(root) then return false end	local prefabModel = PrefabMetadata.GetPrefabModel(root) or root
	local minBounds, maxBounds = getWorldBounds(prefabModel)
	local center = (minBounds + maxBounds) * 0.5

	local stageCenter = root:GetPivot().Position
	local stageHalf = Constants.Stage.Size / 2
	local floorPlaneY = stageCenter.Y - stageHalf + (Constants.Stage.FloorThickness / 2)
	local ceilingPlaneY = stageCenter.Y + stageHalf - (Constants.Stage.FloorThickness / 2)
	local backPlaneZ = stageCenter.Z - stageHalf + (Constants.WallThickness / 2)

	local mount = PrefabMetadata.ReadAttributes(root).ObjectMount
	local offset = Vector3.new(0, 0, 0)
	if mount == "Surface" or mount == "Floor" then
		offset = Vector3.new(stageCenter.X - center.X, floorPlaneY - minBounds.Y, stageCenter.Z - center.Z)
	elseif mount == "Ceiling" then
		offset = Vector3.new(stageCenter.X - center.X, ceilingPlaneY - maxBounds.Y, stageCenter.Z - center.Z)
	elseif mount == "Wall" then
		offset = Vector3.new(stageCenter.X - center.X, stageCenter.Y - center.Y, backPlaneZ - minBounds.Z)
	elseif mount == "Door" then
		offset = Vector3.new(stageCenter.X - center.X, floorPlaneY - minBounds.Y, stageCenter.Z - center.Z)
	elseif mount == "Window" then
		offset = Vector3.new(stageCenter.X - center.X, stageCenter.Y - center.Y, stageCenter.Z - center.Z)
	else
		offset = Vector3.new(stageCenter.X - center.X, floorPlaneY - minBounds.Y, stageCenter.Z - center.Z)
	end

	if offset.Magnitude <= 1e-4 then return false end	shiftModel(prefabModel, offset)
	local subtract = root:FindFirstChild(Constants.Prefab.SubtractModelName)
	if subtract and subtract:IsA("Model") then
		shiftModel(subtract, offset)
	end
	return true
end

function PrefabOperations.AutoSize(root: Model)
	sanitizePrefabTransforms(root)
	local attributes = PrefabMetadata.ReadAttributes(root)
	local boundsCFrame, boundsSize = getPrefabBounds(root)
	local size = PrefabSizing.SnapSize(boundsSize, attributes.ObjectMount)
	PrefabMetadata.ApplyAttributes(root, { Size = size })
	local guide = getSizeGuide(root)
	if guide then
		alignGuideToBounds(guide, boundsCFrame, boundsSize)
	else
		previewSizeGuide(root, 1, boundsCFrame, boundsSize)
	end
	return size
end

function PrefabOperations.ApplySizeGuide(root: Model)
	sanitizePrefabTransforms(root)
	local stage = StageManager.GetStage(root)
	if not stage then return nil end	local guide = stage:FindFirstChild(Constants.Prefab.SizeGuideName)
	if not (guide and guide:IsA("BasePart")) then return nil end	local attributes = PrefabMetadata.ReadAttributes(root)
	local size = PrefabSizing.SnapSize(guide.Size, attributes.ObjectMount)
	PrefabMetadata.ApplyAttributes(root, { Size = size })
	StageManager.RefreshSizeGuide(root, size)
	return size
end

function PrefabOperations.ToggleSizeGuide(root: Model): boolean
	guidePreviewTokens[root] = (guidePreviewTokens[root] or 0) + 1
	local guide = getSizeGuide(root)
	if guide then
		guide:Destroy()
		return true
	end
	local created = ensureSizeGuide(root)
	if created then
		local boundsCFrame, boundsSize = getPrefabBounds(root)
		alignGuideToBounds(created, boundsCFrame, boundsSize)
		return true
	end
	return false
end

function PrefabOperations.ToggleSubtract(root: Model): Model?
	local attributes = PrefabMetadata.ReadAttributes(root)
	if not isDoorWindow(attributes.ObjectMount) then return nil end	local subtract = ensureSubtractModel(root)
	local anyVisible = isSubtractVisible(subtract)
	if anyVisible then
		setSubtractVisibility(root, false)
		local prefabModel = PrefabMetadata.GetPrefabModel(root)
		return prefabModel or root
	end

	ensureSubtractPart(root, subtract)
	setSubtractVisibility(root, true)
	return subtract
end

function PrefabOperations.StorePrefabs(roots: {Model}): {Model}
	local replicatedRoot = PrefabFolders.GetReplicatedRoot()
	local workspaceRoot = PrefabFolders.GetWorkspaceRoot()
	local stored = {}

	for _, root in ipairs(roots) do
		if not root:IsDescendantOf(workspaceRoot) then
			continue
		end
		sanitizePrefabTransforms(root)
		StageManager.RemoveStage(root)
		setSubtractVisibility(root, false)

		local path = PluginUtils.GetPathFromRoot(root, workspaceRoot) or root.Name
		local parts = PluginUtils.SplitPath(path)
		local name = parts[#parts] or root.Name
		table.remove(parts, #parts)
		local targetFolder = PrefabFolders.EnsurePath(replicatedRoot, parts)

		local existing = targetFolder:FindFirstChild(name)
		if existing and existing:IsA("Model") then
			existing:Destroy()
		end

		root.Name = name
		root.Parent = targetFolder

		local attributes = PrefabMetadata.ReadAttributes(root)
		if not isDoorWindow(attributes.ObjectMount) then
			local subtract = root:FindFirstChild(Constants.Prefab.SubtractModelName)
			if subtract and subtract:IsA("Model") then
				subtract:Destroy()
			end
		end
		local size = attributes.Size
		if not size or typeof(size) ~= "Vector3" then
			size = PrefabSizing.CalculatePrefabSize(root)
		end
		size = PrefabSizing.SnapSize(size, attributes.ObjectMount)
		PrefabMetadata.ApplyAttributes(root, { Size = size })
		table.insert(stored, root)
	end

	return stored
end

function PrefabOperations.StoreAllWorkspacePrefabs(): {Model}
	local workspacePrefabs = PrefabCatalog.GetWorkspacePrefabs()
	local roots = {}
	for _, entry in ipairs(workspacePrefabs) do
		table.insert(roots, entry.Model)
	end
	return PrefabOperations.StorePrefabs(roots)
end

function PrefabOperations.PullPrefabs(paths: {string}): {Model}
	local workspaceRoot = PrefabFolders.GetWorkspaceRoot()
	local replicatedRoot = PrefabFolders.GetReplicatedRoot()
	local pulled = {}
	local seen = {}

	for _, path in ipairs(paths) do
		local source = PrefabCatalog.FindPrefabByPath(replicatedRoot, path)
		if source then
			local parts = PluginUtils.SplitPath(path)
			local name = parts[#parts] or source.Name
			table.remove(parts, #parts)
			local targetFolder = PrefabFolders.EnsurePath(workspaceRoot, parts)
			local existing = targetFolder:FindFirstChild(name)
			if existing and existing:IsA("Model") then
				if not seen[existing] then
					seen[existing] = true
					table.insert(pulled, existing)
				end
			else
				local clone = source:Clone()
				clone.Name = name
				clone.Parent = targetFolder
				if not seen[clone] then
					seen[clone] = true
					table.insert(pulled, clone)
				end
			end
		end
	end

	for index, root in ipairs(pulled) do
		sanitizePrefabTransforms(root)
		StageManager.CreateStage(root, index)
		PrefabOperations.SyncSubtractState(root)
		PrefabOperations.AutoPosition(root)
	end
	StageManager.LayoutStages(pulled)
	if pulled[1] then
		StageManager.FocusCameraOnStage(pulled[1])
	end
	return pulled
end

function PrefabOperations.ComputePreview(root: Model)
	local attributes = PrefabMetadata.ReadAttributes(root)
	local size = attributes.Size
	if not size or typeof(size) ~= "Vector3" then
		size = PrefabSizing.CalculatePrefabSize(root)
	end
	size = PrefabSizing.SnapSize(size, attributes.ObjectMount)
	PrefabMetadata.ApplyAttributes(root, { Size = size })
end

return PrefabOperations
