# R04-TC-B-10

Condition: baseline
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Cost: $3.872432550000001
Duration: 472223ms, turns: 86

## Agent's own summary

All tests and typecheck pass. Here's a summary of the implementation:

**New toggle: "Hide captions"** (`hideBoundTextEnabled` in `AppState`)

- **Reachable & discoverable**: added to the main menu's Preferences submenu (checkbox, matching `zenMode`/`gridMode` styling), the canvas right-click context menu, and the shortcuts help dialog — the same places `Zen mode`/`Toggle grid` live. Keyboard shortcut is `Alt+T` (`packages/excalidraw/actions/actionToggleHideBoundText.tsx`).
- **Non-destructive**: the toggle only flips a boolean in `AppState`; the render hook in `packages/excalidraw/renderer/staticScene.ts` simply skips drawing the bound text element for a container when `hideBoundTextEnabled` is on — no element data is touched, so toggling back on immediately restores the exact captions.
- **Works with or without a selection**: no predicate restricts it to a selection state, same as `zenMode`/`gridMode`.
- **Export-safe**: the render skip is gated by `!isExporting`, so `exportToCanvas` always draws captions regardless of the toggle; `exportToSvg`'s renderer doesn't even receive `AppState`, so it's structurally unaffected.
- **Composable with other toggles**: it's a fully independent `AppState` boolean (marked `browser: true, export: false, server: false`, like `zenModeEnabled`), so it doesn't interact with zen/grid/view mode state.
- **Scope**: only affects text bound via `getBoundTextElement` (containers and arrow labels) — freestanding text is untouched, per the ticket.

I also had to add `T` to the shared `CODES` map (`packages/common/src/keys.ts`) since it was missing and needed for the `Alt+T` shortcut. Ran `yarn test:typecheck`, `yarn test:update` (133 snapshots updated, all reflecting only the new `hideBoundTextEnabled: false` field), and `yarn fix` — all green.
