--!strict

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

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
local CAMERA_DISTANCE_MIN = 20
local CAMERA_DISTANCE_MAX = 120
local CAMERA_PAN_SPEED = 55
local CAMERA_PAN_ACCELERATION = 14
local CAMERA_PAN_DAMPING = 6
local CAMERA_MOUSE_PAN_DISTANCE_SCALE = 700
local CAMERA_MOUSE_PAN_DEADZONE = 0.01
local CAMERA_ZOOM_SCROLL_STRENGTH = -60
local CAMERA_ZOOM_KEYBOARD_ACCELERATION = 300
local CAMERA_ZOOM_GAMEPAD_ACCELERATION = 350
local CAMERA_ZOOM_TOUCH_STRENGTH = 2.5
local CAMERA_ZOOM_DAMPING = 10
local CAMERA_ZOOM_DEADZONE = 0.01
local CAMERA_GAMEPAD_DEADZONE = 0.1
local CAMERA_ROTATE_MOUSE_SENSITIVITY = 0.004
local CAMERA_ROTATE_KEYBOARD_SPEED = math.rad(90)
local CAMERA_ROTATE_ACCELERATION = 12
local CAMERA_ROTATE_DAMPING = 8
local CAMERA_ROTATE_DEADZONE = 0.0001

local camera = workspace.CurrentCamera :: Camera
local cameraMode: CameraMode = "Play"
local cameraDistance = DEFAULT_CAMERA_DISTANCE
local cameraDistanceMin = CAMERA_DISTANCE_MIN
local cameraDistanceMax = CAMERA_DISTANCE_MAX
local cameraCenter: Vector3? = nil
local cameraPosition = Vector2.new(0, 0) -- offset of cameraCenter
local cameraBaseUpDirection = Vector3.new(0, 0, 1)
local cameraYaw = 0
local cameraMin: Vector2? = nil
local cameraMax: Vector2? = nil
local isCameraDirty = false
local moveFunction = Controls.moveFunction

local cameraMoveVector: Vector3 = Vector3.new(0, 0, 0)
local cameraVelocity = Vector2.new(0, 0)
local isMousePanning = false
local mousePanLastPosition: Vector2? = nil
local isMouseRotating = false
local mouseRotateLastPosition: Vector2? = nil

local keyboardZoomInHeld = false
local keyboardZoomOutHeld = false
local keyboardZoomInput = 0
local keyboardRotateLeftHeld = false
local keyboardRotateRightHeld = false
local keyboardRotateInput = 0
local gamepadZoomInput = 0
local gamepadZoomInValue = 0
local gamepadZoomOutValue = 0
local zoomVelocity = 0
local rotateVelocity = 0
local zoomAnchorScreen: Vector2? = nil
local touchPoints: {[InputObject]: Vector2} = {}
local touchCount = 0
local lastPinchDistance: number? = nil

local function getCameraCenter(): Vector3
    return cameraCenter or Vector3.new(0, 0, 0)
end

local function getViewportCenter(): Vector2
    local viewportSize = camera.ViewportSize
    return Vector2.new(viewportSize.X * 0.5, viewportSize.Y * 0.5)
end

local function clampCameraDistance(distance: number): number
    return math.clamp(distance, cameraDistanceMin, cameraDistanceMax)
end

local function toVector2(position: Vector3): Vector2
    return Vector2.new(position.X, position.Y)
end

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

local function setCameraUpDirection(direction: Vector3?)
    local nextBase = Vector3.new(0, 0, 1)
    if direction then
        local flattened = Vector3.new(direction.X, 0, direction.Z)
        if flattened.Magnitude >= 1e-4 then
            nextBase = flattened.Unit
        end
    end

    if (nextBase - cameraBaseUpDirection).Magnitude > 1e-4 then
        cameraBaseUpDirection = nextBase
        cameraYaw = 0
    else
        cameraBaseUpDirection = nextBase
    end
    updateCameraPosition()
end

local function resetInputState()
    cameraMoveVector = Vector3.new(0, 0, 0)
    cameraVelocity = Vector2.new(0, 0)
    isMousePanning = false
    mousePanLastPosition = nil
    isMouseRotating = false
    mouseRotateLastPosition = nil
    keyboardZoomInHeld = false
    keyboardZoomOutHeld = false
    keyboardZoomInput = 0
    keyboardRotateLeftHeld = false
    keyboardRotateRightHeld = false
    keyboardRotateInput = 0
    gamepadZoomInput = 0
    gamepadZoomInValue = 0
    gamepadZoomOutValue = 0
    zoomVelocity = 0
    rotateVelocity = 0
    cameraYaw = 0
    zoomAnchorScreen = nil
    touchPoints = {}
    touchCount = 0
    lastPinchDistance = nil
end

local function getCameraUpVector(): Vector3
    if cameraYaw == 0 then
        return cameraBaseUpDirection
    end
    local rotation = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), cameraYaw)
    return rotation:VectorToWorldSpace(cameraBaseUpDirection)
end

local function getCameraRightVector(): Vector3
    local upVector = getCameraUpVector()
    local rightVector = upVector:Cross(Vector3.new(0, -1, 0))
    if rightVector.Magnitude < 1e-4 then
        return Vector3.new(1, 0, 0)
    end
    return rightVector.Unit
end

local function applyZoomDelta(delta: number, anchorScreen: Vector2?): boolean
    if delta == 0 then
        return false
    end

    local oldDistance = cameraDistance
    local newDistance = clampCameraDistance(oldDistance + delta)
    if newDistance == oldDistance then
        return false
    end

    if anchorScreen then
        local center = getCameraCenter()
        local planeY = center.Y
        local ray = camera:ViewportPointToRay(anchorScreen.X, anchorScreen.Y)
        local direction = ray.Direction
        if math.abs(direction.Y) > 1e-4 then
            local t0 = (planeY - ray.Origin.Y) / direction.Y
            local anchorWorld = ray.Origin + direction * t0

            local cameraPosY = center.Y + newDistance
            local t1 = (planeY - cameraPosY) / direction.Y
            local newCameraPos = anchorWorld - direction * t1
            cameraPosition = Vector2.new(newCameraPos.X - center.X, newCameraPos.Z - center.Z)
        end
    end

    cameraDistance = newDistance
    updateCameraPosition()
    return true
end

local function updatePan(dt: number)
    local keyboardInput = Vector2.new(cameraMoveVector.X, cameraMoveVector.Z)
    local targetVelocity = keyboardInput * CAMERA_PAN_SPEED

    if isMousePanning then
        local currentMouse = UserInputService:GetMouseLocation()
        if mousePanLastPosition then
            local delta = currentMouse - mousePanLastPosition
            local studsPerPixel = cameraDistance / CAMERA_MOUSE_PAN_DISTANCE_SCALE
            if delta.Magnitude > CAMERA_MOUSE_PAN_DEADZONE then
                local right = getCameraRightVector()
                local up = getCameraUpVector()
                local worldDelta = (right * delta.X + up * delta.Y) * studsPerPixel / math.max(dt, 1 / 240)
                targetVelocity += Vector2.new(worldDelta.X, worldDelta.Z)
            end
        end
        mousePanLastPosition = currentMouse
    end

    local hasInput = targetVelocity.Magnitude > 0
    local rate = if hasInput then CAMERA_PAN_ACCELERATION else CAMERA_PAN_DAMPING
    local blend = 1 - math.exp(-rate * dt)
    cameraVelocity = cameraVelocity:Lerp(targetVelocity, blend)
    if cameraVelocity.Magnitude > 0.001 then
        cameraPosition = cameraPosition + cameraVelocity * dt
        updateCameraPosition()
    end
end

local function updateZoom(dt: number)
    if keyboardZoomInput ~= 0 then
        zoomVelocity += keyboardZoomInput * CAMERA_ZOOM_KEYBOARD_ACCELERATION * dt
    end
    if gamepadZoomInput ~= 0 then
        zoomVelocity += gamepadZoomInput * CAMERA_ZOOM_GAMEPAD_ACCELERATION * dt
    end

    if math.abs(zoomVelocity) > 0 then
        local changed = applyZoomDelta(zoomVelocity * dt, zoomAnchorScreen)
        if not changed then
            zoomVelocity = 0
        end
    end

    zoomVelocity *= math.exp(-CAMERA_ZOOM_DAMPING * dt)

    if math.abs(zoomVelocity) < CAMERA_ZOOM_DEADZONE and keyboardZoomInput == 0 and gamepadZoomInput == 0 then
        zoomVelocity = 0
        zoomAnchorScreen = nil
    end
end

local function updateKeyboardZoomInput()
    local direction = 0
    if keyboardZoomInHeld then
        direction += 1
    end
    if keyboardZoomOutHeld then
        direction -= 1
    end
    FormexCamera.ZoomKeyboard(direction)
end

local function updateKeyboardRotateInput()
    local direction = 0
    if keyboardRotateLeftHeld then
        direction -= 1
    end
    if keyboardRotateRightHeld then
        direction += 1
    end
    keyboardRotateInput = math.clamp(direction, -1, 1)
end

local function updateRotation(dt: number)
    local targetVelocity = keyboardRotateInput * CAMERA_ROTATE_KEYBOARD_SPEED

    if isMouseRotating then
        local currentMouse = UserInputService:GetMouseLocation()
        if mouseRotateLastPosition then
            local delta = currentMouse - mouseRotateLastPosition
            if math.abs(delta.X) > CAMERA_ROTATE_DEADZONE then
                local mouseVelocity = delta.X * CAMERA_ROTATE_MOUSE_SENSITIVITY / math.max(dt, 1 / 240)
                targetVelocity += mouseVelocity
            end
        end
        mouseRotateLastPosition = currentMouse
    end

    local hasInput = math.abs(targetVelocity) > CAMERA_ROTATE_DEADZONE
    local rate = if hasInput then CAMERA_ROTATE_ACCELERATION else CAMERA_ROTATE_DAMPING
    local blend = 1 - math.exp(-rate * dt)
    rotateVelocity += (targetVelocity - rotateVelocity) * blend

    if math.abs(rotateVelocity) > CAMERA_ROTATE_DEADZONE then
        cameraYaw += rotateVelocity * dt
        updateCameraPosition()
    elseif not hasInput then
        rotateVelocity = 0
    end
end

function FormexCamera.GetCameraMode(): CameraMode
    return cameraMode
end

function FormexCamera.SetCameraMode(mode: CameraMode, center: Vector3?, bound1: Vector3?, bound2: Vector3?, topDirection: Vector3?)
    local isSameMode = mode == cameraMode
    cameraMode = mode
    if not isSameMode then
        resetInputState()
    end

    local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid") :: Model

    if mode == FormexCamera.CameraMode.Play then
        if not isSameMode then
            camera.CameraSubject = humanoid
            camera.CameraType = Enum.CameraType.Custom
            FormexCamera.SetZoomLimits(nil, nil)
        end
    elseif mode == FormexCamera.CameraMode.TopDown then
        if not isSameMode then
            camera.CameraSubject = nil
            camera.CameraType = Enum.CameraType.Scriptable
            FormexCamera.SetCameraCenter(center or (humanoid and humanoid.RootPart and humanoid.RootPart.Position) or Vector3.new(0, 0, 0))
            FormexCamera.SetCameraDistance(DEFAULT_CAMERA_DISTANCE)
            FormexCamera.SetCameraBounds(bound1, bound2)
        end
        if topDirection or not isSameMode then
            setCameraUpDirection(topDirection)
        end
    end

    updateCameraPosition()
end

function FormexCamera.Focus(point: Vector3)
    if cameraCenter then
        cameraPosition = Vector2.new(point.X - cameraCenter.X, point.Z - cameraCenter.Z)
    else
        cameraPosition = Vector2.new(point.X, point.Z)
    end
    updateCameraPosition()
end

function FormexCamera.SetCameraCenter(center: Vector3)
    cameraCenter = center
    cameraPosition = Vector2.new(0, 0)
    updateCameraPosition()
end

function FormexCamera.SetCameraDistance(distance: number)
    cameraDistance = clampCameraDistance(distance)
    zoomVelocity = 0
    updateCameraPosition()
end

function FormexCamera.SetCameraBounds(bound1: Vector3?, bound2: Vector3?)
    if bound1 and bound2 then
        cameraMin = Vector2.new(math.min(bound1.X, bound2.X), math.min(bound1.Z, bound2.Z))
        cameraMax = Vector2.new(math.max(bound1.X, bound2.X), math.max(bound1.Z, bound2.Z))
    else
        cameraMin = nil
        cameraMax = nil
    end
    updateCameraPosition()
end

function FormexCamera.SetZoomLimits(minDistance: number?, maxDistance: number?)
    local minValue = minDistance or CAMERA_DISTANCE_MIN
    local maxValue = maxDistance or CAMERA_DISTANCE_MAX
    if maxValue < minValue then
        maxValue = minValue
    end
    cameraDistanceMin = minValue
    cameraDistanceMax = maxValue
    cameraDistance = clampCameraDistance(cameraDistance)
    updateCameraPosition()
end

function FormexCamera.ZoomKeyboard(direction: number)
    keyboardZoomInput = math.clamp(direction, -1, 1)
    if keyboardZoomInput ~= 0 then
        zoomAnchorScreen = getViewportCenter()
    end
end

function FormexCamera.ZoomMouse(delta: number, screenPoint: Vector2)
    if delta == 0 then
        return
    end
    zoomVelocity += delta * CAMERA_ZOOM_SCROLL_STRENGTH
    zoomAnchorScreen = screenPoint
end

function FormexCamera.ZoomTouch(delta: number, screenPoint: Vector2)
    if delta == 0 then
        return
    end
    zoomVelocity += delta * CAMERA_ZOOM_TOUCH_STRENGTH
    zoomAnchorScreen = screenPoint
end

function FormexCamera.ZoomGamepad(value: number)
    if math.abs(value) < CAMERA_GAMEPAD_DEADZONE then
        gamepadZoomInput = 0
        return
    end
    gamepadZoomInput = math.clamp(value, -1, 1)
    zoomAnchorScreen = getViewportCenter()
end

local function cameraMoveFunction(player: Player, moveVector: Vector3, relativeToCamera: boolean): nil
    if cameraMode ~= FormexCamera.CameraMode.TopDown then        
        return moveFunction(player, moveVector, relativeToCamera)
    end

    cameraMoveVector = moveVector
end
Controls.moveFunction = cameraMoveFunction

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
    if gameProcessedEvent then return end
    if cameraMode ~= FormexCamera.CameraMode.TopDown then return end

    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        isMousePanning = true
        mousePanLastPosition = UserInputService:GetMouseLocation()
        return
    end

    if input.UserInputType == Enum.UserInputType.MouseButton3 then
        isMouseRotating = true
        mouseRotateLastPosition = UserInputService:GetMouseLocation()
        return
    end

    if input.KeyCode == Enum.KeyCode.Space then
        keyboardZoomInHeld = true
        updateKeyboardZoomInput()
        return
    end

    if input.KeyCode == Enum.KeyCode.C
        or input.KeyCode == Enum.KeyCode.LeftControl
        or input.KeyCode == Enum.KeyCode.RightControl
    then
        keyboardZoomOutHeld = true
        updateKeyboardZoomInput()
        return
    end

    if input.KeyCode == Enum.KeyCode.Q then
        keyboardRotateLeftHeld = true
        updateKeyboardRotateInput()
        return
    end

    if input.KeyCode == Enum.KeyCode.E then
        keyboardRotateRightHeld = true
        updateKeyboardRotateInput()
    end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessedEvent)
    if gameProcessedEvent then return end
    if cameraMode ~= FormexCamera.CameraMode.TopDown then return end

    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        isMousePanning = false
        mousePanLastPosition = nil
        return
    end

    if input.UserInputType == Enum.UserInputType.MouseButton3 then
        isMouseRotating = false
        mouseRotateLastPosition = nil
        return
    end

    if input.KeyCode == Enum.KeyCode.Space then
        keyboardZoomInHeld = false
        updateKeyboardZoomInput()
        return
    end

    if input.KeyCode == Enum.KeyCode.C
        or input.KeyCode == Enum.KeyCode.LeftControl
        or input.KeyCode == Enum.KeyCode.RightControl
    then
        keyboardZoomOutHeld = false
        updateKeyboardZoomInput()
        return
    end

    if input.KeyCode == Enum.KeyCode.Q then
        keyboardRotateLeftHeld = false
        updateKeyboardRotateInput()
        return
    end

    if input.KeyCode == Enum.KeyCode.E then
        keyboardRotateRightHeld = false
        updateKeyboardRotateInput()
    end
end)

UserInputService.InputChanged:Connect(function(input, gameProcessedEvent)
    if gameProcessedEvent then return end
    if cameraMode ~= FormexCamera.CameraMode.TopDown then return end

    if input.UserInputType == Enum.UserInputType.MouseWheel then
        FormexCamera.ZoomMouse(input.Position.Z, toVector2(input.Position))
        return
    end

    if input.UserInputType == Enum.UserInputType.Gamepad1 then
        local triggerValue = input.Position.Z
        if input.KeyCode == Enum.KeyCode.ButtonL2 then
            gamepadZoomOutValue = triggerValue
        elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
            gamepadZoomInValue = triggerValue
        end
        FormexCamera.ZoomGamepad(gamepadZoomInValue - gamepadZoomOutValue)
    end
end)

UserInputService.TouchStarted:Connect(function(input, gameProcessedEvent)
    if gameProcessedEvent then return end
    if cameraMode ~= FormexCamera.CameraMode.TopDown then return end

    touchPoints[input] = toVector2(input.Position)
    touchCount += 1
    if touchCount < 2 then
        lastPinchDistance = nil
    end
end)

UserInputService.TouchEnded:Connect(function(input, gameProcessedEvent)
    if gameProcessedEvent then return end
    if cameraMode ~= FormexCamera.CameraMode.TopDown then return end

    if touchPoints[input] then
        touchPoints[input] = nil
        touchCount -= 1
    end
    if touchCount < 2 then
        lastPinchDistance = nil
    end
end)

UserInputService.TouchMoved:Connect(function(input, gameProcessedEvent)
    if gameProcessedEvent then return end
    if cameraMode ~= FormexCamera.CameraMode.TopDown then return end

    if not touchPoints[input] then
        return
    end
    touchPoints[input] = toVector2(input.Position)
    if touchCount < 2 then
        lastPinchDistance = nil
        return
    end

    local points = {}
    for _, position in pairs(touchPoints) do
        table.insert(points, position)
    end
    if #points < 2 then
        lastPinchDistance = nil
        return
    end

    local pointA = points[1]
    local pointB = points[2]
    local center = (pointA + pointB) * 0.5
    local distance = (pointA - pointB).Magnitude

    if lastPinchDistance then
        local delta = distance - lastPinchDistance
        FormexCamera.ZoomTouch(-delta, center)
    end
    lastPinchDistance = distance
end)

local function onRenderStep(dt: number)
    if cameraMode ~= FormexCamera.CameraMode.TopDown then return end

    updatePan(dt)
    updateZoom(dt)
    updateRotation(dt)

    if not isCameraDirty then return end

    local position = Vector3.new(cameraPosition.X, cameraDistance, cameraPosition.Y)
    if cameraCenter then
        position = cameraCenter + position
    end
    camera.CFrame = CFrame.lookAt(position, position + Vector3.new(0, -1, 0), getCameraUpVector())
    isCameraDirty = false
end
RunService:BindToRenderStep("FormexCameraUpdate", Enum.RenderPriority.Camera.Value + 1, onRenderStep)

return FormexCamera
