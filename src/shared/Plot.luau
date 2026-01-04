--!strict

local Formex = require(script.Parent:FindFirstChild("Formex"))

--[[
    Classes used to represent Plots, Levels, Walls, Floors, and Objects
    in the Formex system. These are synced between server and client.

    Creating a new Part is done via server-side call which returns an ID, then client WaitForChild to get the Part instance.
    Creating a new Part starts as a ghost (IsGhost) until it is finished (Finish).
    Ghosts are normal parts shared between other clients while building just like finished parts. They just have IsGhost = true.

    Changes use optimistic client prediction and utlize unified validation on both server and client. The call to the server waits for confirmation and can revert the change.

    Players can see what other players have selected, and two players cannot select the same part at the same time.

    Workspace Hierarchy:
    Plot.Part \ Level.Part \ Walls (Folder) \ Wall.Part
                           \ Floors (Folder) \ Floor.Part
                           \ Objects (Folder) \ Object.Part

    Part.Name is the unique `Id` of the object.
    Parts use Attributes to store metadata such as materials, heights, etc.

    Underlying implementation will monitor Part changes to update the data model:
        `part.Changed:Connect` to monitor property changes
        `part.AttributeChanged:Connect` to monitor attribute changes
        `part.ChildAdded:Connect` on each Folder to monitor Part additions
        `part.ChildRemoved:Connect` on each Folder to monitor Part removals
]]

export type DesignMode = "Play" | "Wall" | "Floor" | "Object"

export type Wall = {
    Id: number,
    Part: Part,
    Level: Level,
    Start: Vector2int16,
    End: Vector2int16,
    Height: number,
    FrontMaterial: number,
    BackMaterial: number,
    IsGhost: boolean,
    IsSelected: boolean,

    UpdatePoints: (newStart: Vector2int16, newEnd: Vector2int16) -> (),
    SetHeight: (newHeight: number) -> (),
    SetFrontMaterial: (materialId: number) -> (),
    SetBackMaterial: (materialId: number) -> (),
    Select: () -> (),
    Finish: () -> (),
    Delete: () -> (),
}

export type Floor = {
    Id: number,
    Part: Part,
    Level: Level,
    Points: {Vector2int16},
    IsGhost: boolean,
    IsSelected: boolean,

    UpdatePoints: (newPoints: {Vector2int16}) -> (),
    SetHeight: (newHeight: number) -> (),
    SetFloorMaterial: (materialId: number) -> (),
    SetCeilingMaterial: (materialId: number) -> (),
    SetFoundationMaterial: (materialId: number) -> (),
    Select: () -> (),
    Finish: () -> (),
    Delete: () -> (),
}

export type Object = {
    Id: number,
    Part: Part,
    Level: Level,
    ModelId: number,
    Position: Vector3,
    Orientation: Vector3,
    IsGhost: boolean,
    IsSelected: boolean,

    SetPosition: (newPosition: Vector3) -> (),
    SetOrientation: (newOrientation: Vector3) -> (),
    Select: () -> (),
    Finish: () -> (),
    Delete: () -> (),
}

export type Level = {
    Id: number,
    Part: Part,
    IsUnlocked: boolean,
    IsActive: boolean,
    Unlock: () -> (),

    Walls: {number: Wall},
    Floors: {number: Floor},
    Objects: {number: Object},

    AddWall: (start: Vector2int16) -> Wall,
    AddFloor: (start: Vector2int16) -> Floor,
    AddObject: (start: Vector2int16, modelId: number) -> Object,
}

export type PermissionItem = {
    UserId: number,
    UserName: string,
    Permission: Formex.Permission,
}

export type Plot = {
    Name: string,
    Part: Part,
    OwnerUserId: number?,
    OwnerName: string?,
    MyPermission: Formex.Permission,
    Segments: {Vector2int16},
    Levels: {number: Level},
    Players: {number: Color3},
    CanUndo: boolean,
    CanRedo: boolean,

    DesignMode: DesignMode,
    SelectedPart: Wall | Floor | Object | nil,
    SetDesignMode: (mode: DesignMode, levelIndex: number) -> (),

    SetName: (newName: string) -> (),
    GetPermissions: () -> {number: PermissionItem},
    SetPermission: (userId: number, permission: Formex.Permission) -> (),
    UnlockSegment: (segment: Vector2int16) -> (),

    DeselectAll: () -> (),
    Undo: () -> (),
    Redo: () -> (),

    IsPointValid: (point: Vector2 | Vector2int16) -> boolean,
    IsLineValid: (lineStart: Vector2 | Vector2int16, lineEnd: Vector2 | Vector2int16) -> boolean,
    IsPolygonValid: (points: {Vector2 | Vector2int16}) -> boolean,
    IsPointNearBoundary: (point: Vector3, threshold: number) -> boolean,

    -- Events
    OnPlotChanged: () -> (),
    OnSelectionChanged: (part: Wall | Floor | Object | nil) -> (),
}

local plot = {} :: Plot

return plot