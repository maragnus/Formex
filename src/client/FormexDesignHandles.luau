--!strict
local FormexClient = require(script.Parent:WaitForChild("FormexClient"))
local Formex = FormexClient.Formex
local Workspace = game:GetService("Workspace")
local formexWorkspace = Workspace:WaitForChild("Formex")
local overlayFolder = Formex.Util.EnsureFolder("FormexDesignOverlays", formexWorkspace)

local HANDLE_SIZE = 3
local HANDLE_ICON_SIZE = 48
local HANDLE_HOVER_SCALE = 1.2
local HANDLE_HOVER_TINT = 0.35

local Handles = {}

type HandleInfo = {
    Part: BasePart,
    Billboard: BillboardGui,
    Icon: ImageLabel,
    Background: ImageLabel,
    Color: Color3,
    IconAsset: string,
    OnClick: (any) -> nil,
    Argument: any,
}

local handles = {} :: {[string]: HandleInfo}
local hoveredHandle: HandleInfo? = nil

local handleIconBackground = Content.fromAssetId(Formex.Icons.CircleBackground)

local function checkHit(ray: Ray): HandleInfo?
    local instances = {}

    for _, handle in pairs(handles) do
        table.insert(instances, handle.Part)
    end

	local params = RaycastParams.new()
	params.IgnoreWater = true
	params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = instances
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 2048, params)
    if not result or not handles[result.Instance.Name] then return nil end

    return handles[result.Instance.Name]
end

function Handles.CreateHandle(name: string, color: Color3, iconAsset: number | string, onClick: (any) -> nil, argument: any): BasePart
    if type(iconAsset) == "number" then
        iconAsset = Content.fromAssetId(iconAsset)
    else
        iconAsset = Content.fromUri(iconAsset)
    end

    local part = handles[name] and handles[name].Part
    local icon: ImageLabel
    
    if not part or not part.Parent then
        part = Instance.new("Part", overlayFolder)
        part.Name = name
        part.Shape = Enum.PartType.Ball
        part.Size = Vector3.new(HANDLE_SIZE, HANDLE_SIZE, HANDLE_SIZE)
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = true
        part.CastShadow = false
        part.Material = Enum.Material.ForceField
        part.CollisionGroup = Formex.CollisionGroup.Grid
        part.Color = color

        local billboard = Instance.new("BillboardGui", part)
        billboard.Name = "HandleBillboard"
        billboard.Size = UDim2.new(0, HANDLE_ICON_SIZE, 0, HANDLE_ICON_SIZE)
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 0.6, 0)
        billboard.LightInfluence = 0
        billboard.AlwaysOnTop = true
        billboard.Adornee = part

        icon = Instance.new("ImageLabel", billboard)
        icon.Name = "Icon"
        icon.AnchorPoint = Vector2.new(0.5, 0.5)
        icon.Position = UDim2.fromScale(0.5, 0.5)
        icon.Size = UDim2.fromScale(0.75, 0.75)
        icon.BackgroundTransparency = 1
        icon.ImageContent = iconAsset
        icon.ZIndex = 2
        icon.ImageColor3 = color

        local background = Instance.new("ImageLabel", billboard)
        background.Name = "Background"
        background.Size = UDim2.fromScale(1, 1)
        background.BackgroundTransparency = 1
        background.ImageContent = handleIconBackground
        background.ImageColor3 = Color3.fromRGB(0, 0, 0) -- color
        background.ImageTransparency = 0.5
        background.ZIndex = 1

        handles[name] = {
            Part = part,
            Color = color,
            IconAsset = iconAsset,
            Billboard = billboard,
            Icon = icon,
            Background = background,
        }
    end

    handles[name].OnClick = onClick
    handles[name].Argument = argument

	return part
end

local function setHandleBillboardVisible(handle: BasePart, visible: boolean)
	local billboard = handle:FindFirstChild("HandleBillboard")
	if billboard and billboard:IsA("BillboardGui") then
		billboard.Enabled = visible
	end
end

function Handles.SetHandleVisible(handle: string | BasePart?, visible: boolean)
    if type(handle) == "string" then
        handle = handles[handle] and handles[handle].Part or nil
    end

	if handle then
		handle.Transparency = visible and 0 or 1
		handle.CanQuery = visible
		setHandleBillboardVisible(handle, visible)
	end
end

function Handles.Clear()
    for _, handle in pairs(handles) do
        handle.Part:Destroy()
    end 
end

local function setHandleHover(handle: HandleInfo?, hovered: boolean)
	if not handle then return end

	local baseColor = handle.Color
	local targetColor = hovered and baseColor:Lerp(Color3.new(1, 1, 1), HANDLE_HOVER_TINT) or baseColor
	local scale = hovered and HANDLE_HOVER_SCALE or 1

	handle.Size = Vector3.new(HANDLE_SIZE * scale, HANDLE_SIZE * scale, HANDLE_SIZE * scale)
	handle.Color = targetColor
    handle.Billboard.Size = UDim2.new(0, HANDLE_ICON_SIZE * scale, 0, HANDLE_ICON_SIZE * scale)
    handle.Icon.ImageColor3 = targetColor
    handle.Background.ImageTransparency = hovered and 0.2 or 0.5
end

function Handles.ClearHandleHover()
    if hoveredHandle then
        setHandleHover(hoveredHandle, false)
        hoveredHandle = nil
    end
end

function Handles.CheckHover(ray: Ray)
    local handle = checkHit(ray)

    if hoveredHandle == handle then	return end

	if hoveredHandle then
		setHandleHover(hoveredHandle, false)
	end

    hoveredHandle = handle

	if hoveredHandle then
		setHandleHover(hoveredHandle, true)
	end
end

function Handles.HandleClicked(ray: Ray): boolean
    local handle = checkHit(ray)

    if handle then
        print("Handle clicked:", handle.Part.Name)
        handle.OnClick(handle.Argument)
        return true
    end

    return false
end

return Handles