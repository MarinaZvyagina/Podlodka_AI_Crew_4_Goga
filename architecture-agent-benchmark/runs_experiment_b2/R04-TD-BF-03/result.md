# R04-TD-BF-03

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: False
Cost: $2.5665906000000005
Duration: 447881ms, turns: 80

## Agent's own summary

# Change Plan

## Task Classification
**Feature** (additive, net-new capability; no existing behavior modified)

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `packages/element/src` | New file `snapToGrid.ts`; `index.ts` already re-exports via `export * from` (no change needed there); `CODEMANIFEST` gains one new type entry | New exported routine `snapElementsToGrid` performing per-element grid snap of position and size |
| `packages/excalidraw/actions` | New file `actionSnapToGrid.tsx`; `CODEMANIFEST` unchanged (see Specification Impact) | New registered `Action` instance `snapSelectionToGrid` |
| `packages/excalidraw/components/App.tsx` | One-line addition to the element context-menu item list (`getContextMenuItems`, ~line 13618-13657) and the import list (~line 309-313) | Makes the action reachable with one right-click + one click, matching `actionFlipHorizontal`/`actionFlipVertical` placement precedent |
| `packages/excalidraw/locales/en.json` | One new key, `labels.snapToGrid` | Canonical source string for the action's menu label (other locales sync via Crowdin, per existing repo convention seen in `git log`) |

`packages/excalidraw/components/App.tsx` and `locales/en.json` sit outside the two documented forest cells (the actions manifest explicitly notes root-app UI wiring is "out of scope for this forest"), but touching them is necessary application wiring of the same kind `actionFlip.ts`/`actionAlign.tsx` already required (icon import, i18n label, context-menu registration) — not a new architectural surface.

## Root Cause Analysis
Not a defect — a capability gap. Every existing grid-snap consumer (`dragSelectedElements`, `resizeMultipleElements`/`transformElements`, inline `getGridPoint` calls in `App.tsx`) is either interactive/pointer-driven or computes one shared offset/scale for the whole selection ("group" behavior). No primitive performs a one-shot, per-element-independent snap of both position and size. Confirmed HIGH confidence in Investigation Report, no breaking change.

## Trace Summary
- `getGridPoint` (packages/common/src/points.ts:69) — reused unmodified for corner rounding.
- `resizeSingleElement` (packages/element/src/resizeElements.ts:722) — reused unmodified per-element, `handleDirection: "se"` anchors the already-snapped top-left corner while growing/shrinking to the snapped bottom-right corner.
- `scene.mutateElement` + `updateBoundElements` (packages/element/src/align.ts:38-46 precedent) — reused pattern for the position snap.
- `getSelectedElements` (packages/element/src/selection.ts:161) default options — reused unmodified to obtain top-level target elements.
- `ActionManager.executeAction`/inline dispatch (packages/excalidraw/actions/manager.tsx:147,176) — unmodified; new action flows through the exact same `perform → captureUpdate → updater` path as every other action, so undo and collaboration sync require zero new code.

## Change Strategy

**1. `packages/element/src/snapToGrid.ts` (new file)**
```ts
export const snapElementsToGrid = (
  elements: readonly NonDeletedExcalidrawElement[],
  elementsMap: NonDeletedSceneElementsMap,
  scene: Scene,
  gridSize: NullableGridSize,
): NonDeletedExcalidrawElement[]
```
- If `gridSize` is `null`, return `elements` unchanged (defensive; `perform` will always pass `appState.gridSize`, which is a `number`, so this is a no-op guard, not expected to trigger).
- For each element:
  - Skip (leave untouched) if it's a bound text element, or an elbow arrow with `startBinding || endBinding` (mirrors `dragElements.ts:44-64`).
  - Compute `[newX, newY] = getGridPoint(element.x, element.y, gridSize)`; if changed, `scene.mutateElement(element, { x: newX, y: newY })` then `updateBoundElements(element, scene)`.
  - Unless the element `isFrameLikeElement` or `isElbowArrow`: compute `[targetX2, targetY2] = getGridPoint(element.x + element.width, element.y + element.height, gridSize)`; `nextWidth = targetX2 - newX`, `nextHeight = targetY2 - newY`; if both `> 0` and either differs from current width/height, call `resizeSingleElement(nextWidth, nextHeight, element, element, elementsMap, scene, "se")`.
- Return the array of (possibly mutated) elements read back from `elementsMap`/`scene` so the caller can merge into the full elements array — mirrors `flipSelectedElements`'s `arrayToMap` + `elements.map` merge pattern in `actionFlip.ts:103-107`.

**2. `packages/excalidraw/actions/actionSnapToGrid.tsx` (new file)**
```ts
export const actionSnapSelectionToGrid = register({
  name: "snapSelectionToGrid",
  label: "labels.snapToGrid",
  icon: gridIcon,
  trackEvent: { category: "element" },
  perform: (elements, appState, _, app) => {
    const targetElements = app.scene.getSelectedElements(appState).length
      ? app.scene.getSelectedElements(appState)
      : getNonDeletedElements(elements);
    const updated = snapElementsToGrid(
      targetElements,
      app.scene.getNonDeletedElementsMap(),
      app.scene,
      appState.gridSize as NullableGridSize,
    );
    const updatedMap = arrayToMap(updated);
    return {
      elements: elements.map((el) => updatedMap.get(el.id) || el),
      appState,
      captureUpdate: CaptureUpdateAction.IMMEDIATELY,
    };
  },
});
```
No `keyTest` (ticket specifies no particular shortcut; avoids picking an arbitrary, possibly-conflicting key combo). No `predicate` (action is always applicable — it degrades to "snap everything" when nothing is selected, per the ticket).

**3. `App.tsx` wiring**: import `actionSnapSelectionToGrid`; add it to the element context-menu array (near `actionFlipHorizontal`/`actionFlipVertical`, since both are "adjust geometry of selection" operations).

**4. `en.json`**: add `"labels": { "snapToGrid": "Snap to grid" }`.

## Specification Impact
- **`packages/element/src/CODEMANIFEST`**: add one new Routine type entry (`"snapElementsToGrid(...)"`) to the body, consistent with existing granularity (the manifest already lists comparable capability-level routines like `transformElements`, `duplicateElements`). Header `Imports`/`Usages`/`Annotations` unchanged — no new cross-cell dependency is introduced (`getGridPoint` comes from `packages/common/src`, already an existing dependency of this cell per `.goga/config.yml`'s dependency graph... to be double-checked at reconciliation step for whether `packages/common/src` needs adding to this cell's `Imports`).
- **`packages/excalidraw/actions/CODEMANIFEST`**: **no change**. Confirmed by re-reading the manifest body: it documents only the generic `Action`/`register`/`ActionManager` contract and does not enumerate individual registered action instances (e.g. `actionFlip`, `actionAlign` have no manifest entries today either), so adding one more instance doesn't touch the contract.

## Usage Impact
No `.usages/*.md` files exist yet for either cell (`.goga/config.yml`'s schema output shows `usages: []` for every cell). No usage file requires creation for this change — it doesn't introduce a new consumption pattern distinct from what `actionFlip.ts`/`actionAlign.tsx` already demonstrate inline. (Usage reconciliation, Step 8, will confirm this rather than assume it.)

## Compatibility Verification
**Backward compatible.** Purely additive: two new files, one new manifest type entry, one new locale key, one new array entry in an existing UI list. No existing exported signature, return shape, file path, or manifest guarantee changes. No existing test can be affected since no existing code path is modified.

## Test Strategy
- Unit test for `snapElementsToGrid` (packages/element/src, colocated `*.test.ts` per repo convention seen in e.g. `actionFlip.test.tsx`): 
  - single rectangle with off-grid x/y/width/height snaps all four to nearest grid line
  - two independently-selected shapes with different offsets each snap to their own nearest grid line (not a shared group offset) — this is the requirement most likely to regress silently, so assert it explicitly
  - element already on-grid is a no-op (no spurious mutation/history entry)
  - bound text element is skipped directly but follows its container (verify via container resize)
  - elbow arrow with bindings is left untouched
  - frame-like element: position snaps, size does not
- Action-level test (`actionSnapToGrid.test.tsx`, mirroring `actionFlip.test.tsx`/`actionDuplicateSelection.test.tsx` structure): empty selection → snaps all elements; non-empty selection → snaps only selection; single `perform` call produces a single undoable history step (assert via the app's history/undo helper used in existing action tests).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `resizeSingleElement` behaves unexpectedly on an untested element subtype (image aspect-ratio lock, container with bound text) | Low-Medium | Medium (visually wrong resize, not data loss) | Reuse the function exactly as designed (no bypass of its internal `boundTextElement`/`shouldMaintainAspectRatio` handling); cover via unit tests per Test Strategy; frame/elbow-arrow explicitly excluded from size-snap where no safe fork exists |
| Degenerate snap collapses a shape's two corners onto the same grid line (nextWidth/Height ≤ 0) | Low | Low (would create a zero-size shape) | Explicit guard: skip size mutation when computed `nextWidth`/`nextHeight` ≤ 0 |
| Context-menu placement choice is subjective/could be contested in review | Low | Low | Mirrors existing `actionFlipHorizontal`/`actionFlipVertical` placement precedent exactly |
| New manifest type entry granularity judgment call (whether `snapElementsToGrid` "deserves" a CODEMANIFEST body entry) | Low | Low | Deferred to Step 7 (manifest reconciler) with this plan's stated rationale; not a blocking ambiguity |

---

Do you approve this plan? Proceed to implementation?
