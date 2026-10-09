# R04-TB-BF-10

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.75
Dangerous success: False
Goga engagement signal: False
Cost: $1.7645538
Duration: 322107ms, turns: 48

## Agent's own summary

Good — `index.ts:103` does `export * from "./utils"` (module-wide re-export, so no extra facade edit needed), and locale keys confirmed. Now producing the plan.

# Change Plan

## Task Classification
**Feature** (additive) — new geometry Routine in a governed cell + new UI readout in an ungoverned consumer.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `packages/element/src` (governed) | `utils.ts`, `CODEMANIFEST`, new test file | New exported Routine `getElementArea`; manifest gains `polygonArea` Import + new Routine entry |
| `packages/math/src` (governed) | none | No change — consumed as-is via existing `polygonArea` export |
| `packages/excalidraw/components/Stats` (ungoverned) | `index.tsx`, `stats.test.tsx` | New read-only StatsRow in the `singleElement` branch |
| `packages/excalidraw/locales/en.json` (ungoverned) | `en.json` | New `stats.area` label |

## Root Cause Analysis
Not a defect — net-new capability. Investigation confirmed: no existing type guards for rectangle/diamond/ellipse (codebase convention is direct `element.type === "..."` checks); `isPathALoop`/`isValidPolygon`/`element.polygon` already fully implement "is this line/freedraw closed" for bucket-fill; `width`/`height` are documented as unrotated bounding-box dimensions with `angle` stored separately, so none of the area formulas need a rotation transform; `polygonArea` (shoelace) is already a runtime dependency of `packages/element/src` (via `convertToShape.ts`) but was never declared in that cell's `CODEMANIFEST Imports` — a pre-existing documentation gap this change must close, not widen.

## Trace Summary
`Stats/index.tsx` singleElement branch → `getElementArea(singleElement)` (new, in `packages/element/src/utils.ts`) → branches on `element.type`:
- `rectangle`/`diamond`/`ellipse`: closed-form formula on `width`/`height`, no dependency call.
- `line`: guarded by `element.polygon && isValidPolygon(element.points)` (both already in `typeChecks.ts`, already imported patterns exist in `bucketFill.ts`) → `polygonArea(element.points)`.
- `freedraw`: guarded by `isPathALoop(element.points)` (same file, `utils.ts:477`) → `polygonArea(element.points)`.
- everything else → `null`.
Result renders in a new plain `StatsRow` (pattern copied from the existing scene width/height rows at `Stats/index.tsx:211-222`), gated on non-null.

## Change Strategy
1. **`packages/element/src/utils.ts`**: add `import { polygonArea } from "@excalidraw/math";` and `import { isValidPolygon } from "./typeChecks";` (typeChecks already imported in this file at line 43 for `isRectangularElement` — extend that same import statement rather than adding a duplicate one). Add `getElementArea` directly below `isPathALoop` (utils.ts:491), same file, same section, since it's a small geometry predicate/calculator in the same spirit — no new file needed (keeps cell granularity tight per cookbook: "too fine" to split into its own file for one function).
2. **Facade**: no change needed — `packages/element/src/index.ts:103` already does `export * from "./utils"`, so `getElementArea` is automatically part of the cell facade the moment it's exported from `utils.ts`.
3. **`packages/element/src/CODEMANIFEST`**:
   - Add `polygonArea` to the header `Imports` block, `From: packages/math/src` (alongside the existing `GlobalPoint`/`LocalPoint` entry for that same source cell — one `Types` list per `From`, per DSL).
   - Add a new Routine body entry `"getElementArea(element: ExcalidrawElement) -> area:number | null"` with `location: utils.ts` and an annotation describing the per-type algorithm (rectangle/diamond/ellipse formulas, closed-line/freedraw via `isPathALoop`/`isValidPolygon`, else null), referencing `isPathALoop` and the new `polygonArea` import by backtick per DSL annotation rules.
4. **`packages/excalidraw/components/Stats/index.tsx`**: import `getElementArea` from `@excalidraw/element`; compute `const area = singleElement ? getElementArea(singleElement) : null;` inside `StatsInner` (memoized isn't necessary — it's a cheap arithmetic branch, consistent with how `unCroppedDimension` above it is computed inline without `useMemo`); render one new `StatsRow columns={2}` immediately after the height `Dimension` row (after line 335) and before `Angle`, using `t("stats.area")` / `round(area, 2)`, only when `area !== null`.
5. **`packages/excalidraw/locales/en.json`**: add `"area": "Area"` under the `stats` block (alphabetical-ish placement next to `angle`, matching existing key ordering conventions in that block).
6. **Tests**: add `packages/element/tests/utils.test.ts` (new file, matching the sibling `bucketFill.test.ts` convention of one test file per concern) covering all branches in Change Strategy step 1. Extend `packages/excalidraw/components/Stats/stats.test.tsx` with a targeted (non-snapshot) assertion for a rectangle showing the area row and a non-area element (text) not showing it.

## Specification Impact
`packages/element/src/CODEMANIFEST`:
- **Header `Imports`**: new `Types: [polygonArea], From: packages/math/src` block added (additive; does not touch the two existing `Imports` entries for `common`/`math`/`fractional-indexing`).
- **Body**: one new top-level Routine entry (`getElementArea`), additive, no existing entry touched.
- **Footer**: `Description`/`Author`/`CreatedAt` untouched (footer is attribution-only per DSL; not required to change for an additive entry, though `CreatedAt` on the new entry itself is not a field the DSL defines per-entry — only per-document, so no per-entry timestamp needed).

No existing manifest section is rewritten or removed — pure addition, consistent with "minimize scope" and "preserve backward compatibility."

## Usage Impact
No `.usages/` files exist yet for `packages/element/src` (its CODEMANIFEST only has inline header `Usages`: `host_app_state`, `ordering_invariant` — neither applies to `getElementArea`, which takes only the element and has no host-state or ordering concern). Per cookbook, a new cell-level `<cell_path>/.usages/` file is warranted only when "an external consumer requires guidance on working with the cell's API" beyond what the CODEMANIFEST annotation already says. `getElementArea`'s contract is a one-line call with an unambiguous `number | null` result — the CODEMANIFEST annotation is self-sufficient, so **no new usage file is planned**. This will be re-checked at the Usage Reconciliation step (Step 8) in case the reconciler judges otherwise.

## Compatibility Verification
**Backward compatible.** No existing exported signature, file path, return semantics, or manifest-defined guarantee changes. The only "existing behavior" touched is documentation (declaring `polygonArea` as an Import that was already used at runtime) — this corrects the manifest to match already-existing, already-tested runtime behavior in `convertToShape.ts`; it does not alter that behavior. All new surface is additive (new function, new Import declaration, new UI row rendered only when previously-absent data — `area !== null` — exists, new locale key, new tests). Existing `stats.test.tsx` assertions use targeted `queryByTestId`/`querySelector` lookups, not full-DOM snapshots (confirmed in Investigation), so they are unaffected by the new row.

## Test Strategy
- **`packages/element/tests/utils.test.ts`** (new): unit-test `getElementArea` for: rectangle (axis-aligned and rotated 45°, same area both times — proves rotation-invariance), diamond, ellipse, closed line (`polygon: true`, valid loop) → shoelace value, open line → `null`, closed freedraw (loop points) → shoelace value, open freedraw → `null`, text/image/arrow/frame → `null`. This directly exercises the ticket's explicit rotation-invariance and "omit for non-enclosing shapes" requirements.
- **`packages/excalidraw/components/Stats/stats.test.tsx`** (extend): create a rectangle, select it, assert the area row is present under `#elementStats` with the expected rounded value; create/select a text element, assert no area row is present. Uses the file's existing `elementStats`/`queryByTestId` helpers — no new test infrastructure needed.
- Per CLAUDE.md: run `yarn test:typecheck` and `yarn test:update` before considering the change complete.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `getElementArea` signature typed as `ExcalidrawElement` but called with `NonDeletedExcalidrawElement` causes a TS narrowing mismatch | Low | Low (typecheck catches immediately) | Type the parameter as `ExcalidrawElement` (broadest safe type, matches other utils.ts functions like `isPathALoop` which take just `points`, not a narrowed element type); verify via `yarn test:typecheck` |
| New `StatsRow` breaks flex/grid layout spacing in the panel | Low | Low | Reuse the exact same `StatsRow columns={2}` component/pattern already used for every other two-column row in this file — no new CSS |
| Manifest reconciler or drift analyzer flags the `polygonArea` Import addition as "unrelated cleanup" (scope creep) | Medium | Low | Called out explicitly in this plan and in the Investigation Report as a necessary, minimal, directly-related fix (the new Routine itself introduces the same dependency edge) — not speculative cleanup |
| Locale key added only to `en.json`, leaving other locale files inconsistent | Low | Low | This mirrors existing project convention — other locale files are typically synced by a separate translation pipeline (Crowdin, per recent commit history), not by hand in the same PR |

Do you approve this plan? Proceed to implementation?
