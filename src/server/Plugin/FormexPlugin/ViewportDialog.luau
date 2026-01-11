--!strict

local StarterGui = game:GetService("StarterGui")

local PluginUtils = require(script.Parent:WaitForChild("PluginUtils"))
local PrefabMetadata = require(script.Parent:WaitForChild("PrefabMetadata"))
local PrefabSizing = require(script.Parent:WaitForChild("PrefabSizing"))
local ViewportUtils = require(script.Parent:WaitForChild("ViewportUtils"))

type ViewportDialog = {
	Show: (self: ViewportDialog) -> (),
	Hide: (self: ViewportDialog) -> (),
	IsVisible: (self: ViewportDialog) -> boolean,
	SetPrefab: (self: ViewportDialog, root: Model?, forceRecalc: boolean?) -> (),
}

local ViewportDialogModule = {}

local function getOrCreateGui()
	local screenGui = StarterGui:FindFirstChild("FormexPrefabGui")
	if screenGui and screenGui:IsA("ScreenGui") then
		return screenGui
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "FormexPrefabGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = StarterGui
	return gui
end

local function getOrCreateViewport(gui: ScreenGui)
	local viewport = gui:FindFirstChild("PrefabPreview")
	if viewport and viewport:IsA("ViewportFrame") then
		return viewport
	end

	local frame = Instance.new("ViewportFrame")
	frame.Name = "PrefabPreview"
	frame.AnchorPoint = Vector2.new(1, 1)
	frame.Position = UDim2.new(1, -20, 1, -20)
	frame.Size = UDim2.new(0, 320, 0, 240)
	frame.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
	frame.BorderSizePixel = 0
	frame.Parent = gui
	return frame
end

function ViewportDialogModule.new(_plugin: Plugin): ViewportDialog
	local screenGui: ScreenGui? = nil
	local viewportFrame: ViewportFrame? = nil
	local camera: Camera? = nil
	local currentModel: Model? = nil

	local function ensureGui()
		if screenGui and screenGui.Parent then
			return
		end
		screenGui = getOrCreateGui()
		viewportFrame = getOrCreateViewport(screenGui)

		camera = viewportFrame:FindFirstChildOfClass("Camera")
		if not camera then
			camera = Instance.new("Camera")
			camera.FieldOfView = 35
			camera.Parent = viewportFrame
		end
		viewportFrame.CurrentCamera = camera
	end

	local dialog = {} :: ViewportDialog

	function dialog:Show()
		ensureGui()
		if screenGui then
			screenGui.Enabled = true
		end
	end

	function dialog:Hide()
		if currentModel then
			currentModel:Destroy()
			currentModel = nil
		end
		if screenGui then
			screenGui:Destroy()
		end
		screenGui = nil
		viewportFrame = nil
		camera = nil
	end

	function dialog:IsVisible(): boolean
		return screenGui ~= nil and screenGui.Enabled
	end

	function dialog:SetPrefab(root: Model?, _forceRecalc: boolean?)
		ensureGui()
		if not viewportFrame or not camera then
			return
		end
		if currentModel then
			currentModel:Destroy()
			currentModel = nil
		end
		if not root then
			return
		end

		local prefabModel = PrefabMetadata.GetPrefabModel(root)
		local sourceModel = prefabModel or root
		local clone = sourceModel:Clone()
		clone.Name = "PreviewModel"
		clone.Parent = viewportFrame
		currentModel = clone

		PluginUtils.DisableScripts(clone)
		for _, part in ipairs(PluginUtils.CollectBaseParts(clone)) do
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.CastShadow = false
		end

		clone:PivotTo(CFrame.new())

		local attributes = PrefabMetadata.ReadAttributes(root)
		local size = attributes.Size
		if not size or typeof(size) ~= "Vector3" then
			size = PrefabSizing.CalculatePrefabSize(root)
		end
		size = PrefabSizing.SnapSize(size, attributes.ObjectMount)
		PrefabMetadata.ApplyAttributes(root, { Size = size })
		camera.CFrame = ViewportUtils.ComputeCameraCFrame(size)
	end

	return dialog
end

return ViewportDialogModule
