# R04-TB-GC-05

Condition: goga_native_architecture
Base tag: condition-c-r04-v1
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: False
Cost: $3.426885299999999
Duration: 405351ms, turns: 63

## Agent's own summary

This is complete. Summary of the change:

**`packages/element/src/shape.ts`** — added `getElementArea(element, elementsMap)`, returning the true enclosed area (rotation-invariant) for rectangles (`w*h`), diamonds (`w*h/2`), ellipses (`π·a·b`), closed/polygon lines, and closed (looped) freedraw strokes via the shoelace formula (`polygonArea`) on the rotated shape geometry. Returns `null` for anything without a meaningful enclosed area (open lines, arrows, text, images, frames, etc.).

**`packages/excalidraw/components/Stats/index.tsx`** — computes `elementArea` for the single-selected element and renders a new "Area" row right after Height (and before Angle), using the same `round(value, 2)` convention as the existing Width/Height rows; the row is simply omitted when area is `null`.

**`packages/excalidraw/locales/en.json`** — added the `stats.area` label.

**`packages/element/tests/shape.test.ts`** (new) — 12 tests covering rectangle/diamond/ellipse area formulas, rotation invariance, closed vs. open lines/freedraw, and `null` for text/arrows.

All typechecks (`yarn test:typecheck`), lint, and the full `packages/element`/`Stats` test suites (588 tests) pass.
