--!strict

local Constants = require(script.Parent:WaitForChild("Constants"))
local PluginUtils = require(script.Parent:WaitForChild("PluginUtils"))
local PrefabMetadata = require(script.Parent:WaitForChild("PrefabMetadata"))

local PrefabSizing = {}

function PrefabSizing.CalculateBoundsSize(prefabModel: Model?): Vector3
	if not prefabModel then
		return Vector3.new(1, 1, 1)
	end
	local _, size = prefabModel:GetBoundingBox()
	return size
end

function PrefabSizing.CalculatePrefabSize(root: Model): Vector3
	local prefabModel = PrefabMetadata.GetPrefabModel(root)
	if not prefabModel then
		return Vector3.new(1, 1, 1)
	end
	return PrefabSizing.CalculateBoundsSize(prefabModel)
end

local function snapSizeComponent(value: number, grid: number?, snapToGrid: boolean): number
	local snapped = PluginUtils.SnapToInteger(value)
	if snapToGrid and grid and grid > 0 then
		snapped = PluginUtils.SnapToGrid(snapped, grid)
	end
	return PluginUtils.Clamped(snapped, 1)
end

function PrefabSizing.SnapSize(size: Vector3, objectMount: string): Vector3
	local snapXZ = objectMount ~= "Surface"
	local x = snapSizeComponent(size.X, Constants.LayoutGridSize, snapXZ)
	local y = snapSizeComponent(size.Y, nil, false)
	local z = snapSizeComponent(size.Z, Constants.LayoutGridSize, snapXZ)
	return Vector3.new(x, y, z)
end

return PrefabSizing
