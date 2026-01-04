--!strict

local Formex = require(script.Parent:FindFirstChild("Formex"))
Formex.Math = require(script.Parent:FindFirstChild("FormexMath"))

Formex.Util = {}

function Formex.UpdateTexture(part: BasePart, texture: Texture, materialId: number)
	local materialInfo = Formex.Materials[materialId]
	if not materialInfo then
		-- part.Material = Enum.Material.Air
		texture.ColorMapContent = Content.fromAssetId(0)
	else
		part.Material = materialInfo.Material or Enum.Material.SmoothPlastic
		texture.ColorMapContent = Content.fromAssetId(materialInfo.AssetId)
		texture.StudsPerTileU = materialInfo.StudsPerTile
		texture.StudsPerTileV = materialInfo.StudsPerTile
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