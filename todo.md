I have a list of changes, please take them one at a time. Update AGENT.md and related documentation with any important changes. Also, please reference each one and how you implemented it in your final summary.

1. Room changes currently snap to `GridSize` instead of `LayoutGridSize`. `Walls` and `Floors` must always snap to `LayoutGridSize`. Only `Objects` can snap to `GridSize`. Fix this issue and make sure it's clearly noted in AGENT.md to future reference.

2. Rooms that are IsExterior (touching the outside of the plot without a wall, so a room exposed to the outside) should not be selectable. These should count as unclaimed space in DesignMode. This way users have a place to click.

3. When in Room DesignMode, I would like to see the floors highlighted of each room on the current level in a different color. Create a nice light color palette of 12 colors that do not conflict with `FormexDesignContext` `selectionColor` or `handleDeleteColor` so that each room can be a slightly unique color. Also, highlight each Door between rooms in a consistent color.

4. When selecting a room, I want the sidebar to be a smarter and more useful.
- Display the Total Area
- Display the number of connected rooms, number of objects
- Display each floor material in use, this way I can replace all instances of a material with another.
- Display each interior wall material in use, find and replace, just like floors.
Interior walls are the wallsides facing into the room.

5. EditMode has both PointMove and PartMove now, but I want to add DisconnectMove. Include it on the Sidebar with the WallDisconnect icon.
Walls currently have Disconnect Handles already by default but I want to remove these and redo it in a consistent way for Floors, Walls, and Rooms.
Disconnect handles should be located at the same location as the point handles for Floors and Walls alike.
Disconnect for Rooms is going to be complicated, currently we merge walls into adjacent rooms, this will have to "unmerge" the walls to create separate rooms. Make sure objects on respective sides stay on the wall related to the room their in. Wall materials can stay the same.

6. After Undo moves or restores a deleted Door or Window ObjectMount object, it doesn't run the Wall Subtract logic. We should probably centralize the logic for changing stuff that runs on create, delete, undo/redo, move. Like pass it a list of affected parts and let it run through the updates. And streamline that logic so it's consistent behavior.

7. After releasing the mouse when moving a wall, it immediately calls BuildWall but delays for a moment after actually releasing the mouse grab. This causes the wall to continue to follow my mouse for a moment after the action is sent to the server.
We need a new helper behavior owned by the Handles system.
  - Handle system should have an SetBusy method that can hide all the handles and display a rotating spinner handle using `Formex.Icons.Spinner` that is positioned centered between all of the current handles. Clear handles should clear busy state too.

8. Selecing an Object chooses the wrong part as the Adornee of the Highlight. It should always select the `Model` that represents them.

9. After deselecting an object, Select DesignMode should be chosen to allow the user to select any type of object.

10. Dropper mode needs to be promoted to a full DesignMode. It should allow selecting any type of Wall side, Floor, or Object. It will automatically switch to the Paint submode of the respective DesignMode. e.g. If I click a wall side, switch to the Wall/Paint DesignMode.
Dropper's new home can be between Select and Room on the Sidebar.

---



3. Some rooms don't have floors. Let's do something a little different. To visualize the the rooms, let's instead do standard edge highlights recessed 1 stud in from the edge of the room. Also, only display these highlights when nothing is selected. Once I select a room, hide them, and return them when nothing is selected. Doors should use an edge highlight directly underneath them based on their size along the wall.

4. Interior Wall materials is misbehaving. It's not corrently identifying only the interior walls only.

11a. Disconnect mode is smart and only shows a Disconnect handle when there's connections to disconnect, but Disconnect mode needs to make sure that every point still has a move handle. So if there's no connections at that point, display the normal move handle instead.

11b. Room split (unmerge) does not consistently work. Sometimes it leaves 

12. Right-clicking in DesignModes should properlu act as a back button.
- Wall/Select with a selection should return to Select DesignMode
- Wall/Step should return to Wall/Start
- Wall/Start should return to Wall/Select
- Floor/Select with a selection should return to Select DesignMode
- Floor/* otherwise behaves perfectly.
- Room/Select with a selection should return to Select DesignMode
- Room/* otherwise behaves perfectly.

---

Switching to the dropper tool and clicking on a floor or wall works correctly. Clicking on a floor switch to Floor/Paint, clicking on a wall switches to Wall/Paint.
However, when I am in Wall Mode and hold Alt and click a Floor, releasing Alt returns me to Wall mode instead of to Floor mode. Also, it never copied the Floor clicked on. Alt mode for Dropper should act like the normal dropper.

There may still be legacy logic for when the dropper had invididual modes Wall/Dropper, Floor/Dropper, but this should all be removed. The Dropper DesignMode is the new replacement, and should be able to automatically switch between Wall, Floor, and Objects.

See @DESIGN_MODES.md for details.


---

I have a bunch of HELPERS on my Data classes in [Formex.luau](src/shared/Formex.luau) 

My original goal was to include helpers to speed up FormexDesign queries, Sidebar queries, and Room calculation. But maintaining these on both client and server is costly and quirky. It's actually faster to query at this point.

Change up this helper system to make it count where it matters. Remove unnecessary helpers, add any that would be really helpful. Rooms are the magic bullet here. Users will be mostly managing Floors, Walls, and Objects using room tools. So we need to make Room calculation really efficient and reliable.

Walls: `ConnectedRoomFront` and `ConnectedRoomBack`
- Walls need to know which side (front/back) relates to which room.
- If one side of a wall is exposed to more than one room, it needs to automatically split. The rule is, one room per wall side.
- Remove other helpers

Floors: `ConnectedRoom`
- If a floor is exposed to more than one room, it needs to automatically split. The rule is, one room per floor. But a room can contain many floors.
- Remove other helpers

Objects: `ConnectedRoom`, `PortalRoom`
- It would be helpful to know which room an object belongs to. Maybe not for the Formex system itself, but for the game that will be built on top of Formex. For doors, it may also be helpful to know which room the door enters into. Let's track these
- Remove other helpers

Queries that happen and we need to review, update, and optimize:
- Room change detection: when a wall, floor, or door object changes, we need to quickly scan to see if we need to recalculate all rooms from scratch, just update existing room data, or nothing important happened.
- Room calculation: when building the rooms, we need to set all of the helpers.
- Room editor: wall merge allows two rooms that touch merge walls in a predictable, expected shared wall.
- Room split: when disconnecting a room from another, we need to clone the wall to give each room a separate wall.
- Sidebar, dropper, paint:
  - We need to know which wall sides are interior so we're only listing the sides that matter.
  - We need to query floors

NOTE: Right now, t