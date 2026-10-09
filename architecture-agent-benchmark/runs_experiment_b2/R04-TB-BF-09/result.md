# R04-TB-BF-09

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.5
Dangerous success: True
Goga engagement signal: True
Cost: $2.7784164
Duration: 379395ms, turns: 67

## Agent's own summary

## Summary

Added a live **Area** readout to the Stats panel for the single-selected-element case (`packages/excalidraw/components/Stats/index.tsx`), backed by a new `getElementArea` helper in `Stats/utils.ts`:

- **Rectangle**: `width × height`
- **Diamond**: `(width × height) / 2` (rhombus from diagonals)
- **Ellipse**: `π × width × height / 4`
- **Line/freedraw**: shoelace-formula polygon area (`polygonArea` from `@excalidraw/math`) over the element's local points, only when the shape is actually closed (`polygon: true` + valid polygon for lines, `isPathALoop` for freedraw) — open strokes get `null` and the row is omitted
- Everything else (text, arrows, open lines/freedraw, frames, images) returns `null` → row omitted

Since points are stored in the element's local (unrotated) coordinate space and the rectangle/diamond/ellipse formulas use only `width`/`height`, area is rotation-invariant by construction — verified by a test that rotates a rectangle and checks the readout is unchanged.

Investigated via `goga schema`/`goga lint` first: the Stats UI isn't one of the 5 governed cells, and all the geometry helpers used (`isPathALoop`, `isValidPolygon`, `isLineElement`, `isFreeDrawElement`, `polygonArea`) were already public exports of the governed `packages/element/src` and `packages/math/src` cells, so no new architectural surface or manifest changes were needed. `goga lint` stayed clean throughout.

Added a `stats.area` locale string, 8 unit tests for `getElementArea`, and 3 integration tests in the Stats panel (live update on resize, rotation-invariance, omitted for text). Ran `yarn test:typecheck`, `eslint`, and the full `stats.test.tsx` suite (27/27 passing) — couldn't visually drive it in a browser since no browser-automation tool was available in this environment, but the dev server did build and serve cleanly.
