# Design Modes

This document is the source of truth for client design modes, tools, and input behavior.
Read this whenever you touch design modes, paint/dropper, handles, selection, or the sidebar.

## Enums and Types

From `src/client/FormexDesignContext.luau`:

- `DesignMode` = "Play" | "Design" | "Select" | "Dropper" | "Expand" | "Floor" | "Wall" | "Object" | "Room"
- `DesignSubMode` = "Normal" | "Paint"
- `EditMode` = "PointMove" | "PartMove" | "DisconnectMove"
- `ActionType` = "Select" | "Start" | "Step" | "Rotate" | "Move"
- `FloorMode` = "Manual" | "Autofill"

`DesignSubMode` only applies to paintable modes (Wall/Floor/Object). Dropper is a full `DesignMode`.

## Client Design System References

- `src/client/Formex/Design.luau`: entry point; manages design state, selection, and input dispatch.
- `src/client/Formex/Design/Context.luau`: shared enums/types/constants and module registry.
- `src/client/Formex/Design/Walls.luau`: wall build/edit/paint/handle logic.
- `src/client/Formex/Design/Floors.luau`: floor build/edit/paint/handle logic.
- `src/client/Formex/Design/Objects.luau`: object interactions and paint/dropper.
- `src/client/Formex/Design/Rooms.luau`: room overlays, selection, and wall/point move handles.
- `src/client/Formex/Design/Handles.luau`: handle creation, hover, and click behavior.
- `src/client/Formex/Design/Highlights.lua`: selection and edge previews.
- `src/client/Gui/FormexSidebar.client.luau`: sidebar and design controls UI.
- `src/client/Gui/FormexTips.client.luau`: design feedback, user suggestions, and tips.

Design flow: `FormexDesign` initializes the context, then calls `Init()` on handles/highlights/walls/floors/objects/rooms. Submodules access each other via `FormexDesignContext.Get()`.

## Global Input Rules

- Selection edits only happen in `DesignSubMode.Normal` for paintable modes.
- In `DesignSubMode.Paint`, primary clicks apply paint and do not select or start build actions.
- In `DesignMode.Dropper`, primary clicks only copy paint settings (no selection/build).
- When handles must be disabled while waiting for server confirmation, wrap the call with `Handles.SetBusy(true)` and `Handles.SetBusy(false)`.
- `EditMode.DisconnectMove` aligns disconnect handles with point handles and avoids moving shared connections for walls, floors, and rooms.

## Paint/Dropper Behavior

Dropper (DesignMode):
- Clicking a wall side/floor/object copies the appearance into paint settings.
- After a successful drop, switch to the matching DesignMode with `DesignSubMode.Paint`.

Alt dropper:
- Holding Alt while in Wall/Floor/Object (Normal or Paint) switches to Dropper for as long as Alt is held.
- While Alt is held, Dropper does not auto-switch to Paint.
- On Alt release, return to the previous mode and sub-mode unless Dropper was used; if used, switch to Paint.

Paint:
- Walls: apply paint to the clicked wall side only; apply height to the whole wall.
- Floors: apply paint to the clicked floor.
- Objects: apply paint to the clicked object;.
- Never change paint settings.

Wall side detection:
- Wall sides are determined from the clicked surface (front/back parts)
  - `WallData.FrontBottomPart` or `WallData.FrontTopPart` indicates front side
  - `WallData.BackBotomPart` or `WallData.BackTopPart` indicates back side
- No wall-side state is stored.

## Design Modes

### Select
Selects any part type and switches to the corresponding DesignMode on success. If a room is selected, exterior rooms (`IsExterior`) are not selectable.

Right-click behavior:
- Cancels the current action (if any) and clears selection only when not in Select mode.
- In Select mode, right-click does not change mode; it just clears selection when applicable.

### Dropper
Primary click copies paint settings from the clicked target and moves to the corresponding Paint sub-mode (unless Alt is held).

Right-click behavior:
- Returns to Select mode.

### Wall
- Normal: select walls and use handles; clicking empty space starts wall placement.
- Start: place the first point for a new wall.
- Step: preview and confirm wall placement.
- Paint: apply `WallPaintSettings` to the clicked wall side only.

Right-click behavior:
- Normal: returns to Select mode.
- Start: returns to Wall/Normal.
- Step: returns to Wall/Start.
- Paint: returns to Dropper mode.

### Floor
- Normal: select floors; clicking empty space starts floor placement.
- Start: place the first point or tile.
- Step: continue placement for manual floors.
- Paint: apply `FloorPaintSettings` to the clicked floor.

Right-click behavior:
- Normal: returns to Select mode.
- Start: returns to Floor/Normal.
- Step: undoes the last point; if no points remain, returns to Floor/Normal.
- Paint: returns to Dropper mode.

### Object
- Normal: select objects; clicking empty space places the current prefab.
- Paint: apply `ObjectPaintSettings` to the clicked object.

Right-click behavior:
- Normal: returns to Select mode.
- Paint: returns to Dropper mode.

### Room
- Normal: select rooms; room overlays tint floors per-room and highlight door connections.
- Handles: room wall/point handles follow `EditMode` rules.

Right-click behavior:
- Normal: returns to Select mode.
- Start: returns to Room/Normal.
- Step: returns to Room/Normal.

### Expand
Plot expansion mode; clicking a segment unlocks it (owners only).

Right-click behavior:
- Returns to Select mode.
