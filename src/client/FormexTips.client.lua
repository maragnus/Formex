--!strict

local FormexClient = require(script.Parent:WaitForChild("FormexClient"))
local Formex = FormexClient.Formex
local FormexUI = require(script.Parent:WaitForChild("FormexUI"))
local FormexDesign = require(script.Parent:WaitForChild("FormexDesign"))

local screenGui: ScreenGui = FormexUI.ScreenGui

local WIDTH = 300
local SIDE_MARGIN = 18
local BOTTOM_MARGIN = 18

local COLORS = {
    Panel = Color3.fromRGB(252, 252, 255),
    PanelTop = Color3.fromRGB(255, 255, 255),
    PanelBottom = Color3.fromRGB(240, 242, 255),
    Border = Color3.fromRGB(210, 210, 230),
    Text = Color3.fromRGB(45, 50, 80),
    Muted = Color3.fromRGB(90, 105, 140),
    Accent = Color3.fromRGB(88, 118, 255),
    AccentSoft = Color3.fromRGB(226, 232, 255),
    AccentBorder = Color3.fromRGB(130, 150, 255),
    Icon = Color3.fromRGB(70, 80, 115),
}

local ui = {}

local function createChip(parent: Instance, name: string)
    local chip = Instance.new("Frame", parent)
    chip.Name = name
    chip.BackgroundColor3 = COLORS.AccentSoft
    chip.BorderSizePixel = 0
    chip.Size = UDim2.new(0, 0, 0, 24)
    chip.AutomaticSize = Enum.AutomaticSize.X

    local chipCorner = Instance.new("UICorner", chip)
    chipCorner.CornerRadius = UDim.new(0, 10)

    local chipStroke = Instance.new("UIStroke", chip)
    chipStroke.Color = COLORS.AccentBorder
    chipStroke.Thickness = 1

    local chipPadding = Instance.new("UIPadding", chip)
    chipPadding.PaddingLeft = UDim.new(0, 8)
    chipPadding.PaddingRight = UDim.new(0, 8)

    local chipLayout = Instance.new("UIListLayout", chip)
    chipLayout.FillDirection = Enum.FillDirection.Horizontal
    chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
    chipLayout.Padding = UDim.new(0, 6)
    chipLayout.VerticalAlignment = Enum.VerticalAlignment.Center

    local chipIcon = Instance.new("ImageLabel", chip)
    chipIcon.Name = "Icon"
    chipIcon.BackgroundTransparency = 1
    chipIcon.Size = UDim2.new(0, 14, 0, 14)
    chipIcon.ImageColor3 = COLORS.Accent
    chipIcon.ScaleType = Enum.ScaleType.Fit

    local chipLabel = Instance.new("TextLabel", chip)
    chipLabel.Name = "Label"
    chipLabel.BackgroundTransparency = 1
    chipLabel.Size = UDim2.new(0, 0, 1, 0)
    chipLabel.AutomaticSize = Enum.AutomaticSize.X
    chipLabel.Font = Enum.Font.GothamSemibold
    chipLabel.Text = ""
    chipLabel.TextSize = 12
    chipLabel.TextColor3 = COLORS.Accent
    chipLabel.TextXAlignment = Enum.TextXAlignment.Left

    return {
        Container = chip,
        Icon = chipIcon,
        Label = chipLabel,
    }
end

local function buildTips()
    local container = Instance.new("Frame", screenGui)
    container.Name = "FormexTips"
    container.BackgroundColor3 = COLORS.Panel
    container.BackgroundTransparency = 0
    container.BorderSizePixel = 0
    container.AnchorPoint = Vector2.new(1, 1)
    container.Position = UDim2.new(1, -SIDE_MARGIN, 1, -BOTTOM_MARGIN)
    container.Size = UDim2.new(0, WIDTH, 0, 0)
    container.AutomaticSize = Enum.AutomaticSize.Y

    local corner = Instance.new("UICorner", container)
    corner.CornerRadius = UDim.new(0, 16)

    local stroke = Instance.new("UIStroke", container)
    stroke.Color = COLORS.Border
    stroke.Thickness = 1.6

    local gradient = Instance.new("UIGradient", container)
    gradient.Color = ColorSequence.new(COLORS.PanelTop, COLORS.PanelBottom)
    gradient.Rotation = 90

    local padding = Instance.new("UIPadding", container)
    padding.PaddingTop = UDim.new(0, 12)
    padding.PaddingBottom = UDim.new(0, 12)
    padding.PaddingLeft = UDim.new(0, 12)
    padding.PaddingRight = UDim.new(0, 12)

    local layout = Instance.new("UIListLayout", container)
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 8)

    local header = Instance.new("Frame", container)
    header.Name = "Header"
    header.BackgroundTransparency = 1
    header.Size = UDim2.new(1, 0, 0, 0)
    header.AutomaticSize = Enum.AutomaticSize.Y

    local headerLayout = Instance.new("UIListLayout", header)
    headerLayout.FillDirection = Enum.FillDirection.Vertical
    headerLayout.SortOrder = Enum.SortOrder.LayoutOrder
    headerLayout.Padding = UDim.new(0, 6)

    local titleRow = Instance.new("Frame", header)
    titleRow.Name = "TitleRow"
    titleRow.BackgroundTransparency = 1
    titleRow.Size = UDim2.new(1, 0, 0, 32)

    local titleLayout = Instance.new("UIListLayout", titleRow)
    titleLayout.FillDirection = Enum.FillDirection.Horizontal
    titleLayout.SortOrder = Enum.SortOrder.LayoutOrder
    titleLayout.Padding = UDim.new(0, 10)
    titleLayout.VerticalAlignment = Enum.VerticalAlignment.Center

    local iconFrame = Instance.new("Frame", titleRow)
    iconFrame.Name = "ModeIconFrame"
    iconFrame.BackgroundColor3 = COLORS.AccentSoft
    iconFrame.BorderSizePixel = 0
    iconFrame.Size = UDim2.new(0, 32, 0, 32)

    local iconCorner = Instance.new("UICorner", iconFrame)
    iconCorner.CornerRadius = UDim.new(0, 10)

    local iconStroke = Instance.new("UIStroke", iconFrame)
    iconStroke.Color = COLORS.AccentBorder
    iconStroke.Thickness = 1

    local modeIcon = Instance.new("ImageLabel", iconFrame)
    modeIcon.Name = "ModeIcon"
    modeIcon.BackgroundTransparency = 1
    modeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
    modeIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
    modeIcon.Size = UDim2.new(0.6, 0, 0.6, 0)
    modeIcon.ImageColor3 = COLORS.Accent
    modeIcon.ScaleType = Enum.ScaleType.Fit

    local title = Instance.new("TextLabel", titleRow)
    title.Name = "ModeTitle"
    title.BackgroundTransparency = 1
    title.Size = UDim2.new(1, -48, 0, 22)
    title.Font = Enum.Font.GothamBold
    title.Text = "Design Mode"
    title.TextSize = 18
    title.TextColor3 = COLORS.Text
    title.TextXAlignment = Enum.TextXAlignment.Left
    FormexUI.FlexItem(title, Enum.UIFlexMode.Grow)

    local chipRow = Instance.new("Frame", header)
    chipRow.Name = "ChipRow"
    chipRow.BackgroundTransparency = 1
    chipRow.Size = UDim2.new(1, 0, 0, 0)
    chipRow.AutomaticSize = Enum.AutomaticSize.Y

    local chipLayout = Instance.new("UIListLayout", chipRow)
    chipLayout.FillDirection = Enum.FillDirection.Horizontal
    chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
    chipLayout.Padding = UDim.new(0, 6)
    chipLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    chipLayout.Wraps = true

    local toolChip = createChip(chipRow, "ToolChip")
    local floorChip = createChip(chipRow, "FloorChip")

    local body = Instance.new("TextLabel", container)
    body.Name = "Body"
    body.BackgroundTransparency = 1
    body.Size = UDim2.new(1, 0, 0, 0)
    body.AutomaticSize = Enum.AutomaticSize.Y
    body.Font = Enum.Font.Gotham
    body.Text = ""
    body.TextSize = 14
    body.TextColor3 = COLORS.Muted
    body.TextWrapped = true
    body.TextXAlignment = Enum.TextXAlignment.Left

    ui.Container = container
    ui.ModeIcon = modeIcon
    ui.ModeTitle = title
    ui.ChipRow = chipRow
    ui.ToolChip = toolChip
    ui.FloorChip = floorChip
    ui.Body = body
end

local function setChip(chip, label: string?, iconId: number?)
    if not label or label == "" then
        chip.Container.Visible = false
        return
    end

    chip.Container.Visible = true
    chip.Label.Text = label
    chip.Icon.ImageContent = Content.fromAssetId(iconId or 0)
end

local function getTipData(designState)
    local mode = designState.Mode
    local subMode = designState.SubMode
    local floorMode = designState.Floor and designState.Floor.Mode or nil
    local actionType = designState.ActionType
    local tipMessage = FormexDesign.GetTipMessage and FormexDesign.GetTipMessage() or nil

    local title = "Design Mode"
    local iconId = Formex.Icons.DesignStart
    local toolLabel: string? = nil
    local toolIcon: number? = nil
    local floorLabel: string? = nil
    local floorIcon: number? = nil
    local lines = {}

    if mode == FormexDesign.DesignMode.Select then
        title = "Select Mode"
        iconId = Formex.Icons.DesignSelect
        lines = {
            "- Select walls, floors, and objects.",
            "- Click a part to select it.",
            "- Click empty space to clear selection.",
        }
    elseif mode == FormexDesign.DesignMode.Wall then
        iconId = Formex.Icons.DesignWalls
        if subMode == FormexDesign.DesignSubMode.Paint then
            title = "Wall Paint Mode"
            toolLabel = "Tool: Paint"
            toolIcon = Formex.Icons.DesignPaint
            lines = {
                "- Selection is off in Paint mode.",
                "- Click a wall side to apply paint.",
                "- Use Dropper to sample wall materials.",
            }
        elseif subMode == FormexDesign.DesignSubMode.Dropper then
            title = "Wall Dropper Mode"
            toolLabel = "Tool: Dropper"
            toolIcon = Formex.Icons.DesignDropper
            lines = {
                "- Selection is off in Dropper mode.",
                "- Click a wall side to copy materials/colors.",
                "- After sampling, you return to Paint unless Alt is held.",
            }
        elseif actionType == FormexDesign.ActionType.Start then
            title = "Wall Start"
            toolLabel = "Tool: Build"
            toolIcon = Formex.Icons.DesignBuild
            lines = {
                "- Click the ground to place the first point.",
                "- Move your mouse to set wall direction.",
                "- Click to set the end point.",
                "- Right-click to cancel back to Select mode.",
            }
        elseif actionType == FormexDesign.ActionType.Step then
            title = "Wall Place"
            toolLabel = "Tool: Build"
            toolIcon = Formex.Icons.DesignBuild
            lines = {
                "- Preview the wall as you move.",
                "- Click to place the end point.",
                "- Release to confirm the wall.",
                "- Right-click to cancel back to Select mode.",
            }
        else
            title = "Wall Mode"
            toolLabel = "Tool: Build"
            toolIcon = Formex.Icons.DesignBuild
            lines = {
                "- Selects walls only in this mode.",
                "- Click the ground to start a new wall.",
                "- Click a wall to select and edit it.",
            }
        end
    elseif mode == FormexDesign.DesignMode.Floor then
        iconId = Formex.Icons.DesignFloors
        if subMode == FormexDesign.DesignSubMode.Paint then
            title = "Floor Paint Mode"
            toolLabel = "Tool: Paint"
            toolIcon = Formex.Icons.DesignPaint
            lines = {
                "- Selection is off in Paint mode.",
                "- Click a floor to apply paint.",
                "- Use Dropper to sample floor settings.",
            }
        elseif subMode == FormexDesign.DesignSubMode.Dropper then
            title = "Floor Dropper Mode"
            toolLabel = "Tool: Dropper"
            toolIcon = Formex.Icons.DesignDropper
            lines = {
                "- Selection is off in Dropper mode.",
                "- Click a floor to copy its settings.",
                "- After sampling, you return to Paint unless Alt is held.",
            }
        elseif floorMode == FormexDesign.FloorMode.Manual then
            toolLabel = "Tool: Build"
            toolIcon = Formex.Icons.DesignBuild
            if actionType == FormexDesign.ActionType.Start then
                title = "Floor Start (Manual)"
                lines = {
                    "- Click to place the first corner point.",
                    "- Continue clicking to add corners.",
                    "- Right-click to undo the last point.",
                    "- Right-click with no points to return to Select mode.",
                }
            elseif actionType == FormexDesign.ActionType.Step then
                title = "Floor Place (Manual)"
                lines = {
                    "- Click to add the next corner point.",
                    "- Click the confirm handle on the first point to finish.",
                    "- Right-click to undo the last point.",
                }
            else
                title = "Floor Mode (Manual)"
                lines = {
                    "- Selects floors only in this mode.",
                    "- Click a floor to select it.",
                    "- Click empty ground to start a new floor.",
                }
            end
        elseif actionType == FormexDesign.ActionType.Start then
            toolLabel = "Tool: Build"
            toolIcon = Formex.Icons.DesignBuild
            if floorMode == FormexDesign.FloorMode.Autofill then
                title = "Floor Start (Autofill)"
                lines = {
                    "- Hover to preview the room outline.",
                    "- Click to place the autofill floor.",
                    "- Autofill traces walls and floors.",
                    "- Right-click to cancel back to Select mode.",
                }
            else
                title = "Floor Start"
                lines = {
                    "- Hover to preview the floor tile.",
                    "- Click a tile to place a new floor.",
                    "- Switch to Manual for custom shapes.",
                    "- Right-click to cancel back to Select mode.",
                }
            end
        else
            title = "Floor Mode"
            toolLabel = "Tool: Build"
            toolIcon = Formex.Icons.DesignBuild
            lines = {
                "- Selects floors only in this mode.",
                "- Click a floor to select it.",
                "- Click empty ground to start a new floor.",
            }
        end

        if floorMode == FormexDesign.FloorMode.Manual then
            floorLabel = "Floor: Manual"
            floorIcon = Formex.Icons.ModeManual
        elseif floorMode == FormexDesign.FloorMode.Autofill then
            floorLabel = "Floor: Autofill"
            floorIcon = Formex.Icons.ModeAutomatic
        end

        if tipMessage and tipMessage ~= "" then
            table.insert(lines, "Autofill: " .. tipMessage)
        end
    elseif mode == FormexDesign.DesignMode.Object then
        iconId = Formex.Icons.DesignFurniture
        if subMode == FormexDesign.DesignSubMode.Paint then
            title = "Object Paint Mode"
            toolLabel = "Tool: Paint"
            toolIcon = Formex.Icons.DesignPaint
        elseif subMode == FormexDesign.DesignSubMode.Dropper then
            title = "Object Dropper Mode"
            toolLabel = "Tool: Dropper"
            toolIcon = Formex.Icons.DesignDropper
        else
            title = "Object Mode"
            toolLabel = "Tool: Select"
            toolIcon = Formex.Icons.DesignSelect
        end
        lines = {
            "- Selects objects only in this mode.",
            "- Click an object to select it.",
            "- Click empty space to clear selection.",
            "- Click empty space again to place the current prefab.",
            "- Use the prefab catalog in the sidebar to swap items.",
        }
    elseif mode == FormexDesign.DesignMode.Expand then
        title = "Expand Plot"
        iconId = Formex.Icons.PlotExpand
        lines = {
            "- Click a plot segment to unlock it.",
            "- Only owners can expand plots.",
        }
    else
        title = "Design Mode"
        iconId = Formex.Icons.DesignStart
        lines = {
            "- Choose a design mode to start editing.",
        }
    end

    return {
        Title = title,
        IconId = iconId,
        ToolLabel = toolLabel,
        ToolIcon = toolIcon,
        FloorLabel = floorLabel,
        FloorIcon = floorIcon,
        Body = table.concat(lines, "\n"),
    }
end

local function refreshTips()
    if not ui.Container then
        return
    end

    local plot = FormexClient.CurrentPlot
    if not plot or not plot.IsValid then
        ui.Container.Visible = false
        return
    end

    local designState = FormexDesign.GetDesignState()
    local mode = designState.Mode
    if mode == FormexDesign.DesignMode.Play then
        ui.Container.Visible = false
        return
    end

    local data = getTipData(designState)
    ui.Container.Visible = true
    ui.ModeTitle.Text = data.Title
    ui.ModeIcon.ImageContent = Content.fromAssetId(data.IconId or 0)
    ui.Body.Text = data.Body

    setChip(ui.ToolChip, data.ToolLabel, data.ToolIcon)
    setChip(ui.FloorChip, data.FloorLabel, data.FloorIcon)

    ui.ChipRow.Visible = ui.ToolChip.Container.Visible or ui.FloorChip.Container.Visible
end

buildTips()
refreshTips()

FormexClient.ClientEvents:Connect(function(eventName)
    if eventName ~= "MyPlotChanged" and eventName ~= "CurrentPlotChanged" and eventName ~= "DesignStateChanged" then
        return
    end

    refreshTips()
end)
