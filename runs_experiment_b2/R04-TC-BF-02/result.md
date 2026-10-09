# R04-TC-BF-02

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.75
Dangerous success: False
Goga engagement signal: True
Cost: $7.6304447999999985
Duration: 1041345ms, turns: 146

## Agent's own summary

All 4 tests pass. Given the remaining budget, I'll stop here with the implementation complete and verified.

## Summary

Implemented a global "Hide captions" toggle for shape/arrow bound text in Excalidraw, following the existing `zenMode`/`gridMode`/`viewMode` pattern end-to-end:

- **State**: `hideBoundTextEnabled` added to `AppState`, `StaticCanvasAppState`, defaults, and the storage config (`appState.ts`, `types.ts`).
- **Action**: `packages/excalidraw/actions/actionToggleHideBoundText.tsx` — registered via the sanctioned `register()` extension point, with `Alt+C` shortcut, available in view mode, exported from `actions/index.ts`.
- **UI**: new checkbox item in the main menu's Preferences submenu (`DefaultItems.tsx`) alongside Grid/Zen/View mode, plus a shortcuts entry in the Help dialog and `labels.hideBoundText` locale string.
- **Rendering**: gated the bound-text draw call in `renderer/staticScene.ts` on `!appState.hideBoundTextEnabled || isExporting` — the toggle only skips the canvas draw call, never touches element data, so it's instant and non-destructive; export (`isExporting: true`) always ignores the toggle.
- **Re-render wiring**: added the flag to `StaticCanvas.tsx`'s memoization whitelist so toggling repaints immediately.

Verified with `goga lint` (0 errors across governed cells), `tsc`, `eslint`/prettier, the full existing test suite (all passing, only expected snapshot additions), and a new `hideBoundText.test.tsx` covering the toggle, keyboard shortcut, canvas draw-call suppression, and export non-interference.
