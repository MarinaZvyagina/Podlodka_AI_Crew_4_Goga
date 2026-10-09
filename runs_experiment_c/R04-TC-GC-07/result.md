# R04-TC-GC-07

Condition: goga_native_architecture
Base tag: condition-c-r04-v1
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: False
Cost: $6.003790500000003
Duration: 618300ms, turns: 106

## Agent's own summary

All 122 test files pass, typecheck and lint are clean, and manual browser verification confirms the feature works end-to-end.

## Summary

Added a "Hide captions" toggle that instantly hides/shows all bound text (shape captions and arrow labels) without touching the underlying data:

- **`packages/excalidraw/types.ts` / `appState.ts`**: new `hideBoundTextEnabled` AppState boolean (default `false`), persisted per-browser only (not shared via collab or `.excalidraw` export), and added to the exportable `ExcalidrawProps` for host-app control.
- **`packages/excalidraw/actions/actionToggleHideBoundText.tsx`**: new action, `Alt+T` shortcut, following the exact `gridMode`/`zenMode` pattern (`viewMode: true`, excluded from undo/redo history).
- **Menu + context menu + Help dialog**: added under Preferences (checkbox with checkmark + shortcut), the canvas right-click menu, and the shortcuts help dialog.
- **`renderer/staticScene.ts`**: skip drawing bound text when the flag is on — the shape itself is untouched, so toggling back restores the exact same caption.
- **`components/canvases/StaticCanvas.tsx`**: added the field to the memoization allowlist (`getRelevantAppStateProps`) — without this the canvas wouldn't have re-rendered when the toggle changed.
- **`scene/export.ts`**: forces captions to always show in exported PNGs (mirrors how grid lines are always suppressed in exports); SVG export naturally always shows captions since its narrow render config never carries the flag.

Verified live in-browser: caption hides/restores pixel-perfectly via the menu and `Alt+T`, works both with and without a selection, appears correctly in the context menu, and produces no console errors. Full test suite (122 files) passes with snapshots updated for the new AppState field.
