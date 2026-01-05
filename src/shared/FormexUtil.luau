--!strict

local Formex = require(script.Parent:FindFirstChild("Formex"))
Formex.Math = require(script.Parent:FindFirstChild("FormexMath"))

Formex.Util = {}

function Formex.UpdateTexture(part: BasePart, texture: Texture, materialId: number?, color: Color3?)
	local materialInfo = materialId and Formex.FloorMaterials[materialId] or nil
	if not materialInfo then
		texture.ColorMapContent = Content.fromAssetId(0)
		texture.StudsPerTileU = 1
		texture.StudsPerTileV = 1
	else
		part.Material = Enum.Material.SmoothPlastic
		texture.ColorMapContent = Content.fromAssetId(materialInfo.AssetId or 0)
		texture.StudsPerTileU = materialInfo.StudsPerTile
		texture.StudsPerTileV = materialInfo.StudsPerTile
	end
	texture.Color3 = color or Color3.new(1, 1, 1)
end

function Formex.Util.ApplyWallMaterial(part: BasePart, materialId: number?, color: Color3?)
	local materialInfo = materialId and Formex.WallMaterials[materialId] or nil
	part.Material = (materialInfo and materialInfo.Material) or Enum.Material.SmoothPlastic
	part.MaterialVariant = materialInfo and materialInfo.MaterialVariant or ""
	if color then
		part.Color = color
	end
end

local function deepClone(original)
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
	folder = Instance.new("Folder", parent)
	folder.Name = name
	return folder
end

function Formex.Util.EnsureTexture(part: BasePart, name: string, face: Enum.NormalId): Texture
	local existing = part:FindFirstChild(name)
	if existing and existing:IsA("Texture") then
		existing.Face = face
		return existing
	end

	local texture = Instance.new("Texture")
	texture.Name = name
	texture.Face = face
	texture.Parent = part
	return texture
end

return Formex.Util
