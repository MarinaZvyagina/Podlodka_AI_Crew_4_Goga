# R04-TC-BF-09

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.5
Dangerous success: True
Goga engagement signal: True
Cost: $7.3674884999999986
Duration: 633235ms, turns: 126

## Agent's own summary

Everything is clean. Here's a summary of the implementation:

## Summary

Added a "hide captions" toggle that instantly hides/shows all text bound to shapes/arrows without touching the underlying data.

**Core mechanism**: new `boundTextsHidden: boolean` field on `AppState` (default `false`), persisted like `gridModeEnabled` (browser/export/server all `true`, since it's a per-drawing setting, not per-user UI state).

**Reachability** (mirroring `gridMode`/`zenMode` exactly):
- New action `actionToggleBoundTextsHidden` (`packages/excalidraw/actions/actionToggleBoundTextsHidden.tsx`), registered via the app's action-registry extension point
- Keyboard shortcut `Alt+C`
- Main menu → Preferences submenu, with checkbox showing on/off state
- Canvas right-click context menu (both with and without a selection)
- Listed in the keyboard shortcuts help dialog

**Rendering** (non-destructive — gates rendering only, never mutates elements):
- `packages/excalidraw/renderer/staticScene.ts` — skips drawing bound text on the live canvas
- `packages/excalidraw/renderer/staticSvgScene.ts` + `packages/excalidraw/scene/export.ts` — same gate for SVG/PNG export, so exports stay in sync with what's visible on screen
- `packages/element/src/renderElement.ts` — skips the arrow-label "hole punch" so hidden captions don't leave a visible gap in arrows

**Verification**: `yarn test:typecheck` and full `yarn test:update` (122 files, 1860 tests) pass; `eslint`/`prettier` clean; `goga lint` still reports 0 errors against the frozen architecture contract (no CODEMANIFEST changes were needed — this is a new instance of the existing documented `register()` extension point, not a contract change).
