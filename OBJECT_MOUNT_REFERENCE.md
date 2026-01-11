# Object Mount and Placement Reference

Read this any time you work on ObjectData positions/rotations, ObjectMount logic, prefab orientation, the plugin stages, or object placement/preview code.

## Prefab orientation (source of truth)
- Prefabs are authored in Studio on the plugin stage (floor + back wall).
- The stored model orientation is the base orientation. Preserve it at runtime.
- Runtime rotation is only a world-space yaw (Y axis) applied on top of the prefab's base orientation.

## Plugin stage reference (editor)
1. Stage pivot is the prefab root pivot position (no rotation).
2. StageBack is centered at `stageCenter + (0, 0, -half)` with thickness `WallThickness`.
3. StageFloor is centered at `stageCenter + (0, -half, 0)` with thickness `FloorThickness`.
4. The StageBack front face normal points toward +Z.
5. AutoPosition aligns prefab AABB to the stage planes:
   1) Floor/Surface: `minY` to floor plane, center X/Z to stage center.
   2) Ceiling: `maxY` to ceiling plane, center X/Z to stage center.
   3) Wall: `minZ` to back plane, center X/Y to stage center.
   4) Door: `minY` to floor plane, center X/Z to stage center.
   5) Window: center X/Y/Z to stage center.
6. For wall-mounted prefabs, stage axes are the reference: +X runs along the wall, +Z points away from the wall.

## Placement math (world)
- `boundsOffset = pivot:ToObjectSpace(boundsCFrame)` (CFrame).
- `baseRotation = boundsCFrame - boundsCFrame.Position` (rotation only).
- Wall yaw from side normal: `yaw = atan2(normal.X, normal.Z)` where `normal` is wall-side normal.
- Pivot placement:
  - `pivotCFrame = CFrame.new(center) * CFrame.Angles(0, yaw, 0) * baseRotation * CFrame.new(-boundsOffset)`

## AABB and Size
- Use `Model:GetBoundingBox()` to get the prefab AABB center and size.
- Always compute bounds from the prefab template model, not a live/rotated instance.
- `Prefab.Size` is the serialized AABB size from the plugin and is used for validation and collisions.
- The prefab template is the `Prefab` child model when present; use the same model for ghosts and final builds.
- Runtime containers must pivot using the prefab model's pivot (respect existing `PrimaryPart`; do not invent one).

## ObjectData field semantics
- `Position`
  - Floor/Ceiling/Surface: center of the prefab AABB in plot-local/world coordinates.
  - Wall/Window: `X` is distance from wall Start along wall direction, `Y` is elevation from floor to the bottom of the AABB, `Z` unused (0).
  - Door: `X` is distance from wall Start, `Y` ignored (0), `Z` unused (0).
- `Rotation`
  - Only `Rotation.Y` (degrees) is used.
  - Wall/Door/Window ignore Rotation; their yaw is derived from wall normal + Side.
- `Side`
  - Wall/Door/Window only.
  - "Front" or "Back" indicates which wall side the object faces.
- `Level`
  - Floor/Ceiling: picks the floor for height.
  - Wall/Door/Window: should match the wall's level.
- `WallId`
  - Required for Wall/Door/Window. Nil for other mounts.

## Floor and wall context
- `FloorData`:
  - `LevelIndex` + `RaiseHeight` determine top surface Y.
  - Ceiling surface is top minus thickness (`FoundationHeight` on level 1, else `InterfloorHeight`).
- `WallData`:
  - `Start`/`End` define wall direction (XZ plane).
  - Right vector is perpendicular to wall direction.
  - Wall side normal is `right` for Back, `-right` for Front.

## Placement helpers (Formex.Objects)
- `GetPrefabBounds(prefab, objectModel?)` -> `(boundsOffset, boundsSize)` from prefab template.
- `PlaceInWall(plotPart, boundsOffset, boundsSize, baseRotation, floorHeight, wall, side, elevation, distance)`:
  - Centers AABB within wall thickness at `distance` from Start and `elevation` from floor.
- `PlaceOnWall(plotPart, boundsOffset, boundsSize, baseRotation, floorHeight, wall, side, elevation, distance)`:
  - Offsets AABB out of the wall by `WallThickness / 2 + projectedHalfDepth`, where `projectedHalfDepth` is the OBB half-depth along the wall normal using the full orientation (`yaw * baseRotation`).
- `PlaceOnFloor(plotPart, boundsOffset, boundsSize, baseRotation, floorHeight, positionX, positionZ, rotationY)`:
  - AABB center sits on top of the floor.
- `PlaceOnCeiling(plotPart, boundsOffset, boundsSize, baseRotation, ceilingHeight, positionX, positionZ, rotationY)`:
  - AABB center hangs from the ceiling.
- `PlaceOnSurface(plotPart, boundsOffset, boundsSize, baseRotation, position, rotationY)`:
  - `position` is the AABB center.
- `GetObjectCFrame(objectData, prefab, plotPart, plotData)`:
  - Canonical placement for both ghosts and final builds. Use this everywhere.

## Rotation and yaw
- All player-driven rotation is world-space yaw (Y axis).
- Wall/Door/Window yaw is derived from wall normal and Side.
- Floor/Ceiling/Surface yaw uses `Rotation.Y` only.

## Validation rules (high level)
- Wall/Door/Window must fit within wall length; elevation must stay inside wall height.
- Floor/Ceiling require a floor at the target XZ.
- Surface requires an upward-facing normal.

## Best practices
- Always work in plot-local/world coordinates, not model local coordinates.
- Use prefab template bounds to avoid compounded rotations.
- Keep ObjectData semantics consistent with the rules above.
