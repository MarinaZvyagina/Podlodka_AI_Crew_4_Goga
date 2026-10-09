# R04-TA-BF-07

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: False
Cost: $1.9817221499999995
Duration: 295240ms, turns: 50

## Agent's own summary

Good, I have the test style. Now producing the Change Plan.

## Change Plan

**Task Classification**: bugfix (input validation / data-safety gap)

**Affected Cells**

| Cell | Files to Modify | What Changes |
|---|---|---|
| packages/common/src | new `filename.ts`, `index.ts`, `CODEMANIFEST` | New `sanitizeFilename` Routine, exported from facade |
| packages/excalidraw/actions | `actionExport.tsx` | `actionChangeProjectName.perform` sanitizes on commit; toast on adjustment (implementation-only, no manifest delta) |
| ungoverned | `ProjectName.tsx`, `data/filesystem.ts`, `locales/en.json` | Input resync for visibility; defense-in-depth sanitization at the disk-write choke point; new toast string |

**Root Cause Analysis**: No sanitization exists anywhere between the free-text rename input and `fileSave()`, the single point that writes to disk.

**Trace Summary**: `ProjectName` → `actionChangeProjectName.perform` → `appState.name` → `App.getName()` → `saveAsJSON`/`exportCanvas`/`resaveAsImageWithScene` → `fileSave()`.

**Change Strategy**

1. **`packages/common/src/filename.ts`** (new file) — export `sanitizeFilename(name: string): string`:
   - Replace `/ \ : * ? " < > |` and control chars (0x00–0x1F) with `_`.
   - Trim, then strip trailing run of dots/spaces (`/[.\s]+$/`) and leading whitespace.
   - If the result is empty, return `DEFAULT_FILENAME` (already in `packages/common/src/constants.ts`, same cell — no cross-cell import needed).
2. **`packages/common/src/index.ts`** — add `export { sanitizeFilename } from "./filename";` alongside existing exports.
3. **`packages/common/src/CODEMANIFEST`** — add a Routine entry for `sanitizeFilename`, peer to `debounce`/`randomId`, in the body section.
4. **`packages/excalidraw/data/filesystem.ts`** (`fileSave`) — apply `sanitizeFilename(opts.name)` before building `fileName`. This is the defense-in-depth guarantee: every disk write is safe regardless of call site (covers host apps passing `props.name` directly, bypassing the rename UI).
5. **`packages/excalidraw/actions/actionExport.tsx`** (`actionChangeProjectName.perform`) — compute `sanitized = sanitizeFilename(value)`; store `appState.name = sanitized`; if `sanitized !== value`, also set a `toast` in the returned appState informing the user the name was adjusted (new i18n key).
6. **`packages/excalidraw/components/ProjectName.tsx`** — add `useEffect(() => setFileName(props.value), [props.value])` so the input visibly reflects the corrected name after commit (satisfies "visible, not silent").
7. **`packages/excalidraw/locales/en.json`** — add one new key under `toast`, e.g. `"fileNameSanitized": "File name adjusted to remove characters not supported in file names"`. Only `en.json` touched, consistent with this repo's Crowdin-sync convention for other locales.

No changes needed to `App.tsx`, `data/json.ts`, `data/index.ts`, `data/resave.ts` — they already thread `name`/`filename` straight to `fileSave()`, which now sanitizes centrally.

**Specification Impact**: `packages/common/src/CODEMANIFEST` gains one new Routine (`sanitizeFilename`) in the Body section — additive only, no existing Header/Body/Footer entries change.

**Usage Impact**: None of `packages/common/src`'s existing `.usages`/Usages entries (`branding_pattern`, `env_detection`) apply to this routine; no usage file changes needed. No cell imports `packages/common/src` types by name that would need a `.usages` update for this addition (consumers just import the new named export directly, same as `debounce`/`randomId`).

**Compatibility Verification**: Backward compatible. For already-safe names, `sanitizeFilename` is a no-op, so behavior for the entire existing test suite and all currently-valid names is unchanged. For currently-unsafe names, behavior changes from "silently broken" to "sanitized and visibly flagged" — this is the fix, not a regression.

**Test Strategy**
- `packages/common/tests/filename.test.ts` (new, matching `url.test.tsx` style): unit-test `sanitizeFilename` against each character class from the ticket (`/ \ : * ? " < > |`), empty/whitespace-only input, trailing-dot/trailing-space input, and a no-op case for already-safe names.
- `packages/excalidraw/tests/excalidraw.test.tsx`: extend `describe("Test name prop")` with a case that renames to an unsafe string via the `ProjectName` input and asserts `appState.name`/the input value end up sanitized.

**Risk Assessment**

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Replacement char (`_`) collides distinct unsafe names into the same sanitized name (e.g. `"a/b"` and `"a:b"` both → `"a_b"`) | Low | Low — only affects display/collision on repeated saves, not correctness/safety | Acceptable; out of scope per ticket (only requires validity, not uniqueness) |
| `useEffect` resync in `ProjectName.tsx` overwrites in-progress typing if appState.name changes for unrelated reasons | Low | Medium | Effect only fires on `props.value` identity change, which only happens via this same commit round-trip today; verified via trace, no other writer of `appState.name` fires mid-typing |
| New toast key untranslated in other locales | Low | Low | Matches existing repo convention (English fallback until next Crowdin sync) |

Do you approve this plan? Proceed to implementation?
