--!strict

local Formex = require(script.Parent)

function Formex.Util.ApplyMaterial(part: BasePart, materialId: number?, color: Color3?)
	local materialInfo = materialId and Formex.Materials[materialId] or nil
	part.Material = materialInfo and materialInfo.Material or Enum.Material.SmoothPlastic
	part.MaterialVariant = materialInfo and materialInfo.MaterialVariant or ""
	part.Color = color or BrickColor.White().Color
end

local function deepClone(original: any): any
    local clone = table.clone(original)
    for key, value in original do
        if type(value) == "table" then
            clone[key] = deepClone(value)
        end
    end
    return clone
end
Formex.Util.DeepClone = deepClone

function Formex.Util.EnsureFolder(name: string, parent: Instance): Folder
	local folder = parent:FindFirstChild(name)
	if folder and folder:IsA("Folder") then
		return folder :: Folder
	end
	local newFolder = Instance.new("Folder", parent)
	newFolder.Name = name
	return newFolder
end

function Formex.Util.EncodeFloorPoints(points: { Vector2int16 }): string
	-- Convert points to a compact string so floor data can be stored on attributes.
	local encoded = {}
	for _, point in ipairs(points) do
		table.insert(encoded, string.format("%d,%d", point.X, point.Y))
	end
	return table.concat(encoded, ";")
end

function Formex.Util.DecodeFloorPoints(value: string?): { Vector2int16 }
	-- Restore points from the attribute string during selection/editing.
	local points = {}
	if not value or value == "" then return points end
	for entry in string.gmatch(value, "([^;]+)") do
		local xStr, yStr = string.match(entry, "([^,]+),([^,]+)")
		if xStr and yStr then
			table.insert(points, Vector2int16.new(tonumber(xStr), tonumber(yStr)))
		end
	end

	return points
end

return Formex.Util
