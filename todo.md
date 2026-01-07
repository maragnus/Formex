`FormexFloors.luau` needs to be completely reworked. The current triangulation is broken needs to be redone with a new approach. Formex floors are made up of user-defined, simple polygons that need to be subdivided into axis-aligned, right triangles.

The ideal algorithm needs to be a naive vertical (X) cross-section pipeline that starts with a list of points, validates a simple polygon, divides into axis-aligned-leg right triangles that provided as a bunch of Wedge Parts contained in a Model. The goal is to subdivide the polygon into axis aligned segments at each unique point along the X axis so that creating right triangles is efficient. We need as few triangles as possible to represent the polygon.

- Points of the polygon are `Vector2int16`
- Floors use the Roblox `Model` as a container with multiple numbered `Part` instances with the `Shape` of "Wedge" to represent trianglular bodies.
- Floors are flat surfaces with a thickness depending on the levelIndex, `Formex.FoundationHeight` for Level 1, and `Formex.InterfloorHeight` at upper levels.
- Wedges are right triangles but not isoceles because their legs can independently be any length.
- Wedges must always be axis aligned so that textures align correctly.
- The Wedges must be in one of the four specified rotations to change which side the hypotenuse is on. Define these rotations as constants.
    (0, 180, 90) and (0, 0, -90) where `Texture.Side = Right` is on top
    (0, 0, -90) and (0, 180, -90) where `Texture.Side = Left` is on top
- `Texture` is added to the sides (representing the top as the floor and bottom as the ceiling) with `OffsetStudsU` and `OffsetStudsV` aligning the texture to the plot's grid so that it is constitent across the surface.
- and aligned Floors are a 2D plane of defined thickness created by the user of a Simple Polygon, no holes, no intersections.
- A floor is a `Model` with numbers `Part`
- Always reuse existing wedge parts when updating a floor. This is why we need item C below so that we do not Destroy and recreate the floor each change.

Implement with an emphasis on KISS and DRY principals. Rely on specified type definitions to avoid unnecessary type and nil checking unless the type explicitely indicates that it may be nil or other types.

Tasks:

A. Export a "polygon cleanup" method that is used before triangulation and when saving the floors. Do not update the live representation because users may be relying on points and winding during their editing.
1. Remove zero length walls (overlapping points)
2. Remove collinear vertices
3. Ensure counter clockwise winding

B. Export a "polygon is valid" method that is used client-side to show the user if their floor is valid, and is used to prevent triangulation for invalid polygons.
1. Contains between 3 to `Formex.MaxFloorPoints` points
2. Is a simple polygon (no overlaps/intersections with itself)
3. Has a positive area
4. Is within unlocked segments: `Formex.Plot.IsLineWithinUnlockedSegments`

C. Create `Formex.Floors.Edit` and update `Formex.Floors.Create` to call it so that parts can be reused.
1. Cleaning the polygon
2. If the polygon isn't valid, then provide a rectangular floor with the min/max bounds of the points.
3. Create the floor using the vertically slice the polygon for naive X cross-sections algorithm

D. Remove all outdated logic in `FormexFloors.luau`

---

Both Walls and Floors editors have this issue:
When a wall/floor is selected, clicking on empty space should clear selection.
When nothing is selected, it should start creating a new wall/floor.

However, right now, when a wall/floor is selected and the user clicks on empty space, it immediately starts creating a new wall/floor, when it should only deselected the object, and require a second click to start creating a new wall/floor.

---

Wall parts need to extend beyond their start and stop points by their half their thickness. This will make exterior angles feel like they join. This is likely in `Formex.Walls.Edit` in `FormexWalls.luau`

---

When clicking on a wall that is already selected, for some reason, it deselects that wall. Then clicking on the same wall again starts creating a new wall instead reselecting that wall. The same exact behavior exists for floors. Fix it.

---

Formex floors are made up of user-defined, simple polygons that need to be subdivided into axis-aligned, right triangles.

`FormexFloors.luau` currently uses a vertical (X-axis) cross-section algorithm to slice up the polygon into individual triangles but it's not good enough. It needs to be sliced into both vertical (X-axis) and horizontal (Y-axis) slices so that it is easy to create triangles to represent the polygon.

The goal is to subdivide the polygon into axis aligned slices at each unique point along the X axis and then the Y axis so that creating right triangles is simple and efficient. Every segment will be one or two triangles.

- Use the existing `Formex.Floors.CleanPolygon` to prepare the polygon for the algorithm.
- Points of the polygon are `Vector2int16`
- Floors use the Roblox `Model` as a container with multiple numbered `Part` instances with the `Shape` of "Wedge" to represent trianglular bodies.
- Floors are flat surfaces with a thickness depending on the levelIndex, `Formex.FoundationHeight` for Level 1, and `Formex.InterfloorHeight` at upper levels.
- Wedges are right triangles but not isoceles because their legs can independently be any length.
- Wedges must always be axis aligned so that textures align correctly.
- The Wedges must be in one of the four specified rotations to change which side the hypotenuse is on. Define these rotations as constants.
    (0, 180, 90) and (0, 0, -90) where `Texture.Side = Right` is on top
    (0, 0, -90) and (0, 180, -90) where `Texture.Side = Left` is on top
- `Texture` is added to the sides (representing the top as the floor and bottom as the ceiling) with `OffsetStudsU` and `OffsetStudsV` set to align the texture so that it is constitent across the surface.
- Always reuse existing wedge parts when updating a floor. This is why we need item C below so that we do not Destroy and recreate the floor each change.

Implement with an emphasis on KISS and DRY principals. Rely on specified type definitions to avoid unnecessary type and nil checking unless the type explicitely indicates that it may be nil or other types.

Tasks:

A. Update `Formex.Floors.Edit` with these steps:
1. Cleaning the polygon
2. If the polygon isn't valid, then provide a rectangular floor with the min/max bounds of the points.
3. Create the floor using the vertically slice the polygon for naive X cross-sections algorithm
4. Prevent calculating or creating more than `MAX_TRIANGLES` triangles

B. Remove all outdated logic in `FormexFloors.luau`


A. Export a "polygon cleanup" method that is used before triangulation and when saving the floors. Do not update the live representation because users may be relying on points and winding during their editing.
1. Remove zero length walls (overlapping points)
2. Remove collinear vertices
3. Ensure counter clockwise winding

B. Export a "polygon is valid" method that is used client-side to show the user if their floor is valid, and is used to prevent triangulation for invalid polygons.
1. Contains between 3 to `Formex.MaxFloorPoints` points
2. Is a simple polygon (no overlaps/intersections with itself)
3. Has a positive area
4. Is within unlocked segments: `Formex.Plot.IsLineWithinUnlockedSegments`

C. Create `Formex.Floors.Edit` and update `Formex.Floors.Create` to call it so that parts can be reused.
1. Cleaning the polygon
2. If the polygon isn't valid, then provide a rectangular floor with the min/max bounds of the points.
3. Create the floor using the vertically slice the polygon for naive X cross-sections algorithm

D. Remove all outdated logic in `FormexFloors.luau`

---

The algorithm is choosing the wrong rotations for the wedges. Here's a chart to help.

Part rotation, Texture.Side for top surface (floor), direction of the hyponenuse:
(0, 180, 90), Right, (1, 0, 1)
(0, 0, 90), Right, (-1, 0, -1)
(0, 0, -90), Left, (1, 0, -1)
(0, -180, -90), Left, (-1, 0, 1)

Create a table at the top of `FormexFloors.luau` to describe how each of the four orientations, better than how I did it above.

Use the table and update the wedges that are created.

---

I need to overhaul how `FormexFloors.lua` represents floors.

Currently, it uses a `Model` with a collection of Wedge-shaped `Part` children to represent the geometry. It also uses `Material` for foundation, `Texture` for floor (top) surface, and `Texture` for ceiling (bottom) surface.

The new implementation needs to continue to use a `Model` container and but with `MeshPart` and `EditableMesh`. And that's a pretty big overhault.

- `EditableMesh` doesn't synchronize over the network, so they will have to be created both server-side and client-side.
- There's already a "Points" attribute on the `Model` for the floor that lists the points as a string.
- We need to subscribe to it via `Model:GetAttributeChangedSignal("Points"):Connect(function() ... end)` to update the client-side mesh.
  - Since the client may also be editing the mesh for a client-side prediction, if they happen to be editing it, it should check to make sure the points have actually changed before rerendering the meshes.
  - We already have `Formex.EncodeFloorPoints` and `Formex.DecodeFloorPoints`
  - Client-side Plot registration in `FormexClient.RegisterPlot` can monitor ChildAdded and ChildRemoved to identify floor changes and subscribe to their attributes.
  - We ALWAYS need to Destroy the `EditableMesh` any time we update a mesh or remove the Floor.
- We need up to three `MeshPart` per floor's `Model`: Floor (top) surface, Foundation (exterior) surface, Ceiling (bottom) surface
  - Ceiling doesn't apply to Level 1 floors, only above floors.
  - These MeshParts should use Material/MaterialVariant instead of Texture. This means that `Formex.FloorMaterials` is obsolete and we'll be using `Formex.WallMaterials` for everthing.

------------------ DONE ------------------

---

Add support for `Formex.FloorData.RaiseHeight` to allow creating raised floors and stairs
- Sidebar needs a slider, the min is 0 (normal floor height) and the max is `Formex.LevelHeight - Formex.InterfloorHeight`, it should increment in steps of `Formex.Grid`
- The `RaiseHeight` in `FormexFloors.luau` is additional height of the floor above the surface. It should also increase the floor thickness.

---

Two changes:

Move Delete handle for walls to be centered under the bottom bounding box of the wall, so it appears in a consistent location regardless of the orientation of the wall.

Add a Flip handle for walls.
- Clicking it flips the wall around (swaps Start and End).
- Use the `Formex.Icons.DirectionIndicator` (which is an arrow pointing up).
- Position it facing center and offset from the center of the wall.
- Rotate it so the arrow is facing outwards from the front of the wall to indicate the direction of the wall.
- When clicking the indicator

---

Whenever a change to a wall or floor is made, a snapshot needs to be created. When a snapshot is created, Undo, or Redo occurs, update the "CanUndo", "CanRedo" attributes on the Plot. This will allow the user to know if they can undo or redo.

---

Add a "Select" option to `DesignMode`. 
- Use the `Formex.Icons.DesignSelect` icon in the sidebar.
- In select mode, the user can select floors, walls, and objects.
- The object will be selected and design mode will be updated respectively.
- Clicking on nothing will perform no action.
- The default DesignMode when entering DesignMode should now be Select

---

Make sure that `FormexDesignFloors.luau` accounts for `Formex.MaxFloorPoints`
- When at the limit for points on the floor, remove all of the Midpoint handles that add vertices.

---

When dragging move handles in `FormexDesign.luau`, `FormexDesignFloors.luau`, `FormexDesignWalls.luau`, the raycast must only hit the segment grids.
- FilterType: Include
- FilterDescendantsInstances: Grid segments
- IgnoreWater: true
- CollisionGroup: not applicable
- RespectCanCollide: false

This will not apply to future `FormexDesignObjects.luau` implementation so make sure it's specific to Floors and Walls.
Objects will use a different mode that includes walls, floor, and grid so it's best to use a collision group.