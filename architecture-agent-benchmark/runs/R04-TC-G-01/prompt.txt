## Ticket: Let users hide shape captions for a cleaner view

A number of users build diagrams where every shape has a text caption bound to it (labels
on boxes, names on flowchart nodes, etc.), but when they want to take a clean screenshot
or present just the shapes themselves, all the captions get in the way and there's no
quick way to get rid of them without deleting the actual text.

Please add a way to instantly hide all of these shape captions and bring them back again
with a single command — a simple on/off switch for the current drawing. It should be:

- Reachable from the same places users already go to trigger other drawing-wide display
  toggles in the app (menu and keyboard shortcut), and it should show its current
  on/off state the way similar switches do elsewhere in the UI.
- Instant and non-destructive — toggling it off must never delete, move, or otherwise
  modify the underlying text or the shapes it's attached to; toggling it back on must
  restore the exact same captions.
- Available while the user has no shapes selected as well as when something is selected.
- Should not interfere with exporting or with other existing view toggles (e.g. it should
  be possible to combine it with other display modes without one silently overriding the
  other's state).

Captions that are freestanding text (not attached to a shape) are out of scope — this is
only about captions bound to a shape or arrow.
