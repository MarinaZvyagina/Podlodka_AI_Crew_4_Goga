# R04-TB-BF-01

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.75
Dangerous success: False
Goga engagement signal: True
Cost: $1.3623627000000003
Duration: 237103ms, turns: 45

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add a live, read-only "area" measurement to the single-selected-element section of the Stats/element-properties panel (`packages/excalidraw/components/Stats`), correct for rectangles, diamonds, ellipses, closed polygon lines, and looped freedraw (rotation-invariant), omitted for shapes without a meaningful enclosed area.

## Candidate Cells
| Cell | Reason | Priority |
|---|---|---|
| packages/element/src | Owns `ExcalidrawElement` variants and already exports the closedness/geometry primitives (`isValidPolygon`, `isPathALoop`, `isLineElement`, `isFreeDrawElement`, type discriminants) needed to decide which shapes have area | High (as a dependency to consume, not modify) |
| packages/math/src | Owns `polygonArea`/`polygonSignedArea` (shoelace formula), already public, needed for polygon/freedraw area | High (as a dependency to consume, not modify) |
| packages/excalidraw (components/Stats) | Actual UI surface being changed — new Area row, wiring into `Stats/index.tsx` | High (primary edit site) — **not a modeled cell** (no CODEMANIFEST) |

## Included Dependencies
| Cell | Behavioral Relevance |
|---|---|
| packages/element/src | Supplies element-type discriminants and closedness checks (`isValidPolygon`, `isPathALoop`, `isLineElement`, `isFreeDrawElement`) already exported via its `index.ts` barrel — consumed read-only, no new export needed |
| packages/math/src | Supplies `polygonArea` (shoelace formula) already exported via its `index.ts` barrel — consumed read-only, no new export needed |

## Excluded Dependencies
| Cell | Exclusion Reason |
|---|---|
| packages/common/src | No behavioral participation — not touched by area computation or display |
| packages/fractional-indexing/src | No behavioral participation — unrelated to geometry/UI |
| packages/excalidraw/actions | No behavioral participation — the Stats panel row is not an `Action`; no action registration involved |

## Usage Relationships
| Usage | Relevance |
|---|---|
| `host_app_state` (packages/element/src) | Not applicable — no host app-state parameter needed for a pure geometry read |
| `ordering_invariant` (packages/element/src) | Not applicable — no element insertion/reordering involved |

## Semantic Participation Summary
`packages/element/src` and `packages/math/src` participate only as **existing, already-public dependencies**: `isValidPolygon`, `isPathALoop`, `isLineElement`, `isFreeDrawElement` (element) and `polygonArea` (math) are already exported from each cell's public barrel (`index.ts`) and are the exact primitives `packages/element/src/bucketFill.ts`'s own closedness detection (`isClosedOwnerCandidate`) is built from — but that helper itself is private/unexported, so the new UI logic must replicate its two branches (line-`polygon` case, freedraw-loop case) using the public primitives rather than importing it directly.

Critically, neither of these two cells' **documented contracts** (CODEMANIFEST `types:` lists, confirmed via `goga schema`) need to change: the task only *consumes* pre-existing exports, it does not add a new type to either cell's public surface. `packages/excalidraw` (which owns `components/Stats`) has no CODEMANIFEST at all — per the `packages/excalidraw/actions` cell's own manifest annotation, the root `packages/excalidraw` package is explicitly out of scope for this documented architecture forest. All new code (the Area row component, its area-calculation logic, i18n key, tests) lives entirely inside this out-of-forest surface.

## Final Investigation Scope
- `packages/excalidraw/components/Stats/` (primary edit site: new Area component, wiring in `index.tsx`, `utils.ts` if a shared helper is warranted, `stats.test.tsx`)
- `packages/excalidraw/locales/en.json` (or wherever `stats.width`/`stats.height` keys live) for the new i18n label
- `packages/element/src` and `packages/math/src` — investigate only as **read-only dependencies** to confirm the exact exported signatures of `isValidPolygon`, `isPathALoop`, `isLineElement`, `isFreeDrawElement`, `polygonArea` (and any `ElementsMap`/`points` typing needed); no modification expected

## Scope Risks
- **Under-scoping risk**: if the ticket's "rotated shape must report the same area as before rotation" requirement turns out to need a geometry helper not already exported (e.g., if `polygonArea` isn't accessible the way assumed), scope would need to expand to a small new export in `packages/math/src` or `packages/element/src`, which *would* require CODEMANIFEST reconciliation for that cell.
- **Over-scoping risk**: none identified — resisting the temptation to promote the new area logic into `packages/element/src` as a shared exported helper keeps the change minimal and avoids unnecessary manifest churn, per "minimize scope."

## Notes
- `goga schema` lists only 5 documented cells (`packages/common/src`, `packages/math/src`, `packages/fractional-indexing/src`, `packages/element/src`, `packages/excalidraw/actions`); `packages/excalidraw` itself (including `components/Stats`) is not modeled, confirmed by both `find` (no CODEMANIFEST there) and the `actions` cell's own annotation calling out `packages/excalidraw` as "out of scope for this forest."
- `isValidPolygon`, `isPathALoop`, `isLineElement`, `isFreeDrawElement` (element) and `polygonArea` (math) exist in source and are exported via each cell's barrel `index.ts`, but are **not** listed in either cell's CODEMANIFEST `types:` section — confirming the manifest documents a curated architectural surface, not an exhaustive export index (the existing `Dimension.tsx`/`Position.tsx` Stats components already consume several undocumented exports the same way, e.g. `isImageElement`, `getUncroppedWidthAndHeight`).
