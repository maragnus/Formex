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

    UpdatePoints: (this: Wall, newStart: Vector2int16, newEnd: Vector2int16) -> (),
    SetHeight: (this: Wall, newHeight: number) -> (),
    SetFrontMaterial: (this: Wall, materialId: number) -> (),
    SetBackMaterial: (this: Wall, materialId: number) -> (),
    Select: (this: Wall) -> (),
    Finish: (this: Wall) -> (),
    Delete: (this: Wall) -> (),
}

export type Floor = {
    Id: number,
    Part: Part,
    Level: Level,
    Points: {Vector2int16},
    IsGhost: boolean,
    IsSelected: boolean,

    UpdatePoints: (this: Floor, newPoints: {Vector2int16}) -> (),
    SetHeight: (this: Floor, newHeight: number) -> (),
    SetFloorMaterial: (this: Floor, materialId: number) -> (),
    SetCeilingMaterial: (this: Floor, materialId: number) -> (),
    SetFoundationMaterial: (this: Floor, materialId: number) -> (),
    Select: (this: Floor) -> (),
    Finish: (this: Floor) -> (),
    Delete: (this: Floor) -> (),
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

    SetPosition: (this: Object, newPosition: Vector3) -> (),
    SetOrientation: (this: Object, newOrientation: Vector3) -> (),
    Select: (this: Object) -> (),
    Finish: (this: Object) -> (),
    Delete: (this: Object) -> (),
}

export type Level = {
    Id: number,
    Part: Part,
    IsUnlocked: boolean,
    IsActive: boolean,
    CanUnlock: boolean,
    Unlock: () -> (),

    Walls: {this: Level, number: Wall},
    Floors: {this: Level, number: Floor},
    Objects: {this: Level, number: Object},

    AddWall: (this: Level, start: Vector2int16) -> Wall,
    AddFloor: (this: Level, start: Vector2int16) -> Floor,
    AddObject: (this: Level, start: Vector2int16, modelId: number) -> Object,
}

export type Segment = {
    Position: Vector2int16,
    IsUnlocked: boolean,
    CanUnlock: boolean,
    Unlock: () -> (),
}

export type PlotPlayer = {
    UserId: number,
    UserName: string,
    Permission: Formex.Permission,
    Color: Color3,
    IsPresent: boolean,
    DesignMode: DesignMode,
    SortOrder: number, -- Plot.Owner = 0, Owner = 1, Manager = 2, VIP = 3, Guest = 4, Banned = 5
}

export type Plot = {
    Id: number,
    Name: string,
    Part: Part,
    OwnerUserId: number?,
    OwnerName: string?,
    MyPermission: Formex.Permission,
    SegmentsUnlocked: number,
    LevelsUnlocked: number,
    Segments: {Segment},
    Levels: {number: Level},
    Players: {PlotPlayer},
    CanUndo: boolean,
    CanRedo: boolean,
    DesignMode: DesignMode,
    SelectedPart: Wall | Floor | Object | nil,

    SetName: (this: Plot, newName: string) -> (),
    SetPermission: (this: Plot, userId: number, permission: Formex.Permission) -> (),

    SetDesignMode: (this: Plot, mode: DesignMode, levelIndex: number) -> (),
    SelectPart: (this: Plot, part: Wall | Floor | Object) -> (),
    DeselectAll: (this: Plot) -> (),
    Undo: (this: Plot) -> (),
    Redo: (this: Plot) -> (),

    IsPointValid: (this: Plot, point: Vector2 | Vector2int16) -> boolean,
    IsLineValid: (this: Plot, lineStart: Vector2 | Vector2int16, lineEnd: Vector2 | Vector2int16) -> boolean,
    IsPolygonValid: (this: Plot, points: {Vector2 | Vector2int16}) -> boolean,
    IsPointNearBoundary: (this: Plot, point: Vector3, threshold: number) -> boolean,

    -- Events
    -- When Plot.*, Plot.Players, Plot.Segments, or Plot.Levels change (no arguments)
    OnPlotChanged: BindableEvent,
    -- When a Part is added, removed, or changed (part: Wall | Floor | Object)
    OnPartChanged: BindableEvent,
    -- When Plot.SelectedPart changes (no arguments)
    OnSelectionChanged: BindableEvent,
}

local plot = {} :: Plot

local Plot = {}
Plot.__index = Plot

export type PlotHooks = {
    Invoke: ((this: Plot, action: string, ...any) -> any)?,
    OnSelectionChanged: ((this: Plot) -> ())?,
}

local function fireSelectionChanged(self: Plot)
    self.OnSelectionChanged:Fire()
    if self._hooks and self._hooks.OnSelectionChanged then
        self._hooks.OnSelectionChanged(self)
    end
end

function Plot.Attach(data: Plot, hooks: PlotHooks?): Plot
    data.Id = data.PlotId
    data.DesignMode = data.DesignMode or "Play"
    data.SelectedPart = data.SelectedPart or nil
    data.OnPlotChanged = data.OnPlotChanged or Instance.new("BindableEvent")
    data.OnPartChanged = data.OnPartChanged or Instance.new("BindableEvent")
    data.OnSelectionChanged = data.OnSelectionChanged or Instance.new("BindableEvent")
    (data :: any)._hooks = hooks
    return setmetatable(data, Plot) :: Plot
end

function Plot:SetName(newName: string)
    if self.Name == newName then
        return
    end
    self.Name = newName
    self.OnPlotChanged:Fire()
    if self._hooks and self._hooks.Invoke then
        self._hooks.Invoke(self, Formex.Function.RenamePlot, newName)
    end
end

function Plot:SetPermission(userId: number, permission: Formex.Permission)
    if self._hooks and self._hooks.Invoke then
        self._hooks.Invoke(self, Formex.Function.SetPermission, userId, permission)
    end
end

function Plot:SetDesignMode(mode: DesignMode, levelIndex: number)
    if self.DesignMode == mode then
        return
    end
    self.DesignMode = mode
    self.OnPlotChanged:Fire()
    if self._hooks and self._hooks.Invoke then
        self._hooks.Invoke(self, "SetDesignMode", mode, levelIndex)
    end
end

function Plot:SelectPart(part: Wall | Floor | Object)
    if self.SelectedPart == part then
        return
    end
    self.SelectedPart = part
    fireSelectionChanged(self)
    if self._hooks and self._hooks.Invoke then
        self._hooks.Invoke(self, "SelectPart", part and part.Id or 0)
    end
end

function Plot:DeselectAll()
    if not self.SelectedPart then
        return
    end
    self.SelectedPart = nil
    fireSelectionChanged(self)
    if self._hooks and self._hooks.Invoke then
        self._hooks.Invoke(self, "DeselectAll")
    end
end

function Plot:Undo()
    if self._hooks and self._hooks.Invoke then
        return self._hooks.Invoke(self, Formex.Function.Undo)
    end
    return false
end

function Plot:Redo()
    if self._hooks and self._hooks.Invoke then
        return self._hooks.Invoke(self, Formex.Function.Redo)
    end
    return false
end

function Plot:IsPointValid(point: Vector2 | Vector2int16): boolean
    return Formex.Plot.IsPointInUnlockedSegments(point, self.SegmentsUnlocked)
end

function Plot:IsLineValid(lineStart: Vector2 | Vector2int16, lineEnd: Vector2 | Vector2int16): boolean
    return Formex.Plot.IsLineWithinUnlockedSegments(lineStart, lineEnd, self.SegmentsUnlocked)
end

function Plot:IsPolygonValid(points: {Vector2 | Vector2int16}): boolean
    for _, point in points do
        if not self:IsPointValid(point) then
            return false
        end
    end
    return true
end

function Plot:IsPointNearBoundary(point: Vector3, threshold: number): boolean
    if not self.Part then
        return false
    end
    return Formex.Plot.IsPointNear(self.Part.Position, point, threshold)
end

return Plot
