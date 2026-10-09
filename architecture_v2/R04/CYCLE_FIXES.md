# CYCLE_FIXES.md — R04 (excalidraw/excalidraw) Condition C

No formalizable circular dependency required a code fix, but one real, structural
**bidirectional dependency was found and disclosed** rather than forced into a false
acyclic shape.

## `packages/common/src` ↔ `packages/math/src` — real, bidirectional, disclosed in prose

`packages/math/src` declares (correctly) an Import of `toBrandedType` from
`packages/common/src`. Facade audit of `packages/common/src` found the reverse edge is also
real: `colors.ts`, `utils.ts`, and `points.ts` genuinely import runtime values and types back
from `@excalidraw/math` (`clamp`, `degreesToRadians`, `average`, `pointFrom`, `pointFromPair`,
`Degrees`, `GlobalCoord`, `GlobalPoint`, `LocalPoint`).

Goga's DSL — and `goga lint`'s `imports_has_not_cyclical_deps` rule — rejects a formal
`Imports:` block in both directions between the same two cells. Since both directions are real
(not a documentation error to fix by deleting one side), the only honest options were: force one
direction to go undocumented (hiding a real dependency), or disclose the true shape in prose
without a formal declaration. Chosen: **disclosed in prose**, in both cells' own Annotations
sections (`packages/common/src/CODEMANIFEST` describes its real pull from `math`; the already-
existing `packages/math/src/CODEMANIFEST` describes its own side) — each cell's own manifest is
honest about what it actually imports, without contradicting Goga's one-formal-direction
constraint.

This differs from every prior repo's cycle handling in this study: R06 had a legitimate shared-
constant edge (no real cycle), R03 had one real cycle fixed by splitting out a leaf cell, R01 had
5 apparent cycles (2 fixed by file relocation, 3 disclosed as narrow/non-separable references).
R04's case is neither fixable by splitting (both cells are already minimal, single-purpose
leaves — `math` is pure geometry, `common` is pure shared utilities, and each genuinely needs a
handful of primitives from the other) nor a false positive — it is a real, small, mutual
dependency between two foundational utility cells, disclosed rather than hidden or forced.

## Everything else: acyclic

Full direct-import analysis across the other pairs among the 6 documented cells (`common`,
`math`, `fractional-indexing`, `element`, `element/arrows`, `excalidraw/actions`) found no other
cycles: `fractional-indexing` is a pure leaf (zero cross-cell imports); `element` depends on
`common`/`math`/`fractional-indexing` (one-directional); the new nested `element/arrows` cell
depends on its parent `element` and on `math`/`common` (one-directional, with the parent's
facade-composition reverse edge — `element/src/index.ts` re-exporting `arrows`'s public API —
documented in prose rather than formalized, since formalizing it would create a two-cell cycle
with `arrows`'s much heavier structural dependency going the other way); `excalidraw/actions`
depends on `common`/`math`/`element` (one-directional, nothing depends back on it).
