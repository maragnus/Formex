local Players = game:GetService("Players")
local FormexClient = require(script.Parent:WaitForChild("FormexClient"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BlurController = require(script.Parent:WaitForChild("BlurController"))

local localPlayer = Players.LocalPlayer

local screenGui: ScreenGui = Instance.new("ScreenGui", localPlayer:WaitForChild("PlayerGui"))
screenGui.Name = "FormexUI"

local footerFrame: Frame = Instance.new("Frame", screenGui)
footerFrame.Name = "FooterFrame"
footerFrame.AnchorPoint = Vector2.new(0.5, 1)
footerFrame.Position = UDim2.new(0.5, 0, 1, 64)
footerFrame.Size = UDim2.new(1, -32, 0, 128)
footerFrame.BackgroundColor3 = Color3.fromRGB(250, 245, 255)
footerFrame.BackgroundTransparency = 0.5
local footerUICorner: UICorner = Instance.new("UICorner", footerFrame)
footerUICorner.CornerRadius = UDim.new(0, 32)
BlurController.new(footerFrame, "Rectangle")

-- Listen for client events
FormexClient.ClientEvents:Connect(function(eventName, ...)
    if eventName ~= "CurrentPlotChanged" then return end
    
    local info = FormexClient.CurrentPlot
    print(info)
end)


BlurController.updateAll();

-- Create UI elements or perform other setup tasks here
print("Formex UI initialized for player:", localPlayer.Name)