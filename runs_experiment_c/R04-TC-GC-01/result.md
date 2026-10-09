# R04-TC-GC-01

Condition: goga_native_architecture
Base tag: condition-c-r04-v1
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: False
Cost: $4.1722247999999995
Duration: 701700ms, turns: 91

## Agent's own summary

This all looks correct and complete. Let me summarize what was implemented.

## Summary

Added a "Hide captions" toggle to instantly hide/show all shape-bound text (captions), following the exact same wiring pattern as existing drawing-wide toggles like grid mode:

- **`packages/excalidraw/types.ts` / `appState.ts`** — new `hideBoundTextEnabled: boolean` AppState field (default `false`), added to the `StaticCanvasAppState` slice since the renderer reads it.
- **`packages/excalidraw/actions/actionToggleHideBoundText.tsx`** — new action (`Alt+C` shortcut, `viewMode: true` so it works with nothing selected or in view mode), registered in `actions/index.ts`, `actions/types.ts`, `actions/shortcuts.ts`.
- **Menu** — new `PreferencesToggleHideBoundTextItem` checkbox in the main-menu Preferences submenu, plus added to both canvas context menus (`App.tsx`), and a `HelpDialog` shortcut entry.
- **`packages/excalidraw/components/icons.tsx`** — new `hideBoundTextIcon` (typography icon + slash, matching the existing "off" icon convention).
- **`packages/excalidraw/renderer/staticScene.ts`** — the actual behavior: bound-text rendering is skipped only when `hideBoundTextEnabled` is true **and** `isExporting` is false, so PNG/SVG export and clipboard copy always include captions regardless of the toggle (SVG export path is entirely separate and never touches this flag).
- Toggling only skips a render call — it never mutates element data, so it's instant, reversible, and independent of other toggles (no shared state with grid/zen/view mode).
- Storage config set to `{ browser: true, export: false, server: false }` (like zen mode) — it persists locally but never gets baked into exported/shared scene files.

Verified with `yarn test:typecheck` (pass) and `yarn test:update` (1860 tests pass; snapshot diffs only add the new default field/action, nothing unrelated changed) and `yarn fix` (clean).
