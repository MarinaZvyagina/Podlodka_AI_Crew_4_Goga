# R04-TA-BF-04

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: False
Cost: $2.0597287500000006
Duration: 259601ms, turns: 47

## Agent's own summary

# Change Plan

## Task Classification
**Feature** (additive extension) — new exported Routine in an existing cell; no existing behavior modified.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `packages/common/src` | `filename.ts` (new), `index.ts` (add one re-export line), `CODEMANIFEST` (add one body entry), `filename.test.ts` (new) | New pure Routine `sanitizeFilename` added and wired into the cell's public facade; no existing file's behavior changes. |

## Root Cause Analysis
Not applicable in the bugfix sense — this is a net-new addition. Per the Investigation Report: no filename-sanitization utility exists anywhere in `packages/common/src` or the repo (confirmed by exhaustive grep, HIGH confidence). `DEFAULT_FILENAME` (`constants.ts:517`, plain string constant `"Untitled"`) exists and is safe to reuse read-only as the empty-result fallback.

## Trace Summary
- `constants.ts` → `DEFAULT_FILENAME` (read-only import into `filename.ts`)
- `filename.ts` (new) → exports `sanitizeFilename`
- `index.ts` → `export * from "./filename"` makes it part of the cell facade, following the exact pattern already used for `./constants`, `./url`, etc.
- No other cell in the documented forest imports or calls this routine (per Scope Resolution Report — zero in-forest dependents).

## Change Strategy
1. Create `packages/common/src/filename.ts`:
   - Define `ILLEGAL_FILENAME_CHARS_REGEX` (module-private, not exported) matching control chars `\x00-\x1f` and `/ \ : * ? " < > |`.
   - Export `sanitizeFilename = (name: string): string => { ... }` that: (a) replaces every match of the illegal-char regex with `"-"`, (b) strips a trailing run of whitespace/dot characters via a second regex pass, (c) returns `DEFAULT_FILENAME` if the result is empty, else the sanitized string.
   - Import `DEFAULT_FILENAME` from `./constants`.
2. Add `export * from "./filename";` to `index.ts`, placed alongside the other `export *` lines (after `./font-metadata`, before `./queue`, matching loose existing ordering — exact position immaterial since it's a flat barrel).
3. Add one new body entry to `packages/common/src/CODEMANIFEST` documenting `sanitizeFilename` as a Routine (signature, location, annotations — see Specification Impact below for exact text).
4. Add `packages/common/src/filename.test.ts` covering: illegal-character replacement, trailing dot/space stripping, empty/whitespace-only input falling back to `DEFAULT_FILENAME`, and a already-valid name passing through unchanged.

No changes to `constants.ts`, `url.ts`, or any other existing file.

## Specification Impact
Add one new body entry to `packages/common/src/CODEMANIFEST`, inserted after the `"isColorDark(...)"` entry (before the closing `---` that begins the footer):

```yaml
"sanitizeFilename(name: string) -> sanitized:string":
  location: filename.ts
  annotations: |
    Convert a free-typed string into a filename that is safe to write to disk on Windows,
    macOS, and Linux. Used wherever a user-editable name (e.g. a drawing's title) becomes
    part of an actual file path for saving/exporting.

    `name`: the raw, unrestricted string as typed by the user
    `sanitized`: a non-empty string containing no characters illegal in a filename on any of
    the three target platforms, and no trailing dot/whitespace

    Algorithm:
    1. Replace every character illegal in a Windows/macOS/Linux filename (control characters,
       and / \ : * ? " < > |) with a "-" separator
    2. Strip any trailing run of whitespace or dot characters (Windows silently drops these,
       which otherwise causes the saved filename to mismatch what the user typed)
    3. If the result is empty, return `DEFAULT_FILENAME`

    Constraints:
    - Must not throw for any string input, including empty or whitespace-only strings
```

No changes to the CODEMANIFEST header (`Imports`/`Usages`/`Annotations`) — the new routine needs no import (it only reads a sibling-file constant, which per DSL scope is an internal implementation detail, not a cross-cell `Imports`) and introduces no new practice.

## Usage Impact
No `.usages/*.md` files currently exist for `packages/common/src` (directory not present in current cell listing — only `CODEMANIFEST` and source files). This change does not introduce a consumer-facing pattern complex enough to warrant creating one (per goga-cookbook: create a usage file when "an external consumer requires guidance on working with the cell's API" beyond what the CODEMANIFEST annotation already states plainly). The CODEMANIFEST annotation above is self-sufficient for consumers (`actionExport.tsx`, `filesystem.ts`) to call `sanitizeFilename(name)` correctly without further documentation. No existing usage file is affected since none exists.

## Compatibility Verification
**Backward compatible.** This is a pure addition:
- No existing exported symbol's signature, behavior, or file location changes.
- `DEFAULT_FILENAME` is read, never mutated or redefined.
- `index.ts` gains one new line; all existing `export *` lines are untouched.
- No existing test can break, since no existing implementation file is touched.

## Test Strategy
New file `packages/common/src/filename.test.ts`, covering `sanitizeFilename`:
1. **Illegal characters replaced** — e.g. `sanitizeFilename('a/b\\c:d*e?f"g<h>i|j')` → all nine illegal chars become `-`.
2. **Control characters replaced** — e.g. a string containing `\x00`/`\x1f` is sanitized without throwing, illegal chars removed/replaced.
3. **Trailing dot stripped** — `sanitizeFilename("Report.")` → `"Report"`.
4. **Trailing whitespace stripped** — `sanitizeFilename("Report   ")` → `"Report"`.
5. **Trailing mixed dot/space run stripped** — `sanitizeFilename("Report. . ")` → `"Report"`.
6. **Empty string falls back** — `sanitizeFilename("")` → `DEFAULT_FILENAME` (`"Untitled"`).
7. **Whitespace-only string falls back** — `sanitizeFilename("   ")` → `DEFAULT_FILENAME`.
8. **Already-valid name passes through unchanged** — `sanitizeFilename("My Drawing 2026")` → `"My Drawing 2026"`.
9. **Interior dots/spaces preserved** — `sanitizeFilename("v1.2 final")` → `"v1.2 final"` (only *trailing* dots/spaces are stripped, not interior ones).

This satisfies the project's `yarn test:update` convention (per `CLAUDE.md`) — tests will be run as part of Step 6 (Testing) and Step 10 (Validation).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Over-aggressive stripping removes characters a user actually wanted (e.g. legitimate use of `:` in a title) | Medium | Low | Replacing with `-` (not deleting) preserves word separation and visual intent; this is standard practice (matches OS-level rename-dialog behavior) and is explicitly in scope per the ticket's stated character list. |
| Regex for trailing dot/space strip also eats a trailing hyphen or other valid char | Low | Low | Regex scoped precisely to `[\s.]+$` (whitespace and dot only); hyphens, letters, digits, etc. are untouched. Covered by test case 9 (interior dots preserved) and test case 3/4/5 (only whitespace/dot). |
| `index.ts` barrel re-export collides with an existing exported name | Low | Medium | Confirmed via grep in Investigation Report: no existing symbol named `sanitizeFilename` (or similar) anywhere in the cell — zero collision risk. |
| CODEMANIFEST body entry placement/formatting violates DSL casing/structure rules | Low | Medium | Entry text modeled directly on the existing `matchKey`/`isColorDark` Routine entries in the same file (same header/annotation/Algorithm/Constraints structure), validated against `goga-cell` DSL spec already loaded. |

---

Do you approve this plan? Proceed to implementation?
