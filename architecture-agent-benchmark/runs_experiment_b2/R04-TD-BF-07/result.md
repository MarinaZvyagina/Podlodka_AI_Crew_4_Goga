# R04-TD-BF-07

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: False
Cost: $2.2835115000000004
Duration: 275950ms, turns: 59

## Agent's own summary

Good, `Keyboard.undo()` from `./helpers/ui` is the standard undo-test pattern. I have everything needed for the plan.

# Change Plan

## Task Classification
**Feature** (net-new, additive action) — no existing behavior is modified.

## Affected Cells
| Cell | Files to Modify | What Changes |
|---|---|---|
| `packages/excalidraw/actions` | New file `actionSnapToGrid.tsx`; edit `index.ts` (export) | New `Action` registered via `register()` |
| `packages/element/src` | None (consume-only: `Scene.mutateElement`, `updateBoundElements`, `rescalePointsInElement`, `isLinearElement`, `isFreeDrawElement`, `isFrameLikeElement`, `CaptureUpdateAction`) | No modification, only new call sites |
| `packages/common/src` | None (consume-only: `getGridPoint`, `MIN_WIDTH_OR_HEIGHT`, `arrayToMap`) | No modification |
| *(out-of-forest)* `packages/excalidraw` root | `components/App.tsx` (import/registration list), `locales/en.json` (new `labels.snapToGrid` key), optionally `actions/shortcuts.ts` | UI wiring only — not manifest-governed |

## Root Cause Analysis
No code path applies grid rounding to elements at rest — every existing `getGridPoint` call site is inside pointer-driven drag/resize/binding/linear-edit interaction code (`dragElements.ts`, `resizeElements.ts`/`App.tsx`, `binding.ts`, `linearElementEditor.ts`). This is additive capability, not a defect fix.

## Trace Summary
`perform(elements, appState, _, app)` → resolve targets (selection, or all non-deleted elements if selection is empty; frame-like elements excluded, matching the `alignActionsPredicate` precedent) → per target, independently: `getGridPoint(x, y, gridSize)` for position, `getGridPoint(x+width, y+height, gridSize)` for the opposite corner → derive `width`/`height` clamped to `MIN_WIDTH_OR_HEIGHT` → `scene.mutateElement(element, { x, y, width, height, ...rescalePointsInElement(element, width, height, true) })` (the spread is `{}` for non-linear/freedraw elements) → `updateBoundElements(element, scene, { simultaneouslyUpdated: targets })` → return `{ appState, elements: <full array>, captureUpdate: CaptureUpdateAction.IMMEDIATELY }`.

## Change Strategy
1. Create `packages/excalidraw/actions/actionSnapToGrid.tsx`:
   - `snapElementsToGrid(targets, appState, scene)` helper — loops `targets`, computes snapped `x/y/width/height` per element as above, calls `scene.mutateElement` + `updateBoundElements`, returns updated elements array (same shape as `alignSelectedElements`).
   - `register({ name: "snapToGrid", label: "labels.snapToGrid", icon: ..., predicate: (elements) => getNonDeletedElements(elements).filter(el => !isFrameLikeElement(el)).length > 0, perform: (elements, appState, _, app) => { const selected = app.scene.getSelectedElements(appState).filter(el => !isFrameLikeElement(el)); const targets = selected.length > 0 ? selected : getNonDeletedElements(elements).filter(el => !isFrameLikeElement(el)); return { appState, elements: <elements array with targets replaced by snapped versions>, captureUpdate: CaptureUpdateAction.IMMEDIATELY }; } })`.
2. Export the new action from `actions/index.ts` alongside the align/distribute exports.
3. Wire UI surface in the root app package (out-of-forest, done directly, no manifest reconciliation applies): import in `App.tsx`'s action import block so `register()`'s side effect runs and it becomes available via context menu / command palette; add `labels.snapToGrid` to `locales/en.json`.
4. No changes to any existing exported function signature in `packages/element/src` or `packages/common/src`.

## Specification Impact
`packages/excalidraw/actions` CODEMANIFEST gains one new `Action`-conforming entry (documented the same way `actionAlignTop` etc. would be, if those were individually catalogued — the manifest currently documents the `Action`/`register`/`ActionManager` contract types, not every concrete action instance, so **no CODEMANIFEST section requires editing**; the new action is an instance of the existing, unchanged `Action` contract). This will be re-verified in the Manifest Reconciliation step.

## Usage Impact
None. `host_app_state` (both cells) already documents exactly the pattern used (`perform` receiving opaque `elements`/`appState`, and `Scene`/`mutateElement` accepting the opaque host shape) — no usage file needs a new example, and no existing usage recipe is invalidated.

## Compatibility Verification
**Backward compatible.** Purely additive: one new file, one new export, one new registered action, zero edits to any existing function body, signature, or documented algorithm in the in-scope cells.

## Test Strategy
New `packages/excalidraw/actions/actionSnapToGrid.test.tsx`, modeled on `actionFlip.test.tsx` (`API.createElement`, render `<Excalidraw>`, `API.setSelectedElements`, `API.executeAction`):
1. Single selected rectangle off-grid → `perform` snaps `x/y/width/height` to the nearest `gridSize` multiples (assert exact expected numbers for a known `gridSize`/offset).
2. No selection → all non-deleted elements on canvas get snapped.
3. Two selected elements at different offsets from the grid → each snaps to *its own* nearest grid line (assert their relative offset from each other changes — proves independent, non-group snapping, satisfying the ticket's explicit requirement).
4. A freedraw or line element → assert `points` are rescaled consistently with the new `width`/`height` (no visual distortion), via `rescalePointsInElement`.
5. `Keyboard.undo()` after the action reverts every snapped element to its exact pre-snap `x/y/width/height` in one step (validates single-undo-step requirement using the existing `Keyboard.undo` test helper, same pattern as `drawShape.test.tsx:726`).

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Frame-like elements corrupted by independent resize (children don't follow) | Medium if included | Medium (visual bug, not data loss) | Exclude frame-like elements from targets, matching the existing `alignActionsPredicate` precedent (`!isFrameLikeElement`) |
| Zero/negative size after rounding for very small shapes | Low | Low (degenerate element) | Clamp with `MIN_WIDTH_OR_HEIGHT` (existing constant, `packages/common/src/constants.ts:521`) |
| Bound arrows/text left visually detached after their container snaps | Low | Medium | Call `updateBoundElements` per element, exact precedent from `alignElements` |
| `getGridPoint`/`MIN_WIDTH_OR_HEIGHT` undocumented in `packages/common/src` CODEMANIFEST (manifest drift, pre-existing) | Confirmed present | Low (doesn't block this task; may surface in Manifest Reconciliation as a pre-existing gap, not caused by this change) | Flag during Step 7 (Manifest Reconciliation); do not silently "fix" an unrelated cell's manifest beyond what's necessary |

Do you approve this plan? Proceed to implementation?
