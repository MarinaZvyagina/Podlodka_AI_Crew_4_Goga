# R04-TA-BF-10

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: False
Cost: $2.608772100000001
Duration: 456312ms, turns: 56

## Agent's own summary

# Change Plan

## Task Classification
**Bugfix** (with minor UX addition: visible feedback when auto-correction occurs). No new architectural surface, no new cell.

## Affected Cells
| Cell | Files to Modify | What Changes |
|---|---|---|
| `packages/common/src` | `utils.ts` (new routine), `utils.test.ts` (new tests), `CODEMANIFEST` (new body entry) | Add `getSanitizedFilename(name: string) -> safeName: string` |
| `packages/excalidraw/actions` | `actionExport.tsx` | `actionChangeProjectName.perform` sanitizes `value` before storing; emits a toast when sanitization changed the value. No CODEMANIFEST change (concrete actions are not individually documented in this cell — established precedent, see Investigation Report) |
| *(non-cell)* `packages/excalidraw/components` | `ProjectName.tsx`, `ImageExportDialog.tsx` | Reflect sanitized value back into the visible input on commit |
| *(non-cell)* `packages/excalidraw/locales` | `en.json` | New `toast.fileNameSanitized` key (source locale only — other locales are Crowdin-managed, not touched) |

## Root Cause Analysis
`fileSave()` (`packages/excalidraw/data/filesystem.ts`) writes `AppState["name"]` verbatim into the OS file name (`${opts.name}.${opts.extension}`) with no sanitization. `actionChangeProjectName.perform` is the sole reducer that writes `AppState["name"]` from user input and currently performs no validation, so any raw keystroke content (including OS-invalid characters, empty/whitespace, or trailing dot/space) flows straight through to disk.

## Trace Summary
`ProjectName.tsx` / `ImageExportDialog.tsx` (user input) → `actionChangeProjectName.perform` (single write site) → `AppState["name"]` → `App.getName()` → `{actionSaveToActiveFile, actionSaveFileToDisk, App.onExportImage→exportCanvas, actionClipboard}` → `fileSave()` → disk. Sanitizing at the single write site fixes every downstream reader with no further changes to save/export code.

## Change Strategy
1. **`packages/common/src/utils.ts`**: add `getSanitizedFilename`, importing `DEFAULT_FILENAME` from `./constants` (already imported in this file's import block — extend it). Regex-replace `[<>:"/\\|?*\x00-\x1f]` with `_`, `.trim()`, strip trailing `/[. ]+$/`, fall back to `DEFAULT_FILENAME` if the result is empty.
2. **`packages/excalidraw/actions/actionExport.tsx`**: in `actionChangeProjectName.perform`, compute `const sanitized = getSanitizedFilename(value)`; store `name: sanitized`; if `sanitized !== value.trim()` (i.e. an actual adjustment occurred, not just the input's own trailing whitespace being typed mid-edit) add `toast: { message: t("toast.fileNameSanitized").replace("{filename}", sanitized), duration: 4000 }` to the returned `appState`. Import `getSanitizedFilename` from `@excalidraw/common`.
3. **`packages/excalidraw/components/ProjectName.tsx`**: in `handleBlur`, compute `const sanitized = getSanitizedFilename(event.target.value)`; `setFileName(sanitized)`; call `props.onChange(sanitized)` only if `sanitized !== props.value`. This makes the correction visible immediately in the field, independent of the reducer's own (redundant, defense-in-depth) sanitization and its toast.
4. **`packages/excalidraw/components/ImageExportDialog.tsx`**: in the inline name field's `onChange`, sanitize before both `setProjectName` and `actionManager.executeAction`, so the dialog's own visible field never diverges from what will actually be saved (the real save path already reads global `appState.name`, so this is a visibility-parity change, not a correctness fix for that field).
5. **`packages/excalidraw/locales/en.json`**: add `"fileNameSanitized": "Name adjusted to \"{filename}\" to make it a valid file name"` under `"toast"`.
6. **`packages/common/src/utils.test.ts`**: add a `describe("getSanitizedFilename", ...)` block.

## Specification Impact
- `packages/common/src/CODEMANIFEST`: add one new body Routine entry for `getSanitizedFilename`, placed alongside the other `utils.ts`-sourced entries (near `debounce`/`arrayToMap`). Justification for documenting it (unlike `escapeDoubleQuotes`/`normalizeEOL`, which are undocumented): this routine is the safety-critical contract this entire ticket exists to establish, consumed cross-cell by `packages/excalidraw/actions`, and its exact sanitization rules (which characters, fallback behavior) are exactly the kind of "behavioral contract" the manifest exists to pin down for future maintainers/agents.
- `packages/excalidraw/actions/CODEMANIFEST`: **no change**. Concrete registered actions are not individually documented in this cell (confirmed: ~20 other actions, including the adjacent `actionChangeExportScale`/`actionChangeExportBackground` in the very same file, have no body entries). Adding one only for this action would be inconsistent, unrequested documentation drift.

## Usage Impact
No `.usages/*.md` files currently exist for either affected cell that reference filename/name-safety behavior, and none of the cookbook's "declare a usage" triggers apply here (no external library, no cross-cutting pattern beyond the routine's own annotation). No usage file changes planned.

## Compatibility Verification
**Backward compatible.** For any name that is already a valid filename (the common case), `getSanitizedFilename` is a no-op and `actionChangeProjectName.perform` produces byte-identical output to today. Behavior only changes for the specific invalid inputs this task was commissioned to fix. No signature, return shape, file path, or manifest guarantee changes. Confirmed zero existing tests reference this code path (Investigation Report).

## Test Strategy
`packages/common/src/utils.test.ts` — `getSanitizedFilename`:
- Each forbidden character (`< > : " / \ | ? *`) individually replaced with `_`
- Empty string → falls back to `DEFAULT_FILENAME`
- Whitespace-only string → falls back to `DEFAULT_FILENAME`
- Trailing dot(s) stripped (`"My Drawing."` → `"My Drawing"`)
- Trailing space(s) stripped (`"My Drawing "` → `"My Drawing"`)
- Mixed trailing dots/spaces stripped (`"My Drawing. ."` → `"My Drawing"`)
- Valid ordinary name passes through unchanged (no-op case, guards the backward-compatibility claim)
- Leading/interior whitespace preserved except at the edges (`"  My Drawing  "` → `"My Drawing"`, `"My  Drawing"` unchanged)

No new test file needed for `actionChangeProjectName`/`ProjectName.tsx` beyond these unit tests — the reducer and component are now thin wrappers around the fully-tested routine; this matches the codebase's current test coverage level for this action family (zero, per investigation) and keeps scope minimal.

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Double-sanitizing (component + reducer) causes the toast to fire when it shouldn't (e.g. reducer toast fires even though the component already displayed the corrected value) | Low | Low (cosmetic) | Compare `sanitized !== value.trim()` in the reducer using the *raw* dispatched value, not a pre-sanitized one — toast condition is independent of what the component already displayed |
| `en.json` key added without updating other locale files breaks i18n key-completeness tooling/CI | Low | Low | Existing convention (per recent commit history: translations flow through Crowdin) — new keys are added to `en.json` only and backfilled by the Crowdin sync job, not manually |
| New CODEMANIFEST entry for `getSanitizedFilename` sets a precedent reviewers may see as inconsistent with the cell's otherwise-partial documentation | Low | Low | Explicitly justified in Specification Impact above; reconciler step (Step 7) will re-verify this is warranted |

---

Do you approve the plan? Proceed to implementation?
