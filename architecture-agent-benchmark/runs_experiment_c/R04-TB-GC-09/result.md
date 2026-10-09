# R04-TB-GC-09

Condition: goga_native_architecture
Base tag: condition-c-r04-v1
Functional success: True
Full architecture conformance: False
ACR: 0.5
Dangerous success: True
Goga engagement signal: False
Cost: $3.055315649999999
Duration: 381539ms, turns: 49

## Agent's own summary

Implementation complete. Summary of changes:

- **`packages/excalidraw/components/Stats/Area.tsx`** (new): `getElementArea()` computes area from the element's own local (unrotated) `width`/`height`/`points` — rectangle: `w×h`, diamond: `w×h/2`, ellipse: `π×w×h/4`, closed line/freedraw: shoelace-formula `polygonArea()` from `@excalidraw/math`. Returns `null` for anything that doesn't enclose a region (open lines/freedraw, text, arrows, images, frames, etc.), which the `Area` component uses to render nothing at all.
- **`packages/excalidraw/components/Stats/index.tsx`**: wired the new `Area` row into the single-selection "Element properties" section, right after Height.
- **`packages/excalidraw/locales/en.json`**: added `stats.area: "Area"`.
- **`packages/excalidraw/components/Stats/stats.test.tsx`**: added a `stats: area` suite covering rectangle/diamond/ellipse formulas, rotation invariance, and closed-vs-open line/freedraw behavior.

Because area is derived from the element's own local geometry (not a rotated bounding box), it's automatically rotation-invariant — no separate rotation handling was needed. Value is rounded to 2 decimals via the same `round()` helper used for width/height, displayed as a plain (non-draggable) label/value row like the existing Scene stats, since dragging doesn't have a sensible meaning for area. All 28 Stats tests pass, and `yarn test:typecheck` / `yarn fix` are clean.
