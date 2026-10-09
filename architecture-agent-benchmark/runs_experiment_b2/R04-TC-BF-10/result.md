# R04-TC-BF-10

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $4.245935999999998
Duration: 1037000ms, turns: 109

## Agent's own summary

The implementation is complete and verified. Summary:

**Feature: "Hide captions" toggle** — a new drawing-wide view toggle that instantly hides text bound to shapes/arrows without modifying data.

- **Architecture check**: Ran `goga schema`/`goga lint` first — only 5 cells are governed (`packages/common/src`, `math`, `element`, `fractional-indexing`, `excalidraw/actions`'s extension-point contract). The new action uses that extension point (`register()`) rather than a bespoke path, and `goga lint` still passes 0 errors after the change.
- **State**: `AppState.hideBoundTextElementsEnabled` (default `false`), persisted to localStorage only (not exported to `.excalidraw` files or synced), mirroring `zenModeEnabled`/`objectsSnapModeEnabled`.
- **Action**: `actionToggleHideBoundTextElements` (`packages/excalidraw/actions/actionToggleHideBoundTextElements.tsx`) — `Alt+T` shortcut, checkbox in the main menu's Preferences submenu, canvas right-click menu, Help dialog, and Command Palette. Works with or without a selection.
- **Rendering**: purely a view-layer filter — `staticScene.ts` skips drawing a bound-text element when `renderConfig.renderBoundTextElements` is false; the underlying element data, `boundElements`, and `containerId` are never touched, so re-enabling restores captions exactly.
- **Export isolation**: `scene/export.ts` hardcodes `renderBoundTextElements: true`, so PNG/canvas exports always include captions regardless of the toggle — same pattern already used for `renderGrid: false`. SVG export path was left untouched (it never reads the new flag), so it also always shows captions. Combines cleanly with grid/zen/snap toggles since none of them touch this new field.
- Added `KEYS.T`/`CODES.T` wasn't present, so extended the existing `CODES` constant table in `packages/common/src/keys.ts` (not a documented manifest type) for reliable Alt+T detection across keyboard layouts.

Verified with `yarn test:typecheck` (clean), `yarn fix` (clean), and `yarn test:update` (122/122 files, 1860 tests passing — 5 initial failures were pre-existing flaky "still loading" timing issues, confirmed by re-running those files in isolation). Snapshot diffs only add the new `hideBoundTextElementsEnabled: false` field, nothing else changed.
