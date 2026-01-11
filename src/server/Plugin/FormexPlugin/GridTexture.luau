--!strict

local Constants = require(script.Parent:WaitForChild("Constants"))

local GridTexture = {}

type GridTextureOptions = {
	OffsetStudsU: number?,
	OffsetStudsV: number?,
}

-- Copied from src/client/FormexDesign.luau applyGridTexture.
function GridTexture.Apply(part: Part, side: Enum.NormalId, options: GridTextureOptions?)
	local texture = Instance.new("Texture")
	texture.Name = tostring(side) .. "Grid"
	texture.Face = side
	texture.ColorMapContent = Content.fromAssetId(Constants.GridTextureAssetId)
	texture.OffsetStudsU = options and options.OffsetStudsU or 2
	texture.OffsetStudsV = options and options.OffsetStudsV or 0
	texture.StudsPerTileU = Constants.LayoutGridSize * 2
	texture.StudsPerTileV = Constants.LayoutGridSize * 2
	texture.Transparency = Constants.GridTextureTransparency
	texture.Color3 = Constants.GridTextureColor
	texture.Parent = part
end

return GridTexture
