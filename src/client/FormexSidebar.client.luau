local Players = game:GetService("Players")
local FormexClient = require(script.Parent:WaitForChild("FormexClient"))
local Formex = FormexClient.Formex
local FormexUI = require(script.Parent:WaitForChild("FormexUI"))
local FormexPrompts = require(script.Parent:WaitForChild("FormexPrompts"))
local FormexDesign = require(script.Parent:WaitForChild("FormexDesign"))

local screenGui: ScreenGui = FormexUI.ScreenGui

local EXPANDED_WIDTH = 360
local COLLAPSED_WIDTH = 72
local HEADER_HEIGHT = 46
local SIDE_MARGIN = 18
local TOP_MARGIN = 18
local BOTTOM_OFFSET = 64

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
}

local sidebarCollapsed = false
local designExpanded = true
local wallFrontMaterialId = Formex.DefaultWallMaterial
local wallBackMaterialId = Formex.DefaultWallMaterial
local cachedOwnerUserId = -1

local ui = {}

local function canDesign(plot: FormexClient.PlotInfo): boolean
    return plot.IsValid and plot.SaveId ~= 0
        and (plot.MyPermission == Formex.Permission.Owner or plot.MyPermission == Formex.Permission.Manager)
end

local function canManage(plot: FormexClient.PlotInfo): boolean
    return plot.IsValid and plot.SaveId ~= 0
        and (plot.MyPermission == Formex.Permission.Owner)
end


local function createSection(parent: Instance, name: string, titleText: string?): (Frame, Frame)
    local card = Instance.new("Frame", parent)
    card.Name = name
    card.BackgroundColor3 = COLORS.Section
    card.BackgroundTransparency = 0
    card.BorderSizePixel = 0
    card.Size = UDim2.new(1, 0, 0, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y

    local cardCorner = Instance.new("UICorner", card)
    cardCorner.CornerRadius = UDim.new(0, 12)

    local cardStroke = Instance.new("UIStroke", card)
    cardStroke.Color = COLORS.SectionBorder
    cardStroke.Thickness = 1.6

    local cardPadding = Instance.new("UIPadding", card)
    cardPadding.PaddingTop = UDim.new(0, 12)
    cardPadding.PaddingBottom = UDim.new(0, 12)
    cardPadding.PaddingLeft = UDim.new(0, 12)
    cardPadding.PaddingRight = UDim.new(0, 12)

    local cardLayout = Instance.new("UIListLayout", card)
    cardLayout.FillDirection = Enum.FillDirection.Vertical
    cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
    cardLayout.Padding = UDim.new(0, 8)

    if titleText then
        local title = Instance.new("TextLabel", card)
        title.Name = "Title"
        title.BackgroundTransparency = 1
        title.Size = UDim2.new(1, 0, 0, 18)
        title.Font = Enum.Font.GothamBold
        title.Text = titleText
        title.TextSize = 16
        title.TextColor3 = COLORS.Text
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.LayoutOrder = 1
    end

    local content = Instance.new("Frame", card)
    content.Name = "Content"
    content.BackgroundTransparency = 1
    content.Size = UDim2.new(1, 0, 0, 0)
    content.AutomaticSize = Enum.AutomaticSize.Y
    content.LayoutOrder = 2

    local contentLayout = Instance.new("UIListLayout", content)
    contentLayout.FillDirection = Enum.FillDirection.Vertical
    contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
    contentLayout.Padding = UDim.new(0, 8)

    return card, content
end

local function createIconButton(parent: Instance, name: string, iconId: number, action: (() -> nil)?)
    local button = Instance.new("ImageButton", parent)
    button.Name = name
    button.AutoButtonColor = false
    button.BackgroundColor3 = COLORS.Section
    button.BackgroundTransparency = 0
    button.BorderSizePixel = 0
    button.Size = UDim2.new(0, 38, 0, 38)

    local corner = Instance.new("UICorner", button)
    corner.CornerRadius = UDim.new(0, 10)

    local stroke = Instance.new("UIStroke", button)
    stroke.Color = COLORS.SectionBorder
    stroke.Thickness = 1.4

    local icon = Instance.new("ImageLabel", button)
    icon.Name = "Icon"
    icon.BackgroundTransparency = 1
    icon.AnchorPoint = Vector2.new(0.5, 0.5)
    icon.Position = UDim2.new(0.5, 0, 0.5, 0)
    icon.Size = UDim2.new(0.6, 0, 0.6, 0)
    icon.ImageContent = Content.fromAssetId(iconId)
    icon.ImageColor3 = COLORS.Icon
    icon.ScaleType = Enum.ScaleType.Fit

    if action then
        button.Activated:Connect(action)
    end

    return {
        Button = button,
        Icon = icon,
        Stroke = stroke,
    }
end

local function setIconButtonActive(buttonInfo, active: boolean)
    if active then
        buttonInfo.Button.BackgroundColor3 = COLORS.AccentSoft
        buttonInfo.Stroke.Color = COLORS.AccentBorder
        buttonInfo.Icon.ImageColor3 = COLORS.Accent
    else
        buttonInfo.Button.BackgroundColor3 = COLORS.Section
        buttonInfo.Stroke.Color = COLORS.SectionBorder
        buttonInfo.Icon.ImageColor3 = COLORS.Icon
    end
end

local function setIconButtonEnabled(buttonInfo, enabled: boolean)
    buttonInfo.Button.Active = enabled
    buttonInfo.Button.AutoButtonColor = enabled
    buttonInfo.Button.BackgroundTransparency = enabled and 0 or 0.4
    buttonInfo.Icon.ImageTransparency = enabled and 0 or 0.5
end

local function snapToGrid(value: number): number
    local grid = Formex.LayoutGridSize
    return math.round(value / grid) * grid
end

local function getWallEndpoints(plotPart: BasePart, wallPart: BasePart): (Vector2int16, Vector2int16)
    local midLocal = plotPart.CFrame:PointToObjectSpace(wallPart.Position)
    local dirLocal = plotPart.CFrame:VectorToObjectSpace(wallPart.CFrame.LookVector)
    dirLocal = Vector3.new(dirLocal.X, 0, dirLocal.Z)
    if dirLocal.Magnitude <= 1e-4 then
        dirLocal = Vector3.new(0, 0, 1)
    else
        dirLocal = dirLocal.Unit
    end

    local halfLength = wallPart.Size.Z / 2
    local startLocal = midLocal - dirLocal * halfLength
    local endLocal = midLocal + dirLocal * halfLength

    local startPoint = Vector2int16.new(snapToGrid(startLocal.X), snapToGrid(startLocal.Z))
    local endPoint = Vector2int16.new(snapToGrid(endLocal.X), snapToGrid(endLocal.Z))
    return startPoint, endPoint
end

local function getMaterialIdFromTexture(texture: Texture?): number?
    if not texture or not texture.ColorMap then
        return nil
    end
    local assetId = tonumber(string.match(texture.ColorMap, "rbxassetid://(%d+)"))
    if not assetId then
        return nil
    end

    for index, materialInfo in Formex.Materials do
        if assetId == materialInfo.AssetId then
            return index
        end
    end

    return nil
end

local function getWallMaterialIds(wallPart: BasePart): (number, number, number, number)
    local frontMaterial = getMaterialIdFromTexture(wallPart:FindFirstChild("Front") :: Texture?) or Formex.DefaultWallMaterial
    local backMaterial = getMaterialIdFromTexture(wallPart:FindFirstChild("Back") :: Texture?) or frontMaterial
    local startMaterial = getMaterialIdFromTexture(wallPart:FindFirstChild("Start") :: Texture?) or frontMaterial
    local endMaterial = getMaterialIdFromTexture(wallPart:FindFirstChild("End") :: Texture?) or frontMaterial
    return frontMaterial, backMaterial, startMaterial, endMaterial
end

local function getWallPart(plot: FormexClient.PlotInfo, wallId: number, level: number): BasePart?
    if not plot.PlotPart then
        return nil
    end
    local levelPart = plot.PlotPart:FindFirstChild(tostring(level))
    if not levelPart then
        return nil
    end
    local wallsFolder = levelPart:FindFirstChild("Walls")
    if not wallsFolder then
        return nil
    end
    local wallPart = wallsFolder:FindFirstChild(tostring(wallId))
    if wallPart and wallPart:IsA("BasePart") then
        return wallPart
    end
    return nil
end

local function applySelectedWallMaterials(frontMaterial: number?, backMaterial: number?)
    local selectionType, wallId, level = FormexDesign.GetSelectionInfo()
    if selectionType ~= FormexDesign.SelectionType.Wall or not wallId or not level then
        return
    end

    local plot = FormexClient.CurrentPlot
    if not plot or not plot.IsValid or not plot.PlotPart then
        return
    end

    local wallPart = getWallPart(plot, wallId, level)
    if not wallPart then
        return
    end

    local startPoint, endPoint = getWallEndpoints(plot.PlotPart, wallPart)
    local existingFront, existingBack, existingStart, existingEnd = getWallMaterialIds(wallPart)
    local newFront = frontMaterial or existingFront
    local newBack = backMaterial or existingBack

    local clientData = {
        WallId = wallId,
        Level = level,
        Start = startPoint,
        End = endPoint,
        FrontMaterial = newFront,
        BackMaterial = newBack,
        StartMaterial = existingStart,
        EndMaterial = existingEnd,
        Part = wallPart,
    }
    Formex.EditWall(clientData, plot.PlotPart)

    local serverData = {
        WallId = wallId,
        Level = level,
        Start = startPoint,
        End = endPoint,
        FrontMaterial = newFront,
        BackMaterial = newBack,
        StartMaterial = existingStart,
        EndMaterial = existingEnd,
        Part = nil,
    }
    FormexClient.BuildWall(serverData, Formex.BuildAction.Edit)
end

local function setCollapsed(collapsed: boolean)
    sidebarCollapsed = collapsed
    if not ui.Container then
        return
    end
    ui.Container.Size = UDim2.new(0, collapsed and COLLAPSED_WIDTH or EXPANDED_WIDTH, 1, -BOTTOM_OFFSET)
    ui.Content.Visible = not collapsed
    ui.PlotInfo.Visible = not collapsed
    ui.HeaderTitle.Visible = not collapsed
    ui.HeaderLayout.HorizontalAlignment = collapsed and Enum.HorizontalAlignment.Center or Enum.HorizontalAlignment.Left
end

local function setDesignExpanded(expanded: boolean)
    designExpanded = expanded
    if ui.DesignControls then
        ui.DesignControls.Visible = expanded
    end
    if ui.DesignExpandIcon then
        local iconId = expanded and Formex.Icons.ChevronUp or Formex.Icons.ChevronDown
        ui.DesignExpandIcon.ImageContent = Content.fromAssetId(iconId)
    end
end

local function updateOwnerAvatar(userId: number)
    if not ui.OwnerAvatar then
        return
    end
    if userId <= 0 then
        cachedOwnerUserId = userId
        ui.OwnerAvatar.ImageContent = Content.fromAssetId(0)
        return
    end
    if cachedOwnerUserId == userId then
        return
    end
    cachedOwnerUserId = userId
    local image = Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size60x60)
    ui.OwnerAvatar.Image = image
end

local function buildSidebar()
    local sidebar = Instance.new("Frame", screenGui)
    sidebar.Name = "FormexSidebar"
    sidebar.BackgroundColor3 = COLORS.Panel
    sidebar.BackgroundTransparency = 0
    sidebar.BorderSizePixel = 0
    sidebar.Position = UDim2.new(0, SIDE_MARGIN, 0, TOP_MARGIN)
    sidebar.Size = UDim2.new(0, EXPANDED_WIDTH, 1, -BOTTOM_OFFSET)
    sidebar.ClipsDescendants = true

    local sidebarCorner = Instance.new("UICorner", sidebar)
    sidebarCorner.CornerRadius = UDim.new(0, 18)

    local sidebarStroke = Instance.new("UIStroke", sidebar)
    sidebarStroke.Color = COLORS.Border
    sidebarStroke.Thickness = 2

    local sidebarGradient = Instance.new("UIGradient", sidebar)
    sidebarGradient.Color = ColorSequence.new(COLORS.PanelTop, COLORS.PanelBottom)
    sidebarGradient.Rotation = 90

    local sidebarPadding = Instance.new("UIPadding", sidebar)
    sidebarPadding.PaddingTop = UDim.new(0, 14)
    sidebarPadding.PaddingBottom = UDim.new(0, 14)
    sidebarPadding.PaddingLeft = UDim.new(0, 14)
    sidebarPadding.PaddingRight = UDim.new(0, 14)

    local sidebarLayout = Instance.new("UIListLayout", sidebar)
    sidebarLayout.FillDirection = Enum.FillDirection.Vertical
    sidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
    sidebarLayout.Padding = UDim.new(0, 12)

    local header = Instance.new("Frame", sidebar)
    header.Name = "Header"
    header.BackgroundTransparency = 1
    header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
    header.LayoutOrder = 1

    local headerLayout = Instance.new("UIListLayout", header)
    headerLayout.FillDirection = Enum.FillDirection.Horizontal
    headerLayout.SortOrder = Enum.SortOrder.LayoutOrder
    headerLayout.Padding = UDim.new(0, 8)
    headerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    headerLayout.VerticalAlignment = Enum.VerticalAlignment.Center

    local headerTitle = Instance.new("TextLabel", header)
    headerTitle.Name = "PlotName"
    headerTitle.BackgroundTransparency = 1
    headerTitle.Size = UDim2.new(1, -48, 1, 0)
    headerTitle.Font = Enum.Font.GothamBold
    headerTitle.Text = "Unnamed"
    headerTitle.TextColor3 = COLORS.Text
    headerTitle.TextSize = 18
    headerTitle.TextXAlignment = Enum.TextXAlignment.Left
    headerTitle.TextTruncate = Enum.TextTruncate.AtEnd
    FormexUI.FlexItem(headerTitle, Enum.UIFlexMode.Grow)

    local collapseButton = createIconButton(header, "Collapse", Formex.Icons.Menu, function()
        setCollapsed(not sidebarCollapsed)
    end)
    collapseButton.Button.Size = UDim2.new(0, 34, 0, 34)
    collapseButton.Button.LayoutOrder = 2

    local content = Instance.new("ScrollingFrame", sidebar)
    content.Name = "Content"
    content.BackgroundTransparency = 1
    content.BorderSizePixel = 0
    content.Size = UDim2.new(1, 0, 1, -HEADER_HEIGHT - 12)
    content.AutomaticCanvasSize = Enum.AutomaticSize.Y
    content.CanvasSize = UDim2.new()
    content.ScrollBarImageTransparency = 0.2
    content.ScrollBarThickness = 6
    content.ScrollingDirection = Enum.ScrollingDirection.Y
    content.LayoutOrder = 2

    local contentPadding = Instance.new("UIPadding", content)
    contentPadding.PaddingLeft = UDim.new(0, 2)
    contentPadding.PaddingRight = UDim.new(0, 2)

    local contentLayout = Instance.new("UIListLayout", content)
    contentLayout.FillDirection = Enum.FillDirection.Vertical
    contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
    contentLayout.Padding = UDim.new(0, 12)

    local plotInfo = Instance.new("Frame", content)
    plotInfo.Name = "PlotInfo"
    plotInfo.BackgroundTransparency = 1
    plotInfo.Size = UDim2.new(1, 0, 0, 0)
    plotInfo.AutomaticSize = Enum.AutomaticSize.Y
    plotInfo.LayoutOrder = 1

    local plotInfoPadding = Instance.new("UIPadding", plotInfo)
    plotInfoPadding.PaddingLeft = UDim.new(0, 2)
    plotInfoPadding.PaddingRight = UDim.new(0, 2)

    local plotInfoLayout = Instance.new("UIListLayout", plotInfo)
    plotInfoLayout.FillDirection = Enum.FillDirection.Vertical
    plotInfoLayout.SortOrder = Enum.SortOrder.LayoutOrder
    plotInfoLayout.Padding = UDim.new(0, 6)

    local ownerRow = Instance.new("Frame", plotInfo)
    ownerRow.Name = "OwnerRow"
    ownerRow.BackgroundTransparency = 1
    ownerRow.Size = UDim2.new(1, 0, 0, 38)

    local ownerRowLayout = Instance.new("UIListLayout", ownerRow)
    ownerRowLayout.FillDirection = Enum.FillDirection.Horizontal
    ownerRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
    ownerRowLayout.Padding = UDim.new(0, 10)
    ownerRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    ownerRowLayout.VerticalAlignment = Enum.VerticalAlignment.Center

    local ownerAvatar = Instance.new("ImageLabel", ownerRow)
    ownerAvatar.Name = "OwnerAvatar"
    ownerAvatar.BackgroundTransparency = 1
    ownerAvatar.Size = UDim2.new(0, 36, 0, 36)
    ownerAvatar.ImageContent = Content.fromAssetId(0)
    ownerAvatar.ScaleType = Enum.ScaleType.Fit
    local avatarCorner = Instance.new("UICorner", ownerAvatar)
    avatarCorner.CornerRadius = UDim.new(1, 0)

    local ownerName = Instance.new("TextLabel", ownerRow)
    ownerName.Name = "OwnerName"
    ownerName.BackgroundTransparency = 1
    ownerName.Size = UDim2.new(1, -48, 1, 0)
    ownerName.Font = Enum.Font.Gotham
    ownerName.Text = "Unclaimed"
    ownerName.TextSize = 15
    ownerName.TextColor3 = COLORS.Muted
    ownerName.TextXAlignment = Enum.TextXAlignment.Left
    FormexUI.FlexItem(ownerName, Enum.UIFlexMode.Grow)

    local permissionLabel = Instance.new("TextLabel", plotInfo)
    permissionLabel.Name = "Permission"
    permissionLabel.BackgroundTransparency = 1
    permissionLabel.Size = UDim2.new(1, 0, 0, 18)
    permissionLabel.Font = Enum.Font.Gotham
    permissionLabel.Text = "Permission: Guest"
    permissionLabel.TextSize = 14
    permissionLabel.TextColor3 = COLORS.Muted
    permissionLabel.TextXAlignment = Enum.TextXAlignment.Left

    local ownerActionsRow = Instance.new("Frame", plotInfo)
    ownerActionsRow.Name = "Actions"
    ownerActionsRow.BackgroundTransparency = 1
    ownerActionsRow.Size = UDim2.new(1, 0, 0, 40)

    local ownerActionsLayout = Instance.new("UIListLayout", ownerActionsRow)
    ownerActionsLayout.FillDirection = Enum.FillDirection.Horizontal
    ownerActionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    ownerActionsLayout.Padding = UDim.new(0, 8)
    ownerActionsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    ownerActionsLayout.VerticalAlignment = Enum.VerticalAlignment.Center

    local claimButton = createIconButton(ownerActionsRow, "Claim", Formex.Icons.PlotClaim, function()
        if FormexClient.ClaimPlot() then
            FormexPrompts.PlotLoad()
        end
    end)

    local renameButton = createIconButton(ownerActionsRow, "Rename", Formex.Icons.PlotRename, function()
        FormexPrompts.PlotRename()
    end)

    local expandButton = createIconButton(ownerActionsRow, "Expand", Formex.Icons.PlotExpand, function()
        if not canManage(FormexClient.CurrentPlot) then return end
        
        local mode = FormexDesign.GetDesignMode()
        if mode ~= FormexDesign.DesignMode.Expand then
            FormexDesign.SetDesignMode(FormexDesign.DesignMode.Expand)
        else
            FormexDesign.SetDesignMode(FormexDesign.DesignMode.Play)
        end
    end)

    local permissionsButton = createIconButton(ownerActionsRow, "Permissions", Formex.Icons.PlotPermissions, function()
        FormexPrompts.PlotPermissions()
    end)

    local designButton = createIconButton(ownerActionsRow, "DesignMode", Formex.Icons.DesignStart, function()
        if not canDesign(FormexClient.CurrentPlot) then return end
        local mode = FormexDesign.GetDesignMode()
        if mode == FormexDesign.DesignMode.Play then
            FormexDesign.SetDesignMode(FormexDesign.DesignMode.Design)
        else
            FormexDesign.SetDesignMode(FormexDesign.DesignMode.Play)
        end
    end)
    
    local unclaimButton = createIconButton(ownerActionsRow, "Unclaim", Formex.Icons.PlotRelease, function()
        local response = FormexUI.Alert("Unclaim Plot", "Are you sure you want to unclaim this plot?", FormexUI.ButtonType.Danger, FormexUI.AlertType.YesNo)
        if response ~= true then return end
        FormexClient.ReleasePlot()
    end)

    local designSection, designContent = createSection(content, "DesignControls", nil)
    designSection.LayoutOrder = 2

    local designHeader = Instance.new("Frame", designContent)
    designHeader.Name = "DesignHeader"
    designHeader.BackgroundTransparency = 1
    designHeader.Size = UDim2.new(1, 0, 0, 32)

    local designHeaderLayout = Instance.new("UIListLayout", designHeader)
    designHeaderLayout.FillDirection = Enum.FillDirection.Horizontal
    designHeaderLayout.SortOrder = Enum.SortOrder.LayoutOrder
    designHeaderLayout.Padding = UDim.new(0, 8)
    designHeaderLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    designHeaderLayout.VerticalAlignment = Enum.VerticalAlignment.Center

    local designHeaderLabel = Instance.new("TextLabel", designHeader)
    designHeaderLabel.Name = "Label"
    designHeaderLabel.BackgroundTransparency = 1
    designHeaderLabel.Size = UDim2.new(1, -40, 1, 0)
    designHeaderLabel.Font = Enum.Font.GothamBold
    designHeaderLabel.Text = "Design Tools"
    designHeaderLabel.TextSize = 16
    designHeaderLabel.TextColor3 = COLORS.Text
    designHeaderLabel.TextXAlignment = Enum.TextXAlignment.Left
    FormexUI.FlexItem(designHeaderLabel, Enum.UIFlexMode.Grow)

    local designExpandButton = createIconButton(designHeader, "ExpandDesign", Formex.Icons.ChevronUp, function()
        setDesignExpanded(not designExpanded)
    end)
    designExpandButton.Button.Size = UDim2.new(0, 28, 0, 28)
    designExpandButton.Button.LayoutOrder = 2

    local designControls = Instance.new("Frame", designContent)
    designControls.Name = "Controls"
    designControls.BackgroundTransparency = 1
    designControls.Size = UDim2.new(1, 0, 0, 0)
    designControls.AutomaticSize = Enum.AutomaticSize.Y

    local designControlsLayout = Instance.new("UIListLayout", designControls)
    designControlsLayout.FillDirection = Enum.FillDirection.Vertical
    designControlsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    designControlsLayout.Padding = UDim.new(0, 10)

    local modeRow = Instance.new("Frame", designControls)
    modeRow.Name = "ModeRow"
    modeRow.BackgroundTransparency = 1
    modeRow.Size = UDim2.new(1, 0, 0, 40)

    local modeRowLayout = Instance.new("UIListLayout", modeRow)
    modeRowLayout.FillDirection = Enum.FillDirection.Horizontal
    modeRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
    modeRowLayout.Padding = UDim.new(0, 8)
    modeRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    modeRowLayout.VerticalAlignment = Enum.VerticalAlignment.Center

    local designModeButtons = {
        Wall = createIconButton(modeRow, "Wall", Formex.Icons.DesignWalls, function()
            FormexDesign.SetDesignMode(FormexDesign.DesignMode.Wall)
        end),
        Floor = createIconButton(modeRow, "Floor", Formex.Icons.DesignFloors, function()
            FormexDesign.SetDesignMode(FormexDesign.DesignMode.Floor)
        end),
        Ceiling = createIconButton(modeRow, "Ceiling", Formex.Icons.DesignCeilings, function()
            FormexDesign.SetDesignMode(FormexDesign.DesignMode.Ceiling)
        end),
        Object = createIconButton(modeRow, "Object", Formex.Icons.DesignFurniture, function()
            FormexDesign.SetDesignMode(FormexDesign.DesignMode.Object)
        end),
        Paint = createIconButton(modeRow, "Paint", Formex.Icons.DesignPaint, function()
            FormexDesign.SetDesignMode(FormexDesign.DesignMode.Paint)
        end),
    }

    local undoRow = Instance.new("Frame", designControls)
    undoRow.Name = "UndoRedo"
    undoRow.BackgroundTransparency = 1
    undoRow.Size = UDim2.new(1, 0, 0, 40)

    local undoRowLayout = Instance.new("UIListLayout", undoRow)
    undoRowLayout.FillDirection = Enum.FillDirection.Horizontal
    undoRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
    undoRowLayout.Padding = UDim.new(0, 8)
    undoRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    undoRowLayout.VerticalAlignment = Enum.VerticalAlignment.Center

    local undoButton = createIconButton(undoRow, "Undo", Formex.Icons.Undo, function()
        FormexDesign.Undo()
    end)

    local redoButton = createIconButton(undoRow, "Redo", Formex.Icons.Redo, function()
        FormexDesign.Redo()
    end)

    local designContentCard = Instance.new("Frame", designControls)
    designContentCard.Name = "DesignContent"
    designContentCard.BackgroundColor3 = COLORS.Section
    designContentCard.BackgroundTransparency = 0
    designContentCard.BorderSizePixel = 0
    designContentCard.Size = UDim2.new(1, 0, 0, 0)
    designContentCard.AutomaticSize = Enum.AutomaticSize.Y

    local contentCorner = Instance.new("UICorner", designContentCard)
    contentCorner.CornerRadius = UDim.new(0, 12)

    local contentStroke = Instance.new("UIStroke", designContentCard)
    contentStroke.Color = COLORS.SectionBorder
    contentStroke.Thickness = 1.4

    local contentPadding = Instance.new("UIPadding", designContentCard)
    contentPadding.PaddingTop = UDim.new(0, 12)
    contentPadding.PaddingBottom = UDim.new(0, 12)
    contentPadding.PaddingLeft = UDim.new(0, 12)
    contentPadding.PaddingRight = UDim.new(0, 12)

    local contentLayout = Instance.new("UIListLayout", designContentCard)
    contentLayout.FillDirection = Enum.FillDirection.Vertical
    contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
    contentLayout.Padding = UDim.new(0, 8)

    local contentTitle = Instance.new("TextLabel", designContentCard)
    contentTitle.Name = "ContentTitle"
    contentTitle.BackgroundTransparency = 1
    contentTitle.Size = UDim2.new(1, 0, 0, 18)
    contentTitle.Font = Enum.Font.GothamSemibold
    contentTitle.Text = "Design Tools"
    contentTitle.TextSize = 16
    contentTitle.TextColor3 = COLORS.Text
    contentTitle.TextXAlignment = Enum.TextXAlignment.Left

    local contentHint = Instance.new("TextLabel", designContentCard)
    contentHint.Name = "Hint"
    contentHint.BackgroundTransparency = 1
    contentHint.Size = UDim2.new(1, 0, 0, 0)
    contentHint.AutomaticSize = Enum.AutomaticSize.Y
    contentHint.Font = Enum.Font.Gotham
    contentHint.Text = ""
    contentHint.TextSize = 14
    contentHint.TextColor3 = COLORS.Muted
    contentHint.TextWrapped = true
    contentHint.TextXAlignment = Enum.TextXAlignment.Left

    local wallContent = Instance.new("Frame", designContentCard)
    wallContent.Name = "WallContent"
    wallContent.BackgroundTransparency = 1
    wallContent.Size = UDim2.new(1, 0, 0, 0)
    wallContent.AutomaticSize = Enum.AutomaticSize.Y

    local wallLayout = Instance.new("UIListLayout", wallContent)
    wallLayout.FillDirection = Enum.FillDirection.Vertical
    wallLayout.SortOrder = Enum.SortOrder.LayoutOrder
    wallLayout.Padding = UDim.new(0, 8)

    local wallHint = Instance.new("TextLabel", wallContent)
    wallHint.Name = "WallHint"
    wallHint.BackgroundTransparency = 1
    wallHint.Size = UDim2.new(1, 0, 0, 0)
    wallHint.AutomaticSize = Enum.AutomaticSize.Y
    wallHint.Font = Enum.Font.Gotham
    wallHint.Text = "Select a wall to apply materials."
    wallHint.TextSize = 14
    wallHint.TextColor3 = COLORS.Muted
    wallHint.TextWrapped = true
    wallHint.TextXAlignment = Enum.TextXAlignment.Left

    local wallFrontSelect = FormexUI.MaterialSelect({
        Parent = wallContent,
        Label = "Front material",
        PartType = Formex.PartType.Wall,
        SelectedMaterial = wallFrontMaterialId,
    }, function(materialId)
        wallFrontMaterialId = materialId or wallFrontMaterialId
        applySelectedWallMaterials(wallFrontMaterialId, nil)
    end)

    local wallBackSelect = FormexUI.MaterialSelect({
        Parent = wallContent,
        Label = "Back material",
        PartType = Formex.PartType.Wall,
        SelectedMaterial = wallBackMaterialId,
    }, function(materialId)
        wallBackMaterialId = materialId or wallBackMaterialId
        applySelectedWallMaterials(nil, wallBackMaterialId)
    end)

    local floorContent = Instance.new("Frame", designContentCard)
    floorContent.Name = "FloorContent"
    floorContent.BackgroundTransparency = 1
    floorContent.Size = UDim2.new(1, 0, 0, 0)
    floorContent.AutomaticSize = Enum.AutomaticSize.Y

    local floorLayout = Instance.new("UIListLayout", floorContent)
    floorLayout.FillDirection = Enum.FillDirection.Vertical
    floorLayout.SortOrder = Enum.SortOrder.LayoutOrder
    floorLayout.Padding = UDim.new(0, 8)

    local floorSelect = FormexUI.MaterialSelect({
        Parent = floorContent,
        Label = "Floor material",
        PartType = Formex.PartType.Floor,
        SelectedMaterial = FormexDesign.GetFloorMaterial(),
    }, function(materialId)
        FormexDesign.SetFloorMaterial(materialId or Formex.DefaultFloorMaterial)
    end)

    local ceilingContent = Instance.new("Frame", designContentCard)
    ceilingContent.Name = "CeilingContent"
    ceilingContent.BackgroundTransparency = 1
    ceilingContent.Size = UDim2.new(1, 0, 0, 0)
    ceilingContent.AutomaticSize = Enum.AutomaticSize.Y

    local ceilingLayout = Instance.new("UIListLayout", ceilingContent)
    ceilingLayout.FillDirection = Enum.FillDirection.Vertical
    ceilingLayout.SortOrder = Enum.SortOrder.LayoutOrder
    ceilingLayout.Padding = UDim.new(0, 8)

    local ceilingSelect = FormexUI.MaterialSelect({
        Parent = ceilingContent,
        Label = "Ceiling material",
        PartType = Formex.PartType.Ceiling,
        SelectedMaterial = FormexDesign.GetFloorMaterial(),
    }, function(materialId)
        FormexDesign.SetFloorMaterial(materialId or Formex.DefaultCeilingMaterial)
    end)

    local objectContent = Instance.new("Frame", designContentCard)
    objectContent.Name = "ObjectContent"
    objectContent.BackgroundTransparency = 1
    objectContent.Size = UDim2.new(1, 0, 0, 0)
    objectContent.AutomaticSize = Enum.AutomaticSize.Y

    local objectLayout = Instance.new("UIListLayout", objectContent)
    objectLayout.FillDirection = Enum.FillDirection.Vertical
    objectLayout.SortOrder = Enum.SortOrder.LayoutOrder
    objectLayout.Padding = UDim.new(0, 6)

    local objectHint = Instance.new("TextLabel", objectContent)
    objectHint.Name = "ObjectHint"
    objectHint.BackgroundTransparency = 1
    objectHint.Size = UDim2.new(1, 0, 0, 0)
    objectHint.AutomaticSize = Enum.AutomaticSize.Y
    objectHint.Font = Enum.Font.Gotham
    objectHint.Text = "Objects: TBD"
    objectHint.TextSize = 14
    objectHint.TextColor3 = COLORS.Muted
    objectHint.TextWrapped = true
    objectHint.TextXAlignment = Enum.TextXAlignment.Left

    local paintContent = Instance.new("Frame", designContentCard)
    paintContent.Name = "PaintContent"
    paintContent.BackgroundTransparency = 1
    paintContent.Size = UDim2.new(1, 0, 0, 0)
    paintContent.AutomaticSize = Enum.AutomaticSize.Y

    local paintLayout = Instance.new("UIListLayout", paintContent)
    paintLayout.FillDirection = Enum.FillDirection.Vertical
    paintLayout.SortOrder = Enum.SortOrder.LayoutOrder
    paintLayout.Padding = UDim.new(0, 6)

    local paintHint = Instance.new("TextLabel", paintContent)
    paintHint.Name = "PaintHint"
    paintHint.BackgroundTransparency = 1
    paintHint.Size = UDim2.new(1, 0, 0, 0)
    paintHint.AutomaticSize = Enum.AutomaticSize.Y
    paintHint.Font = Enum.Font.Gotham
    paintHint.Text = "Paint controls coming soon."
    paintHint.TextSize = 14
    paintHint.TextColor3 = COLORS.Muted
    paintHint.TextWrapped = true
    paintHint.TextXAlignment = Enum.TextXAlignment.Left

    ui.Container = sidebar
    ui.HeaderLayout = headerLayout
    ui.HeaderTitle = headerTitle
    ui.Content = content
    ui.PlotName = headerTitle
    ui.PlotInfo = plotInfo
    ui.OwnerRow = ownerRow
    ui.OwnerAvatar = ownerAvatar
    ui.OwnerName = ownerName
    ui.PermissionLabel = permissionLabel
    ui.OwnerActionsRow = ownerActionsRow
    ui.ActionButtons = {
        Claim = claimButton,
        Rename = renameButton,
        Expand = expandButton,
        Permissions = permissionsButton,
        Design = designButton,
        Unclaim = unclaimButton
    }
    ui.DesignSection = designSection
    ui.DesignControls = designControls
    ui.DesignExpandIcon = designExpandButton.Icon
    ui.DesignModeButtons = designModeButtons
    ui.UndoButton = undoButton
    ui.RedoButton = redoButton
    ui.DesignContentTitle = contentTitle
    ui.DesignContentHint = contentHint
    ui.WallContent = wallContent
    ui.WallHint = wallHint
    ui.WallFrontSelect = wallFrontSelect
    ui.WallBackSelect = wallBackSelect
    ui.FloorContent = floorContent
    ui.FloorSelect = floorSelect
    ui.CeilingContent = ceilingContent
    ui.CeilingSelect = ceilingSelect
    ui.ObjectContent = objectContent
    ui.PaintContent = paintContent

    setCollapsed(sidebarCollapsed)
    setDesignExpanded(designExpanded)
end

local function refreshUI()
    local plot = FormexClient.CurrentPlot :: FormexClient.PlotInfo
    if not plot.IsValid then
        ui.Container.Visible = false
        return
    end

    ui.Container.Visible = true
    ui.PlotName.Text = plot.Name ~= "" and plot.Name or "Unnamed"
    ui.OwnerName.Text = plot.IsClaimed and plot.OwnerName or "Unclaimed"
    ui.PermissionLabel.Text = "Permission: " .. tostring(plot.MyPermission or "Guest")
    updateOwnerAvatar(plot.OwnerUserId)

    local isOwner = plot.IsClaimed and plot.MyPermission == Formex.Permission.Owner
    local isLoaded = plot.SaveId ~= 0

    local allowDesign = canDesign(plot)
    local designMode = FormexDesign.GetDesignMode()
    local inExpand = designMode == FormexDesign.DesignMode.Expand
    local inDesign = designMode ~= FormexDesign.DesignMode.Play and not inExpand

    if inDesign and not allowDesign then
        FormexDesign.SetDesignMode(FormexDesign.DesignMode.Play)
        designMode = FormexDesign.DesignMode.Play
        inDesign = false
    end

    local canClaim = plot.IsValid and not plot.IsClaimed
    local showExpand = allowDesign and isOwner
    local showDesign = allowDesign
    local showManage = isOwner and isLoaded
    local showActions = canClaim or showManage or showDesign

    ui.OwnerRow.Visible = plot.IsClaimed
    ui.PermissionLabel.Visible = plot.IsClaimed

    ui.OwnerActionsRow.Visible = showActions
    ui.ActionButtons.Claim.Button.Visible = canClaim
    ui.ActionButtons.Rename.Button.Visible = showManage
    ui.ActionButtons.Permissions.Button.Visible = showManage
    ui.ActionButtons.Expand.Button.Visible = showExpand
    ui.ActionButtons.Design.Button.Visible = showDesign
    ui.ActionButtons.Unclaim.Button.Visible = plot.IsValid and plot.IsClaimed and isOwner
    ui.DesignSection.Visible = inDesign
    setIconButtonActive(ui.ActionButtons.Design, inDesign)
    setIconButtonActive(ui.ActionButtons.Expand, inExpand)

    if inDesign then
        setDesignExpanded(designExpanded)
    end

    setIconButtonActive(ui.DesignModeButtons.Wall, designMode == FormexDesign.DesignMode.Wall)
    setIconButtonActive(ui.DesignModeButtons.Floor, designMode == FormexDesign.DesignMode.Floor)
    setIconButtonActive(ui.DesignModeButtons.Ceiling, designMode == FormexDesign.DesignMode.Ceiling)
    setIconButtonActive(ui.DesignModeButtons.Object, designMode == FormexDesign.DesignMode.Object)
    setIconButtonActive(ui.DesignModeButtons.Paint, designMode == FormexDesign.DesignMode.Paint)

    local canUndo = plot.CanUndo == true
    local canRedo = plot.CanRedo == true
    setIconButtonEnabled(ui.UndoButton, canUndo)
    setIconButtonEnabled(ui.RedoButton, canRedo)

    local selectionType, wallId, level = FormexDesign.GetSelectionInfo()
    local hasWallSelection = selectionType == FormexDesign.SelectionType.Wall and wallId ~= nil and level ~= nil
    if hasWallSelection then
        local wallPart = getWallPart(plot, wallId :: number, level :: number)
        if wallPart then
            local frontMaterial, backMaterial = getWallMaterialIds(wallPart)
            wallFrontMaterialId = frontMaterial
            wallBackMaterialId = backMaterial
        end
    end

    ui.WallFrontSelect.SetSelected(wallFrontMaterialId)
    ui.WallBackSelect.SetSelected(wallBackMaterialId)
    ui.WallHint.Visible = not hasWallSelection

    local currentFloorMaterial = FormexDesign.GetFloorMaterial()
    ui.FloorSelect.SetSelected(currentFloorMaterial)
    ui.CeilingSelect.SetSelected(currentFloorMaterial)

    ui.WallContent.Visible = false
    ui.FloorContent.Visible = false
    ui.CeilingContent.Visible = false
    ui.ObjectContent.Visible = false
    ui.PaintContent.Visible = false
    ui.DesignContentHint.Visible = false

    if designMode == FormexDesign.DesignMode.Wall then
        ui.DesignContentTitle.Text = "Wall Materials"
        ui.WallContent.Visible = true
    elseif designMode == FormexDesign.DesignMode.Floor then
        ui.DesignContentTitle.Text = "Floor Materials"
        ui.FloorContent.Visible = true
    elseif designMode == FormexDesign.DesignMode.Ceiling then
        ui.DesignContentTitle.Text = "Ceiling Materials"
        ui.CeilingContent.Visible = true
    elseif designMode == FormexDesign.DesignMode.Object then
        ui.DesignContentTitle.Text = "Objects"
        ui.ObjectContent.Visible = true
    elseif designMode == FormexDesign.DesignMode.Paint then
        ui.DesignContentTitle.Text = "Paint"
        ui.PaintContent.Visible = true
    elseif designMode == FormexDesign.DesignMode.Expand then
        ui.DesignContentTitle.Text = "Plot Expansion"
        ui.DesignContentHint.Text = "Select a segment to unlock."
        ui.DesignContentHint.Visible = true
    else
        ui.DesignContentTitle.Text = "Design Tools"
        ui.DesignContentHint.Text = "Choose a design mode to start editing."
        ui.DesignContentHint.Visible = true
    end
end

buildSidebar()
refreshUI()

FormexClient.ClientEvents:Connect(function(eventName)
    if eventName ~= "MyPlotChanged" and eventName ~= "CurrentPlotChanged" and eventName ~= "DesignModeChanged" then
        return
    end

    local plot = FormexClient.CurrentPlot :: FormexClient.PlotInfo
    if not plot.IsValid then
        ui.Container.Visible = false
        return
    end

    refreshUI()
end)
