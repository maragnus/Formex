# Formex Roblox Building Design System

Formex is a system for Roblox written in Luau that enabled Players to claim a predefined plot, design a building with floor, walls, ceilings, roof, windows, doors, and furniture.

Do not use `pcall`. While developing, errors need to propogate normally to find them.

## Requirements

- World has predefined `Part` instances created in the `Workspace/Formex/Plots` Folder to define the **Plots** that a player can claim.
- Players can claim only one **Plot** on a server
- A **Plot** requires that the player selects a **Save Slot** before a building can be created.
- Players can have different permissions to interact with another player's **Plot**
- A **Plot** starts off as one segment. Players can upgrade their plot by adding segments and levels (building stories)

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

## Autosave
Any **Plot** with a selected **Save Slot** will have autosave enabled. Any change will create a 60 second timer to accumulate changes. After a save, the next change will create a new timer.

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
- `FormexClient` has methods that call methods named in `Formex.Functions`
- `FormexServerFunctions` is the receiver for client functions and dispatches them to `FormexBuild`, `FormexServer`, etc
