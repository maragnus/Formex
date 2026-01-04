--!strict

local Formex = require(script.Parent:FindFirstChild("Formex"))

Formex.Materials = {
	{
		Name = "Structure",
		Material = Enum.Material.Wood,
		StudsPerTile = 4,
		AssetId = 10536172711,
	},
	{
		Name = "Checked Tile",
		Material = Enum.Material.CeramicTiles,
		AssetId = 10536172734,
		StudsPerTile = 8,
		Categories = { "Floor", "Wall", "Ceiling" }
	},
	{
		Name = "Beige Tile",
		Material = Enum.Material.CeramicTiles,
		AssetId = 125491924817688,
		StudsPerTile = 4,
		Categories = { "Floor" }
	}
} :: {number: Formex.MaterialInfo}

Formex.Icons = { -- Content.fromAssetId(...)
    Menu = 123614418099512,
    Refresh = 123101975679190,
    AddItem = 128647721275129,
    MoveItem = 83970836971222,
	RotateItem = 101431557821612,
    ResizeItem = 78551851583998,
    DeleteItem = 91738865172085,
    WallExtend = 128647721275129,
    WallDivide = 116931266034105,
    WallDisconnect = 70397467113579,
    PlotExpand = 88488799504419,
    PlotRename = 74166756362476,
    PlotClaim = 85199762467908,
    PlotRelease = 137711830774408,
    PlotPermissions = 83277863761797,
    DesignStart = 78727585562674,
    DesignFurniture = 120639802680464,
    DesignCeilings = 86944909652185,
    DesignFloors = 136537860205120,
    DesignWalls =  105416010695180,
    DesignPaint = 92885878760720,
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
		Size = Vector3.new(4, 6, 4),
		Categories = { "Seating", "Indoors" },
	},
} :: {Formex.ObjectInfo}

return Formex