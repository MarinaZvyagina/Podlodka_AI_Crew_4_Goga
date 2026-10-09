# R04-TB-BF-02

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $2.7881717999999998
Duration: 448159ms, turns: 75

## Agent's own summary

All 100 tests pass, typecheck is clean, and `goga lint` shows no violations. Summary of changes:

- **`packages/element/src/sizeHelpers.ts`**: added `getElementArea(element)`, returning the enclosed area for rectangles, diamonds, and ellipses (from `width`/`height`, which is rotation-invariant), and for closed line/freedraw paths (via the existing `polygonArea` shoelace helper on raw local points, reusing the same "is this a closed loop" checks — `isValidPolygon`/`element.polygon`, `isPathALoop` — already used by the bucket-fill feature). Returns `null` for everything else (text, arrows, open lines/freedraw, images, etc).
- **`packages/excalidraw/components/Stats/index.tsx`**: added a live, read-only "Area" row to the single-element properties panel, shown only when `getElementArea` returns non-null, using the same `round(…, 2)` formatting as width/height.
- **`packages/excalidraw/locales/en.json`**: added the `stats.area` translation key.
- Added tests: unit tests for `getElementArea` (`packages/element/tests/sizeHelpers.test.ts`) and panel integration tests (`stats.test.tsx`) covering live updates on resize, rotation-invariance, and omission for non-enclosing shapes.

Goga's architecture forest only documents 5 leaf cells (`common`, `math`, `element`, `fractional-indexing`, `actions/`); the Stats UI isn't governed by any CODEMANIFEST, so no contract update was needed there. The one touched governed cell (`packages/element/src`) got a small additive helper consistent with existing undocumented-but-exported helpers (e.g. `getUncroppedWidthAndHeight`), and `goga lint` confirms no contract violations.
