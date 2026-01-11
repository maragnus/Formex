--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(script.Parent:WaitForChild("Constants"))
local PluginUtils = require(script.Parent:WaitForChild("PluginUtils"))

local PrefabFolders = {}

function PrefabFolders.GetWorkspaceRoot(): Folder
	local formexFolder = PluginUtils.EnsureFolder(Workspace, Constants.Prefab.WorkspaceRootName)
	return PluginUtils.EnsureFolder(formexFolder, Constants.Prefab.WorkspacePrefabsFolderName)
end

function PrefabFolders.GetStageRoot(): Folder
	local prefabsRoot = PrefabFolders.GetWorkspaceRoot()
	return PluginUtils.EnsureFolder(prefabsRoot, Constants.Prefab.StageFolderName)
end

function PrefabFolders.GetReplicatedRoot(): Folder
	return PluginUtils.EnsureFolder(ReplicatedStorage, Constants.Prefab.ReplicatedPrefabsFolderName)
end

function PrefabFolders.EnsurePath(root: Instance, pathParts: {string}): Instance
	local current: Instance = root
	for _, segment in ipairs(pathParts) do
		current = PluginUtils.EnsureFolder(current, segment)
	end
	return current
end

return PrefabFolders
