# R04-TB-BF-03

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $2.8327406999999996
Duration: 420166ms, turns: 80

## Agent's own summary

Summary of the implementation:

**`packages/element/src/sizeHelpers.ts`** — added `getElementArea(element)`, a pure geometry helper in the documented `packages/element/src` Goga cell:
- Rectangle: `width * height`
- Diamond: `width * height / 2`
- Ellipse: `π * width * height / 4`
- Line/freedraw: shoelace formula (`polygonArea` from `@excalidraw/math`, already present) over the element's local points, but only when the outline is closed via `isPathALoop` — the same predicate the renderer itself uses to decide whether to paint a background fill, so "has area" matches "visually looks filled."
- Everything else (arrows, text, images, frames, open lines) returns `null`.

Rotation is a rigid transform, so no angle handling is needed — width/height and local points are already angle-independent, verified with an explicit rotation-invariance test.

**`packages/excalidraw/components/Stats/index.tsx`** — added a plain read-only "Area" row (following the existing `unCroppedDimension` pattern rather than the editable `DragInput`, since area is derived, not settable) directly below the height row for a single selected element; omitted entirely when `getElementArea` returns `null`.

**Tests** — 16 tests for `getElementArea` covering all shape types, rotation invariance, and open/closed line & freedraw cases; 5 new panel-level tests verifying live updates on resize/rotate and correct omission for non-area shapes.

Verified: `yarn test:typecheck` clean, `goga lint` still 0 errors across all 5 cells, and the full `packages/element` suite (566 tests) plus the Stats panel suite (24 tests) pass.
