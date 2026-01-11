--!strict

local Selection = game:GetService("Selection")
local Workspace = game:GetService("Workspace")

local Constants = require(script.Parent:WaitForChild("Constants"))
local PrefabCatalog = require(script.Parent:WaitForChild("PrefabCatalog"))
local PrefabFolders = require(script.Parent:WaitForChild("PrefabFolders"))
local PrefabMetadata = require(script.Parent:WaitForChild("PrefabMetadata"))
local PrefabOperations = require(script.Parent:WaitForChild("PrefabOperations"))
local PrefabUI = require(script.Parent:WaitForChild("PrefabUI"))
local PluginUtils = require(script.Parent:WaitForChild("PluginUtils"))
local StageManager = require(script.Parent:WaitForChild("StageManager"))
local Utils = require(script.Parent:WaitForChild("Utils"))
local ViewportDialog = require(script.Parent:WaitForChild("ViewportDialog"))

local FormexPlugin = {}

type PrefabEditData = {
	PrefabPath: string?,
	DisplayName: string?,
	IconAssetId: number?,
	ObjectMount: string?,
	Size: Vector3?,
	Categories: string?,
	HasSubtractModel: boolean?,
	StoreMode: string?,
}

local function findPrefabRoot(instance: Instance, workspaceRoot: Folder, replicatedRoot: Folder): Model?
	if instance:IsA("Model") and PrefabCatalog.IsPrefabRoot(instance) then
		return instance
	end
	local ancestor = PluginUtils.FindAncestor(instance, function(target)
		return target:IsA("Model") and PrefabCatalog.IsPrefabRoot(target)
	end, nil)
	if ancestor and ancestor:IsA("Model")
	and (ancestor:IsDescendantOf(workspaceRoot) or ancestor:IsDescendantOf(replicatedRoot)) then
		return ancestor
	end
	return nil
end

local function getSelectedPrefabRoots(): {Model}
	local workspaceRoot = PrefabFolders.GetWorkspaceRoot()
	local replicatedRoot = PrefabFolders.GetReplicatedRoot()
	local roots = {}
	local seen = {}
	for _, instance in ipairs(Selection:Get()) do
		local root = findPrefabRoot(instance, workspaceRoot, replicatedRoot)
		if root and not seen[root] then
			seen[root] = true
			table.insert(roots, root)
		end
	end
	return roots
end

local function buildSelectionData(root: Model): PrefabEditData
	local workspaceRoot = PrefabFolders.GetWorkspaceRoot()
	local replicatedRoot = PrefabFolders.GetReplicatedRoot()
	local attributes = PrefabMetadata.ReadAttributes(root)
	local subtract = root:FindFirstChild(Constants.Prefab.SubtractModelName)
	local hasSubtractModel = subtract ~= nil and subtract:IsA("Model")
	local storeMode = "Store"
	if root:IsDescendantOf(replicatedRoot) then
		storeMode = "Pull"
	end
	local path = PluginUtils.GetPathFromRoot(root, workspaceRoot)
	if not path then
		path = PluginUtils.GetPathFromRoot(root, replicatedRoot)
	end
	return {
		PrefabPath = path,
		DisplayName = attributes.DisplayName,
		IconAssetId = attributes.IconAssetId,
		ObjectMount = attributes.ObjectMount,
		Size = attributes.Size,
		Categories = attributes.Categories,
		HasSubtractModel = hasSubtractModel,
		StoreMode = storeMode,
	}
end

local function collectWorkspacePrefabs(): {Model}
	local entries = PrefabCatalog.GetWorkspacePrefabs()
	table.sort(entries, function(a, b)
		return a.Path < b.Path
	end)
	local roots = {}
	for _, entry in ipairs(entries) do
		table.insert(roots, entry.Model)
	end
	return roots
end

local function layoutWorkspaceStages()
	local roots = collectWorkspacePrefabs()
	for index, root in ipairs(roots) do
		local stage = StageManager.GetStage(root)
		if stage then
			StageManager.PositionStage(root, index)
		else
			StageManager.CreateStage(root, index)
		end
	end
	StageManager.LayoutStages(roots)
end

local function buildCatalogList(filterText: string): {string}
	local list = PrefabCatalog.GetReplicatedPrefabs()
	local results = {}
	local filter = string.lower(filterText or "")
	for _, entry in ipairs(list) do
		if filter == "" or string.find(string.lower(entry.Path), filter, 1, true) then
			table.insert(results, entry.Path)
		end
	end
	table.sort(results)
	return results
end

local function classifySelection(roots: {Model}): ({Model}, {Model})
	local workspaceRoot = PrefabFolders.GetWorkspaceRoot()
	local replicatedRoot = PrefabFolders.GetReplicatedRoot()
	local workspaceRoots = {}
	local replicatedRoots = {}
	for _, root in ipairs(roots) do
		if root:IsDescendantOf(workspaceRoot) then
			table.insert(workspaceRoots, root)
		elseif root:IsDescendantOf(replicatedRoot) then
			table.insert(replicatedRoots, root)
		end
	end
	return workspaceRoots, replicatedRoots
end

local function getPathsFromRoots(roots: {Model}, rootFolder: Instance): {string}
	local paths = {}
	for _, root in ipairs(roots) do
		local path = PluginUtils.GetPathFromRoot(root, rootFolder)
		if path and path ~= "" then
			table.insert(paths, path)
		end
	end
	return paths
end

local function applyObjectMountFromUI(roots: {Model}, data: PrefabEditData?)
	if not data or not data.ObjectMount then
		return
	end
	for _, root in ipairs(roots) do
		PrefabOperations.UpdatePrefab(root, { ObjectMount = data.ObjectMount })
	end
end

local function focusSpawnLocation()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local spawn = Workspace:FindFirstChildOfClass("SpawnLocation") or Workspace:FindFirstChild("SpawnLocation", true)
	if spawn and spawn:IsA("BasePart") then
		local center = spawn.Position
		local offset = Vector3.new(18, 12, 18)
		camera.CFrame = CFrame.new(center + offset, center)
	end
end

local function maybeFocusSpawn()
	if #PrefabCatalog.GetWorkspacePrefabs() == 0 then
		focusSpawnLocation()
	end
end

function FormexPlugin.Init(plugin: Plugin)
	PrefabFolders.GetWorkspaceRoot()
	PrefabFolders.GetReplicatedRoot()

	local viewportDialog = ViewportDialog.new(plugin)
	local previewCleanupToken = 0

	local ui
	ui = PrefabUI.new(plugin, {
		OnPrepare = function()
			local selection = Selection:Get()
			if #selection == 0 then
				Utils.DisplayMessageBox(plugin, "Prepare Prefab", "Select one or more models or parts to prepare.")
				return
			end
			local roots = PrefabOperations.PrepareSelection(selection)
			layoutWorkspaceStages()
			Selection:Set(roots)
			ui:UpdateCatalog(buildCatalogList(""))
		end,
		OnUpdate = function(data)
			local roots = getSelectedPrefabRoots()
			if #roots == 0 then
				Utils.DisplayMessageBox(plugin, "Update Prefab", "Select a prefab root in Workspace/Formex/Prefabs.")
				return
			end
			for _, root in ipairs(roots) do
				PrefabOperations.UpdatePrefab(root, data)
			end
			layoutWorkspaceStages()
			ui:SetSelection(buildSelectionData(roots[1]))
			if viewportDialog:IsVisible() then
				viewportDialog:SetPrefab(roots[1], true)
			end
		end,
		OnStore = function()
			local roots = getSelectedPrefabRoots()
			if #roots == 0 then
				Utils.DisplayMessageBox(plugin, "Store Prefab", "Select one or more prefabs to store.")
				return
			end
			local workspaceRoots, replicatedRoots = classifySelection(roots)
			if #workspaceRoots > 0 and #replicatedRoots > 0 then
				Utils.DisplayMessageBox(plugin, "Store Prefab", "Select prefabs from Workspace or ReplicatedStorage, not both.")
				return
			end
			if #replicatedRoots > 0 then
				local paths = getPathsFromRoots(replicatedRoots, PrefabFolders.GetReplicatedRoot())
				local pulled = PrefabOperations.PullPrefabs(paths)
				layoutWorkspaceStages()
				Selection:Set(pulled)
				ui:UpdateCatalog(buildCatalogList(""))
				if pulled[1] then
					ui:SetSelection(buildSelectionData(pulled[1]))
					PrefabOperations.ComputePreview(pulled[1])
					viewportDialog:SetPrefab(pulled[1], false)
					viewportDialog:Show()
				end
				return
			end

			applyObjectMountFromUI(workspaceRoots, ui:GetCurrentData())
			local stored = PrefabOperations.StorePrefabs(workspaceRoots)
			layoutWorkspaceStages()
			Selection:Set({})
			ui:SetSelection(nil)
			ui:UpdateCatalog(buildCatalogList(""))
			maybeFocusSpawn()
			if stored[1] then
				viewportDialog:SetPrefab(stored[1], true)
				viewportDialog:Show()
			end
		end,
		OnStoreAll = function()
			local stored = PrefabOperations.StoreAllWorkspacePrefabs()
			layoutWorkspaceStages()
			Selection:Set({})
			ui:SetSelection(nil)
			ui:UpdateCatalog(buildCatalogList(""))
			maybeFocusSpawn()
			if stored[1] then
				viewportDialog:SetPrefab(stored[1], true)
				viewportDialog:Show()
			end
		end,
		OnToggleSubtract = function()
			local roots = getSelectedPrefabRoots()
			if #roots == 0 then
				Utils.DisplayMessageBox(plugin, "Toggle Subtract", "Select a Door or Window prefab.")
				return
			end
			local targets = {}
			for _, root in ipairs(roots) do
				local target = PrefabOperations.ToggleSubtract(root)
				if target then
					table.insert(targets, target)
				end
			end
			if #targets > 0 then
				Selection:Set(targets)
			end
		end,
		OnAutoSize = function()
			local roots = getSelectedPrefabRoots()
			if #roots == 0 then
				Utils.DisplayMessageBox(plugin, "Auto Size", "Select a prefab to size.")
				return
			end
			for _, root in ipairs(roots) do
				PrefabOperations.AutoSize(root)
			end
			ui:SetSelection(buildSelectionData(roots[1]))
		end,
		OnAutoPosition = function()
			local roots = getSelectedPrefabRoots()
			if #roots == 0 then
				Utils.DisplayMessageBox(plugin, "Auto Position", "Select a prefab to position.")
				return
			end
			for _, root in ipairs(roots) do
				PrefabOperations.AutoPosition(root)
			end
		end,
		OnApplySizeGuide = function()
			local roots = getSelectedPrefabRoots()
			if #roots == 0 then
				Utils.DisplayMessageBox(plugin, "Size Guide", "Select a prefab to toggle the size guide.")
				return
			end
			for _, root in ipairs(roots) do
				PrefabOperations.ToggleSizeGuide(root)
			end
		end,
		OnPreview = function()
			if viewportDialog:IsVisible() then
				viewportDialog:Hide()
				return
			end
			local roots = getSelectedPrefabRoots()
			if #roots == 0 then
				viewportDialog:Hide()
				return
			end
			viewportDialog:SetPrefab(roots[1], false)
			viewportDialog:Show()
		end,
		OnFocusStage = function()
			local roots = getSelectedPrefabRoots()
			if roots[1] then
				StageManager.FocusCameraOnStage(roots[1])
			end
		end,
		OnPullSelected = function(paths)
			if #paths == 0 then
				local folder = PrefabFolders.GetReplicatedRoot()
				Selection:Set({ folder })
				Utils.DisplayMessageBox(plugin, "Pull Prefabs", "Select one or more prefabs from the catalog.")
				return
			end
			local pulled = PrefabOperations.PullPrefabs(paths)
			layoutWorkspaceStages()
			Selection:Set(pulled)
			ui:UpdateCatalog(buildCatalogList(""))
			if pulled[1] then
				ui:SetSelection(buildSelectionData(pulled[1]))
				PrefabOperations.ComputePreview(pulled[1])
				viewportDialog:SetPrefab(pulled[1], false)
				viewportDialog:Show()
			end
		end,
		OnRefreshCatalog = function(filterText)
			ui:UpdateCatalog(buildCatalogList(filterText))
		end,
	})

	local toolbar = plugin:CreateToolbar("Formex Prefabs")
	local panelButton = toolbar:CreateButton(
		"Prefab Panel",
		"Toggle Formex Prefab Panel",
		Content.fromAssetId(123614418099512).Uri
	)
	local prepareButton = toolbar:CreateButton(
		"Prepare",
		"Prepare selected models as prefabs",
		Content.fromAssetId(136707442598480).Uri
	)
	local storeButton = toolbar:CreateButton(
		"Store",
		"Store selected prefabs to ReplicatedStorage",
		Content.fromAssetId(136537860205120).Uri
	)
	local pullButton = toolbar:CreateButton(
		"Pull",
		"Pull selected prefabs from the catalog",
		Content.fromAssetId(86944909652185).Uri
	)

	panelButton.Click:Connect(function()
		if ui:IsVisible() then
			ui:Hide()
		else
			ui:Show()
		end
	end)

	prepareButton.Click:Connect(function()
		ui:Show()
		local selection = Selection:Get()
		if #selection == 0 then
			Utils.DisplayMessageBox(plugin, "Prepare Prefab", "Select one or more models or parts to prepare.")
			return
		end
		local roots = PrefabOperations.PrepareSelection(selection)
		layoutWorkspaceStages()
		Selection:Set(roots)
		ui:UpdateCatalog(buildCatalogList(""))
	end)

	storeButton.Click:Connect(function()
		ui:Show()
		local roots = getSelectedPrefabRoots()
		if #roots == 0 then
			Utils.DisplayMessageBox(plugin, "Store Prefab", "Select one or more prefabs to store.")
			return
		end
		local workspaceRoots, replicatedRoots = classifySelection(roots)
		if #workspaceRoots > 0 and #replicatedRoots > 0 then
			Utils.DisplayMessageBox(plugin, "Store Prefab", "Select prefabs from Workspace or ReplicatedStorage, not both.")
			return
		end
		if #replicatedRoots > 0 then
			local paths = getPathsFromRoots(replicatedRoots, PrefabFolders.GetReplicatedRoot())
			local pulled = PrefabOperations.PullPrefabs(paths)
			layoutWorkspaceStages()
			Selection:Set(pulled)
			ui:UpdateCatalog(buildCatalogList(""))
			if pulled[1] then
				ui:SetSelection(buildSelectionData(pulled[1]))
				PrefabOperations.ComputePreview(pulled[1])
				viewportDialog:SetPrefab(pulled[1], false)
				viewportDialog:Show()
			end
			return
		end

		applyObjectMountFromUI(workspaceRoots, ui:GetCurrentData())
		local stored = PrefabOperations.StorePrefabs(workspaceRoots)
		layoutWorkspaceStages()
		Selection:Set({})
		ui:SetSelection(nil)
		ui:UpdateCatalog(buildCatalogList(""))
		maybeFocusSpawn()
		if stored[1] then
			viewportDialog:SetPrefab(stored[1], true)
			viewportDialog:Show()
		end
	end)

	pullButton.Click:Connect(function()
		ui:Show()
		ui:UpdateCatalog(buildCatalogList(""))
		local selection = Selection:Get()
		if #selection == 0 then
			local folder = PrefabFolders.GetReplicatedRoot()
			Selection:Set({ folder })
		end
	end)

	ui:UpdateCatalog(buildCatalogList(""))

	Selection.SelectionChanged:Connect(function()
		local roots = getSelectedPrefabRoots()
		previewCleanupToken += 1
		local token = previewCleanupToken
		if roots[1] then
			for _, root in ipairs(roots) do
				PrefabOperations.SanitizePrefab(root)
				PrefabOperations.SyncSubtractState(root)
			end
			local workspaceRoots, replicatedRoots = classifySelection(roots)
			local data = buildSelectionData(roots[1])
			if #workspaceRoots > 0 and #replicatedRoots > 0 then
				data.StoreMode = "Mixed"
			elseif #replicatedRoots > 0 then
				data.StoreMode = "Pull"
			else
				data.StoreMode = "Store"
			end
			ui:SetSelection(data)
			if viewportDialog:IsVisible() then
				viewportDialog:SetPrefab(roots[1], false)
			end
		else
			ui:SetSelection(nil)
			task.delay(5, function()
				if token == previewCleanupToken and #getSelectedPrefabRoots() == 0 then
					viewportDialog:Hide()
				end
			end)
		end
	end)
end

return FormexPlugin
