# R04-TB-GC-10

Condition: goga_native_architecture
Base tag: condition-c-r04-v1
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: False
Cost: $3.135706800000001
Duration: 314552ms, turns: 56

## Agent's own summary

Implementation complete. Summary of changes:

- **`packages/element/src/area.ts`** (new): `getElementArea(element)` returns the enclosed area or `null`. Rectangle → `w*h`, diamond → `w*h/2`, ellipse → `π*w*h/4` (all rotation-invariant since rotation is rigid). Line → shoelace-formula area (`polygonArea` from `@excalidraw/math`) only when `element.polygon` is true; freedraw → same shoelace area only when the stroke loops back on itself (`isPathALoop`). Everything else (text, arrows, open lines/freedraw, images, frames) returns `null`.
- **`packages/excalidraw/components/Stats/index.tsx`**: computes `elementArea` for the single selected element and renders a new "Area" row (same `round(value, 2)` formatting as W/H) right after the W/H rows, omitted when `null`.
- **`packages/excalidraw/locales/en.json`**: added `stats.area: "Area"`.
- Tests: `packages/element/tests/area.test.ts` (unit tests for the helper) and new cases in `stats.test.tsx` covering live updates on resize, rotation invariance, diamond/ellipse formulas, and omission for text/open-line/open-freedraw/arrow.

`yarn test:typecheck`, lint, and the full `yarn test:update` suite (123 files, 1878 tests) all pass.
