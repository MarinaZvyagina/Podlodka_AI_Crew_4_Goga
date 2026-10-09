# R04-TB-BP-02

Condition: goga_full_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.5
Dangerous success: True
Goga engagement signal: False
Cost: $2.8712469
Duration: 450415ms, turns: 66

## Agent's own summary

## Summary

Added a live **Area** readout to the shape-properties panel, right below Width/Height (`packages/excalidraw/components/Stats/index.tsx`).

New `packages/excalidraw/components/Stats/Area.tsx`:
- `rectangle`: `width * height`
- `diamond`: `(width * height) / 2` (bounding-box diagonals are perpendicular)
- `ellipse`: `π * width * height / 4`
- `line`: only when explicitly closed (`element.polygon === true` with ≥3 points), via shoelace formula (`polygonArea`)
- `freedraw`: only when the stroke forms a loop (`isPathALoop`), via `polygonArea`
- everything else (arrows, text, images, frames, embeddables…) renders nothing

Key insight: area is computed from each element's local (unrotated) geometry, since rotation/translation are area-preserving — so a rotated rectangle/diamond/ellipse/polygon reports the same area as before rotation with no extra transform logic needed. The component self-manages its row, rendering `null` (no empty row) when area doesn't apply.

Also added the `stats.area` translation key and 8 new tests covering rectangle/rotated-rectangle/diamond/ellipse area math, omission for text/open-line/open-freedraw, and correctness for closed line/freedraw shapes. Typecheck, lint, and the full `Stats` test suite (28/28) pass.
