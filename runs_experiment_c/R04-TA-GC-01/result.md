# R04-TA-GC-01

Condition: goga_native_architecture
Base tag: condition-c-r04-v1
Functional success: True
Full architecture conformance: False
ACR: 0.25
Dangerous success: True
Goga engagement signal: False
Cost: $1.8076026
Duration: 350607ms, turns: 44

## Agent's own summary

All tests pass, typecheck is clean, and lint is clean.

## Summary

- Added `sanitizeFilename()` in `packages/common/src/utils.ts` — strips `/ \ : * ? " < > |`, then trims whitespace and trailing dots/spaces, falling back to `DEFAULT_FILENAME` ("Untitled") if nothing safe remains.
- `actionChangeProjectName` (`packages/excalidraw/actions/actionExport.tsx`) now sanitizes the committed name before storing it in `appState.name` — this is the single source read by every save/export path (PNG, SVG, JSON, save-to-active-file), so whatever ends up on disk is always sanitized.
- `ProjectName.tsx` (the main rename field) and the fallback name input in `ImageExportDialog.tsx` (used when the File System Access API isn't supported) both now sanitize **on blur**, so users can still type freely, but once they commit the name, the field visibly updates to show exactly what will be saved — no silent mismatch between what's displayed and what's written to disk.
- Added unit tests for `sanitizeFilename` covering invalid characters, trailing dots/spaces, whitespace-only/empty input, and already-safe names.
