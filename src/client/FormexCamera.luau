--!strict

local RunService = game:GetService("RunService")

local FormexClient = require(script.Parent:WaitForChild("FormexClient"))
local Formex = FormexClient.Formex

local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer
local PlayerModule = require(localPlayer.PlayerScripts.PlayerModule)
local Controls = PlayerModule:GetControls()

local FormexCamera = {}

export type CameraMode = "Play" | "TopDown" | "Isometric"
FormexCamera.CameraMode = table.freeze({
	Play = "Play", -- Normal character camera
	TopDown = "TopDown", -- Activate custom top-down camera controller
}) :: {CameraMode: CameraMode}

local DEFAULT_CAMERA_DISTANCE = 50
local CAMERA_PAN_SPEED = 25

local camera = workspace.CurrentCamera :: Camera
local cameraMode: CameraMode = "Play"
local cameraDistance = DEFAULT_CAMERA_DISTANCE
local cameraCenter: Vector3? = nil
local cameraPosition = Vector2.new(0, 0) -- offset of cameraCenter
local cameraMin = Vector2.new(0, 0)
local cameraMax = Vector2.new(0, 0)
local isCameraDirty = false
local moveFunction = Controls.moveFunction

local function clampCameraPosition()
    if cameraMin and cameraMax then
        cameraPosition = Vector2.new(
            math.clamp(cameraPosition.X, cameraMin.X, cameraMax.X),
            math.clamp(cameraPosition.Y, cameraMin.Y, cameraMax.Y)
        )
    end
end

local function updateCameraPosition()
    if cameraMode == FormexCamera.CameraMode.TopDown then
        clampCameraPosition()
        isCameraDirty = true
    else 
        isCameraDirty = false
    end
end

function FormexCamera.GetCameraMode(): CameraMode
    return cameraMode
end

function FormexCamera.SetCameraMode(mode: CameraMode, center: Vector3?, bound1: Vector2?, bound2: Vector2?)
    if mode == cameraMode then return end
    cameraMode = mode

    local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid") :: Model

    if mode == FormexCamera.CameraMode.Play then
        camera.CameraSubject = humanoid
        camera.CameraType = Enum.CameraType.Custom
    elseif mode == FormexCamera.CameraMode.TopDown then
        camera.CameraSubject = nil
        camera.CameraType = Enum.CameraType.Scriptable
        FormexCamera.SetCameraCenter(center or (humanoid and humanoid.RootPart and humanoid.RootPart.Position) or Vector3.new(0, 0, 0))
        FormexCamera.SetCameraDistance(DEFAULT_CAMERA_DISTANCE)
        FormexCamera.SetCameraBounds(bound1, bound2)
    end

    updateCameraPosition()
end

function FormexCamera.Focus(point: Vector3)
    cameraPosition = Vector2.new(point.X, point.Z)
    updateCameraPosition()
end

function FormexCamera.SetCameraCenter(center: Vector3)
    cameraCenter = center
    cameraPosition = Vector2.new(0, 0)
    updateCameraPosition()
end

function FormexCamera.SetCameraDistance(distance: number)
    cameraDistance = distance
    updateCameraPosition()
end

function FormexCamera.SetCameraBounds(bound1: Vector3?, bound2: Vector3?)
    if bound1 and bound2 then
        cameraMin = Vector2.new(math.min(bound1.X, bound2.X), math.min(bound1.Y, bound2.Y))
        cameraMax = Vector2.new(math.max(bound1.X, bound2.X), math.max(bound1.Y, bound2.Y))
    else
        cameraMin = nil
        cameraMax = nil
    end
    updateCameraPosition()
end

local cameraMoveVector: Vector3 = Vector3.new(0, 0, 0)

local function cameraMoveFunction(player: Player, moveVector: Vector3, relativeToCamera: boolean): nil
    if cameraMode ~= FormexCamera.CameraMode.TopDown then        
        return moveFunction(player, moveVector, relativeToCamera)
    end

    print("Camera move vector:", moveVector)

    cameraMoveVector = moveVector
end
Controls.moveFunction = cameraMoveFunction

local function onRenderStep(dt: number)
    if cameraMode ~= FormexCamera.CameraMode.TopDown then return end

    if cameraMoveVector.Magnitude ~= 0 then
        cameraPosition = cameraPosition + Vector2.new(cameraMoveVector.X, cameraMoveVector.Z) * dt * CAMERA_PAN_SPEED
        print(cameraMoveVector, typeof(cameraMoveVector), cameraPosition)
        updateCameraPosition()
    end

    if not isCameraDirty then return end

    local position = Vector3.new(cameraPosition.X, cameraDistance, cameraPosition.Y)
    if cameraCenter then
        position = cameraCenter + position
    end
    camera.CFrame = CFrame.new(position) * CFrame.Angles(-math.rad(90), 0, 0)
end
RunService:BindToRenderStep("FormexCameraUpdate", Enum.RenderPriority.Camera.Value + 1, onRenderStep)

return FormexCamera