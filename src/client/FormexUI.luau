--!strict
local DEBUG = false

local BlurController = require(script.Parent:WaitForChild("BlurController"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local localPlayer = Players.LocalPlayer
local Formex = require(ReplicatedStorage:WaitForChild("Formex"):WaitForChild("Formex"))
local screenGui: ScreenGui = Instance.new("ScreenGui", localPlayer:WaitForChild("PlayerGui"))
screenGui.Name = "FormexUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local FormexUI = {}
FormexUI.ScreenGui = screenGui
FormexUI.BlurController = BlurController

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
FormexUI.ButtonType = table.freeze({
    Primary = "Primary",
    Secondary = "Secondary",
    Success = "Success",
    Info = "Info",
    Warn = "Warn",
    Danger = "Danger",
}) :: {[ButtonType]: ButtonType}

function FormexUI.GetButtonPalette(buttonType: ButtonType)
    return buttonPalette[buttonType] or buttonPalette.Primary
end

export type ButtonStyle = "Solid" | "Outline"
FormexUI.ButtonStyle = table.freeze({
    Solid = "Solid",
    Outline = "Outline"
}) :: {[ButtonStyle]: ButtonStyle}

export type ButtonOptions = {
    Parent: Instance,
    Text: string?,
    Icon: number?,
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
        iconImage.ImageContent = Content.fromAssetId(options.Icon or 0)
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

export type SliderOptions = {
    Parent: Instance,
    Label: string?,
    Min: number,
    Max: number,
    Step: number?,
    Value: number?,
    AllowEmpty: boolean?,
    PlaceholderText: string?,
} | CommonOptions

export type SliderHandle = {
    Frame: Frame,
    Input: TextBox,
    SetValue: (value: number?) -> nil,
    GetValue: () -> number?,
    SetRange: (min: number, max: number) -> nil,
}

function FormexUI.CreateSlider(options: SliderOptions, onChanged: ((value: number?) -> nil)?): SliderHandle
    local name = options.Name or options.Label or "Slider"
    local min = options.Min or 0
    local max = options.Max or 1
    if max < min then
        min, max = max, min
    end
    local step = options.Step
    if step ~= nil and step <= 0 then
        step = nil
    end
    local allowEmpty = options.AllowEmpty == true
    local placeholderText = options.PlaceholderText or ""
    local currentValue: number? = options.Value
    if currentValue == nil and not allowEmpty then
        currentValue = min
    end

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

    local row = Instance.new("Frame", container)
    row.Name = name .. "Row"
    row.BackgroundTransparency = 1
    row.Size = UDim2.new(1, 0, 0, 28)

    local rowLayout = Instance.new("UIListLayout", row)
    rowLayout.FillDirection = Enum.FillDirection.Horizontal
    rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
    rowLayout.Padding = UDim.new(0, 10)
    rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center

    local trackContainer = Instance.new("Frame", row)
    trackContainer.Name = "TrackContainer"
    trackContainer.BackgroundTransparency = 1
    trackContainer.Size = UDim2.new(1, -72, 1, 0)

    local track = Instance.new("ImageButton", trackContainer)
    track.Name = "Track"
    track.AutoButtonColor = false
    track.BackgroundColor3 = Color3.fromRGB(220, 226, 242)
    track.BackgroundTransparency = 0
    track.BorderSizePixel = 0
    track.Size = UDim2.new(1, 0, 0, 12)
    track.Position = UDim2.new(0, 0, 0.5, -6)

    local trackCorner = Instance.new("UICorner", track)
    trackCorner.CornerRadius = UDim.new(0, 6)

    local fill = Instance.new("Frame", track)
    fill.Name = "Fill"
    fill.BackgroundColor3 = Color3.fromRGB(88, 118, 255)
    fill.BackgroundTransparency = 0
    fill.BorderSizePixel = 0
    fill.Size = UDim2.new(0, 0, 1, 0)

    local fillCorner = Instance.new("UICorner", fill)
    fillCorner.CornerRadius = UDim.new(0, 6)

    local handle = Instance.new("Frame", track)
    handle.Name = "Handle"
    handle.Size = UDim2.new(0, 16, 0, 16)
    handle.AnchorPoint = Vector2.new(0.5, 0.5)
    handle.Position = UDim2.new(0, 0, 0.5, 0)
    handle.BackgroundColor3 = Color3.fromRGB(250, 252, 255)
    handle.BackgroundTransparency = 0
    handle.BorderSizePixel = 0
    handle.ZIndex = 2

    local handleCorner = Instance.new("UICorner", handle)
    handleCorner.CornerRadius = UDim.new(1, 0)

    local handleStroke = Instance.new("UIStroke", handle)
    handleStroke.Color = Color3.fromRGB(160, 170, 205)
    handleStroke.Thickness = 1.4

    local input = Instance.new("TextBox", row)
    input.Name = name
    input.Text = ""
    input.Size = UDim2.new(0, 60, 0, 28)
    input.BackgroundColor3 = container.BackgroundColor3
    input.BackgroundTransparency = 0
    input.BorderSizePixel = 0
    input.TextColor3 = Color3.fromRGB(40, 45, 70)
    input.PlaceholderText = placeholderText
    input.ClearTextOnFocus = false
    input.Font = Enum.Font.Gotham
    input.TextSize = 16
    input.TextXAlignment = Enum.TextXAlignment.Center
    input.TextYAlignment = Enum.TextYAlignment.Center

    local defaultStrokeColor = containerStroke.Color
    local focusStrokeColor = Color3.fromRGB(120, 170, 255)
    local isFocused = false
    local internalUpdate = false

    local function setFocusState(focused: boolean)
        containerStroke.Color = focused and focusStrokeColor or defaultStrokeColor
        containerStroke.Thickness = focused and 3 or 1.8
        labelText.TextColor3 = focused and Color3.fromRGB(60, 80, 140) or Color3.fromRGB(90, 100, 130)
    end

    local function coerceValue(value: number?): number?
        if value == nil then
            return nil
        end
        local resolved = value
        if step ~= nil and step > 0 then
            local steps = math.round((resolved - min) / step)
            resolved = min + steps * step
        end
        return math.clamp(resolved, min, max)
    end

    local function formatValue(value: number?): string
        if value == nil then
            return ""
        end
        if step ~= nil and step >= 1 then
            return tostring(math.round(value))
        end
        return tostring(value)
    end

    local function updateVisual()
        local range = max - min
        local alpha = 0
        if currentValue ~= nil and range > 0 then
            alpha = (currentValue - min) / range
        end
        alpha = math.clamp(alpha, 0, 1)
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        handle.Position = UDim2.new(alpha, 0, 0.5, 0)
        local hasValue = currentValue ~= nil
        fill.Visible = hasValue
        handle.Visible = hasValue
    end

    local function setValueInternal(value: number?, emit: boolean?)
        if value == nil then
            if allowEmpty then
                currentValue = nil
            else
                currentValue = min
            end
        else
            currentValue = coerceValue(value)
        end
        updateVisual()
        if not isFocused then
            internalUpdate = true
            input.Text = formatValue(currentValue)
            internalUpdate = false
        end
        if emit and onChanged then
            onChanged(currentValue)
        end
    end

    local function setRange(newMin: number, newMax: number)
        min = newMin
        max = newMax
        if max < min then
            min, max = max, min
        end
        if currentValue ~= nil then
            currentValue = coerceValue(currentValue)
        elseif not allowEmpty then
            currentValue = min
        end
        updateVisual()
        if not isFocused then
            internalUpdate = true
            input.Text = formatValue(currentValue)
            internalUpdate = false
        end
    end

    local function parseInput(text: string): (number?, boolean)
        local trimmed = string.gsub(text or "", "%s", "")
        if trimmed == "" then
            return nil, true
        end
        local value = tonumber(trimmed)
        if not value then
            return nil, false
        end
        return value, true
    end

    local function applyInput(emit: boolean?)
        local value, valid = parseInput(input.Text)
        if not valid then
            if not isFocused then
                internalUpdate = true
                input.Text = formatValue(currentValue)
                internalUpdate = false
            end
            return
        end
        if value == nil and not allowEmpty then
            setValueInternal(currentValue or min, false)
            return
        end
        setValueInternal(value, emit)
    end

    local function updateFromScreenX(x: number)
        local width = track.AbsoluteSize.X
        if width <= 0 then
            return
        end
        local alpha = (x - track.AbsolutePosition.X) / width
        alpha = math.clamp(alpha, 0, 1)
        local value = min + (max - min) * alpha
        setValueInternal(value, true)
    end

    local dragging = false

    track.InputBegan:Connect(function(inputObj)
        if inputObj.UserInputType == Enum.UserInputType.MouseButton1 or inputObj.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            updateFromScreenX(inputObj.Position.X)
        end
    end)

    track.InputEnded:Connect(function(inputObj)
        if inputObj.UserInputType == Enum.UserInputType.MouseButton1 or inputObj.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    UserInputService.InputChanged:Connect(function(inputObj)
        if not dragging then
            return
        end
        if inputObj.UserInputType == Enum.UserInputType.MouseMovement or inputObj.UserInputType == Enum.UserInputType.Touch then
            updateFromScreenX(inputObj.Position.X)
        end
    end)

    UserInputService.InputEnded:Connect(function(inputObj)
        if inputObj.UserInputType == Enum.UserInputType.MouseButton1 or inputObj.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

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
        isFocused = true
        setFocusState(true)
    end)

    input.FocusLost:Connect(function()
        isFocused = false
        setFocusState(false)
        applyInput(true)
    end)

    input:GetPropertyChangedSignal("Text"):Connect(function()
        if internalUpdate then
            return
        end
        if not isFocused then
            return
        end
        applyInput(true)
    end)

    track:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateVisual)

    setFocusState(false)
    setValueInternal(currentValue, false)

    return {
        Frame = container,
        Input = input,
        SetValue = function(value: number?)
            setValueInternal(value, false)
        end,
        GetValue = function()
            return currentValue
        end,
        SetRange = setRange,
    }
end


type ColorOption = { Name: string, Color: Color3 }

local defaultColorPalette: {ColorOption} = {
    { Name = "White", Color = Color3.fromRGB(255, 255, 255) },
    { Name = "Light Gray", Color = Color3.fromRGB(222, 226, 235) },
    { Name = "Gray", Color = Color3.fromRGB(150, 160, 175) },
    { Name = "Charcoal", Color = Color3.fromRGB(75, 80, 95) },
    { Name = "Black", Color = Color3.fromRGB(20, 24, 32) },
    { Name = "Red", Color = Color3.fromRGB(220, 70, 70) },
    { Name = "Orange", Color = Color3.fromRGB(235, 150, 90) },
    { Name = "Gold", Color = Color3.fromRGB(235, 190, 100) },
    { Name = "Yellow", Color = Color3.fromRGB(245, 215, 120) },
    { Name = "Lime", Color = Color3.fromRGB(160, 210, 110) },
    { Name = "Green", Color = Color3.fromRGB(90, 170, 120) },
    { Name = "Teal", Color = Color3.fromRGB(80, 170, 175) },
    { Name = "Cyan", Color = Color3.fromRGB(110, 190, 220) },
    { Name = "Blue", Color = Color3.fromRGB(90, 140, 235) },
    { Name = "Purple", Color = Color3.fromRGB(140, 110, 205) },
    { Name = "Magenta", Color = Color3.fromRGB(200, 110, 190) },
}

local function formatColorHex(color: Color3?): string
    if not color then
        return "None"
    end
    local r = math.clamp(math.round(color.R * 255), 0, 255)
    local g = math.clamp(math.round(color.G * 255), 0, 255)
    local b = math.clamp(math.round(color.B * 255), 0, 255)
    return string.format("#%02X%02X%02X", r, g, b)
end

export type ColorSelectOptions = {
    Parent: Instance,
    Label: string?,
    Colors: {ColorOption}?,
    SelectedColor: Color3?,
    AllowNone: boolean?,
} | CommonOptions

export type ColorSelectHandle = {
    Frame: ImageButton,
    SetSelected: (color: Color3?) -> nil,
    GetSelected: () -> Color3?,
}

function FormexUI.ColorSelect(options: ColorSelectOptions, onChanged: ((color: Color3?) -> nil)?): ColorSelectHandle
    options.Label = options.Label or "Color"
    local palette = options.Colors or defaultColorPalette
    local allowNone = options.AllowNone ~= false
    local selectedColor: Color3? = options.SelectedColor
    local showLabel = options.Label ~= nil and options.Label ~= ""
    local noChrome = (showLabel == false)
    local name = options.Name or options.Label or "ColorSelect"

    local container = Instance.new("ImageButton", options.Parent)
    container.Name = name
    container.AutoButtonColor = false
    container.BackgroundColor3 = Color3.fromRGB(246, 248, 255)
    container.BackgroundTransparency = 0
    container.BorderSizePixel = 0
    container.Size = options.Size or UDim2.new(1, 0, 0, 64)
    container.Visible = options.Visible ~= nil and options.Visible or true
    if options.Position ~= nil then container.Position = options.Position end
    if options.LayoutOrder ~= nil then container.LayoutOrder = options.LayoutOrder end
    if options.Selectable ~= nil then container.Selectable = options.Selectable end
    if options.AutomaticSize ~= nil then container.AutomaticSize = options.AutomaticSize end

    local corner = Instance.new("UICorner", container)
    corner.CornerRadius = UDim.new(0, 10)

    local stroke = Instance.new("UIStroke", container)
    stroke.Color = Color3.fromRGB(205, 210, 230)
    stroke.Thickness = 1.8

    local padding = Instance.new("UIPadding", container)
    padding.PaddingTop = UDim.new(0, noChrome and 0 or 8)
    padding.PaddingBottom = UDim.new(0, noChrome and 0 or 8)
    padding.PaddingLeft = UDim.new(0, noChrome and 0 or 12)
    padding.PaddingRight = UDim.new(0, noChrome and 0 or 12)

    local layout = Instance.new("UIListLayout", container)
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 4)

    local labelText: TextLabel? = nil
    if showLabel then
        labelText = Instance.new("TextLabel", container)
        labelText.Name = "Label"
        labelText.BackgroundTransparency = 1
        labelText.Size = UDim2.new(1, 0, 0, 16)
        labelText.Font = Enum.Font.GothamMedium
        labelText.Text = options.Label or "Color"
        labelText.TextColor3 = Color3.fromRGB(90, 100, 130)
        labelText.TextSize = 13
        labelText.TextXAlignment = Enum.TextXAlignment.Left
    end

    local row = Instance.new("Frame", container)
    row.Name = name .. "Row"
    row.BackgroundTransparency = 1
    row.Size = noChrome and UDim2.new(1, 0, 1, 0) or UDim2.new(1, 0, 0, 26)

    local rowLayout = Instance.new("UIListLayout", row)
    rowLayout.FillDirection = Enum.FillDirection.Horizontal
    rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
    rowLayout.Padding = UDim.new(0, 0)
    rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    rowLayout.HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween 

    local preview = Instance.new("Frame", row)
    preview.Name = "Preview"
    preview.BackgroundColor3 = selectedColor or Color3.fromRGB(235, 238, 245)
    preview.BackgroundTransparency = selectedColor and 0 or 0.25
    preview.Size = UDim2.new(1, -20, 1, 0)
    preview.BorderSizePixel = 0

    local previewCorner = Instance.new("UICorner", preview)
    previewCorner.CornerRadius = UDim.new(0, 8)

    local previewStroke = Instance.new("UIStroke", preview)
    previewStroke.Color = Color3.fromRGB(180, 190, 210)
    previewStroke.Thickness = 1.6

    local chevron: ImageLabel? = nil
    chevron = Instance.new("ImageLabel", row)
    chevron.Name = "Chevron"
    chevron.BackgroundTransparency = 1
    chevron.Size = UDim2.new(0, 14, 0, 14)
    chevron.ImageContent = Content.fromAssetId(Formex.Icons.ChevronDown or 0)
    chevron.ImageColor3 = Color3.fromRGB(120, 130, 160)
    chevron.LayoutOrder = 3

    local function applySelected(color: Color3?)
        selectedColor = color
        preview.BackgroundColor3 = color or Color3.fromRGB(235, 238, 245)
        preview.BackgroundTransparency = color and 0 or 0.25
    end

    applySelected(selectedColor)

    local function getTextColor(bg: Color3): Color3
        local luminance = 0.299 * bg.R + 0.587 * bg.G + 0.114 * bg.B
        if luminance > 0.55 then
            return Color3.fromRGB(35, 40, 60)
        end
        return Color3.fromRGB(245, 248, 255)
    end

    local function openDialog()
        local clearResult = "__ClearColor__"
        local chosen = FormexUI.Dialog({
            Name = name .. "Dialog",
            Title = options.Label or "Select Color",
            Size = "Medium",
            Scrolling = Enum.ScrollingDirection.Y,
            Buttons = {
                { Text = "Cancel", Result = nil, Type = FormexUI.ButtonType.Secondary, Style = FormexUI.ButtonStyle.Outline }
            }
        }, function(dialog)
            local gridFrame = Instance.new("Frame", dialog.ContentFrame)
            gridFrame.Name = "ColorGrid"
            gridFrame.BackgroundTransparency = 1
            gridFrame.Size = UDim2.new(1, 0, 0, 0)
            gridFrame.AutomaticSize = Enum.AutomaticSize.Y

            local gridLayout = Instance.new("UIGridLayout", gridFrame)
            gridLayout.CellSize = UDim2.new(0, 120, 0, 80)
            gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
            gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
            gridLayout.FillDirectionMaxCells = 4

            gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                gridFrame.Size = UDim2.new(1, 0, 0, gridLayout.AbsoluteContentSize.Y)
            end)

            if allowNone then
                local noneTile = Instance.new("ImageButton", gridFrame)
                noneTile.Name = "None"
                noneTile.AutoButtonColor = false
                noneTile.BackgroundColor3 = Color3.fromRGB(245, 246, 252)
                noneTile.BorderSizePixel = 0
                noneTile.Size = UDim2.new(0, 120, 0, 80)

                local noneCorner = Instance.new("UICorner", noneTile)
                noneCorner.CornerRadius = UDim.new(0, 10)

                local noneStroke = Instance.new("UIStroke", noneTile)
                noneStroke.Color = Color3.fromRGB(210, 216, 235)
                noneStroke.Thickness = 1.4

                local noneLabel = Instance.new("TextLabel", noneTile)
                noneLabel.Name = "NoneLabel"
                noneLabel.BackgroundTransparency = 1
                noneLabel.Size = UDim2.new(1, -12, 1, 0)
                noneLabel.Position = UDim2.new(0, 6, 0, 0)
                noneLabel.Font = Enum.Font.GothamSemibold
                noneLabel.Text = "No color"
                noneLabel.TextColor3 = Color3.fromRGB(70, 80, 115)
                noneLabel.TextSize = 16
                noneLabel.TextWrapped = true

                noneTile.Activated:Connect(function()
                    dialog.Close(clearResult)
                end)
            end

            for _, entry in ipairs(palette) do
                local tile = Instance.new("ImageButton", gridFrame)
                tile.Name = "Color_" .. entry.Name
                tile.AutoButtonColor = false
                tile.BackgroundColor3 = entry.Color
                tile.BorderSizePixel = 0
                tile.Size = UDim2.new(0, 120, 0, 80)

                local tileCorner = Instance.new("UICorner", tile)
                tileCorner.CornerRadius = UDim.new(0, 10)

                local tileStroke = Instance.new("UIStroke", tile)
                tileStroke.Color = Color3.fromRGB(210, 216, 235)
                tileStroke.Thickness = 1.4

                local nameLabel = Instance.new("TextLabel", tile)
                nameLabel.Name = "Name"
                nameLabel.BackgroundTransparency = 1
                nameLabel.Size = UDim2.new(1, -12, 1, 0)
                nameLabel.Position = UDim2.new(0, 6, 0, 0)
                nameLabel.Font = Enum.Font.GothamSemibold
                nameLabel.Text = entry.Name .. "\n" .. formatColorHex(entry.Color)
                nameLabel.TextSize = 14
                nameLabel.TextColor3 = getTextColor(entry.Color)
                nameLabel.TextWrapped = true

                tile.Activated:Connect(function()
                    dialog.Close(entry.Color)
                end)
            end
        end)

        if chosen == nil then
            return
        end
        if chosen == clearResult then
            applySelected(nil)
            if onChanged then
                onChanged(nil)
            end
            return
        end
        if typeof(chosen) == "Color3" then
            applySelected(chosen :: Color3)
            if onChanged then
                onChanged(selectedColor)
            end
        end
    end

    local function setFocusState(isFocused: boolean)
        stroke.Color = isFocused and Color3.fromRGB(120, 170, 255) or Color3.fromRGB(205, 210, 230)
        stroke.Thickness = isFocused and 3 or 1.8
        if labelText then
            labelText.TextColor3 = isFocused and Color3.fromRGB(60, 80, 140) or Color3.fromRGB(90, 100, 130)
        end
    end

    container.MouseEnter:Connect(function()
        setFocusState(true)
    end)

    container.MouseLeave:Connect(function()
        setFocusState(false)
    end)

    container.Activated:Connect(openDialog)

    return {
        Frame = container,
        SetSelected = function(color: Color3?)
            applySelected(color)
        end,
        GetSelected = function()
            return selectedColor
        end,
    }
end


type MaterialPartType = "Wall" | "Floor" | "Ceiling" | "Object" | nil
type MaterialInfo = {
    Name: string,
    AssetId: number?,
    PreviewAssetId: number?,
}

export type MaterialSelectOptions = {
    Parent: Instance,
    Label: string?,
    PartType: MaterialPartType?,
    SelectedMaterial: number?,
} | CommonOptions

export type MaterialSelectHandle = {
    Frame: ImageButton,
    SetSelected: (materialId: number?) -> nil,
    GetSelected: () -> number?,
}

local function resolveMaterialList(partType: MaterialPartType?): ({[number]: MaterialInfo}, string)
    return Formex.Materials, "PreviewAssetId"
end

function FormexUI.MaterialSelect(options: MaterialSelectOptions, onChanged: ((materialId: number?) -> nil)?): MaterialSelectHandle
    local selectedMaterialId = options.SelectedMaterial or 0
    local materialList, previewKey = resolveMaterialList(options.PartType)
    local name = options.Name or options.Label or "MaterialSelect"

    local container = Instance.new("ImageButton", options.Parent)
    container.Name = name
    container.AutoButtonColor = false
    container.BackgroundColor3 = Color3.fromRGB(246, 248, 255)
    container.BackgroundTransparency = 0
    container.BorderSizePixel = 0
    container.Size = options.Size or UDim2.new(1, 0, 0, 64)
    container.Visible = options.Visible ~= nil and options.Visible or true
    if options.Position ~= nil then container.Position = options.Position end
    if options.LayoutOrder ~= nil then container.LayoutOrder = options.LayoutOrder end
    if options.Selectable ~= nil then container.Selectable = options.Selectable end
    if options.AutomaticSize ~= nil then container.AutomaticSize = options.AutomaticSize end

    local corner = Instance.new("UICorner", container)
    corner.CornerRadius = UDim.new(0, 10)

    local stroke = Instance.new("UIStroke", container)
    stroke.Color = Color3.fromRGB(205, 210, 230)
    stroke.Thickness = 1.8

    local padding = Instance.new("UIPadding", container)
    padding.PaddingTop = UDim.new(0, 8)
    padding.PaddingBottom = UDim.new(0, 8)
    padding.PaddingLeft = UDim.new(0, 12)
    padding.PaddingRight = UDim.new(0, 12)

    local layout = Instance.new("UIListLayout", container)
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 4)

    local labelText = Instance.new("TextLabel", container)
    labelText.Name = "Label"
    labelText.BackgroundTransparency = 1
    labelText.Size = UDim2.new(1, 0, 0, 16)
    labelText.Font = Enum.Font.GothamMedium
    labelText.Text = options.Label or "Material"
    labelText.TextColor3 = Color3.fromRGB(90, 100, 130)
    labelText.TextSize = 13
    labelText.TextXAlignment = Enum.TextXAlignment.Left

    local row = Instance.new("Frame", container)
    row.Name = "Selected"
    row.BackgroundTransparency = 1
    row.Size = UDim2.new(1, 0, 0, 28)

    local rowLayout = Instance.new("UIListLayout", row)
    rowLayout.FillDirection = Enum.FillDirection.Horizontal
    rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
    rowLayout.Padding = UDim.new(0, 8)

    local preview = Instance.new("ImageLabel", row)
    preview.Name = "Preview"
    preview.BackgroundTransparency = 1
    preview.Size = UDim2.new(0, 24, 0, 24)
    preview.ScaleType = Enum.ScaleType.Fit

    local selectedLabel = Instance.new("TextLabel", row)
    selectedLabel.Name = "SelectedLabel"
    selectedLabel.BackgroundTransparency = 1
    selectedLabel.Size = UDim2.new(1, -60, 1, 0)
    selectedLabel.Font = Enum.Font.Gotham
    selectedLabel.Text = "None"
    selectedLabel.TextSize = 16
    selectedLabel.TextColor3 = Color3.fromRGB(40, 45, 70)
    selectedLabel.TextXAlignment = Enum.TextXAlignment.Left
    selectedLabel.TextYAlignment = Enum.TextYAlignment.Center

    local chevron = Instance.new("ImageLabel", row)
    chevron.Name = "Chevron"
    chevron.BackgroundTransparency = 1
    chevron.Size = UDim2.new(0, 14, 0, 14)
    chevron.ImageContent = Content.fromAssetId(Formex.Icons.ChevronDown or 0)
    chevron.ImageColor3 = Color3.fromRGB(120, 130, 160)
    chevron.LayoutOrder = 3

    local function applySelected(materialId: number?)
        selectedMaterialId = materialId or 0
        local materialInfo = materialList[selectedMaterialId]
        if materialInfo then
            selectedLabel.Text = materialInfo.Name
            local previewId = (materialInfo :: any)[previewKey]
            preview.ImageContent = Content.fromAssetId(previewId or 0)
        else
            selectedLabel.Text = "None"
            preview.ImageContent = Content.fromAssetId(0)
        end
    end

    applySelected(selectedMaterialId)

    local function openDialog()
        local chosen = FormexUI.Dialog({
            Name = name .. "Dialog",
            Title = options.Label or "Select Material",
            Size = "Large",
            Scrolling = Enum.ScrollingDirection.Y,
            Buttons = {
                { Text = "Cancel", Result = nil, Type = FormexUI.ButtonType.Secondary, Style = FormexUI.ButtonStyle.Outline }
            }
        }, function(dialog)
            local gridFrame = Instance.new("Frame", dialog.ContentFrame)
            gridFrame.Name = "MaterialGrid"
            gridFrame.BackgroundTransparency = 1
            gridFrame.Size = UDim2.new(1, 0, 0, 0)
            gridFrame.AutomaticSize = Enum.AutomaticSize.Y

            local gridLayout = Instance.new("UIGridLayout", gridFrame)
            gridLayout.CellSize = UDim2.new(0, 120, 0, 120)
            gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
            gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
            gridLayout.FillDirectionMaxCells = 4

            gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                gridFrame.Size = UDim2.new(1, 0, 0, gridLayout.AbsoluteContentSize.Y)
            end)

            for materialId, materialInfo in ipairs(materialList) do
                
                local tile = Instance.new("ImageButton", gridFrame)
                tile.Name = "Material_" .. tostring(materialId)
                tile.AutoButtonColor = false
                tile.BackgroundColor3 = Color3.fromRGB(245, 248, 255)
                tile.BorderSizePixel = 0
                tile.Size = UDim2.new(0, 120, 0, 120)

                local tileCorner = Instance.new("UICorner", tile)
                tileCorner.CornerRadius = UDim.new(0, 12)

                local tileStroke = Instance.new("UIStroke", tile)
                tileStroke.Color = Color3.fromRGB(210, 216, 235)
                tileStroke.Thickness = 1.4

                local tileLayout = Instance.new("UIListLayout", tile)
                tileLayout.FillDirection = Enum.FillDirection.Vertical
                tileLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
                tileLayout.VerticalAlignment = Enum.VerticalAlignment.Center
                tileLayout.SortOrder = Enum.SortOrder.LayoutOrder
                tileLayout.Padding = UDim.new(0, 6)

                local image = Instance.new("ImageLabel", tile)
                image.Name = "Preview"
                image.BackgroundTransparency = 1
                image.Size = UDim2.new(0, 64, 0, 64)
                local previewId = (materialInfo :: any)[previewKey]
                image.ImageContent = Content.fromAssetId(previewId or 0)
                image.ScaleType = Enum.ScaleType.Fit

                local nameLabel = Instance.new("TextLabel", tile)
                nameLabel.Name = "Name"
                nameLabel.BackgroundTransparency = 1
                nameLabel.Size = UDim2.new(1, -8, 0, 24)
                nameLabel.Font = Enum.Font.GothamMedium
                nameLabel.Text = materialInfo.Name
                nameLabel.TextSize = 14
                nameLabel.TextColor3 = Color3.fromRGB(60, 70, 100)
                nameLabel.TextWrapped = true

                tile.Activated:Connect(function()
                    dialog.Close(materialId)
                end)
            end
        end)

        if chosen ~= nil then
            applySelected(chosen)
            if onChanged then
                onChanged(chosen)
            end
        end
    end

    local function setFocusState(isFocused: boolean)
        stroke.Color = isFocused and Color3.fromRGB(120, 170, 255) or Color3.fromRGB(205, 210, 230)
        stroke.Thickness = isFocused and 3 or 1.8
        labelText.TextColor3 = isFocused and Color3.fromRGB(60, 80, 140) or Color3.fromRGB(90, 100, 130)
    end

    container.MouseEnter:Connect(function()
        setFocusState(true)
    end)

    container.MouseLeave:Connect(function()
        setFocusState(false)
    end)

    container.Activated:Connect(openDialog)

    return {
        Frame = container,
        SetSelected = applySelected,
        GetSelected = function()
            return selectedMaterialId
        end
    }
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
FormexUI.AlertType = table.freeze({
    OkOnly = "OkOnly",
    OkCancel = "OkCancel",
    YesNo = "YesNo",
    YesNoCancel = "YesNoCancel",
    RetryCancel = "RetryCancel"
})

local okButton = { Text = "OK", Result = true, Type = FormexUI.ButtonType.Primary } :: ButtonInfo
local yesButton = { Text = "Yes", Result = true, Type = FormexUI.ButtonType.Primary } :: ButtonInfo
local noButton = { Text = "No", Result = false, Type = FormexUI.ButtonType.Error } :: ButtonInfo
local retryButton = { Text = "Retry", Result = true, Type = FormexUI.ButtonType.Primary } :: ButtonInfo
local cancelButton = { Text = "Cancel", Result = nil, Type = FormexUI.ButtonType.Secondary, Style = FormexUI.ButtonStyle.Outline } :: ButtonInfo
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
    local iconId = tonumber(icon) or 0

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
        iconImage.ImageContent = Content.fromAssetId(iconId)
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
