--!strict

local Constants = require(script.Parent:WaitForChild("Constants"))
local PluginUtils = require(script.Parent:WaitForChild("PluginUtils"))

local PrefabMetadata = {}

-- Copied from src/shared/FormexObjects.luau resolveObjectMount.
function PrefabMetadata.ResolveObjectMount(value: any): string
	if value == "Ceiling" then
		return "Ceiling"
	elseif value == "Floor" then
		return "Floor"
	elseif value == "Wall" then
		return "Wall"
	elseif value == "Window" then
		return "Window"
	elseif value == "Door" then
		return "Door"
	elseif value == "Surface" then
		return "Surface"
	end
	return "Floor"
end

-- Copied from src/shared/FormexObjects.luau parseStringList.
function PrefabMetadata.ParseStringList(value: any): {string}
	if type(value) ~= "string" then
		return {}
	end
	local result = {}
	for entry in string.gmatch(value, "([^,]+)") do
		local trimmed = string.gsub(entry, "^%s*(.-)%s*$", "%1")
		if trimmed ~= "" then
			table.insert(result, trimmed)
		end
	end
	return result
end

function PrefabMetadata.ReadAttributes(model: Model)
	local sizeValue = model:GetAttribute(Constants.Attributes.Size)
	local resolvedSize = typeof(sizeValue) == "Vector3" and sizeValue or nil
	return {
		DisplayName = model:GetAttribute(Constants.Attributes.DisplayName) or model.Name,
		IconAssetId = model:GetAttribute(Constants.Attributes.IconAssetId) or 0,
		ObjectMount = PrefabMetadata.ResolveObjectMount(model:GetAttribute(Constants.Attributes.ObjectMount)),
		Size = resolvedSize,
		Categories = model:GetAttribute(Constants.Attributes.Categories) or "",
	}
end

function PrefabMetadata.ApplyAttributes(model: Model, data)
	if data.DisplayName ~= nil then
		model:SetAttribute(Constants.Attributes.DisplayName, data.DisplayName)
	end
	if data.IconAssetId ~= nil then
		model:SetAttribute(Constants.Attributes.IconAssetId, data.IconAssetId)
	end
	if data.ObjectMount ~= nil then
		model:SetAttribute(Constants.Attributes.ObjectMount, PrefabMetadata.ResolveObjectMount(data.ObjectMount))
	end
	if data.Size ~= nil then
		model:SetAttribute(Constants.Attributes.Size, data.Size)
	end
	if data.Categories ~= nil then
		model:SetAttribute(Constants.Attributes.Categories, data.Categories)
	end
end

function PrefabMetadata.GetPrefabModel(root: Model): Model?
	local prefabModel = root:FindFirstChild(Constants.Prefab.PrefabModelName)
	if prefabModel and prefabModel:IsA("Model") then return prefabModel end
	return nil
end

function PrefabMetadata.EnsurePrefabModel(root: Model): Model
	return PluginUtils.GetOrCreateChildModel(root, Constants.Prefab.PrefabModelName)
end

return PrefabMetadata
