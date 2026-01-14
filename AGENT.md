# Formex Roblox Building Design System

Formex is a system for Roblox written in Luau that enabled Players to claim a predefined plot, design a building with floor, walls, ceilings, roof, windows, doors, and furniture.

Do not use `pcall`. While developing, errors need to propogate normally to find them.

## Related Documents

Always check these related documents with reviewing or updating these systems:

- Read `OBJECT_MOUNT_REFERENCE.md` any time you touch ObjectData positions/rotations, ObjectMount rules, prefab orientation, or plugin/placement logic.
- Read `DESIGN_MODES.md` before making changes to design modes, tools, paint/dropper logic, handles, selection, sidebar behavior, or any `FormexDesign*.luau` files.

## Coding Standards

0. Rule zero is don't be dumb. It is critical that you're not dumb or doing dumb things.

1. The first line of every .luau module must be: --!strict

2. Avoid using "rbxassetid://" and URIs for assets, instead, use Asset ID via `Content.fromAssetId` and avoid unnecessary wrapper functions.
    - `ImageLabel`:
    `imageLabel.ImageContent = Content.fromAssetId(assetId: number)`
    - `Texture`: `texture.ColorMapContent = Content.fromAssetId(assetId: number)` 

3. Simple exits should always be contained to one line, for example:
    - `if not plotInfo or not plotInfo.IsValid then return true end`
    - `if not Walls[wallId] then contiue end`

4. Always update `FormexSerialization.luau` when changing serializable properties on `Formex.LevelData`, `Formex.WallData`, `Formex.FloorData`, `Formex.ObjectData` data type definitions

5. Luau requires that a `local function` is always defined before it's first usage. Make sure this is always the case when adding a new `local function` by resolving in one of these ways:
    - Make the function a `function module.*`
    - Move the usage below the declaration
    - Move the function and it's dependencies up

6. Null-checking a non-nullable property or function argument is dumb, don't do that.
    Rely on specified type definitions to **avoid unnecessary type checks and nil checks** unless the type explicitely indicates that it may be nil or unexpected types.
    - Always assume with 100% certainty that non-nullable types are strictly adhered to and DO NOT check them for nil. It is imperitive that we always get nil reference errors to find root cause issues.
    `function example(value: string?)` value might be a nil, you can use checks
    `function example(value: string)` value WILL NEVER BE nil, you MUST NOT check it for nil
    In summary, NEVER EVER CHECK FOR nil IF THE TYPE INDICATES THAT IT SHOULD NOT BE nil.

7. When you are trying to diagnose an error with the user, the first step is to remove ALL unnecessary nil checks first to see if this will uncover the error. Also, remove any fallbacks for values that should not be nil, because these also cover up root cause.

8. When you are trying to diagnose an error with the user, if the issue isn't completely obvious, do not fuck around and find out with random changes, adding fallback behavior, or nil checks. Instead, add some useful `print()` statements and ask the user to test the behavior and see if you can triangulate it. We are always trying to find the root cause, not bandaid the issue.

Note that the values in `Formex.LevelData` are assumed to NEVER be nil, never check them for nil, never treat them as nullable 
These are BAD PRACTICE, DO NOT DO IT: `if levelData.Walls then` or `levelData.Walls or {}` or `levelData.Part or PlotData:WaitForChild(tostring(levelData.LevelIndex))`

```luau
export type LevelData = {
	-- Serialized properties
	LevelIndex: number,
	Walls: {[number]: WallData}, -- {[WallId]: WallData}
	Floors: {[number]: FloorData}, -- {[FloorId]: FloorData}
	Objects: {[number]: ObjectData}, -- {[ObjectId]: ObjectData}
	Rooms: {[number]: RoomData}, -- {[RoomId]: RoomData}

	-- Runtime properties
	Part: Part,
	WallFolder: Folder,
	FloorFolder: Folder,
	ObjectFolder: Folder,
}
```

7. When creating a table of a type that has non-nullable properties, you are REQUIRED to populate the required fields.

8. Luau type casting for assigments is not valid syntax `(value :: any).Levels = ...` just use `value.Levels = ...` instead.

## Requirements

- Wall, floor, and room XY snapping must use `Formex.LayoutGridSize`; only object placement uses `Formex.ObjectGridSize` / `Formex.GridSize`.
- World has predefined `Part` instances named "PlotPlaceholder" created in the `Workspace/Formex/Plots` Folder to define the **Plots** that a player can claim.
- Players can claim only one **Plot** on a server
- A **Plot** requires that the player selects a **Save Slot** before a building can be created.
- a **Plot** can define permissions for other **Players**, even including sharing owner status.
- A **Plot** starts off owning one segment. Players can upgrade their plot by adding segments and levels (building stories)
- A **Save Slot** defines the building on a plot. If no **Save** is loaded, then the PlotPlaceholder is empty and cannot be updating until a **Save** is loaded or new one is created.
- Implement with an emphasis on KISS and DRY principals. 
- When handles must be disabled while waiting for server confirmation, wrap the call with `Handles.SetBusy(true)` and `Handles.SetBusy(false)` to show the spinner.

## Ideal flow

1. Player joins server and explores the world
2. Player finds an available **Plot** and chooses to claim it
3. Player must choose from their existing **Save Slot** options or "Create a new **Save Slot**"
4. Server loads in that **Save Slot** to the **Plot**
5. Server autosaves each **Plot** according to Autosave rules
6. Player disconnects and their claimed **Plot** is saved and unclaimed, clearing it entirely.

## Plot Permissions

A **Plot** has a permissions list of other players that can interact with it. The owner of a plot always has the **Owner** permission and cannot be changed. Anyone with the **Owner** permission can update the permissions of other players.

- Owner: Rename the plot, Update permissions, Purchase upgrades

## Workspace Structure

- A **Plot** has parts organized as follows: 
  Workspace\Formex: Folder\Plots: Folder
      PlotPlaceholder: Part
          {levelId: number}: Part
              Walls: Folder
                  {WallId}: Model
                      FrontBottom: Part
                      FrontTop: Part (optional)
                      BackBottom: Part
                      BackTop: Part (optional)
              Floors: Folder
                  {FloorId}: Model
                      Floor: MeshPart
                      Foundation: MeshPart
                      Ceiling: MeshPart (optional)
                      Floor (Client): MeshPart (client-side)
                      Foundation (Client): MeshPart (client-side)
                      Ceiling (Client): MeshPart  (client-side, optional)
              Objects: Folder
                  {ObjectId}: Model
                      Object: Model
                          Parts...
                      Subtract: Model (optional)
                          Parts...
- Formex entirely owns and maintains this exact hierarchy. It can be safely assumed that this will be strictly adhered to at all times.
- Walls are divided into front-side and back-side Block-shaped parts, and also top and bottom parts if the wall has a split height.
  - Walls use Material/MaterialVariant and Color for design
  - Wall is total thickness of `Formex.WallThickness` and maximum height of `Formex.LevelHeight`, but is user adjustable
- Floors are simple polygons made up of Wedge-shaped parts turned on their side to create axis-aligned right triangles.
  - Floors use `Texture` children with `Texture.Side` to represent color and design of their floor (top) and ceiling (bottom)
  - Floors also use Material/MaterialVariant and Color for design of their sides
  - Floor and Ceilings are a grid of `Formex.LayoutGrid` size, and `Formex.FoundationHeight` for Level 1, and `Formex.InterfloorHeight` at upper levels.
  - Floors uses a complex algorithm to triangulate the polygon into a collection axis-aligned right triangles.
- Shared module `Formex.luau` provides a shared interface to create Wall and Floor parts for server-side geometry and client-side ghosts for designing as well as confirm validity.

## Server/Client PlotData Sync (Attributes)

- Server-side rendering writes the authoritative attributes onto each **Model** (`FormexWalls.luau`, `FormexFloors.luau`, and object builders).
- Clients maintain a local `PlotData` copy in `FormexClient.luau` by watching the plot hierarchy (`Plots/{level}/Walls|Floors|Objects`) and subscribing to model attribute changes.
- Clients never infer wall/floor/object data from Part properties; always read `model:GetAttribute(name) or default`.
- Floors trigger client mesh updates on attribute changes (`Formex.Floors.RenderClientMeshes` for geometry, `Formex.Floors.ApplyClientMaterials` for appearance).
- `FormexClient` emits `FormexEvents` (`PlotPartChanged`) so selection/UI can refresh immediately.
- Client selection/lookup by id must use `PlotData` references (`Levels[*].Walls/Floors/Objects`) and not traverse the Workspace hierarchy as a fallback.
- When applying client-side predictions, update model attributes via the shared builders (`Formex.Walls.Edit`, `Formex.Floors.Edit`) so `PlotData` stays in sync.
- If a client-side predicted model is created, assign the server-returned id, then replace it once the authoritative model appears (keep this reconciliation logic centralized, e.g. in `FormexDesignContext`).

## Multiplayer Undo/Redo System

- Each plot maintains an in-memory undo/redo history per player, created on the player’s first edit transaction for that plot.
- Undo/redo history never persists to saves/serialization and remains in memory even after a player disconnects.
- `Formex.MaxUndoQueueSize` caps the undo depth (32). When exceeded, drop the oldest undo entry.
- Any non-undo/redo change clears the redo queue for that player/plot.
- Undo pushes the current state into the redo queue. Redo pushes the current state into the undo queue.
- Transactions store the full snapshot of the plot state before a change, plus selection metadata.
- Selection metadata includes the edit mode and the selected item (type + level + id) at snapshot time.
- Undo/redo should restore the snapshot and reselect the stored item, switching design modes accordingly.
- `CanUndo`/`CanRedo` are player attributes (not plot attributes). Update them when the player’s `CurrentPlotId` changes and after any history mutation.
- `FormexDesign.luau` subscribes to player `CanUndo`/`CanRedo` and updates Design State.
- `FormexSidebar.client.luau` reads `DesignState.CanUndo`/`CanRedo` to enable/disable undo/redo UI.

## Changing PlotData Types

When updating `PlotData`, `LevelData`, `WallData`, `FloorData`, or `ObjectData`:
- Update type definitions in `src/shared/Formex.luau`.
- Update save/load and versioning in `src/shared/FormexSerialization.luau`.
- Update server render/attribute writers (`src/shared/FormexWalls.luau`, `src/shared/FormexFloors.luau`, plus any object builders) so Models expose the new attributes.
- Update client watchers in `src/client/FormexClient.luau` to read/store the new attributes and subscribe to changes.
- Update selection/UX readers (`src/client/FormexDesign.luau`, `src/client/FormexDesignWalls.luau`, `src/client/FormexDesignFloors.luau`).

## Shared Modules
- `Formex.luau` is the shared interface between client and server, contains constants and utilities, hub of related modules
  - `Formex.Walls` is provided by `FormexWalls.luau` for created, updating, and validating walls
  - `Formex.Floors` is provided by `FormexFloors.luau` for created, updating, and validating floors
  - `Formex.Plot` is provided by `FormexPlot.luau` for maintaining the plot itself
  - `Formex.Serialization` is provided by `FormexSerialization.luau` is responsible for the save format of `Formex.PlotData`

## Modules
- `Formex` is the shared interface between client and server

### Server-side
- `FormexSystem`: manage core plot ownership and common systems
- `FormexPlot`: handles client functions related to plot management
- `FormexBuild`: handles client functions related to building and designing

### Client-side
- `FormexCamera`: manages camera modes
- `FormexClient`: core management for the Formex state
- `FormexDesign`: design mode functionality (floors, walls, objects) and all the 3D design tools
- `FormexSidebar`: UI for the sidebar menu
- `FormexPrompts`: UI popups
- `FormexUI`: custom UI component library

## Communication
- `FormexClient` has methods that call methods named in `Formex.Function`
- `FormexServerFunctions` is the receiver for client functions and dispatches them to `FormexBuild`, `FormexServer`, etc

## Large Changes Check-In
- For large, multi-file changes, pause to confirm assumptions and present a brief proposed approach before implementing.
- Use short clarification questions when requirements are ambiguous or likely to affect architecture.
