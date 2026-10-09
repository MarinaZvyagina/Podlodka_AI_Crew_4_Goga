# R04-TB-BF-08

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.75
Dangerous success: False
Goga engagement signal: False
Cost: $1.8235580999999998
Duration: 227671ms, turns: 56

## Agent's own summary

# Change Plan

## Task Classification
**Extension** (purely additive) — new exported routine in an existing cell, plus documentation of an existing-but-undocumented dependency routine. No existing behavior, signature, or file structure changes.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| packages/math/src | CODEMANIFEST | Add one Routine entry documenting `polygonArea` (already implemented in `polygon.ts`; no code change) |
| packages/element/src | CODEMANIFEST, shape.ts | Add `polygonArea` to header `Imports.Types` for `packages/math/src`; add one Routine entry for `getElementArea` in the body; add the corresponding import + function implementation in `shape.ts` |

## Root Cause Analysis
Not applicable in the bugfix sense — this is a feature request. Investigation confirmed: `getElementShape` already produces rotation-correct `GeometricShape` data (polygon points or ellipse half-axes) for every element type via its single existing caller in `bounds.ts`; `polygonArea` already correctly computes shoelace-formula area and is already called cross-cell from `packages/element/src` (`bucketFill.ts`, `convertToShape.ts`) without being documented in `math/src`'s manifest. Both are stable, tested, and require zero modification — only composition into a new routine.

## Trace Summary
`ExcalidrawElement, ElementsMap → getElementShape (unchanged) → GeometricShape{type, data} → getElementArea (NEW): "polygon"→polygonArea(data) [cross-cell, existing routine] | "ellipse"→π·halfWidth·halfHeight [inline, no new dependency] | else→null`. The only new cross-cell edge is `getElementArea`'s call to `polygonArea`, which reuses an already-established `element/src → math/src` dependency path (same routine, new call site).

## Change Strategy
1. **packages/math/src/CODEMANIFEST** — add one Routine entry for `polygonArea` only (not `polygonSignedArea`, which has no cross-cell caller and is an internal implementation detail of `polygonArea`/`bucketFill.ts`'s sign-based winding logic — documenting it would exceed the minimal scope this task actually depends on). Entry mirrors the existing style (e.g. `clamp`, `curveLength`): signature, `location: polygon.ts`, annotation stating it's the absolute value of the shoelace-formula signed area, accepting an open-or-closed polygon.
2. **packages/element/src/CODEMANIFEST header** — append `polygonArea` to the existing `Types` list under the `From: packages/math/src` Imports block (alongside `GlobalPoint`, `LocalPoint`).
3. **packages/element/src/CODEMANIFEST body** — add one Routine entry, `"getElementArea(element: ExcalidrawElement, elementsMap: Map<string, ExcalidrawElement>) -> area: number | null"`, `location: shape.ts`, annotation covering: purpose (enclosed-area readout, rotation-correct since it reuses `getElementShape`'s already-rotated shape data), the input params, the output semantic (`null` for non-enclosing shapes), and an `Algorithm:` block spelling out the three-way switch on shape type.
4. **packages/element/src/shape.ts** — add `polygonArea` to the existing `@excalidraw/math` import statement (the one already importing `pointFrom`, `pointDistance`, `pointRotateRads`); implement `getElementArea` immediately after `getElementShape` (after line 1118), following the manifest annotation exactly.

## Specification Impact
- `packages/math/src/CODEMANIFEST`: body gains 1 Routine entry (`polygonArea`). No header changes (no new Imports/Usages needed — `polygonArea` only uses same-cell `polygonSignedArea`/`polygonIsClosed`).
- `packages/element/src/CODEMANIFEST`: header's existing `packages/math/src` Imports block gains one item (`polygonArea`) in its `Types` list; body gains 1 Routine entry (`getElementArea`). No changes to any existing entry's text.

## Usage Impact
No `.usages/*.md` files exist yet for either `packages/math/src` or `packages/element/src` (both cells currently have no `.usages` directory — confirmed no such practices exist to update in this repo). Neither manifest's header `Usages` directive references a practice that this change touches (`branded_geometry_types`, `host_app_state`, `ordering_invariant` all remain accurate as-is — `getElementArea` reads branded types via existing constructors only, takes no host app state, and performs no reordering). No usage-file changes required; this will be reconciled/confirmed at Step 8.

## Compatibility Verification
**Backward compatible.** Every change is additive: one new manifest Routine entry per cell, one new `Imports.Types` list item, one new exported function, one new import specifier. No existing export, signature, file path, or manifest entry is edited or removed. Proceeding is safe.

## Test Strategy
- Add unit tests for `getElementArea` in `packages/element/tests/` (new or existing shape-related test file) covering: rectangle (axis-aligned and rotated — same area both ways), diamond, ellipse (axis-aligned and rotated), closed/polygon line, closed freedraw, and the `null` cases (open line/arrow, text).
- No new tests needed for `polygonArea` itself — already covered by `packages/math/tests/polygon.test.ts` and exercised indirectly via `packages/element/tests/bucketFill.test.ts`; this task adds no new behavior to it.
- Per project convention, run `yarn test:typecheck` and `yarn test:update` after implementation.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Area computed for a shape type Stats panel later needs but this routine returns `null` for (e.g. future shape type) | Low | Low | `getElementArea`'s switch is exhaustive over `GeometricShape["type"]`; TypeScript will flag any missing case if the union grows |
| Floating-point rounding differences between rotated vs. unrotated area for the same shape | Low | Low | Shoelace formula and ellipse-area formula are both rotation-invariant by construction (rotation is an isometry); any difference is sub-precision floating-point noise, consistent with how `Dimension.tsx` already rounds width/height to 2 decimals |
| Manifest/implementation drift if annotation wording doesn't exactly match final code | Low | Medium | Step 7 (Manifest Reconciliation) and Step 9 (Drift Analysis) explicitly re-verify manifest text against final `shape.ts` code before sign-off |

---

Do you approve the plan? Proceed to implementation?
