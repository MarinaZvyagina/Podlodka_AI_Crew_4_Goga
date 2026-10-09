# R04-TB-BP-06

Condition: goga_full_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.5
Dangerous success: True
Goga engagement signal: False
Cost: $5.064911100000001
Duration: 797292ms, turns: 86

## Agent's own summary

## Summary

Added a live **Area** readout to the Stats side panel, right below the Angle field:

- **`packages/excalidraw/components/Stats/Area.tsx`** (new) — computes area per shape type:
  - rectangle: `width × height`
  - diamond: `width × height / 2`
  - ellipse: `π × width × height / 4`
  - line/freedraw: shoelace formula (`polygonArea` from `@excalidraw/math`) over the element's own points, only when the path is closed (`polygon: true` or `isPathALoop`)
  - everything else (text, arrows, open lines/freedraw, images, frames, etc.): omitted entirely
- **`packages/excalidraw/components/Stats/index.tsx`** — wires the `Area` row into the single-element properties section, after Angle.
- **`packages/excalidraw/locales/en.json`** — added the `stats.area: "Area"` label.

Since area is computed from each shape's own local geometry (width/height, or local `points`) rather than its screen-space bounding box, rotation doesn't affect the result — verified live in the browser: a 200×100 rectangle stayed at area 20000 after rotating it ~40°, even though its bounding box grew to 220×202.

Verified end-to-end in a real running instance (dev server + headless Chromium): rectangle (20000), diamond (10000), ellipse (15707.96), and a closed hand-drawn line (6000) all show correct values; an open line and a text label correctly show no Area row at all (confirmed via DOM inspection, not just visual absence). Typecheck, lint, and the existing Stats test suite (19 tests) all pass.
