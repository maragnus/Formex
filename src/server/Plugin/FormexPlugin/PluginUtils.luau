--!strict

local PluginUtils = {}

function PluginUtils.EnsureFolder(parent: Instance, name: string): Folder
	local folder = parent:FindFirstChild(name)
	if folder and folder:IsA("Folder") then
		return folder
	end

	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = parent
	return created
end

-- Copied from src/shared/FormexObjects.luau splitPath.
function PluginUtils.SplitPath(path: string): {string}
	local parts = {}
	for segment in string.gmatch(path, "[^/]+") do
		table.insert(parts, segment)
	end
	return parts
end

function PluginUtils.JoinPath(parts: {string}): string
	return table.concat(parts, "/")
end

function PluginUtils.GetPathFromRoot(instance: Instance, root: Instance): string?
	local parts = {}
	local current: Instance? = instance
	while current and current ~= root do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end
	if current ~= root then
		return nil
	end
	return PluginUtils.JoinPath(parts)
end

function PluginUtils.FindAncestor(instance: Instance, predicate: (Instance) -> boolean, stopAt: Instance?): Instance?
	local current: Instance? = instance
	while current do
		if predicate(current) then
			return current
		end
		if stopAt and current == stopAt then
			break
		end
		current = current.Parent
	end
	return nil
end

function PluginUtils.GetUniqueSelectionRoots(selection: {Instance}): {Instance}
	local roots = {}
	for _, instance in ipairs(selection) do
		local isChild = false
		for _, other in ipairs(selection) do
			if other ~= instance and instance:IsDescendantOf(other) then
				isChild = true
				break
			end
		end
		if not isChild then
			table.insert(roots, instance)
		end
	end
	return roots
end

function PluginUtils.CollectBaseParts(model: Instance): {BasePart}
	local parts = {}
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			table.insert(parts, child)
		end
	end
	return parts
end

function PluginUtils.DisableScripts(model: Instance)
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("Script") or child:IsA("LocalScript") or child:IsA("ModuleScript") then
			if child:IsA("Script") or child:IsA("LocalScript") then
				child.Disabled = true
			end
		end
	end
end

function PluginUtils.SnapToInteger(value: number): number
	return math.round(value)
end

function PluginUtils.SnapToGrid(value: number, grid: number): number
	if grid <= 0 then
		return value
	end
	return math.round(value / grid) * grid
end

function PluginUtils.Clamped(value: number, minValue: number): number
	if value < minValue then
		return minValue
	end
	return value
end

function PluginUtils.GetOrCreateChildModel(parent: Instance, name: string): Model
	local model = parent:FindFirstChild(name)
	if model and model:IsA("Model") then
		return model
	end
	local created = Instance.new("Model")
	created.Name = name
	created.Parent = parent
	return created
end

return PluginUtils
