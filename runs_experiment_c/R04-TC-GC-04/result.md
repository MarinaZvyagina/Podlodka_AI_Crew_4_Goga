# R04-TC-GC-04

Condition: goga_native_architecture
Base tag: condition-c-r04-v1
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: False
Cost: $6.972584400000001
Duration: 1203973ms, turns: 111

## Agent's own summary

## Summary

Implemented a "Toggle captions" feature that hides/shows all text bound to shapes and arrows, following the exact same pattern as the existing `zenMode`/`gridMode` toggles:

**New AppState flag:** `hideCaptionsEnabled` (`packages/excalidraw/types.ts`, `appState.ts`) — persists locally, syncs across collab, and survives `.excalidraw` export, same tier as `gridModeEnabled`.

**New action** `actionToggleHideCaptions` (`packages/excalidraw/actions/actionToggleHideCaptions.tsx`) — reachable via:
- Main menu → Preferences → "Toggle captions" checkbox (shows live on/off state)
- Keyboard shortcut `Alt+C`
- Canvas right-click context menu (both view-mode and edit-mode variants)

**Rendering:** gated at the single point in `renderer/staticScene.ts` where a resolved bound-text element gets painted (`if (boundTextElement && !appState.hideCaptionsEnabled)`). Since this function backs both the live on-screen canvas and canvas-based PNG export/clipboard copy, toggling it produces exactly the "clean screenshot" the ticket describes, without touching element data — the caption's text and its binding to the container are never modified, so toggling back on restores it pixel-identical.

**Verified:**
- `yarn test:typecheck` and full `yarn test:update` (1860 tests) pass; snapshot diffs are only the expected new `hideCaptionsEnabled: false` field appearing in serialized AppState.
- `yarn fix` (lint/format) clean.
- End-to-end in a real browser: drew a rectangle with a bound caption, confirmed the menu item and `Alt+C` shortcut both hide/restore the caption exactly while leaving the shape untouched, confirmed it works with and without a selection, and confirmed it composes correctly with Zen mode (both active simultaneously, neither overriding the other).
