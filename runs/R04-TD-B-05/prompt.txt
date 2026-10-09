## Ticket: One-click "snap to grid" for shapes already on the canvas

The grid/snapping feature currently only helps while a shape is actively being dragged or
resized — if a user draws freehand or pastes shapes in and only turns grid snapping on
afterward, there's no way to line those existing shapes up with the grid short of
manually nudging each one.

Please add a command that snaps the position and size of the currently selected shapes to
the grid in one step, using the grid spacing that's already configured for the drawing.
If nothing is selected, it should apply to every shape on the canvas. Multiple shapes
should each snap independently based on their own position/size, not as a single group.

Requirements:

- Works from the selection the user already has on the canvas.
- Produces the same visual result a user would get by manually dragging each shape a tiny
  amount with grid snapping on (i.e. rounded to the nearest grid line).
- Undo (Ctrl+Z / Cmd+Z) must revert the snap in a single step, exactly like every other
  edit in the app.
- Must keep working correctly for people collaborating on the same drawing together —
  the change needs to reach collaborators the same way any other edit does.
