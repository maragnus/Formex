--!strict

local Constants = require(script.Parent:WaitForChild("Constants"))
local PrefabFolders = require(script.Parent:WaitForChild("PrefabFolders"))
local PrefabMetadata = require(script.Parent:WaitForChild("PrefabMetadata"))
local PluginUtils = require(script.Parent:WaitForChild("PluginUtils"))

local PrefabCatalog = {}

export type PrefabEntry = {
	Model: Model,
	Path: string,
	DisplayName: string,
	IconAssetId: number,
	ObjectMount: string,
	Size: Vector3,
	Categories: string,
}

local function buildEntry(model: Model, pathName: string): PrefabEntry
	local attributes = PrefabMetadata.ReadAttributes(model)
	local size = attributes.Size
	if not size or typeof(size) ~= "Vector3" then
		local prefabModel = PrefabMetadata.GetPrefabModel(model)
		local _, boundsSize = (prefabModel or model):GetBoundingBox()
		size = boundsSize
	end
	return {
		Model = model,
		Path = pathName,
		DisplayName = attributes.DisplayName,
		IconAssetId = attributes.IconAssetId,
		ObjectMount = attributes.ObjectMount,
		Size = size,
		Categories = attributes.Categories,
	}
end

local function collectPrefabs(root: Instance, prefix: string, list: {PrefabEntry}, skipFolderName: string?)
	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("Model") then
			local pathName = prefix ~= "" and (prefix .. "/" .. child.Name) or child.Name
			table.insert(list, buildEntry(child, pathName))
		elseif child:IsA("Folder") then
			if skipFolderName and child.Name == skipFolderName then
				continue
			end
			local folderPrefix = prefix ~= "" and (prefix .. "/" .. child.Name) or child.Name
			collectPrefabs(child, folderPrefix, list, skipFolderName)
		end
	end
end

function PrefabCatalog.GetWorkspacePrefabs(): {PrefabEntry}
	local list = {}
	local root = PrefabFolders.GetWorkspaceRoot()
	collectPrefabs(root, "", list, Constants.Prefab.StageFolderName)
	return list
end

function PrefabCatalog.GetReplicatedPrefabs(): {PrefabEntry}
	local list = {}
	local root = PrefabFolders.GetReplicatedRoot()
	collectPrefabs(root, "", list, nil)
	return list
end

function PrefabCatalog.FindPrefabByPath(root: Instance, path: string): Model?
	local parts = PluginUtils.SplitPath(path)
	local current: Instance = root
	for _, segment in ipairs(parts) do
		local child = current:FindFirstChild(segment)
		if not child then
			return nil
		end
		current = child
	end
	if current:IsA("Model") then
		return current
	end
	return nil
end

function PrefabCatalog.FindWorkspacePrefab(path: string): Model?
	return PrefabCatalog.FindPrefabByPath(PrefabFolders.GetWorkspaceRoot(), path)
end

function PrefabCatalog.FindReplicatedPrefab(path: string): Model?
	return PrefabCatalog.FindPrefabByPath(PrefabFolders.GetReplicatedRoot(), path)
end

function PrefabCatalog.IsPrefabRoot(model: Instance): boolean
	if not model:IsA("Model") then
		return false
	end
	return model:FindFirstChild(Constants.Prefab.PrefabModelName) ~= nil
end

return PrefabCatalog
