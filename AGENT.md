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

## Coding Standards

Avoid using "rbxassetid://" and URIs for assets, instead, use Asset ID via `Content.fromAssetId` and avoid unnecessary wrapper functions.
- `ImageLabel`:
`imageLabel.ImageContent = Content.fromAssetId(assetId: number)`
- `Texture`: `texture.ColorMapContent = Content.fromAssetId(assetId: number)` 

Always update `FormexSerialization.luau` when changing `Formex.PlotData`, `Formex.LevelData`, `Formex.WallData`, `Formex.FloorData`, `Formex.ObjectData`

## Shared Modules
- `Formex.luau` is the shared interface between client and server, contains constants and utilities, hub of related modules
  - `Formex.Walls` is provided by `FormexWalls.luau` for created, updating, and validating walls
  - `Formex.Floors` is provided by `FormexFloors.luau` for created, updating, and validating floors
  - `Formex.Plot` is provided by `FormexPlot.luau` for maintaining the plot itself
  - `Formex.Serialization` is provided by `FormexSerialization.luau` is responsible for the save format of `Formex.PlotData`

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
