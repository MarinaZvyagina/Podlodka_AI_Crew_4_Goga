# R04-TD-BF-01

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: False
Cost: $2.1845087999999997
Duration: 357709ms, turns: 65

## Agent's own summary

# Change Plan

## Task Classification
**Feature** (new, additive action) — extends `packages/excalidraw/actions` with a new command; no existing behavior is modified.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `packages/excalidraw/actions` | New: `actionSnapToGrid.ts`. Edit: `index.ts` (export), `CODEMANIFEST` (document new type + reconcile `Imports`) | New `Action` object `actionSnapToGrid`, registered via `register()`, exported from the cell facade |
| `packages/element/src` | New: `snapElementsToGrid.ts` (small helper housing the per-element snap algorithm, called by the action). Edit: `index.ts` (export), `CODEMANIFEST` (add the new routine to `types:`) | New routine that snaps one element's position+size to the grid, reusing `mutateElement`, `updateBoundElements`, `resizeSingleElement` internally |
| `packages/common/src` | None | `getGridPoint` consumed as-is, no change |
| App-level (outside the 5-cell forest, required for reachability) | `packages/excalidraw/components/CommandPalette/CommandPalette.tsx` (add list entry), `packages/excalidraw/locales/en.json` (add label string) | Wires the action into the command palette/keyboard-shortcut surface; not governed by any CODEMANIFEST in this forest |

**Design note:** the actual snap algorithm is placed in `packages/element/src` (not inline in the action) because it needs `resizeSingleElement`'s `ElementsMap`/`Scene` machinery, which is that cell's contract surface — this keeps `packages/excalidraw/actions` a thin dispatcher, matching the existing `actionAlign.tsx` → `alignElements` (in `element/src`) split.

## Root Cause Analysis
No existing code path lets a user retroactively snap already-placed elements to the grid in one step — all `getGridPoint` call sites are wired to live pointer interaction (drag/resize/line-editing). This is a feature gap, not a defect. (Full detail in Investigation Report above.)

## Trace Summary
New action → `app.scene.getSelectedElements(appState)` (fallback: `app.scene.getNonDeletedElements()` filtered for `!locked`) → per element, skip bound-text (`containerId` set) and elbow arrows with both bindings → `snapElementsToGrid` helper: `getGridPoint` for position → `scene.mutateElement` + `updateBoundElements` → `getGridPoint` on the snapped bottom-right corner for the size target → `resizeSingleElement(nextW, nextH, el, el, scene.getNonDeletedElementsMap(), scene, "se", {shouldMaintainAspectRatio:false})` → action returns `{elements, appState, captureUpdate: CaptureUpdateAction.IMMEDIATELY}`.

## Change Strategy
1. **`packages/element/src/snapToGrid.ts`** (new file): export `snapElementToGrid(element, scene, gridSize)` — encapsulates the getGridPoint → mutateElement → updateBoundElements → resizeSingleElement sequence for exactly one non-deleted, non-locked, non-bound-text, non-fully-bound-elbow-arrow element. Clamps `nextWidth`/`nextHeight` to `MIN_WIDTH_OR_HEIGHT` (from `@excalidraw/common`, same constant `Stats/Dimension.tsx` uses) to avoid degenerate/negative sizes when an element is smaller than the grid spacing.
2. **`packages/element/src/index.ts`**: add `export * from "./snapToGrid";`.
3. **`packages/excalidraw/actions/actionSnapToGrid.ts`** (new file): `register({ name: "snapToGrid", label: "labels.snapToGrid", icon, trackEvent: {category:"canvas"}, predicate: (elements, appState) => !appState.viewModeEnabled, perform: (elements, appState, _, app) => {...}, keyTest: undefined })`. `perform`: get selection via `app.scene.getSelectedElements(appState)`; if empty, fall back to `getNonDeletedElements(elements).filter(el => !el.locked)`; call `snapElementToGrid` per element with `appState.gridSize` wrapped the same way `getEffectiveGridSize` gates it elsewhere (grid snapping only applies when a grid size is configured — following existing convention, do **not** silently no-op when grid is off; the ticket says "using the grid spacing that's already configured," so read `appState.gridSize` directly, consistent with `dragElements.ts`'s use of the raw `gridSize` prop). Return `{ elements, appState, captureUpdate: CaptureUpdateAction.IMMEDIATELY }`.
4. **`packages/excalidraw/actions/index.ts`**: export `actionSnapToGrid`.
5. **`packages/excalidraw/components/CommandPalette/CommandPalette.tsx`**: add `actionManager.actions.snapToGrid` to the `elementsCommands` array with an explicit `predicate: () => true` transformer override (so it's available with no selection, unlike the array's default `selectedElements.length > 0` predicate).
6. **`packages/excalidraw/locales/en.json`**: add `"labels.snapToGrid": "Snap to grid"`.
7. **CODEMANIFEST reconciliation** (Step 7 of the pipeline, not done here): add `snapElementToGrid` to `packages/element/src`'s `types:`/body, and reconcile `packages/excalidraw/actions`'s CODEMANIFEST `Imports`/body per the manifest-reconciler's own rules (may choose to document only the headline type, matching existing precedent where individual align actions aren't separately enumerated — final call deferred to that step).

## Specification Impact
- `packages/element/src/CODEMANIFEST`: add a new Routine entry for `snapElementToGrid(element, scene, gridSize) -> element:ExcalidrawElement`, documenting its algorithm (round position, then round the far corner and resize toward it, anchoring the near corner) and its reuse of `mutateElement`/`updateBoundElements`/`resizeSingleElement`.
- `packages/excalidraw/actions/CODEMANIFEST`: per existing precedent (individual align/z-index actions are not separately enumerated in the body — the manifest documents the `Action`/`register`/`ActionManager` extension-point contract itself), no new body entry is strictly required; the manifest reconciler will confirm whether to add a short mention in `Annotations` noting grid-snap is a supported action category, consistent with cookbook guidance to keep the manifest at the contract-shape level rather than an exhaustive action registry.
- No changes to `packages/common/src` or `packages/math/src` manifests — consumed unchanged.

## Usage Impact
No `.usages/*.md` files currently exist for `packages/element/src` or `packages/excalidraw/actions` in this forest, so none require updates. If the manifest reconciler determines a cell-level usage file should be added to document the new `snapElementToGrid` consumption pattern for future consumers, that will be created in Step 7/8, not here.

## Compatibility Verification
**Backward compatible.** No existing function signature, file path, output format, return semantics, or manifest guarantee changes. All changes are additive (new files, new exports, one new array entry in `CommandPalette.tsx`, one new locale key). Confirmed NO on all six Breaking Change Assessment questions in the Investigation Report.

## Test Strategy
Add `packages/excalidraw/actions/actionSnapToGrid.test.tsx` (mirroring the style of `actionFlip.test.tsx`/`actionDuplicateSelection.test.tsx` already in that directory) covering:
- Single selected rectangle snaps `x`/`y`/`width`/`height` to the nearest grid line, matching hand-computed expected values for a known `gridSize`.
- Two selected shapes at different offsets from the grid each snap independently (not as a merged bounding box) — assert each element's own rounded values.
- No selection → every non-deleted, unlocked element on the canvas is snapped; a locked element is left untouched.
- A single `Ctrl+Z` after the action restores the pre-snap `x`/`y`/`width`/`height` for all affected elements (one history step).
- A rectangle with bound text: container snaps; bound text repositions/rewraps via the existing `resizeSingleElement` bound-text path rather than being independently mis-snapped.
- Arrow bound to two rectangles: after both rectangles snap, `updateBoundElements` keeps the arrow attached (endpoints move with the bound shapes).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Element smaller than grid spacing collapses to near-zero/negative size after independent corner rounding | Medium | Visual glitch, possible flipped element | Clamp `nextWidth`/`nextHeight` to `MIN_WIDTH_OR_HEIGHT` before calling `resizeSingleElement`, mirroring `Stats/Dimension.tsx` |
| Frame children could visually drift relative to their frame since each element (including the frame itself) snaps independently rather than as a group | Low | Minor sub-grid-cell visual offset between frame and children | Accepted limitation — ticket explicitly requires independent per-shape snapping, not group-preserving; documented, not blocking |
| Elbow arrows (auto-routed, position derived from bound elements) snapped directly could fight their own auto-routing | Medium | Visual jitter/incorrect routing | Exclude elbow arrows with both bindings from direct snapping (they'll visually follow their now-snapped bound shapes automatically, same exclusion pattern as `dragSelectedElements`) |
| `resizeSingleElement` is not listed in `packages/element/src`'s `types:` schema summary | Low | Perceived manifest violation | Investigation confirmed this is already a load-bearing cross-cell dependency (`Stats/Dimension.tsx`, `Stats/MultiDimension.tsx`); Manifest Reconciliation step will add it to `types:` for documentation currency |
| Command palette entry needs its own predicate override to remain available with no selection | Low | Command invisible when nothing selected, contradicting "apply to all" requirement | Explicit `predicate: () => true` override on the `CommandPalette.tsx` list entry, per Change Strategy step 5 |

---

Do you approve this plan? Proceed to implementation?
