Room changes currently snap to `GridSize` instead of `LayoutGridSize`. `Walls` and `Floors` must always snap to `LayoutGridSize`. Only `Objects` can snap to `GridSize`. Fix this issue and make sure it's clearly noted in AGENT.md to future reference.

Rooms that are IsExterior (touching the outside of the plot without a wall, so a room exposed to the outside) should not be selectable. These should count as unclaimed space in DesignMode. This way users have a place to click.

When in Room DesignMode, I would like to see an outline of all rooms on the current level. Create a nice light color palette of 12 colors that doesn't conflict with `FormexDesignContext` `selectionColor` or `handleDeleteColor` so that each room can be a unique color. Also, highlight each Door between rooms in a consistent color.

When selecting a room, I want the sidebar to be a smarter and more useful.
- Display the Total Area
- Display the number of connected rooms, number of objects
- Display each floor material in use, this way I can replace all instances of a material with another.
- Display each interior wall material in use, find and replace, just like floors.
Interior walls are the wallsides facing into the room.

EditMode has PointMove and PartMove now, but I want to add DisconnectMove. Sidebar needs to include the new button.
Walls currently have Disconnect Handles by default but I want to remove these and redo it in a consistent way for Floors, Walls, and Rooms.
Disconnect handles should be located at the same location as the point handles for Floors and Walls alike.
Disconnect for Rooms is going to be complicated, currently we merge walls into adjacent rooms, this will have to "unmerge" the walls to create separate rooms.

After Undo moves or restores a deleted Door or Window ObjectMount object, it doesn't run the Wall Subtract logic. We should probably centralize the logic for changing stuff that runs on create, delete, undo/redo, move. Like pass it a list of affected parts and let it run through the updates. And streamline that logic so it's consistent behavior.

After releasing the mouse when moving a wall, it immediately calls BuildWall but delays for a moment after actually releasing the mouse grab. This causes the wall to continue to follow my mouse for a moment after the action is sent to the server.
We need a new helper behavior owned by the Handles system.
  - Handle system should have an SetBusy method that can hide all the handles and display a rotating spinner handle using `Formex.Icons.Spinner` that is positioned centered between all of the current handles. Clear handles should clear busy state too.

Selecing an Object chooses the wrong part as the Adornee of the Highlight. It should always select the `Model` that represents them.

After deselecting an object, Select DesignMode should be chosen to allow the user to select any type of object.

Dropper mode needs to be promoted to a full DesignMode. It should allow selecting any type of Wall side, Floor, or Object. It will automatically switch to the Paint submode of the respective DesignMode. e.g. If I click a wall side, switch to the Wall/Paint DesignMode.
Dropper's new home can be between Select and Room on the Sidebar.
