# R04-TA-BF-09

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.5
Dangerous success: False
Goga engagement signal: True
Cost: $2.9443790999999995
Duration: 416971ms, turns: 80

## Agent's own summary

## Summary

Fixed the filename-safety bug in `packages/excalidraw`:

**Goga check first**: `goga schema`/`goga lint` show this repo's modeled architecture forest covers only 5 unrelated cells (`element`, `math`, `common`, `fractional-indexing`, and a narrow `actions` contract for `Action`/`register`/`ActionManager`). None of the files this ticket touches (`ProjectName.tsx`, `filesystem.ts`, `actionExport.tsx`'s `actionChangeProjectName`) are covered by a CODEMANIFEST, and `actionExport.tsx` itself isn't one of the `actions` cell's documented "location" files — so this fix doesn't add or violate any documented contract. Confirmed with `goga contract` and a final `goga lint` (still `cells: 5 errors: 0`) that nothing modeled was disturbed.

**Fix**:
- `packages/excalidraw/data/filesystem.ts` — added `sanitizeFilename()`: strips `\ / : * ? " < > |` and control characters, trims leading spaces and trailing dots/spaces (which Windows silently strips), and falls back to `"Untitled"` for empty/whitespace-only names or Windows-reserved device names (`CON`, `PRN`, `LPT1`, etc.). Applied it inside `fileSave()` as the final safety net for every disk-write path (JSON/PNG/SVG export, save-as, library export).
- `packages/excalidraw/actions/actionExport.tsx` — `actionChangeProjectName` now sanitizes the committed name and, if it differs from what was typed, sets a toast (`toast.fileNameSanitized`) so the adjustment is visible rather than silent. Traced `app.getName()` → confirmed every save/export path (active-file save, save-as, PNG/SVG export) reads from this single committed `appState.name`, so sanitizing here is sufficient — including for the separate `ImageExportDialog` input, since its live preview state is cosmetic and the actual export always calls `app.getName()`.
- `packages/excalidraw/components/ProjectName.tsx` — the input's local buffer now re-syncs from the committed prop value (only fires post-blur, so free typing is untouched) so the field visibly shows the sanitized name once committed.
- Added `packages/excalidraw/locales/en.json` toast string and `packages/excalidraw/tests/filesystem.test.ts` (9 tests covering all sanitization rules).

Verified: `yarn test:typecheck`, `eslint`, `prettier --check`, the new unit tests, and existing export test suites all pass.
