--!strict

local ViewportUtils = {}

function ViewportUtils.ComputeCameraCFrame(size: Vector3): CFrame
	local maxSize = math.max(size.X, size.Y, size.Z)
	local fov = math.rad(35)
	local distance = (maxSize * 0.75) / math.tan(fov / 2)
	distance = math.max(distance, maxSize * 1.6)

	local yaw = math.rad(45)
	local pitch = math.rad(18)
	local offset = Vector3.new(
		math.sin(yaw) * math.cos(pitch),
		math.sin(pitch),
		math.cos(yaw) * math.cos(pitch)
	) * distance

	return CFrame.new(offset, Vector3.new(0, 0, 0))
end

return ViewportUtils
