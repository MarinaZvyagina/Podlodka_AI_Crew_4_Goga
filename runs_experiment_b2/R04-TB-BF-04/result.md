# R04-TB-BF-04

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $7.102654949999998
Duration: 963849ms, turns: 142

## Agent's own summary

Implementation complete. Summary of what was done:

**`packages/element/src` (Goga-governed cell, changed via full `goga-change` pipeline):**
- Added `getElementArea(element, elementsMap)` in `shape.ts` — returns the true rotation-correct enclosed area for rectangle/diamond/ellipse (always), and for line/freedraw only when closed and filled (reusing the existing `shouldTestInside` gate); returns `undefined` for arrows, text, images, frames, and open/unfilled outlines.
- Documented it in `CODEMANIFEST` (new Routine entry + `polygonArea` import from `packages/math/src`).
- Also documented `packages/math/src`'s previously-undocumented `polygonArea` export, since this change made it a real cross-cell dependency.
- 12 new unit tests (`packages/element/tests/getElementArea.test.ts`) covering rotation-invariance, closed/open/unfilled cases.
- `goga lint`: 5 cells, 0 errors. `yarn test:typecheck`: clean. Full `packages/element` suite: 569/569 passing.

**Stats panel UI (not Goga-governed, ordinary engineering):**
- Added an "Area" row to `packages/excalidraw/components/Stats/index.tsx`, shown only when `getElementArea` returns a value, rounded to 2 decimals to match the existing width/height display convention.
- Added the `stats.area` translation key to `en.json`.
- Added/extended tests in `stats.test.tsx`: area displays and live-updates as width changes, rotation doesn't change the reported area, and text elements (no enclosed area) correctly show no area row.
- Full Stats test suite: 21/21 passing; typecheck clean.

All changes are additive and backward-compatible — nothing existing was modified in behavior. Nothing has been committed; let me know if you'd like me to create a commit.
