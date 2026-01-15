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

4. Always update `src/shared/Serialization.luau` when changing serializable properties on `Formex.LevelData`, `Formex.WallData`, `Formex.FloorData`, `Formex.ObjectData` data type definitions

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
    - There will NEVER be unexpected objects that do not match this hierarchy, you are free to make assumptions, such as `wallPart:ClearAllChildren()` to clear all wall parts.
- Walls are divided into front-side and back-side Block-shaped parts, and also top and bottom parts if the wall has a split height.
  - Walls use Material/MaterialVariant and Color for design
  - Wall is total thickness of `Formex.WallThickness` and maximum height of `Formex.LevelHeight`, but is user adjustable
- Floors are simple polygons made up of Wedge-shaped parts turned on their side to create axis-aligned right triangles.
  - Floors use `Texture` children with `Texture.Side` to represent color and design of their floor (top) and ceiling (bottom)
  - Floors also use Material/MaterialVariant and Color for design of their sides
  - Floor and Ceilings are a grid of `Formex.LayoutGrid` size, and `Formex.FoundationHeight` for Level 1, and `Formex.InterfloorHeight` at upper levels.
  - Floors uses a complex algorithm to triangulate the polygon into a collection axis-aligned right triangles.
- Shared module `src/shared/init.luau` (ReplicatedStorage/Formex) provides the shared interface to create wall/floor parts for server-side geometry and client-side ghosts for designing as well as confirm validity.

## Server/Client PlotData Sync (Attributes)

- Server-side rendering writes the authoritative attributes onto each **Model** (shared builders in `src/shared/Walls.luau`, `src/shared/Floors.luau`, and `src/shared/Objects.luau`).
- Clients maintain a local `PlotData` copy in `src/client/Client.luau` by watching the plot hierarchy (`Plots/{level}/Walls|Floors|Objects`) and subscribing to model attribute changes.
- Clients never infer wall/floor/object data from Part properties; always read `model:GetAttribute(name) or default`.
- Floors trigger client mesh updates on attribute changes (`Formex.Floors.RenderClientMeshes` for geometry, `Formex.Floors.ApplyClientMaterials` for appearance).
- `FormexClient` emits `FormexEvents` (`PlotPartChanged`) so selection/UI can refresh immediately.
- Client selection/lookup by id must use `PlotData` references (`Levels[*].Walls/Floors/Objects`) and not traverse the Workspace hierarchy as a fallback.
- When applying client-side predictions, update model attributes via the shared builders (`Formex.Walls.Edit`, `Formex.Floors.Edit`) so `PlotData` stays in sync.
- If a client-side predicted model is created, assign the server-returned id, then replace it once the authoritative model appears (keep this reconciliation logic centralized, e.g. in `src/client/Design/Context.luau`).

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
- `src/client/Design/init.luau` subscribes to player `CanUndo`/`CanRedo` and updates Design State.
- `FormexSidebar.client.luau` reads `DesignState.CanUndo`/`CanRedo` to enable/disable undo/redo UI.

## Changing PlotData Types

When updating `PlotData`, `LevelData`, `WallData`, `FloorData`, or `ObjectData`:
- Update type definitions in `src/shared/init.luau`.
- Update save/load and versioning in `src/shared/Serialization.luau`.
- Update server render/attribute writers (`src/shared/Walls.luau`, `src/shared/Floors.luau`, `src/shared/Objects.luau`) so Models expose the new attributes.
- Update client watchers in `src/client/Client.luau` to read/store the new attributes and subscribe to changes.
- Update selection/UX readers in `src/client/Design` (`init.luau`, `Walls.luau`, `Floors.luau`, `Objects.luau`, `Rooms.luau`).

## File Map (refactored)

### Shared (ReplicatedStorage/Formex)
- `src/shared/init.luau`: Formex root; constants, enums, type defs, network function names, and exported module tables.
- `src/shared/Data.luau`: material catalog + UI icon ids.
- `src/shared/Buffer.luau`: base64 buffer reader/writer used by serialization.
- `src/shared/Serialization.luau`: versioned save/load of PlotData (walls/floors/objects) using Buffer; clamps/snap values and NextId.
- `src/shared/Util.luau`: helpers (EnsureFolder, DeepClone, ApplyMaterial, encode/decode floor points).
- `src/shared/Math.luau`: line/polygon intersection helpers.
- `src/shared/Plot.luau`: segment grid math (bitmasks, bounds, level offsets, unlocked checks).
- `src/shared/Poly.luau`: polygon/segment graph utilities for tracing faces and intersection tests.
- `src/shared/Walls.luau`: wall validation plus create/edit geometry + attributes; split helper.
- `src/shared/Floors.luau`: polygon cleaning/triangulation, validation, mesh create/edit, client mesh/material rendering.
- `src/shared/Objects.luau`: prefab lookup (ReplicatedStorage/Workspace), mount placement math, design encode/decode, object create/edit/carving.
- `src/shared/Rooms.luau`: rebuilds room adjacency/metadata from wall/floor geometry with caching.
- `src/shared/Transaction.luau`: copy-on-write transaction validation/apply for walls/floors/objects; returns merge info, selection snapshot, and NextId updates.

### Server (ServerScriptService/Formex)
- `src/server/init.server.luau`: bootstraps plot registration via System.
- `src/server/Server.luau`: loads shared Formex modules server-side.
- `src/server/System.luau`: authoritative plot registry and state (claim/unassign, attribute sync, DataStore save/load queue, level placeholders, render + wall carve refresh).
- `src/server/Plot.luau`: player plot actions (claim/release, rename, save list/load/delete/new, permissions, segment unlock) delegating to System.
- `src/server/Build.luau`: applies build transactions with shared Transaction; spawns/edits models, queues carving, tracks undo/redo per player, updates CanUndo/CanRedo.
- `src/server/ServerFunctions.server.luau`: `FormexFunctions` RemoteFunction dispatcher wiring `Formex.Function.*` to Plot/Build.
- `src/server/Plugin/FormexPlugin/*`: Studio prefab toolkit (workspace/ReplicatedStorage prefab roots, metadata read/write, sizing, staging/layout, grid textures, viewport dialogs, UI).

### Client (StarterPlayerScripts/Formex)
- `src/client/init.client.luau`: bootstrap; tracks player plot attributes and registers plots with Client.
- `src/client/Client.luau`: client PlotData mirror and event hub; watches plot folders/attributes, runs predictions, wraps remote calls (plot actions, build transactions, undo/redo), emits `FormexEvents`.
- `src/client/DesignCamera.luau`: camera controller for play/top-down/expand design views.
- `src/client/FormexUI.luau`: UI component library/dialog helpers (alerts, rows, fields).
- `src/client/FormexPrompts.luau`: plot/save/permission prompts using FormexUI.
- `src/client/FormexPrefabCatalog.luau`: prefab browser UI + viewport previews.
- `src/client/Gui/FormexSidebar.client.luau`: sidebar UX for design/plot actions (tools, materials, undo/redo), with `src/client/Gui/FormexFooter.client.luau` status bar and `src/client/Gui/FormexTips.client.lua` tips overlay.
- `src/client/BlurController.luau`: depth-of-field blur helper for UI backdrops.
- `src/client/TestEditableMeshCount.client.luau`: debug helper for editable mesh counts.
- `src/client/Design/init.luau`: design-mode orchestrator (input routing, ghosting, selection, state, overlays) wiring Handles/Highlights/Context + FormexClient.
- `src/client/Design/Context.luau`: shared enums/constants/state accessors for design modules (design mode, paint/build settings, selection snapshot).
- `src/client/Design/Handles.luau`: interactive 3D handles + busy spinner management.
- `src/client/Design/Highlights.lua`: selection/highlight/edge previews and room overlays.
- `src/client/Design/Floors.luau`: floor edit hub (handles, paint/dropper) coordinating Manual vs Autofill flows.
- `src/client/Design/FloorsManual.luau`: manual polygon placement/edit handles for floors.
- `src/client/Design/FloorsAutofill.luau`: room-tracing autofill polygon builder using Poly/wall/floor segments.
- `src/client/Design/Walls.luau`: wall placement/edit/paint and wall-handle logic.
- `src/client/Design/Objects.luau`: object placement/rotation/paint with ghost previews and build transactions.
- `src/client/Design/Rooms.luau`: room selection overlays plus wall/point move/merge handles tied to rooms.

### Networking
- `ReplicatedStorage/FormexFunctions` RemoteFunction uses names in `Formex.Function.*`; client wrappers live in `src/client/Client.luau` and server routing in `src/server/ServerFunctions.server.luau`.

## Large Changes Check-In
- For large, multi-file changes, pause to confirm assumptions and present a brief proposed approach before implementing.
- Use short clarification questions when requirements are ambiguous or likely to affect architecture.
