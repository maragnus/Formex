# Formex Roblox Building Design System

Formex is a system for Roblox written in Luau that enabled Players to claim a predefined plot, design a building with floor, walls, ceilings, roof, windows, doors, and furniture.

Do not use `pcall`. While developing, errors need to propogate normally to find them.

## Requirements

- Luau requires that a `local function` is always defined before it's first usage. Make sure this is always the case when adding a new `local function` by resolving in one of these ways:
    - Make the function a `function module.*`
    - Move the usage below the declaration
    - Move the function and it's dependencies up

- World has predefined `Part` instances named "PlotPlaceholder" created in the `Workspace/Formex/Plots` Folder to define the **Plots** that a player can claim.
- Players can claim only one **Plot** on a server
- A **Plot** requires that the player selects a **Save Slot** before a building can be created.
- a **Plot** can define permissions for other **Players**, even including sharing owner status.
- A **Plot** starts off owning one segment. Players can upgrade their plot by adding segments and levels (building stories)
- A **Save Slot** defines the building on a plot. If no **Save** is loaded, then the PlotPlaceholder is empty and cannot be updating until a **Save** is loaded or new one is created.
- Implement with an emphasis on KISS and DRY principals. 
- Rely on specified type definitions (e.g. `export type` from `Formex.luau`) to **avoid unnecessary type checks and nil checks** unless the type explicitely indicates that it may be nil or unexpected types.
- Implement with an emphasis on KISS and DRY principals. 
- Rely on specified type definitions (e.g. `export type` from `Formex.luau`) to **avoid unnecessary type checks and nil checks** unless the type explicitely indicates that it may be nil or unexpected types.

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
                      Parts...
              Floors: Folder
                  {FloorId}: Model
                      Parts...
              Objects: Folder
                  {ObjectId}: Model
                      Object: Model
                          Parts...
                      Subtract: Model
                          Parts...
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

## Coding Standards

Avoid using "rbxassetid://" and URIs for assets, instead, use Asset ID via `Content.fromAssetId` and avoid unnecessary wrapper functions.
- `ImageLabel`:
`imageLabel.ImageContent = Content.fromAssetId(assetId: number)`
- `Texture`: `texture.ColorMapContent = Content.fromAssetId(assetId: number)` 

## Paint/Dropper Behavior

- Paint and Dropper are sub-modes only for Wall, Floor, and Object design modes.
- While in Paint or Dropper, primary clicks never select or start build actions; they only attempt paint or dropper.
- Dropper:
  - Walls: copy wall height plus the clicked side's split height, top/bottom material, and top/bottom color into wall paint settings.
  - Floors: copy raise height, floor/ceiling/foundation materials, and colors into floor paint settings.
  - After a successful drop, switch to Paint unless AltMode is holding Dropper.
- Paint:
  - Walls: apply paint settings to the clicked side only; apply height to the whole wall; never change paint settings.
  - Floors: apply paint settings to the clicked floor; never change paint settings.
- Wall side detection comes from the clicked surface (front/back parts or hit position); no wall-side state is stored.
- AltMode:
  - Holding Alt while in Normal or Paint forces Dropper mode.
  - While Alt is held, Dropper does not auto-switch to Paint.
  - On Alt release, return to the last sub-mode unless the dropper was used; if used, switch to Paint.
- Wall build settings are separate from wall paint settings; normal-mode edits update build/selection, not paint.

Always update `FormexSerialization.luau` when changing `Formex.PlotData`, `Formex.LevelData`, `Formex.WallData`, `Formex.FloorData`, `Formex.ObjectData`

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

## Design System (Client)
- `src/client/FormexDesign.luau`: entry point; manages design state, selection, and input dispatch; initializes the context and submodules.
- `src/client/FormexDesignContext.luau`: owns design enums/constants/shared types and stores shared dependencies/modules; submodules access each other through the context.
- `src/client/FormexDesignWalls.luau`: wall build/edit/paint/handle logic; reads wall appearance from model attributes.
- `src/client/FormexDesignFloors.luau`: floor build/edit/paint/handle logic; reads floor appearance from model attributes.
- `src/client/FormexDesignObjects.luau`: object design interactions (currently minimal).
- `src/client/FormexDesignHandles.luau`: shared handle creation, hover, and click behavior.
- `src/client/FormexDesignHighlights.lua`: selection and edge preview highlighting.

Design flow: `FormexDesign` initializes the context with Formex client/camera dependencies, then calls `Init()` on handles/highlights/walls/floors/objects. Submodules use `FormexDesignContext.Get()` for shared dependencies and for cross-module access, and all wall/floor materials/colors are sourced from model attributes.

## Communication
- `FormexClient` has methods that call methods named in `Formex.Function`
- `FormexServerFunctions` is the receiver for client functions and dispatches them to `FormexBuild`, `FormexServer`, etc
