--!strict

local Formex = require(script.Parent:FindFirstChild("Formex"))

-- Represented as Part.MaterialVariant
-- WARNING this list is ordered and indexed, removing and reordering items will break existing builds
Formex.Materials = {
	{
		Name = "Basic Plaster",
		Material = Enum.Material.Plaster,
		MaterialVariant = "Basic Plaster",
		PreviewAssetId = 129376458712399,
	},
	{
		Name = "Ceramic Tiles",
		Material = Enum.Material.CeramicTiles,
		MaterialVariant = "Ceramic Tiles",
		PreviewAssetId = 129376458712399,
	},
	{
		Name = "Carpet",
		Material = Enum.Material.Carpet,
		MaterialVariant = "Commercial Carpet",
		PreviewAssetId = 119901194214934,
	},
	{
		Name = "Arcade Stars",
		Material = Enum.Material.Carpet,
		MaterialVariant = "Arcade Stars",
		PreviewAssetId = 105056201224798,
	},
	{
		Name = "Arcade Lines",
		Material = Enum.Material.Carpet,
		MaterialVariant = "Arcade Lines",
		PreviewAssetId = 102853832787062,
	},
	{
		Name = "Brick",
		Material = Enum.Material.Brick,
		MaterialVariant = "Brick",
		PreviewAssetId = 107922567322014,
	},
	{
		Name = "Rough Brick",
		Material = Enum.Material.Brick,
		MaterialVariant = "Rough Brick",
		PreviewAssetId = 107922567322014,
	},
	{
		Name = "Cobblestone",
		Material = Enum.Material.CeramicTiles,
		MaterialVariant = "Cobblestone",
		PreviewAssetId = 129376458712399,
	},
	{
		Name = "Checkered Tiles",
		Material = Enum.Material.CeramicTiles,
		MaterialVariant = "Checkered Tiles",
		PreviewAssetId = 81652242056434,
	},
	{
		Name = "Speckle Tiles",
		Material = Enum.Material.CeramicTiles,
		MaterialVariant = "Speckle Tiles",
		PreviewAssetId = 98900012004141,
	},
	{
		Name = "Wood Panels",
		Material = Enum.Material.Wood,
		MaterialVariant = "WoodFloor",
		PreviewAssetId = 133949919154473,
	}
} :: {number: Formex.MaterialInfo}

Formex.Icons = { -- Content.fromAssetId(...)
    Menu = 123614418099512,
	Confirm = 116875236311469,
	Cancel = 92308571652477,
    Refresh = 123101975679190,
	DirectionIndicator = 81358910239829,
    ModeAutomatic = 134762217816858,
    ModeManual = 83671159533759,
    AddItem = 128647721275129,
    MoveItem = 83970836971222,
	RotateItem = 101431557821612,
    ResizeItem = 78551851583998,
    DeleteItem = 91738865172085,
	ElevateItem = 95483409978733,
    WallExtend = 128647721275129,
    WallDivide = 116931266034105,
    WallDisconnect = 70397467113579,
    PlotExpand = 88488799504419,
    PlotRename = 74166756362476,
    PlotClaim = 85199762467908,
    PlotRelease = 137711830774408,
    PlotPermissions = 83277863761797,
	DesignStart = 78727585562674,
	DesignSelect = 129357891944983,
    DesignFurniture = 120639802680464,
    DesignFloors = 108407135224343,
    DesignWalls =  105416010695180,
    DesignBuild = 121737476159985,
    DesignPaint = 92885878760720,
	DesignDropper = 92599750112347,
	DesignRoom = 136707442598480,
    Undo = 118863163301402,
    Redo = 118241293985419,
    ChevronDown = 84853982697443,
    ChevronUp = 125753605575669,
    AlertPrimary = 103853485477063,
    AlertSecondary = 115719232269249,
    AlertInfo = 119134101744939,
    AlertWarn = 111518129231234,
    AlertDanger = 73134495809587,
	SecurityLock = 71709652798579,
	SecurityUnlock = 95498189643385,
	SecurityKey = 115917399534136,
	Camera = 70772215979759,
    CircleBackground = 114484129436279,
} :: {[string]: number}

Formex.Furniture = {
	{
		Name = "Modern Chair",
		IconAssetId = 128201486227303,
		PrefabName = "Chairs/ModernChair",
		ObjectMount = Formex.MountType.Floor,
		Size = Vector3.new(4, 6, 4),
		Categories = { "Seating", "Indoors" },
		DefaultDesign = { Formex.DefaultWallMaterial },
	},
} :: {Formex.ObjectPrefab}

return Formex
