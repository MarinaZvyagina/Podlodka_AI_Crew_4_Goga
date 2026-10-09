# R04-TB-BF-06

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $5.192430899999998
Duration: 541419ms, turns: 72

## Agent's own summary

The implementation is complete and verified. Summary:

**Core logic** — `packages/element/src/shape.ts`: added `getElementArea(element)`, returning rotation-invariant area:
- rectangle → `width * height`
- diamond → `width * height / 2`
- ellipse → `π * width * height / 4`
- line/freedraw → shoelace formula (`polygonArea` from `@excalidraw/math`) over the element's own points, only when the outline actually loops closed (`isPathALoop`) — open strokes return `null`
- everything else (text, images, frames, arrows, etc.) → `null`

Since the formula operates on each element's own local `width`/`height`/`points` rather than its rotated bounding box, area is automatically correct after rotation with no extra rotation math needed.

**UI wiring** — `packages/excalidraw/components/Stats/index.tsx`: computes `singleElementArea` for the selected element and renders an "Area" row right after Height (before Angle), matching the panel's existing rounding convention (`round(value, 2)`). The row is simply omitted when area is `null`, so open lines/text/etc. show nothing misleading. Multi-selection is unaffected, as the ticket only asked for single-shape measurement parity.

**Tests**: added `packages/element/tests/area.test.ts` (10 unit tests covering all shape types, rotation invariance, and open-vs-closed line/freedraw), plus 7 new integration tests in `stats.test.tsx` exercising the live panel (resize updates, rotation invariance, diamond/ellipse formulas, and correct omission for text/open lines).

**Verification**: `yarn test:typecheck` clean, `eslint --max-warnings=0` clean, 36/36 relevant tests pass, and `goga lint` reports 0 errors — the change stayed within `packages/element/src`'s documented contract (the frozen architecture forest only governs 5 cells; the Stats UI itself is outside that scope, consistent with `ARCHITECTURE_CONTRACTS.md`).
