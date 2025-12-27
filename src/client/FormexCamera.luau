--!strict

local FormexClient = require(script.Parent:WaitForChild("FormexClient"))
local Formex = FormexClient.Formex

local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

local FormexCamera = {}

export type CameraMode = "Play" | "TopDown" | "Isometric"
FormexCamera.CameraModes = {
	Play = "Play", -- Normal character camera
	TopDown = "TopDown", -- Activate custom top-down camera controller
	Isometric = "Isometric" -- Activate custom isometric camera controller (FOV 0.000125, 45 degrees)
} :: {CameraMode: CameraMode}

function FormexCamera.SetCameraMode(mode: CameraMode)
    -- TODO out of scope
end

function FormexCamera.Focus(point: Vector3)
    -- TODO out of scope
end

function FormexCamera.SetCameraBounds(corner1: Vector3, corner2: Vector3)
    -- TODO out of scope
end

return FormexCamera