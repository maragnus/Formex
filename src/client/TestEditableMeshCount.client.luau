--!strict
--[[
1) Create a blank EditableMesh via AssetService:CreateEditableMesh().
2) Build geometry: add vertices (AddVertex), then triangles (AddTriangle).
3) For each triangle, assign explicit attributes:
   - Normals: AddNormal + SetFaceNormals
   - UVs: AddUV + SetFaceUVs
   - Colors: AddColor + SetFaceColors
4) Remove unused IDs with EditableMesh:RemoveUnused().
5) Clone the mesh into FixedSize using AssetService:CreateEditableMeshAsync(Content.fromObject(editableMesh), { FixedSize = true }).
   Clients hit a strict EditableMesh memory budget; we observed a hard limit around 8 non-fixed-size meshes. FixedSize meshes are more memory-efficient.
6) Destroy the original EditableMesh once cloned using EditableMesh:Destroy()
7) Create a MeshPart from the fixed-size mesh via AssetService:CreateMeshPartAsync(Content.fromObject(fixedSizeMesh))
   MeshPart displays the EditableMesh in the world for visual testing.
]]

local Workspace = game:GetService("Workspace")
local AssetService = game:GetService("AssetService")

local meshCount = 0
local intervalSeconds = 1

local FACE_GRID = 4
local SIDE_SIZE = 4
local TRIANGLES_PER_FACE = FACE_GRID * FACE_GRID * 2
local TRIANGLES_PER_MESH = TRIANGLES_PER_FACE * 6

local function setFaceAttributes(
	editableMesh: EditableMesh,
	faceId: number,
	normal: Vector3,
	uv0: Vector2,
	uv1: Vector2,
	uv2: Vector2,
	color: Color3 
)
	local normalId = editableMesh:AddNormal(normal)
	local uvId0 = editableMesh:AddUV(uv0)
	local uvId1 = editableMesh:AddUV(uv1)
	local uvId2 = editableMesh:AddUV(uv2)
	local colorId0 = editableMesh:AddColor(color, 1)
	local colorId1 = editableMesh:AddColor(color, 1)
	local colorId2 = editableMesh:AddColor(color, 1)

	editableMesh:SetFaceNormals(faceId, { normalId, normalId, normalId })
	editableMesh:SetFaceUVs(faceId, { uvId0, uvId1, uvId2 })
	editableMesh:SetFaceColors(faceId, { colorId0, colorId1, colorId2 })
end

local function addGridFace(
	editableMesh: EditableMesh,
	origin: Vector3,
	uDir: Vector3,
	vDir: Vector3,
	normal: Vector3,
	faceIndex: number
): number
	local gridSize = FACE_GRID + 1
	local vertexIds = table.create(gridSize * gridSize)

	for v = 0, FACE_GRID do
		for u = 0, FACE_GRID do
			local index = (v * gridSize) + u + 1
			local uAlpha = u / FACE_GRID
			local vAlpha = v / FACE_GRID
			local position = origin + (uDir * uAlpha) + (vDir * vAlpha)
			vertexIds[index] = editableMesh:AddVertex(position)
		end
	end

	for v = 0, FACE_GRID - 1 do
		for u = 0, FACE_GRID - 1 do
			local v00 = vertexIds[(v * gridSize) + u + 1]
			local v10 = vertexIds[(v * gridSize) + u + 2]
			local v01 = vertexIds[((v + 1) * gridSize) + u + 1]
			local v11 = vertexIds[((v + 1) * gridSize) + u + 2]

			local u0 = u / FACE_GRID
			local v0 = v / FACE_GRID
			local u1 = (u + 1) / FACE_GRID
			local v1 = (v + 1) / FACE_GRID

			faceIndex += 1
			local faceId0 = editableMesh:AddTriangle(v00, v10, v11)
			local color0 = Color3.fromHSV((faceIndex - 1) / TRIANGLES_PER_MESH, 0.8, 1)
			setFaceAttributes(editableMesh, faceId0, normal, Vector2.new(u0, v0), Vector2.new(u1, v0), Vector2.new(u1, v1), color0)

			faceIndex += 1
			local faceId1 = editableMesh:AddTriangle(v00, v11, v01)
			local color1 = Color3.fromHSV((faceIndex - 1) / TRIANGLES_PER_MESH, 0.8, 1)
			setFaceAttributes(editableMesh, faceId1, normal, Vector2.new(u0, v0), Vector2.new(u1, v1), Vector2.new(u0, v1), color1)
		end
	end

	return faceIndex
end

local function createWorstCaseEditableMesh(): EditableMesh
	-- https://create.roblox.com/docs/reference/engine/classes/EditableMesh
	local editableMesh = AssetService:CreateEditableMesh()
	local faceIndex = 0
	local half = SIDE_SIZE / 2

	faceIndex = addGridFace(
		editableMesh,
		Vector3.new(-half, -half, half),
		Vector3.new(SIDE_SIZE, 0, 0),
		Vector3.new(0, SIDE_SIZE, 0),
		Vector3.new(0, 0, 1),
		faceIndex
	)
	faceIndex = addGridFace(
		editableMesh,
		Vector3.new(half, -half, -half),
		Vector3.new(-SIDE_SIZE, 0, 0),
		Vector3.new(0, SIDE_SIZE, 0),
		Vector3.new(0, 0, -1),
		faceIndex
	)
	faceIndex = addGridFace(
		editableMesh,
		Vector3.new(half, -half, half),
		Vector3.new(0, 0, -SIDE_SIZE),
		Vector3.new(0, SIDE_SIZE, 0),
		Vector3.new(1, 0, 0),
		faceIndex
	)
	faceIndex = addGridFace(
		editableMesh,
		Vector3.new(-half, -half, -half),
		Vector3.new(0, 0, SIDE_SIZE),
		Vector3.new(0, SIDE_SIZE, 0),
		Vector3.new(-1, 0, 0),
		faceIndex
	)
	faceIndex = addGridFace(
		editableMesh,
		Vector3.new(-half, half, half),
		Vector3.new(SIDE_SIZE, 0, 0),
		Vector3.new(0, 0, -SIDE_SIZE),
		Vector3.new(0, 1, 0),
		faceIndex
	)
	faceIndex = addGridFace(
		editableMesh,
		Vector3.new(-half, -half, -half),
		Vector3.new(SIDE_SIZE, 0, 0),
		Vector3.new(0, 0, SIDE_SIZE),
		Vector3.new(0, -1, 0),
		faceIndex
	)

	local removed = editableMesh:RemoveUnused()
	if #removed > 0 then
		print("Removed unused IDs:", #removed)
	end

	local fixedSizeMesh = AssetService:CreateEditableMeshAsync(
		Content.fromObject(editableMesh),
		{ FixedSize = true }
	)
	editableMesh:Destroy()

	return fixedSizeMesh
end

if false then
	task.spawn(function()
		while true do
			local attempt = meshCount + 1
			print("Creating EditableMeshPart:", attempt)

			local position = Vector3.new(math.random(-50, 50), 5, math.random(-50, 50))
			local editableMesh = createWorstCaseEditableMesh()
			local meshPart = AssetService:CreateMeshPartAsync(
				Content.fromObject(editableMesh),
				{ CollisionFidelity = Enum.CollisionFidelity.Hull }
			)
			meshPart.Position = position
			meshPart.Size = Vector3.new(5, 5, 5)
			meshPart.Parent = Workspace
			meshCount = attempt

			print("EditableMeshParts created:", meshCount)
			task.wait(intervalSeconds)
		end
	end)
end