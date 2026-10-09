# R04-TB-BF-05

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.75
Dangerous success: False
Goga engagement signal: True
Cost: $1.8304902000000003
Duration: 249448ms, turns: 55

## Agent's own summary

No cell-level `.usages/` files exist yet in any of the three cells — only inline `Usages` blocks in the CODEMANIFEST headers, already read. Now producing the final Investigation Report.

# Investigation Report

## Task Summary
Add a new exported pure function `getElementArea(element: ExcalidrawElement): number | null` to the `packages/element/src` cell, computing the enclosed area of a shape (closed-form for rectangle/diamond/ellipse/image/iframe/embeddable; shoelace polygon area for closed+filled line/freedraw outlines; `null` for shapes without a meaningful enclosed area). This supports a downstream Stats-panel UI feature (out of scope here) and requires no change to any existing behavior — it is a pure, additive leaf function.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `packages/element/src` | Target cell — hosts the new `getElementArea` export and its `CODEMANIFEST` | High |
| `packages/math/src` | Dependency provider — `polygonArea` (existing, unmodified) | Medium |
| `packages/common/src` | Dependency provider — `isTransparent` (existing, unmodified) | Medium |

## Tracing Summary
Confirmed via `goga-change-tracer`: `getElementArea` is a pure leaf routine with zero existing callers (grep for the identifier across `packages/` returns no hits). Call graph:
- Rectanguloid types (`rectangle`, `image`, `iframe`, `embeddable`) → `width * height`
- `diamond` → `(width * height) / 2`
- `ellipse` → `(Math.PI * width * height) / 4`
- `line` / `freedraw` → gated by `isPathALoop(element.points)` (local, `utils.ts:477`) AND `hasBackground(element.type)` (local, `comparisons.ts:3`) AND `!isTransparent(element.backgroundColor)` (cross-cell, `packages/common/src/colors.ts:360`) → `polygonArea(element.points)` (cross-cell, `packages/math/src/polygon.ts:106`)
- All other types (`text`, `arrow`, `frame`, `magicframe`, `selection`, non-looped/unfilled line/freedraw) → `null`

## Data Flow Analysis
Every input (`element.type`, `element.width`, `element.height`, `element.points: readonly LocalPoint[]`, `element.backgroundColor: string`) is local to the single element being queried — none require `elementsMap` or any other element's data. `element.angle` (rotation) is applied only at render/hit-test time and never mutates `width`/`height`/`points` (confirmed in `renderElement.ts`/`shape.ts` usage patterns), so both the closed-form formulas and the shoelace polygon computation are inherently rotation-invariant — satisfying the ticket's "rotated shape must report the same area as before rotation" requirement without any extra transform. Output (`number | null`) is a bare return value with no side effects and no persistence in this cell.

## Manifest Algorithm Analysis
`packages/element/src/CODEMANIFEST` has no existing entry for area computation (confirmed absent — this is a new Routine, not a mutation). Its Header `Imports` currently lists only `{arrayToMap, Emitter}` from `packages/common/src`, `{GlobalPoint, LocalPoint}` from `packages/math/src`, and `{generateNKeysBetween}` from `packages/fractional-indexing/src`. Per the DSL (`goga-cell`) and cookbook rules, the new body entry's use of `isTransparent` and `polygonArea` obligates adding both to the Header `Imports` — the manifest cannot document the new routine correctly without this addition. No existing `Usages`/`Annotations` in the header (`host_app_state`, `ordering_invariant`) apply to this routine — it touches neither host application state nor element ordering.

## Affected Usages

| Usage | Cell | Classification | Reason |
|---|---|---|---|
| `host_app_state` | packages/element/src | NOT AFFECTED | `getElementArea` takes only an `ExcalidrawElement`; no host app state parameter |
| `ordering_invariant` | packages/element/src | NOT AFFECTED | No element insertion/reordering/restoration involved |
| `branded_geometry_types` | packages/math/src | INDIRECTLY AFFECTED | `getElementArea` passes `element.points` (already typed `LocalPoint[]`) straight into `polygonArea`'s generic `Point extends LocalPoint | GlobalPoint` parameter — consistent with the existing branding convention, no new branding logic needed |
| `branding_pattern` / `env_detection` | packages/common/src | NOT AFFECTED | Neither branding construction nor environment detection is involved in calling `isTransparent` |

No `.usages/*.md` files exist yet in any of the three cells (confirmed via directory listing) — only inline header `Usages` blocks, all reviewed above.

## Rejected Hypotheses
- **H1 — Signature should include `elementsMap` (matching the pattern of `getElementAbsoluteCoords`/`getElementBounds`)**: Rejected. Those functions need `elementsMap` to resolve bound/related elements or absolute coordinates; `getElementArea` needs neither — every input is local to the element. Including an unused parameter would violate the "minimize scope" and "no speculative modifications" invariants.
- **H2 — Area for closed line/freedraw should use `getElementShape`/`ShapeCache` (the rough.js-tessellated hit-testing geometry in `packages/element/src/shape.ts`, which itself depends on `packages/utils/src`, a cell outside the frozen forest)**: Rejected. `packages/utils/src` has no `CODEMANIFEST` and is not part of the governed forest; routing area computation through it would pull an ungoverned dependency into a governed cell and considerably increase surface area for a "sensible rounding" precision requirement that a direct shoelace pass over `element.points` already satisfies.
- **H3 — Frame/magicframe should report bounding-box area since they have width/height**: Rejected per task's explicit scope — frames are organizational containers, not "shapes with a meaningful enclosed area" in the floor-plan/diagram sense the ticket targets; excluded to match the out-of-scope UI requirement's intent (frames excluded alongside text/arrow/selection).

## Confirmed Root Cause
Not a bug fix — a net-new capability. Root evidence chain: (1) `packages/element/src` owns the `ExcalidrawElement` type hierarchy and is the only cell with sufficient type information to discriminate on `element.type`; (2) all geometry primitives needed (`polygonArea`, `isTransparent`) already exist in already-imported dependency cells, requiring no new cell creation; (3) `isPathALoop` and `hasBackground` are already local to `packages/element/src`, confirmed by direct reads of `utils.ts:477` and `comparisons.ts:3`; (4) zero existing callers/collisions for the proposed name, confirmed by repo-wide grep — the addition is purely incremental.

## Confidence Level
**HIGH** — every fact (type shapes, function signatures, export paths, CODEMANIFEST current state, absence of name collisions) was confirmed by direct file reads and greps in this session, not inferred. No ambiguity remains for the planner.

## Breaking Change Assessment
1. Will existing function call with same arguments produce different behavior? **NO** — `getElementArea` is a new export; no existing function's behavior changes.
2. Will existing file paths change? **NO** — only new content added to `sizeHelpers.ts`; no file moved or removed.
3. Will output format change? **NO** — no existing output format exists for this capability.
4. Will return value semantics change? **NO** — net-new return semantics for a net-new function.
5. Will manifest-defined guarantees be altered? **NO** — only additive: one new Routine entry plus two new `Imports.Types` entries in `packages/element/src/CODEMANIFEST`; all existing manifest entries remain untouched.
6. Will existing tests break? **NO** — no existing test references `getElementArea` or any modified code path; existing exports/behavior are untouched.

**No breaking change detected.** Pipeline may proceed to Planning.
