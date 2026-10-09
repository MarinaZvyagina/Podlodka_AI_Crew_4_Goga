# R04-TC-GC-06

Condition: goga_native_architecture
Base tag: condition-c-r04-v1
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: False
Cost: $5.676130049999999
Duration: 920470ms, turns: 128

## Agent's own summary

## Summary

Implemented a "Hide captions" toggle that instantly hides/shows all shape-bound text (captions), following the same pattern as Excalidraw's existing `gridModeEnabled`/`zenModeEnabled` display toggles:

- **New `AppState.hideCaptionsEnabled` flag** (`types.ts`, `appState.ts`) — defaults to `false`, persists locally per-browser but is excluded from exported `.excalidraw` JSON and shareable-link snapshots (`export: false, server: false`), matching `zenModeEnabled`.
- **New action** `actionToggleHideCaptions` (`Alt+C` shortcut, works in view mode) registered in the action system, main menu (Menu → Preferences → "Hide captions"), canvas right-click context menu, and the keyboard shortcuts help dialog.
- **Rendering**: gated the bound-text render call in `renderer/staticScene.ts` on `!appState.hideCaptionsEnabled`, but only when *not* exporting (`isExporting` check) — mirroring how `renderGrid` is handled — so the toggle never affects `exportToCanvas`/`exportToSvg` output.
- Wired the flag through `StaticCanvasAppState` and `StaticCanvas.tsx`'s memoization selector so live re-renders pick up the change immediately.

Verified via `yarn test:typecheck`, `yarn test:update` (all 1860 tests pass, snapshots updated), and `yarn fix`, plus an end-to-end Playwright run against the dev server: drew a shape with a bound caption, toggled hiding via the menu and via `Alt+C` (caption disappears/reappears, shape untouched, no console errors), and confirmed the Export dialog preview still renders the caption while it's hidden on canvas.
