--!strict

--[[

Exported methods:
- GetCameraMode()
- GetTopDownState()
- ApplyTopDownState(state)
- SetCameraMode(mode, center, bound1, bound2, topDirection)
- Focus(point)
- SetFocalPoint(point)
- SetFocalHeight(height)
- SetCameraCenter(center)
- SetCameraDistance(value)
- SetCameraBounds(bound1, bound2)
- SetZoomLimits(minDistance, maxDistance)
- SetInvertMouseWheel(value)
- ZoomKeyboard(direction)
- ZoomMouse(delta, screenPoint)
- ZoomTouch(delta, screenPoint)
- ZoomGamepad(value)

Features:
- Orbit camera around a focal point with yaw, tilt, and distance.
- Bounds-aware focal panning relative to rotation, plus keyboard/gamepad movement.
- Mouse wheel zooms toward cursor; touch pinch zooms and rotates.
- Smooth, momentum-based pan/tilt/rotate/zoom with simultaneous input support.

Why it's a good top-down choice:
- Familiar RTS/creator controls that stay stable across devices.
- Predictable framing with focal bounds and zoom anchors.
- Responsive, low-jitter motion that still feels smooth and deliberate.
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer
local PlayerModule = require(localPlayer.PlayerScripts.PlayerModule)
local Controls = PlayerModule:GetControls()

local DesignCamera = {}

export type CameraMode = "Play" | "TopDown"
DesignCamera.CameraMode = table.freeze({
	Play = "Play",
	TopDown = "TopDown",
}) :: {[CameraMode]: CameraMode}

export type TopDownState = {
	Position: Vector2,
	Distance: number,
	Yaw: number,
	Tilt: number,
	Height: number?,
}

local DEFAULT_CAMERA_DISTANCE = 50
local CAMERA_DISTANCE_MIN = 20
local CAMERA_DISTANCE_MAX = 120

local CAMERA_PAN_SPEED = 55
local CAMERA_PAN_ACCELERATION = 14
local CAMERA_PAN_DAMPING = 6
local CAMERA_PAN_DEADZONE = 0.001
local CAMERA_MOUSE_PAN_DEADZONE = 0.01

local CAMERA_ZOOM_SCROLL_STRENGTH = -60
local CAMERA_ZOOM_KEYBOARD_ACCELERATION = 300
local CAMERA_ZOOM_GAMEPAD_ACCELERATION = 350
local CAMERA_ZOOM_TOUCH_STRENGTH = 2.5
local CAMERA_ZOOM_DAMPING = 10
local CAMERA_ZOOM_DEADZONE = 0.01
local CAMERA_GAMEPAD_DEADZONE = 0.1

local CAMERA_ROTATE_MOUSE_SENSITIVITY = 0.004
local CAMERA_ROTATE_TOUCH_SENSITIVITY = 1
local CAMERA_ROTATE_KEYBOARD_SPEED = math.rad(90)
local CAMERA_ROTATE_ACCELERATION = 12
local CAMERA_ROTATE_DAMPING = 8
local CAMERA_ROTATE_DEADZONE = 0.0001

local CAMERA_TILT_MOUSE_SENSITIVITY = 0.004
local CAMERA_TILT_ACCELERATION = 12
local CAMERA_TILT_DAMPING = 8
local CAMERA_TILT_DEADZONE = 0.0001
local CAMERA_TILT_MIN = 0
local CAMERA_TILT_MAX = math.rad(45)

local EPSILON = 1e-4

local camera = workspace.CurrentCamera :: Camera
local cameraMode: CameraMode = "Play"

local distance = DEFAULT_CAMERA_DISTANCE
local distanceMin = CAMERA_DISTANCE_MIN
local distanceMax = CAMERA_DISTANCE_MAX

local baseCenter: Vector3? = nil
local focalOffset = Vector2.new(0, 0)
local focalHeight = 0
local boundsMin: Vector2? = nil
local boundsMax: Vector2? = nil

local baseUpDirection = Vector3.new(0, 0, 1)
local yaw = 0
local tilt = 0

local panVelocity = Vector2.new(0, 0)
local zoomVelocity = 0
local yawVelocity = 0
local tiltVelocity = 0
local touchRotateImpulse = 0

local cameraMoveVector = Vector3.new(0, 0, 0)
local cameraMoveRelativeToCamera = false

local isMousePanning = false
local lastMousePanPosition: Vector2? = nil
local isMouseRotating = false
local lastMouseRotatePosition: Vector2? = nil

local keyboardZoomInHeld = false
local keyboardZoomOutHeld = false
local keyboardZoomInput = 0
local keyboardRotateLeftHeld = false
local keyboardRotateRightHeld = false
local keyboardRotateInput = 0

local gamepadZoomInput = 0
local gamepadZoomInValue = 0
local gamepadZoomOutValue = 0

local zoomAnchorScreen: Vector2? = nil
local invertMouseWheel = false

local touchPoints: {[InputObject]: Vector2} = {}
local touchCount = 0
local lastPinchDistance: number? = nil
local lastPinchAngle: number? = nil

local isCameraDirty = false
local moveFunction = Controls.moveFunction

local function getBaseCenter(): Vector3
	return baseCenter or Vector3.new(0, 0, 0)
end

local function getViewportCenter(): Vector2
	local viewportSize = camera.ViewportSize
	return Vector2.new(viewportSize.X * 0.5, viewportSize.Y * 0.5)
end

local function clampDistance(value: number): number
	return math.clamp(value, distanceMin, distanceMax)
end

local function clampTilt(value: number): number
	return math.clamp(value, CAMERA_TILT_MIN, CAMERA_TILT_MAX)
end

local function clampFocalOffset()
	if boundsMin and boundsMax then
		focalOffset = Vector2.new(
			math.clamp(focalOffset.X, boundsMin.X, boundsMax.X),
			math.clamp(focalOffset.Y, boundsMin.Y, boundsMax.Y)
		)
	end
end

local function markCameraDirty()
	if cameraMode == DesignCamera.CameraMode.TopDown then
		isCameraDirty = true
	end
end

local function setCameraUpDirection(direction: Vector3?)
	local nextBase = Vector3.new(0, 0, 1)
	if direction then
		local flattened = Vector3.new(direction.X, 0, direction.Z)
		if flattened.Magnitude >= EPSILON then
			nextBase = flattened.Unit
		end
	end

	if (nextBase - baseUpDirection).Magnitude > EPSILON then
		baseUpDirection = nextBase
		yaw = 0
	else
		baseUpDirection = nextBase
	end
	markCameraDirty()
end

local function getCameraUpVector(): Vector3
	if yaw == 0 then return baseUpDirection end
	local rotation = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), yaw)
	return rotation:VectorToWorldSpace(baseUpDirection)
end

local function getCameraRightVector(): Vector3
	local upVector = getCameraUpVector()
	local rightVector = Vector3.new(0, 1, 0):Cross(upVector)
	if rightVector.Magnitude < EPSILON then
		return Vector3.new(1, 0, 0)
	end
	return rightVector.Unit
end

local function getCameraForwardVector(): Vector3
	local forward = Vector3.new(0, -1, 0)
	if tilt == 0 then return forward end
	local rightVector = getCameraRightVector()
	local rotation = CFrame.fromAxisAngle(rightVector, -tilt)
	return rotation:VectorToWorldSpace(forward)
end

local function getCameraFocus(): Vector3
	local base = getBaseCenter()
	return Vector3.new(base.X + focalOffset.X, focalHeight, base.Z + focalOffset.Y)
end

local function getPanAxes(): (Vector3, Vector3)
	local focus = getCameraFocus()
	local forward = getCameraForwardVector()
	local cameraPosition = focus - forward * distance
	local cameraCFrame = CFrame.lookAt(cameraPosition, focus, getCameraUpVector())
	local right = cameraCFrame.RightVector
	local up = cameraCFrame.UpVector
	right = Vector3.new(right.X, 0, right.Z)
	up = Vector3.new(up.X, 0, up.Z)
	if right.Magnitude < EPSILON then
		right = getCameraRightVector()
	else
		right = right.Unit
	end
	if up.Magnitude < EPSILON then
		up = getCameraUpVector()
	else
		up = up.Unit
	end
	return right, up
end

local function setFocalPoint(point: Vector3)
	local base = getBaseCenter()
	focalOffset = Vector2.new(point.X - base.X, point.Z - base.Z)
	focalHeight = point.Y
	clampFocalOffset()
	markCameraDirty()
end

local function getRayFromScreen(screenPoint: Vector2): (Vector3?, Vector3?)
	local viewport = camera.ViewportSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return nil, nil
	end

	local halfFov = math.rad(camera.FieldOfView) * 0.5
	local tanHalfFov = math.tan(halfFov)
	if tanHalfFov <= 0 then
		return nil, nil
	end

	local aspect = viewport.X / viewport.Y
	local x = (screenPoint.X / viewport.X - 0.5) * 2
	local y = (screenPoint.Y / viewport.Y - 0.5) * -2

	local focus = getCameraFocus()
	local forward = getCameraForwardVector()
	local cameraPosition = focus - forward * distance
	local cameraCFrame = CFrame.lookAt(cameraPosition, focus, getCameraUpVector())
	local right = cameraCFrame.RightVector
	local up = cameraCFrame.UpVector
	local look = cameraCFrame.LookVector

	local direction = (right * (x * aspect * tanHalfFov) + up * (y * tanHalfFov) + look).Unit
	return cameraPosition, direction
end

local function solveFocusForAnchor(anchorWorld: Vector3, rayDirection: Vector3, newDistance: number): Vector3
	local forward = getCameraForwardVector()
	local denom = rayDirection.Y
	if math.abs(denom) < EPSILON then
		return getCameraFocus()
	end
	local offset = forward * newDistance - rayDirection * (forward.Y * newDistance / denom)
	return anchorWorld + offset
end

local function applyZoomDelta(delta: number, anchorScreen: Vector2?): boolean
	if delta == 0 then return false end
	local oldDistance = distance
	local newDistance = clampDistance(oldDistance + delta)
	if newDistance == oldDistance then
		zoomVelocity = 0
		return false
	end

	if anchorScreen then
		local focus = getCameraFocus()
		local cameraPosition, rayDirection = getRayFromScreen(anchorScreen)
		if cameraPosition and rayDirection and math.abs(rayDirection.Y) > EPSILON then
			local t = (focus.Y - cameraPosition.Y) / rayDirection.Y
			local anchorWorld = cameraPosition + rayDirection * t
			local nextFocus = solveFocusForAnchor(anchorWorld, rayDirection, newDistance)
			setFocalPoint(nextFocus)
		end
	end

	distance = newDistance
	markCameraDirty()
	return true
end

local function getPanPixelScale(): (number, number)
	local viewport = camera.ViewportSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return 0, 0
	end

	local halfFov = math.rad(camera.FieldOfView) * 0.5
	local tanHalfFov = math.tan(halfFov)
	if tanHalfFov <= 0 then
		return 0, 0
	end

	local viewHeight = 2 * distance * tanHalfFov
	local viewWidth = viewHeight * (viewport.X / viewport.Y)
	return viewWidth / viewport.X, viewHeight / viewport.Y
end

local function updatePan(dt: number)
	local targetVelocity = Vector2.new(0, 0)

	local moveMagnitude = cameraMoveVector.Magnitude
	if moveMagnitude > 0 then
		if cameraMoveRelativeToCamera then
			local right, up = getPanAxes()
			local worldMove = right * cameraMoveVector.X + up * cameraMoveVector.Z
			targetVelocity += Vector2.new(worldMove.X, worldMove.Z) * CAMERA_PAN_SPEED
		else
			targetVelocity += Vector2.new(cameraMoveVector.X, cameraMoveVector.Z) * CAMERA_PAN_SPEED
		end
	end

	if isMousePanning then
		local currentMouse = UserInputService:GetMouseLocation()
		if lastMousePanPosition then
			local delta = currentMouse - lastMousePanPosition
			if delta.Magnitude > CAMERA_MOUSE_PAN_DEADZONE then
				local scaleX, scaleY = getPanPixelScale()
				local right, up = getPanAxes()
				local worldDelta = (-right * (delta.X * scaleX) + up * (delta.Y * scaleY)) / math.max(dt, 1 / 240)
				targetVelocity += Vector2.new(worldDelta.X, worldDelta.Z)
			end
		end
		lastMousePanPosition = currentMouse
	end

	local hasInput = targetVelocity.Magnitude > CAMERA_PAN_DEADZONE
	local rate = if hasInput then CAMERA_PAN_ACCELERATION else CAMERA_PAN_DAMPING
	local blend = 1 - math.exp(-rate * dt)
	panVelocity = panVelocity:Lerp(targetVelocity, blend)

	if panVelocity.Magnitude > CAMERA_PAN_DEADZONE then
		local nextOffset = focalOffset + panVelocity * dt
		if boundsMin and boundsMax then
			local clampedX = math.clamp(nextOffset.X, boundsMin.X, boundsMax.X)
			local clampedY = math.clamp(nextOffset.Y, boundsMin.Y, boundsMax.Y)
			if clampedX ~= nextOffset.X then
				panVelocity = Vector2.new(0, panVelocity.Y)
			end
			if clampedY ~= nextOffset.Y then
				panVelocity = Vector2.new(panVelocity.X, 0)
			end
			focalOffset = Vector2.new(clampedX, clampedY)
		else
			focalOffset = nextOffset
		end
		markCameraDirty()
	elseif not hasInput then
		panVelocity = Vector2.new(0, 0)
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
	DesignCamera.ZoomKeyboard(direction)
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
	local targetYawVelocity = keyboardRotateInput * CAMERA_ROTATE_KEYBOARD_SPEED
	local targetTiltVelocity = 0

	if isMouseRotating then
		local currentMouse = UserInputService:GetMouseLocation()
		if lastMouseRotatePosition then
			local delta = currentMouse - lastMouseRotatePosition
			if math.abs(delta.X) > CAMERA_ROTATE_DEADZONE then
				local mouseVelocity = delta.X * CAMERA_ROTATE_MOUSE_SENSITIVITY / math.max(dt, 1 / 240)
				targetYawVelocity += mouseVelocity
			end
			if math.abs(delta.Y) > CAMERA_TILT_DEADZONE then
				local mouseTiltVelocity = -delta.Y * CAMERA_TILT_MOUSE_SENSITIVITY / math.max(dt, 1 / 240)
				targetTiltVelocity += mouseTiltVelocity
			end
		end
		lastMouseRotatePosition = currentMouse
	end

	if touchRotateImpulse ~= 0 then
		targetYawVelocity += touchRotateImpulse / math.max(dt, 1 / 240)
		touchRotateImpulse = 0
	end

	local hasInput = math.abs(targetYawVelocity) > CAMERA_ROTATE_DEADZONE
	local rate = if hasInput then CAMERA_ROTATE_ACCELERATION else CAMERA_ROTATE_DAMPING
	local blend = 1 - math.exp(-rate * dt)
	yawVelocity += (targetYawVelocity - yawVelocity) * blend

	if math.abs(yawVelocity) > CAMERA_ROTATE_DEADZONE then
		yaw += yawVelocity * dt
		markCameraDirty()
	elseif not hasInput then
		yawVelocity = 0
	end

	local hasTiltInput = math.abs(targetTiltVelocity) > CAMERA_TILT_DEADZONE
	local tiltRate = if hasTiltInput then CAMERA_TILT_ACCELERATION else CAMERA_TILT_DAMPING
	local tiltBlend = 1 - math.exp(-tiltRate * dt)
	tiltVelocity += (targetTiltVelocity - tiltVelocity) * tiltBlend

	if math.abs(tiltVelocity) > CAMERA_TILT_DEADZONE then
		tilt = clampTilt(tilt + tiltVelocity * dt)
		markCameraDirty()
	elseif not hasTiltInput then
		tiltVelocity = 0
	end
end

local function resetInputState()
	cameraMoveVector = Vector3.new(0, 0, 0)
	cameraMoveRelativeToCamera = false
	panVelocity = Vector2.new(0, 0)
	zoomVelocity = 0
	yawVelocity = 0
	tiltVelocity = 0
	touchRotateImpulse = 0
	isMousePanning = false
	lastMousePanPosition = nil
	isMouseRotating = false
	lastMouseRotatePosition = nil
	keyboardZoomInHeld = false
	keyboardZoomOutHeld = false
	keyboardZoomInput = 0
	keyboardRotateLeftHeld = false
	keyboardRotateRightHeld = false
	keyboardRotateInput = 0
	gamepadZoomInput = 0
	gamepadZoomInValue = 0
	gamepadZoomOutValue = 0
	yaw = 0
	tilt = 0
	zoomAnchorScreen = nil
	touchPoints = {}
	touchCount = 0
	lastPinchDistance = nil
	lastPinchAngle = nil
end

local function wrapAngleDelta(value: number): number
	if value > math.pi then
		return value - math.pi * 2
	end
	if value < -math.pi then
		return value + math.pi * 2
	end
	return value
end

local function applyCameraTransform()
	local focus = getCameraFocus()
	local forward = getCameraForwardVector()
	local cameraPosition = focus - forward * distance
	camera.CFrame = CFrame.lookAt(cameraPosition, focus, getCameraUpVector())
end

function DesignCamera.GetCameraMode(): CameraMode
	return cameraMode
end

function DesignCamera.GetTopDownState(): TopDownState
	return {
		Position = Vector2.new(focalOffset.X, focalOffset.Y),
		Distance = distance,
		Yaw = yaw,
		Tilt = tilt,
		Height = focalHeight,
	} :: TopDownState
end

function DesignCamera.ApplyTopDownState(state: TopDownState)
	focalOffset = Vector2.new(state.Position.X, state.Position.Y)
	distance = clampDistance(state.Distance)
	yaw = state.Yaw
	tilt = clampTilt(state.Tilt)
	if state.Height ~= nil then
		focalHeight = state.Height
	end
	panVelocity = Vector2.new(0, 0)
	zoomVelocity = 0
	yawVelocity = 0
	tiltVelocity = 0
	clampFocalOffset()
	markCameraDirty()
end

function DesignCamera.SetCameraMode(mode: CameraMode, center: Vector3?, bound1: Vector3?, bound2: Vector3?, topDirection: Vector3?)
	local isSameMode = mode == cameraMode
	cameraMode = mode
	if not isSameMode then
		resetInputState()
	end

	local character = localPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil

	if mode == DesignCamera.CameraMode.Play then
		if not isSameMode then
			camera.CameraSubject = humanoid
			camera.CameraType = Enum.CameraType.Custom
			DesignCamera.SetZoomLimits(nil, nil)
		end
	elseif mode == DesignCamera.CameraMode.TopDown then
		if not isSameMode then
			camera.CameraSubject = nil
			camera.CameraType = Enum.CameraType.Scriptable
			local fallbackCenter = if humanoid and humanoid.RootPart then humanoid.RootPart.Position else Vector3.new(0, 0, 0)
			DesignCamera.SetCameraCenter(center or fallbackCenter)
			DesignCamera.SetCameraDistance(DEFAULT_CAMERA_DISTANCE)
			DesignCamera.SetCameraBounds(bound1, bound2)
		end
		if topDirection or not isSameMode then
			setCameraUpDirection(topDirection)
		end
	end

	markCameraDirty()
end

function DesignCamera.Focus(point: Vector3)
	setFocalPoint(point)
end

function DesignCamera.SetFocalPoint(point: Vector3)
	setFocalPoint(point)
end

function DesignCamera.SetFocalHeight(height: number)
	focalHeight = height
	markCameraDirty()
end

function DesignCamera.SetCameraCenter(center: Vector3)
	baseCenter = center
	focalOffset = Vector2.new(0, 0)
	focalHeight = center.Y
	clampFocalOffset()
	markCameraDirty()
end

function DesignCamera.SetCameraDistance(value: number)
	distance = clampDistance(value)
	zoomVelocity = 0
	markCameraDirty()
end

function DesignCamera.SetCameraBounds(bound1: Vector3?, bound2: Vector3?)
	if bound1 and bound2 then
		boundsMin = Vector2.new(math.min(bound1.X, bound2.X), math.min(bound1.Z, bound2.Z))
		boundsMax = Vector2.new(math.max(bound1.X, bound2.X), math.max(bound1.Z, bound2.Z))
	else
		boundsMin = nil
		boundsMax = nil
	end
	clampFocalOffset()
	markCameraDirty()
end

function DesignCamera.SetZoomLimits(minDistance: number?, maxDistance: number?)
	local minValue = minDistance or CAMERA_DISTANCE_MIN
	local maxValue = maxDistance or CAMERA_DISTANCE_MAX
	if maxValue < minValue then
		maxValue = minValue
	end
	distanceMin = minValue
	distanceMax = maxValue
	distance = clampDistance(distance)
	markCameraDirty()
end

function DesignCamera.SetInvertMouseWheel(value: boolean)
	invertMouseWheel = value == true
end

function DesignCamera.ZoomKeyboard(direction: number)
	keyboardZoomInput = math.clamp(direction, -1, 1)
	if keyboardZoomInput ~= 0 then
		zoomAnchorScreen = getViewportCenter()
	end
end

function DesignCamera.ZoomMouse(delta: number, screenPoint: Vector2)
	if delta == 0 then return end
	local appliedDelta = if invertMouseWheel then -delta else delta
	zoomVelocity += appliedDelta * CAMERA_ZOOM_SCROLL_STRENGTH
	zoomAnchorScreen = screenPoint
end

function DesignCamera.ZoomTouch(delta: number, screenPoint: Vector2)
	if delta == 0 then return end
	zoomVelocity += delta * CAMERA_ZOOM_TOUCH_STRENGTH
	zoomAnchorScreen = screenPoint
end

function DesignCamera.ZoomGamepad(value: number)
	if math.abs(value) < CAMERA_GAMEPAD_DEADZONE then
		gamepadZoomInput = 0
		return
	end
	gamepadZoomInput = math.clamp(value, -1, 1)
	zoomAnchorScreen = getViewportCenter()
end

local function cameraMoveFunction(_player: Player, moveVector: Vector3, relativeToCamera: boolean): nil
	if cameraMode ~= DesignCamera.CameraMode.TopDown then
		return moveFunction(_player, moveVector, relativeToCamera)
	end
	cameraMoveVector = moveVector
	cameraMoveRelativeToCamera = relativeToCamera
end
Controls.moveFunction = cameraMoveFunction

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then return end
	if cameraMode ~= DesignCamera.CameraMode.TopDown then return end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		isMousePanning = true
		lastMousePanPosition = UserInputService:GetMouseLocation()
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton3 then
		isMouseRotating = true
		lastMouseRotatePosition = UserInputService:GetMouseLocation()
		return
	end

	if input.KeyCode == Enum.KeyCode.Space then
		keyboardZoomInHeld = true
		updateKeyboardZoomInput()
		return
	end

	if input.KeyCode == Enum.KeyCode.C
		or input.KeyCode == Enum.KeyCode.LeftControl
		or input.KeyCode == Enum.KeyCode.RightControl then
		keyboardZoomOutHeld = true
		updateKeyboardZoomInput()
		return
	end

	if input.KeyCode == Enum.KeyCode.E then
		keyboardRotateLeftHeld = true
		updateKeyboardRotateInput()
		return
	end

	if input.KeyCode == Enum.KeyCode.Q then
		keyboardRotateRightHeld = true
		updateKeyboardRotateInput()
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then return end
	if cameraMode ~= DesignCamera.CameraMode.TopDown then return end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		isMousePanning = false
		lastMousePanPosition = nil
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton3 then
		isMouseRotating = false
		lastMouseRotatePosition = nil
		return
	end

	if input.KeyCode == Enum.KeyCode.Space then
		keyboardZoomInHeld = false
		updateKeyboardZoomInput()
		return
	end

	if input.KeyCode == Enum.KeyCode.C
		or input.KeyCode == Enum.KeyCode.LeftControl
		or input.KeyCode == Enum.KeyCode.RightControl then
		keyboardZoomOutHeld = false
		updateKeyboardZoomInput()
		return
	end

	if input.KeyCode == Enum.KeyCode.E then
		keyboardRotateLeftHeld = false
		updateKeyboardRotateInput()
		return
	end

	if input.KeyCode == Enum.KeyCode.Q then
		keyboardRotateRightHeld = false
		updateKeyboardRotateInput()
	end
end)

UserInputService.InputChanged:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then return end
	if cameraMode ~= DesignCamera.CameraMode.TopDown then return end
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		DesignCamera.ZoomMouse(input.Position.Z, Vector2.new(input.Position.X, input.Position.Y))
		return
	end

	if input.UserInputType == Enum.UserInputType.Gamepad1 then
		local triggerValue = input.Position.Z
		if input.KeyCode == Enum.KeyCode.ButtonL2 then
			gamepadZoomOutValue = triggerValue
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			gamepadZoomInValue = triggerValue
		end
		DesignCamera.ZoomGamepad(gamepadZoomInValue - gamepadZoomOutValue)
	end
end)

UserInputService.TouchStarted:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then return end
	if cameraMode ~= DesignCamera.CameraMode.TopDown then return end
	touchPoints[input] = Vector2.new(input.Position.X, input.Position.Y)
	touchCount += 1
	if touchCount < 2 then
		lastPinchDistance = nil
		lastPinchAngle = nil
	end
end)

UserInputService.TouchEnded:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then return end
	if cameraMode ~= DesignCamera.CameraMode.TopDown then return end
	if touchPoints[input] then
		touchPoints[input] = nil
		touchCount -= 1
	end
	if touchCount < 2 then
		lastPinchDistance = nil
		lastPinchAngle = nil
	end
end)

UserInputService.TouchMoved:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then return end
	if cameraMode ~= DesignCamera.CameraMode.TopDown then return end
	if not touchPoints[input] then return end
	touchPoints[input] = Vector2.new(input.Position.X, input.Position.Y)
	if touchCount < 2 then
		lastPinchDistance = nil
		lastPinchAngle = nil
		return
	end

	local points = {}
	for _, position in pairs(touchPoints) do
		table.insert(points, position)
	end
	if #points < 2 then
		lastPinchDistance = nil
		lastPinchAngle = nil
		return
	end

	local pointA = points[1]
	local pointB = points[2]
	local center = (pointA + pointB) * 0.5
	local distancePixels = (pointA - pointB).Magnitude
	local angle = math.atan2(pointB.Y - pointA.Y, pointB.X - pointA.X)

	if lastPinchDistance then
		local delta = distancePixels - lastPinchDistance
		DesignCamera.ZoomTouch(-delta, center)
	end
	if lastPinchAngle then
		local deltaAngle = wrapAngleDelta(angle - lastPinchAngle)
		touchRotateImpulse += -deltaAngle * CAMERA_ROTATE_TOUCH_SENSITIVITY
	end

	lastPinchDistance = distancePixels
	lastPinchAngle = angle
end)

local function onRenderStep(dt: number)
	if cameraMode ~= DesignCamera.CameraMode.TopDown then return end
	updateRotation(dt)
	updateZoom(dt)
	updatePan(dt)

	if not isCameraDirty then return end
	applyCameraTransform()
	isCameraDirty = false
end

RunService:BindToRenderStep("DesignCameraUpdate", Enum.RenderPriority.Camera.Value + 1, onRenderStep)

return DesignCamera
