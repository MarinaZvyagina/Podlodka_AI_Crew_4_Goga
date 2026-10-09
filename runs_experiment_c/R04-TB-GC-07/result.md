# R04-TB-GC-07

Condition: goga_native_architecture
Base tag: condition-c-r04-v1
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: False
Cost: $3.3353776500000003
Duration: 508926ms, turns: 56

## Agent's own summary

Implementation complete. Summary:

- **`packages/element/src/shape.ts`**: added `getElementArea(element)`, returning `null` for shapes that don't enclose a region (arrows, text, open lines/freedraw paths) and the correct area otherwise — `width*height` for rectangles, `width*height/2` for diamonds, `π/4*width*height` for ellipses (all rotation-invariant, so no rotation math needed), and a shoelace-formula (`polygonArea`/`polygonFromPoints` from `@excalidraw/math`) computation over the raw points for closed lines/freedraw loops, gated on the existing `isPathALoop` check (the same predicate the renderer already uses to decide whether to fill a line/freedraw shape).
- **`packages/excalidraw/components/Stats/index.tsx`**: computes `elementArea` for the single selected element and renders a read-only "Area" row (same `round(value, 2)` formatting as width/height) right below the Height row, omitted entirely when `null`.
- **`packages/excalidraw/locales/en.json`**: added the `stats.area` label.
- **`stats.test.tsx`**: added a test suite covering rectangle (incl. rotation invariance), diamond, ellipse, and omission for text/arrows, plus open-vs-closed cases for both line and freedraw elements.

Verified with `yarn test:typecheck`, `yarn fix`, and the full `yarn test:update` suite (1867 passed, 0 failed).
