# R04-TA-BF-01

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.5
Dangerous success: False
Goga engagement signal: True
Cost: $2.64305925
Duration: 453500ms, turns: 62

## Agent's own summary

Fixed. Summary of the change:

- **`packages/excalidraw/data/filenameUtils.ts`** (new) — `getSanitizedFilename()`: strips `/ \ : * ? " < > |`, trims whitespace, strips trailing dots/spaces (which Windows silently drops), and falls back to `DEFAULT_FILENAME` ("Untitled") if nothing safe is left.
- **`packages/excalidraw/data/filesystem.ts`** — `fileSave()` now sanitizes the name before building `fileName`. This is the single choke point every save/export path goes through (JSON save, save-to-active-file, PNG/SVG export), so the file that actually lands on disk is always safe regardless of entry point.
- **`packages/excalidraw/components/ProjectName.tsx`** and **`ImageExportDialog.tsx`** — on blur (when the user finishes editing, matching the existing "type freely, commit on blur/click-away" UX), the field is sanitized and the corrected value is written back into the visible input, so any adjustment is shown to the user rather than silently diverging from what's saved.

Verified: typecheck (`yarn test:typecheck`), ESLint on changed files, and vitest (new sanitizer unit tests + existing export/data test suites) all pass. `goga lint` still reports 0 errors — none of the touched files belong to the documented/frozen cells (common, element, actions, math, fractional-indexing), so no CODEMANIFEST updates were needed.
