--!strict
--[[
FormexDesignHandles
Creates and manages interactive 3D handles used by design submodules.
Exports:
- Init(): load shared dependencies
- CreateHandle(name, color, iconAsset, onClick, argument): BasePart
- SetHandleVisible(handle, visible): ()
- Clear(): ()
- ClearHandleHover(): ()
- CheckHover(ray): ()
- HandleClicked(ray): boolean
]]
local Context = require(script.Parent:WaitForChild("FormexDesignContext"))
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local HANDLE_PART_SIZE = 0.2
local HANDLE_ICON_SIZE = 48
local HANDLE_HOVER_SCALE = 1.2
local HANDLE_HOVER_TINT = 0.35

local Handles = {}

local Formex: any
local overlayFolder: Folder
local handleIconBackground: any
local playerGui: PlayerGui? = nil
local useGuiInput = false

type HandleInfo = {
    Part: BasePart,
    Billboard: BillboardGui,
    Icon: ImageButton,
    Background: ImageLabel,
    Color: Color3,
    IconAsset: any,
    OnClick: (any) -> nil,
    Argument: any,
}

local handles = {} :: {[string]: HandleInfo}
local hoveredHandle: HandleInfo? = nil

local function setActionHeld(active: boolean)
	local ctx = Context.Get()
	if ctx.SetActionHeld then
		ctx.SetActionHeld(active)
	end
end

local function handlePrimaryRelease()
	local ctx = Context.Get()
	if ctx.HandlePrimaryRelease then
		ctx.HandlePrimaryRelease()
	end
end

function Handles.Init()
	local ctx = Context.Get()
	Formex = ctx.Formex
	overlayFolder = ctx.OverlayFolder
	handleIconBackground = Content.fromAssetId(Formex.Icons.CircleBackground)
	local player = Players.LocalPlayer
	if not player then
		error("FormexDesignHandles missing LocalPlayer", 2)
	end
	playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	useGuiInput = true
end

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

local function setHandleHover(handle: HandleInfo?, hovered: boolean)
	if not handle then return end

	local baseColor = handle.Color
	local targetColor = hovered and baseColor:Lerp(Color3.new(1, 1, 1), HANDLE_HOVER_TINT) or baseColor
	local scale = hovered and HANDLE_HOVER_SCALE or 1

	handle.Part.Size = Vector3.new(HANDLE_PART_SIZE * scale, HANDLE_PART_SIZE * scale, HANDLE_PART_SIZE * scale)
	handle.Part.Color = targetColor
    handle.Billboard.Size = UDim2.new(0, HANDLE_ICON_SIZE * scale, 0, HANDLE_ICON_SIZE * scale)
    handle.Icon.ImageColor3 = targetColor
    handle.Background.ImageTransparency = hovered and 0.2 or 0.5
end

local function setHoveredHandle(handle: HandleInfo?)
	if hoveredHandle == handle then
		return
	end

	if hoveredHandle then
		setHandleHover(hoveredHandle, false)
	end

	hoveredHandle = handle

	if hoveredHandle then
		setHandleHover(hoveredHandle, true)
	end
end

local function bindHandleInput(handleInfo: HandleInfo)
	handleInfo.Icon.MouseEnter:Connect(function()
		setHoveredHandle(handleInfo)
	end)

	handleInfo.Icon.MouseLeave:Connect(function()
		if hoveredHandle == handleInfo then
			setHoveredHandle(nil)
		end
	end)

	handleInfo.Icon.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if not handleInfo.Billboard.Enabled then
			return
		end
		setActionHeld(true)
		if handleInfo.OnClick then
			handleInfo.OnClick(handleInfo.Argument)
		end
	end)

	handleInfo.Icon.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		setActionHeld(false)
		handlePrimaryRelease()
	end)
end

function Handles.CreateHandle(name: string, color: Color3, iconAsset: number | string, onClick: (any) -> nil, argument: any): BasePart
	if not overlayFolder or not Formex then
		error("FormexDesignHandles not initialized", 2)
	end
	if not playerGui then
		error("FormexDesignHandles missing PlayerGui", 2)
	end

    if type(iconAsset) == "number" then
        iconAsset = Content.fromAssetId(iconAsset)
    else
        iconAsset = Content.fromUri(iconAsset)
    end

    local handleInfo = handles[name]
    local part = handleInfo and handleInfo.Part
    local icon: ImageButton
    
    if not part or not part.Parent or not handleInfo or not handleInfo.Billboard or not handleInfo.Billboard.Parent then
        part = Instance.new("Part", overlayFolder)
        part.Name = name
        part.Size = Vector3.new(HANDLE_PART_SIZE, HANDLE_PART_SIZE, HANDLE_PART_SIZE)
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = true
        part.CastShadow = false
        -- part.CollisionGroup = Formex.CollisionGroup.Grid
        part.Color = color
        part.Transparency = 1

        local billboard = Instance.new("BillboardGui", playerGui)
        billboard.Name = "HandleBillboard"
        billboard.Size = UDim2.new(0, HANDLE_ICON_SIZE, 0, HANDLE_ICON_SIZE)
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 0, 0)
        billboard.LightInfluence = 0
        billboard.AlwaysOnTop = true
        billboard.Adornee = part
        billboard.Active = true

        icon = Instance.new("ImageButton", billboard)
        icon.Name = "Icon"
        icon.AnchorPoint = Vector2.new(0.5, 0.5)
        icon.Position = UDim2.fromScale(0.5, 0.5)
        icon.Size = UDim2.fromScale(0.75, 0.75)
        icon.BackgroundTransparency = 1
        icon.ImageContent = iconAsset
        icon.AutoButtonColor = false
        icon.Active = true
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
        handleInfo = handles[name]

		bindHandleInput(handleInfo)
    end

    handleInfo.OnClick = onClick
    handleInfo.Argument = argument
    handleInfo.Color = color
    handleInfo.IconAsset = iconAsset
    handleInfo.Part.Color = color
    handleInfo.Icon.ImageColor3 = color
	handleInfo.Icon.ImageContent = iconAsset
	handleInfo.Billboard.Adornee = handleInfo.Part
	if handleInfo.Billboard.Parent ~= playerGui then
		handleInfo.Billboard.Parent = playerGui
	end

	return part
end

function Handles.GetHandleIcon(handle: BasePart?): ImageButton?
	if not handle then
		return nil
	end
	local info = handles[handle.Name]
	if not info then
		return nil
	end
	return info.Icon
end

function Handles.SetHandleVisible(handle: string | BasePart?, visible: boolean)
	local handleInfo = nil :: HandleInfo?
	if type(handle) == "string" then
		handleInfo = handles[handle]
	elseif handle then
		handleInfo = handles[handle.Name]
	end

	if handleInfo then
		handleInfo.Part.Transparency = 1
		handleInfo.Part.CanQuery = visible
		handleInfo.Billboard.Enabled = visible
		handleInfo.Icon.Active = visible
		if not visible and hoveredHandle == handleInfo then
			setHoveredHandle(nil)
		end
	end
end

function Handles.Clear()
	if hoveredHandle then
		setHoveredHandle(nil)
	end
    for _, handle in pairs(handles) do
        handle.Part:Destroy()
		handle.Billboard:Destroy()
    end 
end

function Handles.ClearHandleHover()
    if hoveredHandle then
        setHoveredHandle(nil)
    end
end

function Handles.CheckHover(ray: Ray)
	if useGuiInput then
		return
	end
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
	if useGuiInput then
		return false
	end
    local handle = checkHit(ray)

    if handle then
        print("Handle clicked:", handle.Part.Name)
        handle.OnClick(handle.Argument)
        return true
    end

    return false
end

return Handles
