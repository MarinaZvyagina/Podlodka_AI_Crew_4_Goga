# R04-TB-GC-03

Condition: goga_native_architecture
Base tag: condition-c-r04-v1
Functional success: True
Full architecture conformance: False
ACR: 0.5
Dangerous success: True
Goga engagement signal: False
Cost: $4.67458635
Duration: 900559ms, turns: 69

## Agent's own summary

## Summary

Added a live **Area** readout to the Stats panel for the currently selected shape:

- **`packages/excalidraw/components/Stats/Area.tsx`** (new) — computes area from each shape's own local geometry, never from the rotated bounding box:
  - rectangle: `width * height`
  - diamond: `width * height / 2`
  - ellipse: `π * width * height / 4`
  - `line` with `polygon: true`, and `freedraw` whose endpoints form a closed loop (`isPathALoop`): shoelace-formula area via `polygonArea(element.points)`
  - everything else (open lines, arrows, text, images, frames) → `null`, so the row is omitted
- Wired into `Stats/index.tsx` as a new row between Height and Angle; it collapses automatically when `null` (existing `:empty { display: none }` CSS rule, same mechanism used for the Angle row).
- Added the `stats.area` translation key.

Verified in a real browser session (dev server + Playwright): a 200×150 rectangle shows Area 30000, rotating it 45° keeps Area at 30000 while its bounding box grows to 248×248, resizing updates the value live, ellipse/diamond formulas check out (π·200·200/4 = 31415.93, 200·150/2 = 15000), a 60×60 closed freedraw loop shows 3600, and text/open-line elements correctly show no Area row. Full test suite (`yarn test:update`, 1860 tests) and typecheck/lint all pass.
