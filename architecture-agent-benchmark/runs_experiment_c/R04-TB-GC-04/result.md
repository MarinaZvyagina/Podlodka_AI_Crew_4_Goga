# R04-TB-GC-04

Condition: goga_native_architecture
Base tag: condition-c-r04-v1
Functional success: True
Full architecture conformance: False
ACR: 0.5
Dangerous success: True
Goga engagement signal: False
Cost: $3.2000065500000003
Duration: 298959ms, turns: 62

## Agent's own summary

Everything checks out. Summary of the change:

**Added a live "Area" readout to the Stats panel** (`packages/excalidraw/components/Stats/`):

- **`Area.tsx`** (new): computes area for a single selected element by reusing the existing `getElementShape` geometry utility (the same one used for hit-testing) and the shoelace-formula `polygonArea` from `@excalidraw/math`.
  - Rectangle/diamond/line/freedraw → `polygonArea` on the rotated, absolute-coordinate outline (rotation-correct by construction, since the outline points are already rotated).
  - Ellipse → `π × halfWidth × halfHeight`.
  - Only `rectangle`, `diamond`, `ellipse`, `line`, `freedraw` are eligible; line/freedraw only report an area when their outline is closed and filled (same "encloses a region" gate the app already uses for click-inside hit-testing) — open lines and text are omitted entirely, per spec.
- **`index.tsx`**: wired `<Area>` in as a new row right after Height, shown whenever a single element is selected — same lifecycle as the existing Width/Height rows, so it updates live as the shape is moved/resized/reshaped.
- **`en.json`**: added the `stats.area` label ("Area"), rounded to 2 decimals via `round()`, consistent with how Width/Height are displayed.
- Added 6 tests in `stats.test.tsx` covering: rectangle area unaffected by rotation, diamond = half its bounding box, ellipse formula, closed/filled line area, and omission for open lines and text.

Typecheck, lint, and the full Stats test suite (25 tests) all pass.
