--!strict

local Constants = {}

-- Copied values from src/shared/Formex.luau for prefab rules.
Constants.LayoutGridSize = 4
Constants.ObjectGridSize = 1
Constants.WallThickness = 0.5

-- Copied from src/client/FormexDesign.luau applyGridTexture.
Constants.GridTextureAssetId = 116671576387684
Constants.GridTextureColor = Color3.fromRGB(200, 200, 200)
Constants.GridTextureTransparency = 0.15

Constants.Stage = {
	Size = 16,
	Gap = 4,
	YOffset = -500,
	FloorThickness = 0.2,
}

Constants.Prefab = {
	WorkspaceRootName = "Formex",
	WorkspacePrefabsFolderName = "Prefabs",
	ReplicatedPrefabsFolderName = "FormexPrefabs",
	PrefabModelName = "Prefab",
	SubtractModelName = "Subtract",
	StageModelName = "Stage",
	SizeGuideName = "SizeGuide",
	StageFolderName = "Stages",
}

Constants.Attributes = {
	DisplayName = "DisplayName",
	IconAssetId = "IconAssetId",
	ObjectMount = "ObjectMount",
	Size = "Size",
	Categories = "Categories",
	StageId = "StageId",
}

Constants.ObjectMounts = {
	"Surface",
	"Ceiling",
	"Floor",
	"Wall",
	"Door",
	"Window",
}

return Constants
