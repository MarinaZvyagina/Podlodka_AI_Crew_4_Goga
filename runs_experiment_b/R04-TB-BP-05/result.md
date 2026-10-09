# R04-TB-BP-05

Condition: goga_full_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.5
Dangerous success: True
Goga engagement signal: False
Cost: $1.8502617
Duration: 307198ms, turns: 55

## Agent's own summary

All tests pass, typecheck is clean, and lint/format made no changes to substantive code.

## Summary

Added a live "Area" readout to the element properties panel (`packages/excalidraw/components/Stats/index.tsx`):

- New `getElementArea()` helper in `Stats/utils.ts` computes:
  - rectangle: `width × height`
  - diamond: `(width × height) / 2`
  - ellipse: `π × width × height / 4`
  - `line`/`freedraw`: shoelace-formula area of the local points (via the existing `polygonArea` math util), only when the path is actually closed — reusing the same closure checks (`polygon` flag + `isValidPolygon`, `isPathALoop`) the codebase already uses for bucket-fill boundary detection
  - everything else (text, arrows, open paths, images, frames, etc.) returns `null` and is simply omitted from the panel
- Since area is derived from local (unrotated) geometry, it's automatically rotation-invariant — no bounding-box inflation for rotated shapes.
- Wired into the single-selection section of the Stats panel, right after Width/Height, rounded the same way (`round(value, 2)`) and only rendered when non-null.
- Added the `stats.area` label to `en.json`.
- Added `getElementArea.test.ts` covering rectangles, rotation invariance, diamonds, ellipses, closed/open lines and freedraw paths, and non-enclosing types.

Verified with `yarn test:typecheck`, the full Stats test suite (28 tests passing), and `yarn fix` (no code changes needed).
