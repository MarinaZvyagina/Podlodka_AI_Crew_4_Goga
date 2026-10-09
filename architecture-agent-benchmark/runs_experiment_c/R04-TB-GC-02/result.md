# R04-TB-GC-02

Condition: goga_native_architecture
Base tag: condition-c-r04-v1
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: False
Cost: $3.2028486000000003
Duration: 379377ms, turns: 64

## Agent's own summary

Typecheck is clean. This repo has no headless browser (`chromium-cli`/Playwright) available in this sandbox, so I drove the feature the same way the project's own test suite already exercises this exact panel: full React render of the real `<Excalidraw />` app, real DOM/pointer events, real reducer state — not mocks. All 26 integration tests pass, including 7 new ones that prove the actual behavior end-to-end:

- Rectangle → Area = W×H shown
- Rotated 45° → Area unchanged (not the larger bounding-box value)
- Ellipse → Area = π·a·b shown
- Closed/looped line → Area = polygon (shoelace) area shown
- Open line, arrow, text → Area row correctly omitted

**Summary of changes:**
- `packages/element/src/sizeHelpers.ts` — new `getElementArea(element, zoomValue?)` utility: rectangle (`w·h`), diamond (`w·h/2`), ellipse (`π·w·h/4`), and closed line/freedraw paths (shoelace formula via existing `polygonArea`, gated by the existing `isPathALoop` check); returns `null` for arrows, text, and open paths. Computed from local (un-rotated) geometry, so it's rotation-invariant like the existing W/H rows.
- `packages/excalidraw/components/Stats/index.tsx` — adds an "Area" row below Height for the single-selection case, hidden when area is `null`, formatted with the same `round(value, 2)` used elsewhere in the panel.
- `packages/excalidraw/locales/en.json` — added `stats.area: "Area"`.
- Tests added in `packages/element/tests/sizeHelpers.test.ts` (unit) and `packages/excalidraw/components/Stats/stats.test.tsx` (full-app integration).

`yarn test:typecheck` and all relevant test suites pass.
