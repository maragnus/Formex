--!strict

local Constants = require(script.Parent:WaitForChild("Constants"))
local PluginUtils = require(script.Parent:WaitForChild("PluginUtils"))

type PrefabEditData = {
	PrefabPath: string?,
	DisplayName: string?,
	IconAssetId: number?,
	ObjectMount: string?,
	Size: Vector3?,
	Categories: string?,
	HasSubtractModel: boolean?,
	StoreMode: string?,
}

type Callbacks = {
	OnPrepare: () -> (),
	OnUpdate: (PrefabEditData) -> (),
	OnStore: () -> (),
	OnStoreAll: () -> (),
	OnToggleSubtract: () -> (),
	OnAutoSize: () -> (),
	OnAutoPosition: () -> (),
	OnApplySizeGuide: () -> (),
	OnPreview: () -> (),
	OnFocusStage: () -> (),
	OnPullSelected: ({string}) -> (),
	OnDeleteSelected: ({string}) -> (),
	OnRefreshCatalog: (string) -> (),
}

type PrefabUI = {
	Show: (self: PrefabUI) -> (),
	Hide: (self: PrefabUI) -> (),
	IsVisible: (self: PrefabUI) -> boolean,
	SetSelection: (self: PrefabUI, data: PrefabEditData?) -> (),
	UpdateCatalog: (self: PrefabUI, entries: {string}) -> (),
	GetCurrentData: (self: PrefabUI) -> PrefabEditData,
}

local PrefabUIFactory = {}

local ICON_PRIMARY = 121737476159985
local ICON_REFRESH = 123101975679190
local ICON_SAVE = 136537860205120
local ICON_LOAD = 86944909652185
local ICON_SUBTRACT = 70397467113579
local ICON_AUTO_POSITION = 83970836971222
local ICON_AUTO_SIZE = 108407135224343
local ICON_FOCUS = 88488799504419
local ICON_PREVIEW = 70772215979759
local ICON_UPDATE_ATTRIBUTES = 116875236311469
local ICON_OBJECT_MOUNT = 114484129436279
local ICON_DELETE = 91738865172085

local function createWidget(plugin: Plugin): DockWidgetPluginGui
	local info = DockWidgetPluginGuiInfo.new(
		Enum.InitialDockState.Left,
		false,
		false,
		360,
		640,
		320,
		480
	)
	local widget = plugin:CreateDockWidgetPluginGuiAsync("FormexPrefabPanel", info)
	widget.Title = "Formex Prefabs"
	return widget
end

local function createSection(container: Instance, title: string)
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Parent = container

	local header = Instance.new("TextLabel")
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.GothamBold
	header.Text = title
	header.TextColor3 = Color3.fromRGB(235, 235, 235)
	header.TextSize = 14
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Size = UDim2.new(1, -16, 0, 24)
	header.Position = UDim2.new(0, 8, 0, 6)
	header.Parent = frame

	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, -16, 0, 0)
	content.Position = UDim2.new(0, 8, 0, 30)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = content

	return content
end

local function createLabel(container: Instance, text: string)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.Text = text
	label.TextColor3 = Color3.fromRGB(210, 210, 210)
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.new(1, 0, 0, 18)
	label.Parent = container
	return label
end

local function createTextBox(container: Instance, placeholder: string): TextBox
	local box = Instance.new("TextBox")
	box.BackgroundColor3 = Color3.fromRGB(34, 34, 40)
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Font = Enum.Font.Gotham
	box.PlaceholderText = placeholder
	box.Text = ""
	box.TextColor3 = Color3.fromRGB(235, 235, 235)
	box.TextSize = 12
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Size = UDim2.new(1, 0, 0, 26)
	box.Parent = container
	return box
end

local function setControlsVisible(controls: {Instance}, visible: boolean)
	for _, control in ipairs(controls) do
		control.Visible = visible
	end
end

local function createButton(container: Instance, label: string): TextButton
	local button = Instance.new("TextButton")
	button.BackgroundColor3 = Color3.fromRGB(46, 46, 54)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.Text = label
	button.TextColor3 = Color3.fromRGB(235, 235, 235)
	button.TextSize = 12
	button.TextXAlignment = Enum.TextXAlignment.Center
	button.Size = UDim2.new(1, 0, 0, 28)
	button.Parent = container
	return button
end

local function addButtonIcon(button: TextButton, assetId: number)
	local padding = button:FindFirstChildOfClass("UIPadding")
	if padding then
		padding.PaddingLeft = UDim.new(0, 0)
		padding.PaddingRight = UDim.new(0, 0)
		padding.PaddingTop = UDim.new(0, 0)
		padding.PaddingBottom = UDim.new(0, 0)
	end

	local layoutFrame = Instance.new("Frame")
	layoutFrame.Name = "IconLayout"
	layoutFrame.BackgroundTransparency = 1
	layoutFrame.Size = UDim2.fromScale(1, 1)
	layoutFrame.Parent = button

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = layoutFrame

	local icon = Instance.new("ImageLabel")
	icon.Name = "ButtonIcon"
	icon.BackgroundTransparency = 1
	icon.ImageContent = Content.fromAssetId(assetId)
	icon.Size = UDim2.new(0, 16, 0, 16)
	icon.Parent = layoutFrame

	local label = Instance.new("TextLabel")
	label.Name = "ButtonLabel"
	label.BackgroundTransparency = 1
	label.Font = button.Font
	local defaultText = button.Text
	label.TextColor3 = button.TextColor3
	label.TextSize = button.TextSize
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Size = UDim2.new(0, 0, 1, 0)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Parent = layoutFrame

	label.Text = defaultText
	button.TextXAlignment = Enum.TextXAlignment.Center
	button.TextTransparency = 1
	button.TextStrokeTransparency = 1
	button:GetPropertyChangedSignal("Text"):Connect(function()
		label.Text = button.Text
	end)
end

local function createHorizontalGroup(container: Instance): Frame
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 28)
	row.Parent = container

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	return row
end

local function createVectorInputs(container: Instance, label: string)
	local header = createLabel(container, label)
	local row = createHorizontalGroup(container)
	local x = createTextBox(row, "X")
	x.Size = UDim2.new(0.33, -4, 0, 26)
	local y = createTextBox(row, "Y")
	y.Size = UDim2.new(0.33, -4, 0, 26)
	local z = createTextBox(row, "Z")
	z.Size = UDim2.new(0.33, -4, 0, 26)
	return header, x, y, z
end

local function parseNumber(text: string): number?
	local value = tonumber(text)
	if value == nil then return nil end
	return value
end

local function parseVector(x: TextBox, y: TextBox, z: TextBox): Vector3?
	local vx = parseNumber(x.Text)
	local vy = parseNumber(y.Text)
	local vz = parseNumber(z.Text)
	if vx == nil or vy == nil or vz == nil then return nil end
	return Vector3.new(vx, vy, vz)
end

function PrefabUIFactory.new(plugin: Plugin, callbacks: Callbacks): PrefabUI
	local widget = createWidget(plugin)
	local base = Instance.new("Frame")
	base.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	base.BorderSizePixel = 0
	base.Size = UDim2.fromScale(1, 1)
	base.Parent = widget

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	scroll.Parent = base

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	local selectionSection = createSection(scroll, "Selection")
	local selectionMessage = createLabel(selectionSection, "Select a prefab to edit it, or pull one from the catalog below.")
	selectionMessage.TextWrapped = true
	selectionMessage.Size = UDim2.new(1, 0, 0, 32)
	selectionMessage.Visible = false
	local selectionControls = {}
	local selectedPathBox = createTextBox(selectionSection, "Prefab Path")
	table.insert(selectionControls, selectedPathBox)
	local displayNameBox = createTextBox(selectionSection, "Display Name")
	table.insert(selectionControls, displayNameBox)
	local iconAssetBox = createTextBox(selectionSection, "Icon Asset Id")
	table.insert(selectionControls, iconAssetBox)

	local mountLabel = createLabel(selectionSection, "Object Mount")
	table.insert(selectionControls, mountLabel)
	local mountButton = createButton(selectionSection, "Floor")
	table.insert(selectionControls, mountButton)

	local subtractWarning = Instance.new("TextLabel")
	subtractWarning.BackgroundTransparency = 1
	subtractWarning.Font = Enum.Font.GothamBold
	subtractWarning.Text = "Missing Subtract model. Click Toggle Subtract to create it."
	subtractWarning.TextColor3 = Color3.fromRGB(255, 196, 64)
	subtractWarning.TextSize = 12
	subtractWarning.TextWrapped = true
	subtractWarning.TextXAlignment = Enum.TextXAlignment.Left
	subtractWarning.Size = UDim2.new(1, 0, 0, 32)
	subtractWarning.Visible = false
	subtractWarning.Parent = selectionSection
	table.insert(selectionControls, subtractWarning)

	local categoriesBox = createTextBox(selectionSection, "Categories (comma list)")
	table.insert(selectionControls, categoriesBox)

	local sizeLabel, sizeX, sizeY, sizeZ = createVectorInputs(selectionSection, "Size (W / H / D)")
	table.insert(selectionControls, sizeLabel)
	table.insert(selectionControls, sizeX)
	table.insert(selectionControls, sizeY)
	table.insert(selectionControls, sizeZ)
	local sizeButtonRow = createHorizontalGroup(selectionSection)
	table.insert(selectionControls, sizeButtonRow)
	local autoSizeButton = createButton(sizeButtonRow, "Auto Size")
	autoSizeButton.Size = UDim2.new(0.5, -3, 0, 26)
	local guideSizeButton = createButton(sizeButtonRow, "Toggle Size Guide")
	guideSizeButton.Size = UDim2.new(0.5, -3, 0, 26)
	local autoPositionButton = createButton(selectionSection, "Auto Position")
	table.insert(selectionControls, autoPositionButton)

	local actionSection = createSection(scroll, "Actions")
	local prepareButton = createButton(actionSection, "Prepare Selection")
	local updateButton = createButton(actionSection, "Update Attributes")
	local storeButton = createButton(actionSection, "Store Selected")
	local storeAllButton = createButton(actionSection, "Store All Workspace Prefabs")
	local toggleSubtractButton = createButton(actionSection, "Toggle Subtract")
	local focusStageButton = createButton(actionSection, "Focus Stage")
	local previewButton = createButton(actionSection, "Toggle Preview")
	local updateButtonHeight = updateButton.Size.Y.Offset
	local storeButtonHeight = storeButton.Size.Y.Offset
	local toggleSubtractHeight = toggleSubtractButton.Size.Y.Offset
	local focusStageButtonHeight = focusStageButton.Size.Y.Offset
	local previewButtonHeight = previewButton.Size.Y.Offset
	local storeButtonDefaultText = storeButton.Text

	local function updateStoreButton(mode: string?)
		if mode == "Pull" then
			storeButton.Text = "Pull Selected"
		elseif mode == "Mixed" then
			storeButton.Text = "Store/Pull Selected"
		else
			storeButton.Text = storeButtonDefaultText
		end
	end

	local function setActionButtonState(button: TextButton, visible: boolean, height: number)
		button.Visible = visible
		button.Size = UDim2.new(1, 0, 0, visible and height or 0)
	end

	local catalogSection = createSection(scroll, "Replicated Prefab Catalog")
	local searchBox = createTextBox(catalogSection, "Search")
	local refreshButton = createButton(catalogSection, "Refresh Catalog")
	local pullButton = createButton(catalogSection, "Pull Selected")
	local deleteButton = createButton(catalogSection, "Delete Selected")

	local catalogList = Instance.new("ScrollingFrame")
	catalogList.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	catalogList.BorderSizePixel = 0
	catalogList.Size = UDim2.new(1, 0, 0, 220)
	catalogList.CanvasSize = UDim2.new()
	catalogList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	catalogList.ScrollBarThickness = 6
	catalogList.Parent = catalogSection

	local catalogLayout = Instance.new("UIListLayout")
	catalogLayout.Padding = UDim.new(0, 4)
	catalogLayout.SortOrder = Enum.SortOrder.LayoutOrder
	catalogLayout.Parent = catalogList

	local selectedCatalog: {[string]: boolean} = {}

	local mountIndex = 3
	local hasSelection = false
	local function updateMountButton()
		mountButton.Text = Constants.ObjectMounts[mountIndex]
	end
	updateMountButton()

	addButtonIcon(mountButton, ICON_OBJECT_MOUNT)
	addButtonIcon(autoSizeButton, ICON_AUTO_SIZE)
	addButtonIcon(autoPositionButton, ICON_AUTO_POSITION)
	addButtonIcon(prepareButton, ICON_PRIMARY)
	addButtonIcon(updateButton, ICON_UPDATE_ATTRIBUTES)
	addButtonIcon(storeButton, ICON_SAVE)
	addButtonIcon(storeAllButton, ICON_SAVE)
	addButtonIcon(toggleSubtractButton, ICON_SUBTRACT)
	addButtonIcon(focusStageButton, ICON_FOCUS)
	addButtonIcon(previewButton, ICON_PREVIEW)
	addButtonIcon(pullButton, ICON_LOAD)
	addButtonIcon(deleteButton, ICON_DELETE)
	addButtonIcon(refreshButton, ICON_REFRESH)

	mountButton.MouseButton1Click:Connect(function()
		mountIndex += 1
		if mountIndex > #Constants.ObjectMounts then
			mountIndex = 1
		end
		updateMountButton()
		if hasSelection then
			callbacks.OnUpdate({ ObjectMount = mountButton.Text })
		end
	end)

	autoSizeButton.MouseButton1Click:Connect(function()
		callbacks.OnAutoSize()
	end)

	autoPositionButton.MouseButton1Click:Connect(function()
		callbacks.OnAutoPosition()
	end)

	guideSizeButton.MouseButton1Click:Connect(function()
		callbacks.OnApplySizeGuide()
	end)

	prepareButton.MouseButton1Click:Connect(function()
		callbacks.OnPrepare()
	end)

	local function buildInputData(): PrefabEditData
		return {
			PrefabPath = selectedPathBox.Text,
			DisplayName = displayNameBox.Text,
			IconAssetId = tonumber(iconAssetBox.Text),
			ObjectMount = mountButton.Text,
			Categories = categoriesBox.Text,
			Size = parseVector(sizeX, sizeY, sizeZ),
		}
	end

	updateButton.MouseButton1Click:Connect(function()
		callbacks.OnUpdate(buildInputData())
	end)

	storeButton.MouseButton1Click:Connect(function()
		callbacks.OnStore()
	end)

	storeAllButton.MouseButton1Click:Connect(function()
		callbacks.OnStoreAll()
	end)

	toggleSubtractButton.MouseButton1Click:Connect(function()
		callbacks.OnToggleSubtract()
	end)

	focusStageButton.MouseButton1Click:Connect(function()
		callbacks.OnFocusStage()
	end)

	previewButton.MouseButton1Click:Connect(function()
		callbacks.OnPreview()
	end)

	refreshButton.MouseButton1Click:Connect(function()
		callbacks.OnRefreshCatalog(searchBox.Text)
	end)

	pullButton.MouseButton1Click:Connect(function()
		local selections = {}
		for path, isSelected in pairs(selectedCatalog) do
			if isSelected then
				table.insert(selections, path)
			end
		end
		table.sort(selections)
		callbacks.OnPullSelected(selections)
	end)

	deleteButton.MouseButton1Click:Connect(function()
		local selections = {}
		for path, isSelected in pairs(selectedCatalog) do
			if isSelected then
				table.insert(selections, path)
			end
		end
		table.sort(selections)
		callbacks.OnDeleteSelected(selections)
	end)

	local ui = {} :: PrefabUI

	function ui:Show()
		widget.Enabled = true
	end

	function ui:Hide()
		widget.Enabled = false
	end

	function ui:IsVisible(): boolean
		return widget.Enabled
	end

	function ui:SetSelection(data: PrefabEditData?)
		if not data then
			hasSelection = false
			selectionMessage.Visible = true
			setControlsVisible(selectionControls, false)
			selectedPathBox.Text = ""
			displayNameBox.Text = ""
			iconAssetBox.Text = ""
			categoriesBox.Text = ""
			sizeX.Text = ""
			sizeY.Text = ""
			sizeZ.Text = ""
			subtractWarning.Visible = false
			setActionButtonState(updateButton, false, updateButtonHeight)
			setActionButtonState(storeButton, false, storeButtonHeight)
			setActionButtonState(toggleSubtractButton, false, toggleSubtractHeight)
			setActionButtonState(focusStageButton, false, focusStageButtonHeight)
			setActionButtonState(previewButton, true, previewButtonHeight)
			updateStoreButton(nil)
			return
		end
		hasSelection = true
		selectionMessage.Visible = false
		setControlsVisible(selectionControls, true)

		selectedPathBox.Text = data.PrefabPath or ""
		displayNameBox.Text = data.DisplayName or ""
		iconAssetBox.Text = data.IconAssetId and tostring(data.IconAssetId) or ""
		categoriesBox.Text = data.Categories or ""

		if data.ObjectMount then
			local found = table.find(Constants.ObjectMounts, data.ObjectMount)
			if found then
				mountIndex = found
				updateMountButton()
			end
		end

		local isDoorWindow = data.ObjectMount == "Door" or data.ObjectMount == "Window"
		setActionButtonState(updateButton, true, updateButtonHeight)
		setActionButtonState(storeButton, true, storeButtonHeight)
		setActionButtonState(focusStageButton, true, focusStageButtonHeight)
		setActionButtonState(previewButton, true, previewButtonHeight)
		setActionButtonState(toggleSubtractButton, isDoorWindow, toggleSubtractHeight)
		subtractWarning.Visible = isDoorWindow and data.HasSubtractModel == false

		updateStoreButton(data.StoreMode)

		if data.Size then
			sizeX.Text = tostring(PluginUtils.SnapToInteger(data.Size.X))
			sizeY.Text = tostring(PluginUtils.SnapToInteger(data.Size.Y))
			sizeZ.Text = tostring(PluginUtils.SnapToInteger(data.Size.Z))
		else
			sizeX.Text = ""
			sizeY.Text = ""
			sizeZ.Text = ""
		end
	end

	function ui:UpdateCatalog(entries: {string})
		selectedCatalog = {}
		for _, child in ipairs(catalogList:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		for _, path in ipairs(entries) do
			local row = Instance.new("Frame")
			row.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
			row.BorderSizePixel = 0
			row.Size = UDim2.new(1, -6, 0, 26)
			row.Parent = catalogList

			local checkbox = Instance.new("TextButton")
			checkbox.BackgroundColor3 = Color3.fromRGB(44, 44, 52)
			checkbox.BorderSizePixel = 0
			checkbox.Size = UDim2.new(0, 22, 0, 22)
			checkbox.Position = UDim2.new(0, 4, 0.5, -11)
			checkbox.Font = Enum.Font.GothamBold
			checkbox.Text = ""
			checkbox.TextSize = 12
			checkbox.TextColor3 = Color3.fromRGB(235, 235, 235)
			checkbox.Parent = row

			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.Gotham
			label.Text = path
			label.TextColor3 = Color3.fromRGB(225, 225, 225)
			label.TextSize = 12
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.Size = UDim2.new(1, -34, 1, 0)
			label.Position = UDim2.new(0, 32, 0, 0)
			label.Parent = row

			local function updateRow()
				local isSelected = selectedCatalog[path] == true
				checkbox.Text = isSelected and "X" or ""
				row.BackgroundColor3 = isSelected and Color3.fromRGB(36, 36, 44) or Color3.fromRGB(28, 28, 34)
			end

			checkbox.MouseButton1Click:Connect(function()
				selectedCatalog[path] = not selectedCatalog[path]
				updateRow()
			end)

			updateRow()
		end
	end

	function ui:GetCurrentData(): PrefabEditData
		return buildInputData()
	end

	return ui
end

return PrefabUIFactory
