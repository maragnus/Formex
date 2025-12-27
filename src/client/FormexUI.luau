--!strict
local DEBUG = true

local BlurController = require(script.Parent:WaitForChild("BlurController"))
local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer
local screenGui: ScreenGui = Instance.new("ScreenGui", localPlayer:WaitForChild("PlayerGui"))
screenGui.Name = "FormexUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local FormexUI = {}
FormexUI.ScreenGui = screenGui
FormexUI.BlurController = BlurController
local currentContentParent: Instance? = nil

local buttonPalette = {
    Primary = { Base = Color3.fromRGB(88, 118, 255), Text = Color3.fromRGB(248, 249, 255) },
    Secondary = { Base = Color3.fromRGB(215, 220, 232), Text = Color3.fromRGB(16, 20, 24) },
    Success = { Base = Color3.fromRGB(68, 180, 124), Text = Color3.fromRGB(245, 250, 248) },
    Info = { Base = Color3.fromRGB(88, 174, 255), Text = Color3.fromRGB(245, 248, 255) },
    Warn = { Base = Color3.fromRGB(255, 195, 88), Text = Color3.fromRGB(60, 45, 16) },
    Danger = { Base = Color3.fromRGB(236, 96, 116), Text = Color3.fromRGB(255, 245, 245) },
}

local function lighten(color: Color3, amount: number): Color3
    return color:Lerp(Color3.new(1, 1, 1), math.clamp(amount, 0, 1))
end

local function darken(color: Color3, amount: number): Color3
    return color:Lerp(Color3.new(0, 0, 0), math.clamp(amount, 0, 1))
end

local function normalizeAsset(assetId: string): string
    if not assetId or assetId == "" then return "rbxassetid://0" end
    if string.find(assetId, "^rbxassetid://") then
        return assetId
    end
    return "rbxassetid://" .. assetId
end

export type FlexItemOptions = {
    FlexMode: Enum.UIFlexMode,
    GrowRatio: number?,
    StrinkRatio: number?,
    ItemLineAlignment: Enum.ItemLineAlignment?,
}

function FormexUI.FlexItem(item: Instance, flexMode: Enum.UIFlexMode | FlexItemOptions)    
    local flexItem = Instance.new("UIFlexItem", item)
    if type(flexMode) == "table" then
        flexItem.FlexMode = flexMode.FlexMode
        if flexMode.GrowRatio ~= nil then flexItem.GrowRatio = flexMode.GrowRatio end
        if flexMode.ShrinkRatio ~= nil then flexItem.ShrinkRatio = flexMode.StrinkRatio end
        if flexMode.ItemLineAlignment ~= nil then flexItem.ItemLineAlignment = flexMode.ItemLineAlignment end
    elseif flexMode ~= nil then
        flexItem.FlexMode = flexMode
    end
    return flexItem
end 

export type CommonOptions = {
    Name: string?,
    Position: UDim2?,
    Size: UDim2?,
    Padding: number | UDim | nil,
    BackgroundTransparency: number?,
    AutomaticSize: Enum.AutomaticSize?,
    LayoutOrder: number?,
    Selectable: boolean?,
    Visible: boolean?,
    FlexMode: Enum.UIFlexMode?,
    FlexGrowRatio: number?,
    FlexShrinkRatio: number?,
    ItemLineAlignment: Enum.ItemLineAlignment,
}

local function updateGUIObject(instance: GuiObject, options: CommonOptions)
    if options.Name ~= nil then instance.Name = options.Name end
    if options.Position ~= nil then instance.Position = options.Position end
    if options.Size ~= nil then instance.Size = options.Size end
    if options.LayoutOrder ~= nil then instance.LayoutOrder = options.LayoutOrder end
    if options.Selectable ~= nil then instance.Selectable = options.Selectable end
    if options.Visible ~= nil then instance.Visible = options.Visible end
    if options.AutomaticSize ~= nil then instance.AutomaticSize = options.AutomaticSize end
    if options.BackgroundTransparency ~= nil then
        instance.BackgroundTransparency = options.BackgroundTransparency
    else
        instance.BackgroundTransparency = 1
    end
    if options.Padding ~= nil then
        local padding = Instance.new("UIPadding", instance)
        padding.PaddingRight = type(options.Padding) == "number" and UDim.new(0, options.Padding) or options.Padding
    end
    if options.FlexMode then FormexUI.FlexItem(instance, options) end
end

export type LabelOptions = {
    Parent: Instance,
    Text: string?,
    BackgroundTransparency: number?,
    TextXAlignment: Enum.TextXAlignment?,
    TextYAlignment: Enum.TextYAlignment?,
    Font: Enum.Font?,
    TextSize: number?,
    TextColor3: Color3?,
    FlexMode: Enum.UIFlexMode?,
    FlexGrowRatio: number?,
    FlexShrinkRatio: number?,
    ItemLineAlignment: Enum.ItemLineAlignment,
    TextWrapped: boolean?
} | CommonOptions

function FormexUI.CreateLabel(options: LabelOptions)
    local label = Instance.new("TextLabel", options.Parent)
    if options.Name then label.Name = options.Name end
    label.Text = options.Text or ""
    label.TextXAlignment = options.TextXAlignment or Enum.TextXAlignment.Center
    label.TextYAlignment = options.TextYAlignment or Enum.TextYAlignment.Center
    label.Font = options.Font or Enum.Font.Gotham
    label.TextSize = options.TextSize or 14
    label.TextColor3 = options.TextColor3 or Color3.fromRGB(0, 0, 0)
    label.TextWrapped = options.TextWrapped or false
    updateGUIObject(label, options)
end

export type FlexOptions = {
    Parent: Instance,
    SortOrder: Enum.SortOrder?,
    Gap: number?,
    HorizontalAlignment: Enum.HorizontalAlignment?,
    VerticalAlignment: Enum.VerticalAlignment?,
    AutomaticSize: Enum.AutomaticSize?,
    Wraps: boolean?,
} | CommonOptions

function FormexUI.CreateRow(options: FlexOptions)
    local header = Instance.new("Frame", options.Parent)
    updateGUIObject(header, options)

    local headerLayout = Instance.new("UIListLayout", header)
    headerLayout.FillDirection = Enum.FillDirection.Horizontal
    headerLayout.SortOrder = options.SortOrder or Enum.SortOrder.LayoutOrder
    headerLayout.Padding = UDim.new(0, options.Gap or 0)
    headerLayout.HorizontalAlignment = options.HorizontalAlignment or Enum.HorizontalAlignment.Center
    headerLayout.VerticalAlignment = options.VerticalAlignment or Enum.VerticalAlignment.Center
    headerLayout.Wraps = options.Wraps or false

    return header
end

function FormexUI.CreateColumn(options: FlexOptions)
    local header = Instance.new("Frame", options.Parent)
    updateGUIObject(header, options)

    local headerLayout = Instance.new("UIListLayout", header)
    headerLayout.FillDirection = Enum.FillDirection.Vertical
    headerLayout.SortOrder = options.SortOrder or Enum.SortOrder.LayoutOrder
    headerLayout.Padding = UDim.new(0, options.Gap or 0)
    headerLayout.HorizontalAlignment = options.HorizontalAlignment or Enum.HorizontalAlignment.Center
    headerLayout.VerticalAlignment = options.VerticalAlignment or Enum.VerticalAlignment.Center
    headerLayout.Wraps = options.Wraps or false

    return header
end

export type ButtonType = "Primary" | "Secondary" | "Success" | "Info" | "Warn" | "Danger"
FormexUI.ButtonTypes = {
    Primary = "Primary",
    Secondary = "Secondary",
    Success = "Success",
    Info = "Info",
    Warn = "Warn",
    Danger = "Danger",
} :: {[ButtonType]: ButtonType}

function FormexUI.GetButtonPalette(buttonType: ButtonType)
    return buttonPalette[buttonType] or buttonPalette.Primary
end

export type ButtonStyle = "Solid" | "Outline"
FormexUI.ButtonStyles = {
    Solid = "Solid",
    Outline = "Outline"
} :: {[ButtonStyle]: ButtonStyle}

export type ButtonOptions = {
    Parent: Instance,
    Text: string?,
    Icon: string?,
    Type: ButtonType?,
    Style: ButtonStyle?,
    IsPressed: boolean?, -- Appears pressed for toggle button style
} | CommonOptions

function FormexUI.CreateButton(options: ButtonOptions, action: (GuiButton) -> boolean)
    local palette = buttonPalette[options.Type] or buttonPalette.Primary
    local baseColor = palette.Base
    local outlineTextColor = (options.Type == "Secondary" or options.Type == "Warn") and darken(baseColor, 0.35) or baseColor
    local hasLabel = options.Text ~= nil and options.Text ~= ""
    local isIconOnly = options.Icon ~= nil and not hasLabel
    local buttonHeight = 44
    local buttonWidth = isIconOnly and buttonHeight or 132

    options.Size = options.Size or UDim2.new(0, buttonWidth, 0, buttonHeight)
    options.Style = options.Style or "Solid"
    options.Type = options.Type or "Primary"

    local button = Instance.new("ImageButton", options.Parent)
    updateGUIObject(button, options)
    button.AutoButtonColor = false
    button.ClipsDescendants = false
    button.Visible = false
    button.BorderSizePixel = 0
    button.BackgroundTransparency = 0

    local buttonCorner = Instance.new("UICorner", button)
    buttonCorner.CornerRadius = UDim.new(0, 12)

    local stroke = Instance.new("UIStroke", button)
    stroke.Thickness = 2
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

    local gradient = Instance.new("UIGradient", button)
    gradient.Rotation = 90

    local padding = Instance.new("UIPadding", button)
    padding.PaddingLeft = UDim.new(0, isIconOnly and 10 or 14)
    padding.PaddingRight = UDim.new(0, isIconOnly and 10 or 14)

    local contentLayout = Instance.new("UIListLayout", button)
    contentLayout.FillDirection = Enum.FillDirection.Horizontal
    contentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    contentLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
    local contentSpacing = hasLabel and (options.Icon and 8 or 4) or 0
    contentLayout.Padding = UDim.new(0, contentSpacing)

    local iconImage: ImageLabel? = nil
    if options.Icon then
        iconImage = Instance.new("ImageLabel", button)
        iconImage.Name = "Icon"
        iconImage.BackgroundTransparency = 1
        iconImage.Size = UDim2.new(0, 18, 0, 18)
        iconImage.Image = normalizeAsset(options.Icon)
        iconImage.ScaleType = Enum.ScaleType.Fit
    end

    local labelText: TextLabel? = nil
    if hasLabel then
        labelText = Instance.new("TextLabel", button)
        labelText.Name = "Label"
        labelText.BackgroundTransparency = 1
        labelText.Size = UDim2.new(0, 0, 1, 0)
        labelText.AutomaticSize = Enum.AutomaticSize.X
        labelText.Font = Enum.Font.GothamSemibold
        labelText.Text = options.Text or ""
        labelText.TextSize = 16
        labelText.TextColor3 = palette.Text
        labelText.TextXAlignment = Enum.TextXAlignment.Left
        labelText.TextYAlignment = Enum.TextYAlignment.Center
        labelText.ZIndex = 2
    end

    local function applyStyle(isHover: boolean, isActive: boolean)
        local pressed = options.IsPressed or isActive

        if options.Style == "Outline" then
            local tint = baseColor:Lerp(Color3.new(1, 1, 1), pressed and 0.2 or (isHover and 0.14 or 0.1))
            button.BackgroundColor3 = tint
            stroke.Color = darken(baseColor, 0.15)
            gradient.Color = ColorSequence.new(lighten(tint, 0.04), darken(tint, 0.02))
            if labelText then
                labelText.TextColor3 = outlineTextColor
            end
            if iconImage then
                iconImage.ImageColor3 = outlineTextColor
            end
        else
            local top = lighten(baseColor, pressed and 0.02 or (isHover and 0.18 or 0.12))
            local bottom = darken(baseColor, pressed and 0.14 or (isHover and 0.04 or 0.06))
            button.BackgroundColor3 = baseColor
            stroke.Color = darken(baseColor, 0.2)
            gradient.Color = ColorSequence.new(top, bottom)
            if labelText then
                labelText.TextColor3 = palette.Text
            end
            if iconImage then
                iconImage.ImageColor3 = palette.Text
            end
        end
    end

    button.MouseEnter:Connect(function()
        applyStyle(true, false)
    end)

    button.MouseLeave:Connect(function()
        applyStyle(false, false)
    end)

    button.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            applyStyle(false, true)
        end
    end)

    button.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            applyStyle(false, false)
        end
    end)

    applyStyle(false, options.IsPressed or false)

    if action then
        button.Activated:Connect(function(inputObject, clickCount)
            button.Active = false
            button.Interactable = false
            if DEBUG then
                action(button, inputObject, clickCount)
            else
                local success, message = pcall(action, button, inputObject, clickCount)
                if not success then
                    warn("Error on " .. button.Name .. " click: " .. message)
                end
            end
            button.Interactable = true
            button.Active = true
        end)
    end

    return button
end

export type DialogSize = "Small" | "Medium" | "Large"

export type ButtonInfo = {
    Result: any?, -- if nil, returns Dialog.Result
} | ButtonOptions

export type Dialog = {
    Name: string,
    Title: string,
    Size: DialogSize,
    Frame: Frame,
    ContentFrame: Frame,
    ButtonsFrame: Frame,
    Result: any,
    Close: (result: any?) -> nil,
}

local dialogSizes = {
    Small = 360,
    Medium = 480,
    Large = 640
}

export type TextInputOptions = {
    Parent: Instance,
    Label: string?,
    Text: string?,
} | CommonOptions


function FormexUI.CreateTextInput(options: TextInputOptions, onChanged: ((value: string) -> nil)?): TextBox
    local name = options.Name or options.Label or "TextInput"
    local container = Instance.new("Frame", options.Parent)
    container.Name = name .. "Container"
    container.Active = true
    container.Size = UDim2.new(1, 0, 0, 64)
    container.AutomaticSize = Enum.AutomaticSize.None
    container.BackgroundColor3 = Color3.fromRGB(246, 248, 255)
    container.BackgroundTransparency = 0
    container.BorderSizePixel = 0

    local containerCorner = Instance.new("UICorner", container)
    containerCorner.CornerRadius = UDim.new(0, 10)

    local containerStroke = Instance.new("UIStroke", container)
    containerStroke.Color = Color3.fromRGB(205, 210, 230)
    containerStroke.Thickness = 1.8

    local containerPadding = Instance.new("UIPadding", container)
    containerPadding.PaddingTop = UDim.new(0, 8)
    containerPadding.PaddingBottom = UDim.new(0, 8)
    containerPadding.PaddingLeft = UDim.new(0, 12)
    containerPadding.PaddingRight = UDim.new(0, 12)

    local containerLayout = Instance.new("UIListLayout", container)
    containerLayout.FillDirection = Enum.FillDirection.Vertical
    containerLayout.SortOrder = Enum.SortOrder.LayoutOrder
    containerLayout.Padding = UDim.new(0, 4)

    local labelText = Instance.new("TextLabel", container)
    labelText.Name = name .. "Label"
    labelText.BackgroundTransparency = 1
    labelText.Size = UDim2.new(1, 0, 0, 16)
    labelText.Font = Enum.Font.GothamMedium
    labelText.Text = options.Label or ""
    labelText.TextColor3 = Color3.fromRGB(90, 100, 130)
    labelText.TextSize = 13
    labelText.TextXAlignment = Enum.TextXAlignment.Left

    local input = Instance.new("TextBox", container)
    input.Name = name
    input.Text = options.Text ~= nil and tostring(options.Text) or ""
    input.Size = UDim2.new(1, 0, 0, 28)
    input.BackgroundColor3 = container.BackgroundColor3
    input.BackgroundTransparency = 0
    input.BorderSizePixel = 0
    input.TextColor3 = Color3.fromRGB(40, 45, 70)
    input.PlaceholderText = ""
    input.ClearTextOnFocus = false
    input.Font = Enum.Font.Gotham
    input.TextSize = 16
    input.TextXAlignment = Enum.TextXAlignment.Left
    input.TextYAlignment = Enum.TextYAlignment.Center

    local function emitChange()
        if onChanged then
            onChanged(input.Text)
        end
    end

    local defaultStrokeColor = containerStroke.Color
    local focusStrokeColor = Color3.fromRGB(120, 170, 255)

    local function setFocusState(isFocused: boolean)
        containerStroke.Color = isFocused and focusStrokeColor or defaultStrokeColor
        containerStroke.Thickness = isFocused and 3 or 1.8
        labelText.TextColor3 = isFocused and Color3.fromRGB(60, 80, 140) or Color3.fromRGB(90, 100, 130)
    end

    container.InputBegan:Connect(function(inputObj)
        if inputObj.UserInputType == Enum.UserInputType.MouseButton1 or inputObj.UserInputType == Enum.UserInputType.Touch then
            input:CaptureFocus()
        end
    end)

    labelText.InputBegan:Connect(function(inputObj)
        if inputObj.UserInputType == Enum.UserInputType.MouseButton1 or inputObj.UserInputType == Enum.UserInputType.Touch then
            input:CaptureFocus()
        end
    end)

    input.Focused:Connect(function()
        setFocusState(true)
    end)

    input.FocusLost:Connect(function()
        setFocusState(false)
        emitChange()
    end)

    input:GetPropertyChangedSignal("Text"):Connect(emitChange)

    setFocusState(false)

    return input
end

function FormexUI.Corner(parent: GuiObject, radius: number)
    local corner = Instance.new("UICorner", parent)
    corner.CornerRadius = UDim.new(0, radius)
    return corner
end

function FormexUI.Padding(parent: GuiObject, top: number, right: number?, bottom: number?, left: number?)
    local padding = Instance.new("UIPadding", parent)
    padding.PaddingTop = UDim.new(0, top)
    padding.PaddingRight = UDim.new(0, right or top)
    padding.PaddingBottom = UDim.new(0, bottom or top)
    padding.PaddingLeft = UDim.new(0, left or right or top)
    return padding
end

local FOOTER_CONTENT_HEIGHT = 44
local FOOTER_EDGE_BOUNDARY = 64
local FOOTER_BORDER = 16
local FOOTER_CORNER_RADIUS = 32
local FOOTER_TOTAL_HEIGHT = FOOTER_CONTENT_HEIGHT + FOOTER_BORDER * 4

function FormexUI.Footer(parent: ScreenGui)
    local footerFrame = Instance.new("Frame", parent)
    footerFrame.Name = "Footer"
    footerFrame.BackgroundColor3 = Color3.fromRGB(250, 245, 255)
    footerFrame.BackgroundTransparency = 0.5
    footerFrame.Position = UDim2.new(0, FOOTER_EDGE_BOUNDARY, 1, -FOOTER_TOTAL_HEIGHT + FOOTER_CORNER_RADIUS / 4)
    footerFrame.Size = UDim2.new(1, -FOOTER_EDGE_BOUNDARY * 2, 0, FOOTER_TOTAL_HEIGHT + FOOTER_CORNER_RADIUS)

    FormexUI.Padding(footerFrame, FOOTER_BORDER, FOOTER_BORDER, FOOTER_BORDER + FOOTER_CORNER_RADIUS, FOOTER_BORDER)
    FormexUI.Corner(footerFrame, FOOTER_CORNER_RADIUS)
    BlurController.new(footerFrame, "Rectangle")

    local footerContainer = Instance.new("ScrollingFrame", footerFrame)
    footerContainer.Name = "Container"
    footerContainer.BackgroundColor3 = Color3.fromRGB(250, 245, 255)
    footerContainer.BackgroundTransparency = 0
    footerContainer.Size = UDim2.new(1, 0, 1, 0)
    footerContainer.AutomaticCanvasSize = Enum.AutomaticSize.X
    footerContainer.ScrollingDirection = Enum.ScrollingDirection.X
    footerContainer.ScrollingEnabled = true
    FormexUI.Padding(footerContainer, FOOTER_BORDER, FOOTER_BORDER, FOOTER_BORDER, FOOTER_BORDER)
    FormexUI.Corner(footerContainer, FOOTER_CORNER_RADIUS * 0.75)
    
    local dialogStroke = Instance.new("UIStroke", footerContainer)
    dialogStroke.Color = Color3.fromRGB(210, 210, 230)
    dialogStroke.Thickness = 2

    local footerLayout: UIListLayout = Instance.new("UIListLayout", footerContainer)
    footerLayout.FillDirection = Enum.FillDirection.Horizontal
    footerLayout.Padding = UDim.new(0, 16)
    footerLayout.SortOrder = Enum.SortOrder.LayoutOrder

    return footerContainer
end


export type DialogOptions = {
    Name: string,
    Title: string,
    Size: DialogSize?,
    CanClose: boolean?,
    CloseResult: any?,
    Scrolling: Enum.ScrollingDirection?,
    Buttons: {[number]: ButtonInfo}?
}

function FormexUI.Dialog(options: DialogOptions, contents: ((dialog: Dialog) -> nil))
    local result: any = nil
    local closed = false
    local dialog: Dialog = {
        Name = options.Name or "Dialog",
        Title = options.Title or "Dialog",
        Size = options.Size or "Small",
        Buttons = options.Buttons or { {Label = "OK" } },
        CanClose = options.CanClose ~= nil and options.CanClose or true,
        Result = nil
    }
    local size = dialogSizes[options.Size or "Small"] or dialogSizes.Small

    dialog.Close = function(dialogResult)
        if closed then return end
        closed = true
        if dialogResult ~= nil then
            dialog.Result = dialogResult
        end
        result = dialog.Result
    end

    local overlay = Instance.new("Frame", screenGui)
    overlay.Name = dialog.Name .. "Overlay"
    overlay.Active = true
    overlay.BackgroundTransparency = 0.45
    overlay.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
    overlay.BorderSizePixel = 0
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.ZIndex = 20

    local dialogFrame = Instance.new("Frame", overlay)
    dialogFrame.Name = dialog.Name
    dialogFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    dialogFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    dialogFrame.Size = UDim2.new(0, size, 0, 0)
    dialogFrame.AutomaticSize = Enum.AutomaticSize.Y
    dialogFrame.BackgroundColor3 = Color3.fromRGB(252, 252, 255)
    dialogFrame.BackgroundTransparency = 0
    dialogFrame.BorderSizePixel = 0
    dialogFrame.ZIndex = 21

    local dialogCorner = Instance.new("UICorner", dialogFrame)
    dialogCorner.CornerRadius = UDim.new(0, 16)
    local dialogStroke = Instance.new("UIStroke", dialogFrame)
    dialogStroke.Color = Color3.fromRGB(210, 210, 230)
    dialogStroke.Thickness = 2
    local dialogGradient = Instance.new("UIGradient", dialogFrame)
    dialogGradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(240, 242, 255))
    dialogGradient.Rotation = 90
    local dialogPadding = Instance.new("UIPadding", dialogFrame)
    dialogPadding.PaddingTop = UDim.new(0, 16)
    dialogPadding.PaddingBottom = UDim.new(0, 16)
    dialogPadding.PaddingLeft = UDim.new(0, 16)
    dialogPadding.PaddingRight = UDim.new(0, 16)
    local dialogLayout = Instance.new("UIListLayout", dialogFrame)
    dialogLayout.FillDirection = Enum.FillDirection.Vertical
    dialogLayout.SortOrder = Enum.SortOrder.LayoutOrder
    dialogLayout.Padding = UDim.new(0, 12)
    dialogLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

    local header = Instance.new("Frame", dialogFrame)
    header.Name = "Header"
    header.BackgroundTransparency = 1
    header.Size = UDim2.new(1, 0, 0, 32)
    header.LayoutOrder = 1

    local titleText = Instance.new("TextLabel", header)
    titleText.Name = "Title"
    titleText.BackgroundTransparency = 1
    titleText.Size = UDim2.new(1, options.CanClose and -36 or 0, 1, 0)
    titleText.Font = Enum.Font.GothamBold
    titleText.Text = dialog.Title
    titleText.TextColor3 = Color3.fromRGB(50, 55, 80)
    titleText.TextSize = 20
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.ZIndex = dialogFrame.ZIndex + 1

    if options.CanClose then
        local closeButton = Instance.new("TextButton", header)
        closeButton.Name = "Close"
        closeButton.AnchorPoint = Vector2.new(1, 0.5)
        closeButton.Position = UDim2.new(1, 0, 0.5, 0)
        closeButton.Size = UDim2.new(0, 28, 0, 28)
        closeButton.AutoButtonColor = true
        closeButton.BackgroundColor3 = Color3.fromRGB(245, 245, 255)
        closeButton.Text = "X"
        closeButton.Font = Enum.Font.GothamBold
        closeButton.TextSize = 14
        closeButton.TextColor3 = Color3.fromRGB(90, 95, 120)
        closeButton.ZIndex = dialogFrame.ZIndex + 1
        local closeCorner = Instance.new("UICorner", closeButton)
        closeCorner.CornerRadius = UDim.new(0, 8)
        local closeStroke = Instance.new("UIStroke", closeButton)
        closeStroke.Color = Color3.fromRGB(210, 210, 225)
        closeStroke.Thickness = 1
        closeButton.Activated:Connect(function()
            dialog.Close(options.CloseResult)
        end)
    end

    local scrollHeights = {
        Small = 260,
        Medium = 320,
        Large = 380,
    }
    local contentContainer: GuiObject
    if options.Scrolling then
        local scrollingFrame = Instance.new("ScrollingFrame", dialogFrame)
        scrollingFrame.Name = "ContentContainer"
        scrollingFrame.BackgroundTransparency = 1
        scrollingFrame.Size = UDim2.new(1, 0, 0, scrollHeights[dialog.Size] or 320)
        scrollingFrame.AutomaticSize = Enum.AutomaticSize.None
        scrollingFrame.LayoutOrder = 2
        scrollingFrame.ScrollingDirection = options.Scrolling
        scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.XY
        scrollingFrame.CanvasSize = UDim2.new()
        scrollingFrame.ScrollBarImageTransparency = 0.15
        scrollingFrame.ScrollBarThickness = 6
        scrollingFrame.BorderSizePixel = 0
        contentContainer = scrollingFrame
    else
        local frame = Instance.new("Frame", dialogFrame)
        frame.Name = "ContentContainer"
        frame.BackgroundTransparency = 1
        frame.Size = UDim2.new(1, 0, 0, 0)
        frame.AutomaticSize = Enum.AutomaticSize.Y
        frame.LayoutOrder = 2
        contentContainer = frame
    end

    local contentFrame = Instance.new("Frame", contentContainer)
    contentFrame.Name = "Content"
    contentFrame.BackgroundTransparency = 1
    contentFrame.Size = UDim2.new(1, 0, 0, 0)
    contentFrame.AutomaticSize = Enum.AutomaticSize.Y
    contentFrame.LayoutOrder = 1
    local contentLayout = Instance.new("UIListLayout", contentFrame)
    contentLayout.FillDirection = Enum.FillDirection.Vertical
    contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
    contentLayout.Padding = UDim.new(0, 8)

    local buttonsFrame = Instance.new("Frame", dialogFrame)
    buttonsFrame.Name = "Buttons"
    buttonsFrame.BackgroundTransparency = 1
    buttonsFrame.Size = UDim2.new(1, 0, 0, 48)
    buttonsFrame.LayoutOrder = 3
    local buttonsLayout = Instance.new("UIListLayout", buttonsFrame)
    buttonsLayout.FillDirection = Enum.FillDirection.Horizontal
    buttonsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    buttonsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    buttonsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    buttonsLayout.Padding = UDim.new(0, 8)

    dialog.Frame = dialogFrame
    dialog.ContentFrame = contentFrame
    dialog.ButtonsFrame = buttonsFrame

    local blur = BlurController.new(dialogFrame, "Rectangle")
    overlay.Destroying:Connect(function()
        blur:Destroy()
    end)

    if contents then
        if DEBUG then
            contents(dialog)
        else
            local success, err = pcall(contents, dialog)
            if not success then
                warn("[FormexUI.Dialog] Failed to build dialog contents:", err)
                dialog.Close(false)
            end
        end
    end

    for index, buttonInfo in ipairs(options.Buttons or {}) do
        buttonInfo.Parent = buttonsFrame
        local button = FormexUI.CreateButton(buttonInfo, function() dialog.Close(buttonInfo.Result) end)

        button.Visible = true
        button.LayoutOrder = index
        button.ZIndex = dialogFrame.ZIndex + 1
    end

    while not closed and overlay.Parent do
        task.wait(0.05)
    end

    overlay:Destroy()

    return result
end

export type AlertOptions = {
    Name: string?,
    Title: string?,
    Message: string?,
    Type: ButtonType?,
    Size: DialogSize?,
    CanClose: boolean?,
    CloseResult: any?,
    Buttons: {ButtonInfo}?,
    Icon: string?,
    Result: any?,
}

export type AlertType = "OkOnly" | "OkCancel" | "YesNo" | "YesNoCancel" | "RetryCancel"
FormexUI.AlertTypes = {
    OkOnly = "OkOnly",
    OkCancel = "OkCancel",
    YesNo = "YesNo",
    YesNoCancel = "YesNoCancel",
    RetryCancel = "RetryCancel"
}

local okButton = { Text = "OK", Result = true, Type = FormexUI.ButtonTypes.Primary } :: ButtonInfo
local yesButton = { Text = "Yes", Result = true, Type = FormexUI.ButtonTypes.Primary } :: ButtonInfo
local noButton = { Text = "No", Result = false, Type = FormexUI.ButtonTypes.Error } :: ButtonInfo
local retryButton = { Text = "Retry", Result = true, Type = FormexUI.ButtonTypes.Primary } :: ButtonInfo
local cancelButton = { Text = "Cancel", Result = nil, Type = FormexUI.ButtonTypes.Secondary, Style = FormexUI.ButtonStyles.Outline } :: ButtonInfo
FormexUI.ButtonGroups = {
    OkOnly = {okButton},
    OkCancel = {okButton, cancelButton},
    YesNo = {yesButton, noButton},
    YesNoCancel = {yesButton, noButton, cancelButton},
    RetryCancel = {retryButton, cancelButton},
} :: {[AlertType]: {ButtonInfo}}
local alertIcons = {
    Primary = "103853485477063",
    Secondary = "115719232269249",
    Info = "119134101744939",
    Warn = "111518129231234",
    Danger = "73134495809587",
} :: {[ButtonType]: string}

type ButtonPalette = { Base: Color3, Text: Color3 }

function FormexUI.Alert(title: string, message: string, type: ButtonType, alertType: AlertType): any
    local palette = FormexUI.GetButtonPalette(type)
    local buttons = FormexUI.ButtonGroups[alertType]
    local icon = alertIcons[type]

    return FormexUI.Dialog({
        Name = "AlertDialog",
        Title = title or "Alert",
        Size = "Small",
        CanClose = alertType == "OkCancel" or alertType == "YesNoCancel" or alertType == "RetryCancel",
        CloseResult = nil,
        Buttons = buttons,
    }, function(dialog)
        local content = FormexUI.CreateRow({
            Parent = dialog.ContentFrame,
            Name = "AlertContent",
            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.new(1, 0, 0, 0),
            Gap = 12,
            HorizontalAlignment = Enum.HorizontalAlignment.Left,
            VerticalAlignment = Enum.VerticalAlignment.Top,
        })

        local iconImage = Instance.new("ImageLabel", content)
        iconImage.Name = "IconImage"
        iconImage.BackgroundTransparency = 1
        iconImage.Size = UDim2.new(0, 48, 0, 48)
        iconImage.Image = normalizeAsset(icon)
        iconImage.ImageColor3 = palette.Base
        iconImage.ScaleType = Enum.ScaleType.Fit

        FormexUI.CreateLabel({
            Parent = content,
            Name = "Message",
            Text = message,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            TextSize = 16,
            TextColor3 = Color3.fromRGB(55, 60, 85),
            Font = Enum.Font.Gotham,
            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.new(1, -60, 0, 0),
            TextWrapped = true
        })
    end)
end

return FormexUI
