# R04-TC-B-06

Condition: baseline
Functional success: True
Full architecture conformance: False
ACR: 0.5
Dangerous success: True
Cost: $4.657218150000001
Duration: 681991ms, turns: 96

## Agent's own summary

Confirmed — every snapshot change is exactly the new `hideBoundTextCaptions: false` field, nothing else changed.

## Summary

Implemented a "Hide captions" toggle for shape/arrow-bound text, following the same pattern as existing view toggles like Zen mode and Grid mode:

- **New `appState.hideBoundTextCaptions` boolean** (`types.ts`, `appState.ts`), default `false`, persisted locally (not exported/synced, matching Zen mode's semantics as a personal view preference).
- **New action** `actionToggleHideBoundTextCaptions` (`packages/excalidraw/actions/actionToggleHideBoundTextCaptions.tsx`) bound to `Alt+T`, registered alongside grid/zen mode in the action manager, context menu, command palette, and Help dialog shortcut list.
- **Menu entry** in the main menu's Preferences submenu with a checkbox showing on/off state, reachable regardless of selection.
- **Rendering chokepoint**: in `renderer/staticScene.ts`, the container's bound-text label is skipped only when `hideBoundTextCaptions && !isExporting` — the element data itself is never touched, and both PNG/canvas export and the separate SVG export path are unaffected since they either check `isExporting` or don't share this code path.
- Added `hideBoundTextCaptions` to `StaticCanvasAppState`'s memoization allowlist in `StaticCanvas.tsx` so toggling actually triggers a redraw.

Verified end-to-end with Playwright against the dev server: drawing a rectangle with a "Hello" caption, toggling via the menu (checkmark appears/disappears, caption hides/restores exactly), and toggling via `Alt+T` with nothing selected — all worked with no console errors. `yarn test:typecheck`, `yarn fix` (lint), and `yarn test:update` (1860 tests) all pass; the only snapshot diffs are the new default field appearing in serialized `AppState`.
