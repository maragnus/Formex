--!strict

local FormexClient = require(script.Parent:WaitForChild("FormexClient"))
local Formex = FormexClient.Formex
local FormexUI = require(script.Parent:WaitForChild("FormexUI"))
local FormexDesign = require(script.Parent:WaitForChild("FormexDesign"))

local screenGui: ScreenGui = FormexUI.ScreenGui

local FormexPrefabCatalog = {}

local COLORS = {
	Panel = Color3.fromRGB(252, 252, 255),
	PanelTop = Color3.fromRGB(255, 255, 255),
	PanelBottom = Color3.fromRGB(240, 242, 255),
	Border = Color3.fromRGB(210, 210, 230),
	Section = Color3.fromRGB(245, 248, 255),
	SectionBorder = Color3.fromRGB(210, 216, 235),
	Text = Color3.fromRGB(45, 50, 80),
	Muted = Color3.fromRGB(90, 105, 140),
	Accent = Color3.fromRGB(88, 118, 255),
	AccentSoft = Color3.fromRGB(226, 232, 255),
	AccentBorder = Color3.fromRGB(130, 150, 255),
	Icon = Color3.fromRGB(70, 80, 115),
	Overlay = Color3.fromRGB(16, 18, 28),
} :: {[string]: Color3}

local PREVIEW_FOV = 35

type PreviewHandle = {
	Root: Frame,
	SetPrefab: (self: PreviewHandle, prefab: Formex.ObjectPrefab?) -> (),
}

local function computeCameraCFrame(size: Vector3): CFrame
	local maxSize = math.max(size.X, size.Y, size.Z)
	local fov = math.rad(PREVIEW_FOV)
	local distance = (maxSize * 0.75) / math.tan(fov / 2)
	distance = math.max(distance, maxSize * 1.6)

	local yaw = math.rad(45)
	local pitch = math.rad(18)
	local offset = Vector3.new(
		math.sin(yaw) * math.cos(pitch),
		math.sin(pitch),
		math.cos(yaw) * math.cos(pitch)
	) * distance

	return CFrame.new(offset, Vector3.new(0, 0, 0))
end

local function getPrefabAssetId(prefab: Formex.ObjectPrefab): number?
	if prefab.Attributes then
		local assetId = prefab.Attributes.AssetId or prefab.Attributes.PreviewAssetId
		if type(assetId) == "number" and assetId > 0 then return assetId end
	end
	return nil
end

local function resolvePreviewModel(prefab: Formex.ObjectPrefab): Model?
	local root = prefab.Model
	if not root then return nil end
	local prefabChild = root:FindFirstChild("Prefab")
	if prefabChild and prefabChild:IsA("Model") then return prefabChild end
	local modelChild = root:FindFirstChild("Model")
	if modelChild and modelChild:IsA("Model") then return modelChild end
	return root
end

local function applyPreviewModelSettings(model: Model)
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			child.Anchored = true
			child.CanCollide = false
			child.CanTouch = false
			child.CanQuery = false
			child.CastShadow = false
		elseif child:IsA("BaseScript") then
			child.Disabled = true
		end
	end
end

local function clearPreviewContent(content: Frame)
	for _, child in ipairs(content:GetChildren()) do
		child:Destroy()
	end
end

function FormexPrefabCatalog.CreatePreview(parent: Instance, size: UDim2?): PreviewHandle
	local root = Instance.new("Frame", parent)
	root.Name = "PrefabPreview"
	root.BackgroundColor3 = COLORS.PanelTop
	root.BackgroundTransparency = 0
	root.BorderSizePixel = 0
	root.Size = size or UDim2.new(1, 0, 1, 0)
	root.ClipsDescendants = true

	local corner = Instance.new("UICorner", root)
	corner.CornerRadius = UDim.new(0, 12)

	local stroke = Instance.new("UIStroke", root)
	stroke.Color = COLORS.SectionBorder
	stroke.Thickness = 1.4

	local content = Instance.new("Frame", root)
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, 0, 1, 0)
	content.ClipsDescendants = true

	local handle = {} :: PreviewHandle
	handle.Root = root

	function handle:SetPrefab(prefab: Formex.ObjectPrefab?)
		clearPreviewContent(content)
		if not prefab then
			local emptyLabel = Instance.new("TextLabel", content)
			emptyLabel.Name = "Empty"
			emptyLabel.BackgroundTransparency = 1
			emptyLabel.Size = UDim2.new(1, 0, 1, 0)
			emptyLabel.Font = Enum.Font.Gotham
			emptyLabel.Text = "No preview"
			emptyLabel.TextSize = 14
			emptyLabel.TextColor3 = COLORS.Muted
			return
		end

		local assetId = getPrefabAssetId(prefab)
		if assetId then
			local image = Instance.new("ImageLabel", content)
			image.Name = "Image"
			image.BackgroundTransparency = 1
			image.Size = UDim2.new(1, 0, 1, 0)
			image.ImageContent = Content.fromAssetId(assetId)
			image.ImageColor3 = Color3.new(1, 1, 1)
			image.ScaleType = Enum.ScaleType.Fit
			return
		end

		local sourceModel = resolvePreviewModel(prefab)
		if not sourceModel then
			local fallback = Instance.new("TextLabel", content)
			fallback.Name = "Missing"
			fallback.BackgroundTransparency = 1
			fallback.Size = UDim2.new(1, 0, 1, 0)
			fallback.Font = Enum.Font.Gotham
			fallback.Text = "Preview unavailable"
			fallback.TextSize = 14
			fallback.TextColor3 = COLORS.Muted
			return
		end

		local viewport = Instance.new("ViewportFrame", content)
		viewport.Name = "Viewport"
		viewport.BackgroundTransparency = 1
		viewport.Size = UDim2.new(1, 0, 1, 0)

		local camera = Instance.new("Camera")
		camera.FieldOfView = PREVIEW_FOV
		camera.Parent = viewport
		viewport.CurrentCamera = camera

		local clone = sourceModel:Clone()
		clone.Name = "PreviewModel"
		clone.Parent = viewport
		applyPreviewModelSettings(clone)
		clone:PivotTo(CFrame.new())

		local sizeValue = prefab.Size
		if not sizeValue or typeof(sizeValue) ~= "Vector3" then
			sizeValue = clone:GetExtentsSize()
		end
		camera.CFrame = computeCameraCFrame(sizeValue)
	end

	return handle
end

local ui = {
	Container = nil :: Frame?,
	Panel = nil :: Frame?,
	SearchBox = nil :: TextBox?,
	CategoryRow = nil :: Frame?,
	CategoryButtons = {} :: {[string]: any},
	Grid = nil :: ScrollingFrame?,
	GridLayout = nil :: UIGridLayout?,
	ItemButtons = {} :: {[string]: any},
	ResultLabel = nil :: TextLabel?,
}

local currentCategory = "All"
local currentSearch = ""
local selectedPrefabName: string? = nil

local function createChipButton(parent: Instance, label: string, onClick: () -> ())
	local button = Instance.new("TextButton", parent)
	button.Name = "Chip_" .. label
	button.BackgroundColor3 = COLORS.Section
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Size = UDim2.new(0, 0, 0, 28)
	button.AutomaticSize = Enum.AutomaticSize.X
	button.Font = Enum.Font.GothamSemibold
	button.Text = label
	button.TextSize = 12
	button.TextColor3 = COLORS.Text
	button.TextXAlignment = Enum.TextXAlignment.Center

	local corner = Instance.new("UICorner", button)
	corner.CornerRadius = UDim.new(0, 10)

	local stroke = Instance.new("UIStroke", button)
	stroke.Color = COLORS.SectionBorder
	stroke.Thickness = 1.2

	local padding = Instance.new("UIPadding", button)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)

	button.Activated:Connect(onClick)

	return {
		Button = button,
		Stroke = stroke,
		Label = label,
	}
end

local function setChipActive(chip, active: boolean)
	if active then
		chip.Button.BackgroundColor3 = COLORS.AccentSoft
		chip.Stroke.Color = COLORS.AccentBorder
		chip.Button.TextColor3 = COLORS.Accent
	else
		chip.Button.BackgroundColor3 = COLORS.Section
		chip.Stroke.Color = COLORS.SectionBorder
		chip.Button.TextColor3 = COLORS.Text
	end
end

local function setItemActive(item, active: boolean)
	if active then
		item.Button.BackgroundColor3 = COLORS.AccentSoft
		item.Stroke.Color = COLORS.AccentBorder
	else
		item.Button.BackgroundColor3 = COLORS.Section
		item.Stroke.Color = COLORS.SectionBorder
	end
end

local function getPrefabCategories(prefabs: {Formex.ObjectPrefab}): {string}
	local seen = {}
	local categories = { "All" }
	for _, prefab in ipairs(prefabs) do
		for _, category in ipairs(prefab.Categories or {}) do
			if category ~= "" and not seen[category] then
				seen[category] = true
				table.insert(categories, category)
			end
		end
	end
	table.sort(categories, function(a, b)
		if a == "All" then return true end
		if b == "All" then return false end
		return string.lower(a) < string.lower(b)
	end)
	return categories
end

local function matchesSearch(prefab: Formex.ObjectPrefab, searchText: string): boolean
	if searchText == "" then return true end
	local name = string.lower(prefab.Name or "")
	local prefabName = string.lower(prefab.PrefabName or "")
	return string.find(name, searchText, 1, true) ~= nil
		or string.find(prefabName, searchText, 1, true) ~= nil
end

local function matchesCategory(prefab: Formex.ObjectPrefab, category: string): boolean
	if category == "All" then return true end
	for _, entry in ipairs(prefab.Categories or {}) do
		if entry == category then return true end
	end
	return false
end

local function clearGrid()
	if not ui.Grid then return end
	for _, child in ipairs(ui.Grid:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	ui.ItemButtons = {}
end

local function rebuildCategoryRow(prefabs: {Formex.ObjectPrefab})
	if not ui.CategoryRow then return end
	for _, child in ipairs(ui.CategoryRow:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	ui.CategoryButtons = {}

	local categories = getPrefabCategories(prefabs)
	local hasCategory = false
	for _, category in ipairs(categories) do
		if category == currentCategory then
			hasCategory = true
			break
		end
	end
	if not hasCategory then
		currentCategory = "All"
	end
	for _, category in ipairs(categories) do
		local buttonInfo = createChipButton(ui.CategoryRow, category, function()
			currentCategory = category
			for name, chip in pairs(ui.CategoryButtons) do
				setChipActive(chip, name == currentCategory)
			end
			FormexPrefabCatalog.Refresh(false)
		end)
		ui.CategoryButtons[category] = buttonInfo
		setChipActive(buttonInfo, category == currentCategory)
	end
end

local function buildCard(parent: Instance, prefab: Formex.ObjectPrefab)
	local card = Instance.new("ImageButton", parent)
	card.Name = "Prefab_" .. prefab.PrefabName
	card.AutoButtonColor = false
	card.BackgroundColor3 = COLORS.Section
	card.BorderSizePixel = 0
	card.Size = UDim2.new(0, 180, 0, 210)

	local corner = Instance.new("UICorner", card)
	corner.CornerRadius = UDim.new(0, 12)

	local stroke = Instance.new("UIStroke", card)
	stroke.Color = COLORS.SectionBorder
	stroke.Thickness = 1.4

	local padding = Instance.new("UIPadding", card)
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)

	local layout = Instance.new("UIListLayout", card)
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)

	local preview = FormexPrefabCatalog.CreatePreview(card, UDim2.new(1, 0, 0, 120))
	preview.Root.LayoutOrder = 1
	preview:SetPrefab(prefab)

	local nameLabel = Instance.new("TextLabel", card)
	nameLabel.Name = "Label"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0, 20)
	nameLabel.Font = Enum.Font.GothamSemibold
	nameLabel.Text = prefab.Name
	nameLabel.TextSize = 14
	nameLabel.TextColor3 = COLORS.Text
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.LayoutOrder = 2

	local mountLabel = Instance.new("TextLabel", card)
	mountLabel.Name = "Mount"
	mountLabel.BackgroundTransparency = 1
	mountLabel.Size = UDim2.new(1, 0, 0, 16)
	mountLabel.Font = Enum.Font.Gotham
	mountLabel.Text = tostring(prefab.ObjectMount)
	mountLabel.TextSize = 12
	mountLabel.TextColor3 = COLORS.Muted
	mountLabel.TextXAlignment = Enum.TextXAlignment.Center
	mountLabel.LayoutOrder = 3

	card.Activated:Connect(function()
		FormexDesign.UpdateDesignState({ Object = { PrefabName = prefab.PrefabName } })
		FormexPrefabCatalog.Hide()
	end)

	ui.ItemButtons[prefab.PrefabName] = {
		Button = card,
		Stroke = stroke,
	}
	setItemActive(ui.ItemButtons[prefab.PrefabName], prefab.PrefabName == selectedPrefabName)
end

local function rebuildGrid(prefabs: {Formex.ObjectPrefab})
	clearGrid()
	if not ui.Grid then return end
	for _, prefab in ipairs(prefabs) do
		buildCard(ui.Grid, prefab)
	end

	if ui.ResultLabel then
		ui.ResultLabel.Text = string.format("%d prefabs", #prefabs)
	end
end

local function refreshSelection()
	for prefabName, item in pairs(ui.ItemButtons) do
		setItemActive(item, prefabName == selectedPrefabName)
	end
end

local function buildCatalog()
	if ui.Container then return end
	local overlay = Instance.new("Frame", screenGui)
	overlay.Name = "FormexPrefabCatalog"
	overlay.BackgroundTransparency = 1
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.Visible = false

	local dimmer = Instance.new("Frame", overlay)
	dimmer.Name = "Dimmer"
	dimmer.BackgroundColor3 = COLORS.Overlay
	dimmer.BackgroundTransparency = 0.35
	dimmer.BorderSizePixel = 0
	dimmer.Size = UDim2.new(1, 0, 1, 0)

	local panel = Instance.new("Frame", overlay)
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.Size = UDim2.new(1, -72, 1, -72)
	panel.BackgroundColor3 = COLORS.Panel
	panel.BorderSizePixel = 0

	local panelCorner = Instance.new("UICorner", panel)
	panelCorner.CornerRadius = UDim.new(0, 18)

	local panelStroke = Instance.new("UIStroke", panel)
	panelStroke.Color = COLORS.Border
	panelStroke.Thickness = 1.8

	local gradient = Instance.new("UIGradient", panel)
	gradient.Color = ColorSequence.new(COLORS.PanelTop, COLORS.PanelBottom)
	gradient.Rotation = 90

	local padding = Instance.new("UIPadding", panel)
	padding.PaddingTop = UDim.new(0, 16)
	padding.PaddingBottom = UDim.new(0, 16)
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)

	local layout = Instance.new("UIListLayout", panel)
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 12)

	local header = Instance.new("Frame", panel)
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 42)
	header.LayoutOrder = 1

	local headerLayout = Instance.new("UIListLayout", header)
	headerLayout.FillDirection = Enum.FillDirection.Horizontal
	headerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	headerLayout.Padding = UDim.new(0, 10)
	headerLayout.VerticalAlignment = Enum.VerticalAlignment.Center

	local title = Instance.new("TextLabel", header)
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -60, 1, 0)
	title.Font = Enum.Font.GothamBold
	title.Text = "Prefab Catalog"
	title.TextSize = 20
	title.TextColor3 = COLORS.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	FormexUI.FlexItem(title, Enum.UIFlexMode.Grow)

	local closeButton = Instance.new("ImageButton", header)
	closeButton.Name = "Close"
	closeButton.AutoButtonColor = false
	closeButton.BackgroundColor3 = COLORS.Section
	closeButton.BorderSizePixel = 0
	closeButton.Size = UDim2.new(0, 36, 0, 36)

	local closeCorner = Instance.new("UICorner", closeButton)
	closeCorner.CornerRadius = UDim.new(0, 10)

	local closeStroke = Instance.new("UIStroke", closeButton)
	closeStroke.Color = COLORS.SectionBorder
	closeStroke.Thickness = 1.2

	local closeIcon = Instance.new("ImageLabel", closeButton)
	closeIcon.Name = "Icon"
	closeIcon.BackgroundTransparency = 1
	closeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	closeIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
	closeIcon.Size = UDim2.new(0.55, 0, 0.55, 0)
	closeIcon.ImageContent = Content.fromAssetId(Formex.Icons.Cancel or 0)
	closeIcon.ImageColor3 = COLORS.Icon

	closeButton.Activated:Connect(function()
		FormexPrefabCatalog.Hide()
	end)

	local filterRow = Instance.new("Frame", panel)
	filterRow.Name = "FilterRow"
	filterRow.BackgroundTransparency = 1
	filterRow.Size = UDim2.new(1, 0, 0, 50)
	filterRow.LayoutOrder = 2

	local filterLayout = Instance.new("UIListLayout", filterRow)
	filterLayout.FillDirection = Enum.FillDirection.Horizontal
	filterLayout.SortOrder = Enum.SortOrder.LayoutOrder
	filterLayout.Padding = UDim.new(0, 12)
	filterLayout.VerticalAlignment = Enum.VerticalAlignment.Center

	local searchFrame = Instance.new("Frame", filterRow)
	searchFrame.Name = "Search"
	searchFrame.BackgroundColor3 = COLORS.Section
	searchFrame.BorderSizePixel = 0
	searchFrame.Size = UDim2.new(0.6, 0, 1, 0)
	searchFrame.LayoutOrder = 1

	local searchCorner = Instance.new("UICorner", searchFrame)
	searchCorner.CornerRadius = UDim.new(0, 12)

	local searchStroke = Instance.new("UIStroke", searchFrame)
	searchStroke.Color = COLORS.SectionBorder
	searchStroke.Thickness = 1.4

	local searchPadding = Instance.new("UIPadding", searchFrame)
	searchPadding.PaddingLeft = UDim.new(0, 12)
	searchPadding.PaddingRight = UDim.new(0, 12)

	local searchBox = Instance.new("TextBox", searchFrame)
	searchBox.Name = "SearchBox"
	searchBox.BackgroundTransparency = 1
	searchBox.ClearTextOnFocus = false
	searchBox.PlaceholderText = "Search prefabs"
	searchBox.Size = UDim2.new(1, 0, 1, 0)
	searchBox.Font = Enum.Font.Gotham
	searchBox.Text = ""
	searchBox.TextSize = 16
	searchBox.TextColor3 = COLORS.Text
	searchBox.TextXAlignment = Enum.TextXAlignment.Left

	local resultLabel = Instance.new("TextLabel", filterRow)
	resultLabel.Name = "ResultLabel"
	resultLabel.BackgroundTransparency = 1
	resultLabel.Size = UDim2.new(0.4, -12, 1, 0)
	resultLabel.Font = Enum.Font.Gotham
	resultLabel.Text = "0 prefabs"
	resultLabel.TextSize = 14
	resultLabel.TextColor3 = COLORS.Muted
	resultLabel.TextXAlignment = Enum.TextXAlignment.Right
	resultLabel.LayoutOrder = 2

	local categoryRow = Instance.new("Frame", panel)
	categoryRow.Name = "Categories"
	categoryRow.BackgroundTransparency = 1
	categoryRow.Size = UDim2.new(1, 0, 0, 0)
	categoryRow.AutomaticSize = Enum.AutomaticSize.Y
	categoryRow.LayoutOrder = 3

	local categoryLayout = Instance.new("UIListLayout", categoryRow)
	categoryLayout.FillDirection = Enum.FillDirection.Horizontal
	categoryLayout.SortOrder = Enum.SortOrder.LayoutOrder
	categoryLayout.Padding = UDim.new(0, 8)
	categoryLayout.Wraps = true

	local grid = Instance.new("ScrollingFrame", panel)
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.Size = UDim2.new(1, 0, 1, -170)
	grid.LayoutOrder = 4
	grid.ScrollBarThickness = 6
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.ScrollingDirection = Enum.ScrollingDirection.Y

	local gridLayout = Instance.new("UIGridLayout", grid)
	gridLayout.CellSize = UDim2.new(0, 180, 0, 210)
	gridLayout.CellPadding = UDim2.new(0, 12, 0, 12)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder

	ui.Container = overlay
	ui.Panel = panel
	ui.SearchBox = searchBox
	ui.CategoryRow = categoryRow
	ui.Grid = grid
	ui.GridLayout = gridLayout
	ui.ResultLabel = resultLabel

	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		currentSearch = string.lower(searchBox.Text or "")
		FormexPrefabCatalog.Refresh(false)
	end)

	dimmer.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
			FormexPrefabCatalog.Hide()
		end
	end)
end

function FormexPrefabCatalog.Refresh(forceRebuild: boolean?)
	buildCatalog()
	if not ui.Container then return end
	local prefabs = Formex.Objects.GetPrefabs()
	if forceRebuild or next(ui.CategoryButtons) == nil then
		rebuildCategoryRow(prefabs)
	end

	local filtered = {}
	for _, prefab in ipairs(prefabs) do
		if matchesCategory(prefab, currentCategory) and matchesSearch(prefab, currentSearch) then
			table.insert(filtered, prefab)
		end
	end

	table.sort(filtered, function(a, b)
		return string.lower(a.Name or "") < string.lower(b.Name or "")
	end)

	rebuildGrid(filtered)
	refreshSelection()
end

function FormexPrefabCatalog.Show()
	buildCatalog()
	if not ui.Container then return end
	local plot = FormexClient.CurrentPlot
	if not plot or not plot.IsValid then return end
	local state = FormexDesign.GetDesignState()
	if state.Mode ~= FormexDesign.DesignMode.Object then return end
	selectedPrefabName = state.Object and state.Object.PrefabName or nil
	ui.Container.Visible = true
	FormexPrefabCatalog.Refresh(true)
end

function FormexPrefabCatalog.Hide()
	if ui.Container then
		ui.Container.Visible = false
	end
end

function FormexPrefabCatalog.IsVisible(): boolean
	return ui.Container ~= nil and ui.Container.Visible
end

function FormexPrefabCatalog.Toggle()
	if FormexPrefabCatalog.IsVisible() then
		FormexPrefabCatalog.Hide()
	else
		FormexPrefabCatalog.Show()
	end
end

FormexClient.ClientEvents:Connect(function(eventName)
	if eventName ~= "DesignStateChanged" and eventName ~= "CurrentPlotChanged" then return end
	if not ui.Container or not ui.Container.Visible then return end
	local plot = FormexClient.CurrentPlot
	if not plot or not plot.IsValid then
		FormexPrefabCatalog.Hide()
		return
	end

	local state = FormexDesign.GetDesignState()
	if state.Mode ~= FormexDesign.DesignMode.Object then
		FormexPrefabCatalog.Hide()
		return
	end

	selectedPrefabName = state.Object and state.Object.PrefabName or nil
	refreshSelection()
end)

return FormexPrefabCatalog
