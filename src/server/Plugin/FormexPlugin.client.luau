--!strict

-- This plugin is a helper for creating and managing Formex object prefabs
-- It provides toolbar buttons to prepare, edit, store, and recall prefabs
-- When a user selects a prefab in the workspace, they can use these buttons to manage it
-- It also helps with positioning the thumbnail camera to create a consistent look for prefab icons

local Toolbar = plugin:CreateToolbar("Formex")
local Selection = game:GetService("Selection")

export type ObjectMount = "Surface" | "Ceiling" | "Floor" | "Wall" | "Door" | "Window"

local createPrefabButton = Toolbar:CreateButton(
	"Prepare Prefab",
	"Convert the selection into a prefab",
	"rbxassetid://121737476159985")
-- Wraps the selected parts into a prefab structure and adds necessary Attributes
-- Prompts for a name for the prefab, ObjectMount, and other metadata
-- Upserts the prefab into ServerStorage/FormexPrefabs

local editPrefabButton = Toolbar:CreateButton(
	"Edit Prefab Data",
	"Edit the attributes of a selected prefab",
	"rbxassetid://121737476159985")
-- Prompts for a name for the prefab, ObjectMount, and other metadata
-- Upserts the prefab into ServerStorage/FormexPrefabs

local storePrefabButton = Toolbar:CreateButton(
	"Store Prefab",
	"Push a prefab into storage",
	"rbxassetid://121737476159985")
-- Upserts the selected prefab(s) into ServerStorage/FormexPrefabs
-- Destroys the prefab(s) in the workspace after storing

local recallPrefabButton = Toolbar:CreateButton(
	"Recall Prefab",
	"Pull a prefab from storage",
	"rbxassetid://121737476159985")
-- Displays a box to select existing prefabs and clones the prefab from ServerStorage/FormexPrefabs into the workspace to edit it

local function displayMessageBox(title, message)
    local messageBox = plugin:CreateDockWidgetPluginGuiAsync("FormexAlertBox",
        DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, true, false, 200, 150, 150, 100))
    messageBox.Title = title

    local textLabel = Instance.new("TextLabel", messageBox)
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.Text = message

    local closeButton = Instance.new("TextButton", messageBox)
    closeButton.Size = UDim2.new(0, 100, 0, 30)
    closeButton.Position = UDim2.new(0.5, -50, 1, -40)
    closeButton.Text = "Close"
    closeButton.MouseButton1Click:Connect(function()
        messageBox.Enabled = false
        messageBox:Destroy()
    end)
end

local function preparePrefab(parts: {Instance})
    -- Wrap parts into a Model and set up necessary properties for prefab
    local prefabModel = Instance.new("Model")
end

createPrefabButton.Click:Connect(function()
    local selectedParts = Selection:Get()

    if #selectedParts == 0 then
        displayMessageBox("Formex Create Prefab", "No parts selected. Please select parts to create a prefab.")
        return
    end

	print("prefab!")
end)

