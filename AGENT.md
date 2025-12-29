# Formex Roblox Building Design System

Formex is a system for Roblox written in Luau that enabled Players to claim a predefined plot, design a building with floor, walls, ceilings, roof, windows, doors, and furniture.

Do not use `pcall`. While developing, errors need to propogate normally to find them.

## Requirements

- World has predefined `Part` instances named "PlotPlaceholder" created in the `Workspace/Formex/Plots` Folder to define the **Plots** that a player can claim.
- Players can claim only one **Plot** on a server
- A **Plot** requires that the player selects a **Save Slot** before a building can be created.
- a **Plot** can define permissions for other **Players**, even including sharing owner status.
- A **Plot** starts off owning one segment. Players can upgrade their plot by adding segments and levels (building stories)
- A **Save Slot** defines the building on a plot. If no **Save** is loaded, then the PlotPlaceholder is empty and cannot be updating until a **Save** is loaded or new one is created.

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
                Walls (Folder)
                    {WallId}: Part
                Floors (Folder)
                    {FloorId}: Part
                Ceilings (Folder)
                    {CeilingId}: Part
                Objects: Folder
                    {ObjectId}: Part
- Wall and Floor/Ceiling parts
  - Use `Texture` children with `Texture.Side` to represent `MaterialInfo`
- Wall is a `Part` with a thickness of `Formex.WallThickness` and height of `Formex.LevelHeight`
  - Wall has `FrontMaterial`, `BackMaterial`, `StartMaterial`, and `EndMaterial` that represents `Formex.Materials` used on the sides and end caps of the wall.
  - Top of walls uses `Formex.WallTopMaterial`
- Floor and Ceilings are a grid of `Formex.LayoutGrid` size, and `Formex.FoundationHeight` for Level 1, and `Formex.InterfloorHeight` at upper levels.
- Floors and ceilings are complicated
    - One `Part` represents both the floor and the ceiling of the adjacent level.
    - If a floor is added, it also adds the respective ceiling. Likewise for adding a ceiling. Except on the Level 1 and level `Formex.MaxPlotSize.Levels`.
- Shared `Formex` provides a shared interface to create Wall and Floor/Ceiling parts for server-side geometry and client-side ghosts for designing.

## Optimizations

**Problem:** A 100% full building can have 9,216 Floor/Ceiling parts
**Solution:** Server can optimize a floor by converting large consecutive tiles into a single Part that represents all of them. Single this may be an expensive optimization, this optimization should be suspended while a player is in design mode. This means that a player needs to request "Design Mode" from the server.

## Autosave
Any **Plot** with a selected **Save Slot** will have autosave enabled. Some changes save immediately, Others create a 60 second timer to accumulate changes. After a save, the next change will create a new timer.

## Modules
- `Formex` is the shared interface between client and server

### Server-side
- `FormexSystem`: manage core plot ownership and common systems
- `FormexPlot`: handles client functions related to plot management
- `FormexBuild`: handles client functions related to building and designing

### Client-side
- `FormexCamera`: manages camera modes
- `FormexClient`: core management for the Formex state
- `FormexDesign`: design mode functionality (floors, walls, objects)
- `FormexFooter`: UI for the footer menu
- `FormexPrompts`: UI popups
- `FormexUI`: custom UI component library

## Communication
- `FormexClient` has methods that call methods named in `Formex.Function`
- `FormexServerFunctions` is the receiver for client functions and dispatches them to `FormexBuild`, `FormexServer`, etc
