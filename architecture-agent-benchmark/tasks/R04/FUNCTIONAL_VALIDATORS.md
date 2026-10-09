# FUNCTIONAL_VALIDATORS.md — R04 (excalidraw/excalidraw)

Pinned commit: `e160ff7ba0641fba729c528482de5277ffb19c58`.

This file documents the 4 standalone, runnable functional validator scripts
that complement the existing architecture validators
(`validators/task_X_AC*.sh`). Together, `functional_success` (this file) and
the architecture checks feed the benchmark's `Dangerous Success` metric
(functionally-working but architecturally-wrong implementations).

## How they work

Each `validators/task_X_functional.sh <repo-path>`:
1. Copies a fixture test file from `validators/fixtures/task_X_test.tsx`
   into the target repo at the path its imports expect (a package-relative
   test file, matching this repo's own `*.test.tsx` co-location convention).
2. Runs `npx vitest run <injected path>` from the repo root (same invocation
   the repo's own `yarn test` machinery uses; `vitest.config.mts` lives at
   the repo root and resolves the `@excalidraw/*` workspace aliases).
3. Prints `PASS: ...` / `FAIL: ...` and exits 0 / 1 accordingly.
4. Removes the injected fixture file on exit (via a `trap ... EXIT`), whether
   the run passed, failed, or errored.

All four were verified by actually applying `controls/task_X_positive.diff`
and `controls/task_X_negative.diff` to a clean checkout of the pinned
commit at `/tmp/benchmark-repos/R04`, running the validator, and resetting
(`git checkout` + removing new untracked files) before moving to the next
task. Repo was left clean (only the pre-existing untracked `.goga/`,
`docs/`, and `CODEMANIFEST` leftovers) at the end.

---

## Task A — filename sanitization

**Checks:** committing a new drawing name (via the pre-existing, registered
`actionChangeProjectName` action in `packages/excalidraw/actions/
actionExport.tsx`) always results in `appState.name` being a non-empty
string containing none of `\ / : * ? " < > |` and never starting/ending
with a dot or whitespace, across empty-string, whitespace-only,
reserved-character, and trailing-dot/whitespace inputs.

**Fixture:** `validators/fixtures/task_A_test.tsx` → injected at
`packages/excalidraw/actions/__bench_functional_task_A.test.tsx`.

**Command:** `npx vitest run packages/excalidraw/actions/__bench_functional_task_A.test.tsx` (from repo root).

**Implementation-agnosticism:** drives the pre-existing
`actionChangeProjectName` export via `actionManager.executeAction(...)` and
asserts only against `h.state.name` (a stable, pre-existing observable). It
does not import any new symbol the candidate might introduce (e.g. a
hypothetical `sanitizeFilename` helper module) — it passes regardless of
where/how sanitization is centralized internally.

**Observed results:**
- Positive control (`controls/task_A_positive.diff` — sanitizer centralized
  in new `data/filename.ts`): **PASS** — `7 passed (7)`.
- Negative control (`controls/task_A_negative.diff` — sanitization
  duplicated inline in `actionExport.tsx` and `filesystem.ts`): **PASS** —
  `7 passed (7)`.
- This matches `CONTROL_RESULTS.md`: the negative control is functionally
  correct (both call sites independently implement the same fix correctly)
  — only the architecture check (AC2: single source of truth) catches the
  duplication. Confirms the functional/architecture split works as
  designed for this task.

---

## Task B — live shape-area readout in the Stats panel

**Checks:** right-clicking the canvas → "Stats" → selecting a shape shows a
correct area value for rectangles, diamonds, ellipses (including rotated
rectangles, which must match the unrotated area), and closed
polygon-mode lines (shoelace area of actual points, not the bounding-box
area) — and shows no (or a `null`) area value for open lines, arrows, and
text.

**Fixture:** `validators/fixtures/task_B_test.tsx` → injected at
`packages/excalidraw/components/Stats/__bench_functional_task_B.test.tsx`.

**Command:** `npx vitest run packages/excalidraw/components/Stats/__bench_functional_task_B.test.tsx`.

**Implementation-agnosticism:** drives the feature end-to-end through the
UI (context-menu → Stats panel → element selection), not through any new
helper the candidate might add. Value extraction is two-tiered: primarily
the repo's existing testid convention (`stats-area`, following the existing
`stats-element-type` precedent), with a generic fallback that scans every
`.exc-stats__row` (the pre-existing `StatsRow` wrapper, not introduced by
this feature) for a row whose label reads "Area".

**Observed results:**
- Positive control (`controls/task_B_positive.diff` — area computed via
  `getElementArea()` reusing `getElementShape()`/`polygonArea()`):
  **PASS** — `7 passed (7)`.
- Negative control (`controls/task_B_negative.diff` — inline shoelace loop
  + hardcoded per-type formulas directly in `Stats/index.tsx`): **PASS** —
  `7 passed (7)`.
- This matches `CONTROL_RESULTS.md` exactly: this is the one R04 task where
  the functional check is *expected* to pass for both controls (the trap's
  ad hoc formulas happen to be numerically correct for these shapes/angles)
  — architecture check AC2 (no inline geometry formulas) is what
  discriminates. Confirmed live via `vitest`, not merely inferred: this is
  the textbook "Dangerous Success" case in the R04 set — a
  functional-only gate would rate the negative control as fully correct.

---

## Task C — hide-captions toggle

**Checks:** a captions on/off toggle is reachable from a menu (the same
surface used by sibling display toggles like grid mode/zen mode), starts
off, toggles reversibly, works with nothing selected, never mutates/deletes
the underlying shape or its bound caption text (and restores byte-identical
state on toggle-back), and does not clobber unrelated display toggles
(e.g. grid mode).

**Fixture:** `validators/fixtures/task_C_test.tsx` → injected at
`packages/excalidraw/actions/__bench_functional_task_C.test.tsx`.

**Command:** `npx vitest run packages/excalidraw/actions/__bench_functional_task_C.test.tsx`.

**Implementation-agnosticism:** the ticket never names a mechanism,
appState field, or keyboard shortcut, so this fixture deliberately avoids
hardcoding any of those (unlike the original recon-phase test, which
asserted directly on a literal `appState.captionsHiddenEnabled` field and a
literal `Alt+K` shortcut). Instead it looks for a menu item whose *visible
label* contains "caption" in two real, pre-existing UI surfaces this
codebase's own sibling toggles use by default:
1. the canvas right-click context menu (`.context-menu`, built by
   `App.getContextMenuItems()` from the registered-actions list — this is
   how `gridMode`/`zenMode` are reachable out of the box, confirmed against
   this repo's own `tests/excalidraw.test.tsx`), reading on/off via the
   generic `checkmark` CSS class every action-backed item gets from
   `action.checked?.(appState)`;
2. as a fallback, the main hamburger menu when composed with
   `<MainMenu><MainMenu.DefaultItems.Preferences/></MainMenu>` (the
   officially exported host-composable location for this exact class of
   toggle), reading on/off via the shared `DropdownMenuItemCheckbox`
   icon convention (checkmark svg vs. empty placeholder).

Neither path assumes a field name; both are conventions already used by
every other toggle in the codebase, not invented for this feature. A
"not reachable from any menu at all" implementation is intentionally
still failed by this check, because that is a literal, explicit
requirement in the ticket text itself ("reachable from the same places...
menu"), not an architecture-only nicety.

**Observed results:**
- Positive control (`controls/task_C_positive.diff` — registered
  `actionToggleCaptionsVisibility`, wired into `getContextMenuItems`'s
  canvas menu): **PASS** — `4 passed (4)`.
- Negative control (`controls/task_C_negative.diff` — bespoke global
  `window.addEventListener("keydown", ...)`, with a `Preferences`-item
  component defined but never wired into the rendered `Preferences` menu or
  the context menu): **FAIL** — `4 failed (4)`, all failing with "no menu
  item (context menu or main menu) found whose visible label contains
  'caption'". This is a genuine, reproducible functional failure (not just
  an architecture-grep finding): the trap's toggle is real and functions
  correctly once triggered via its private keyboard listener, but it is
  provably unreachable from any menu, which the ticket explicitly requires.
  This strengthens the discrimination beyond what `CONTROL_RESULTS.md`'s
  original AC1/AC2-only (architecture-only) analysis captured for this task.

---

## Task D — one-click "snap selection to grid"

**Checks:** triggering the command snaps selected shapes' x/y/width/height
independently to the nearest grid multiple (matching manual drag-snap
rounding), leaves unselected shapes untouched, snaps every shape when
nothing is selected, bumps `version`/`versionNonce` on every snapped
element, and — the ticket's own explicit requirement — a single undo fully
reverts the snap.

**Fixture:** `validators/fixtures/task_D_test.tsx` (merges the two
Phase-5-authored test files named in this task's own `metadata_D.yaml`
recon: the plain functional test and the `.architecture.test.tsx` undo/
version test) → injected at
`packages/excalidraw/actions/__bench_functional_task_D.test.tsx`.

**Command:** `npx vitest run packages/excalidraw/actions/__bench_functional_task_D.test.tsx`.

**Implementation-agnosticism:** drives the feature exclusively through the
pre-existing `actionManager.executeAction()` / `createUndoAction(h.history)`
dispatch path — the same one every other action's own test suite in this
repo uses. The one candidate-authored symbol it requires,
`actionSnapSelectionToGrid`, is expected to be exported by name from the
actions barrel (`packages/excalidraw/actions/index.ts`), following this
codebase's own verb+noun action-naming convention (`actionAlign*`,
`actionToggle*`, ...) — this is also the exact name used by both the
positive and negative reference diffs, and was reused unchanged per the
task instructions ("Reuse those test files directly... e.g.
`actionSnapSelectionToGrid.architecture.test.tsx`").

**Observed results:**
- Positive control (`controls/task_D_positive.diff` — uses
  `scene.mutateElement()` + `captureUpdate: CaptureUpdateAction.
  IMMEDIATELY`): **PASS** — `4 passed (4)`.
- Negative control (`controls/task_D_negative.diff` — direct in-place
  property mutation, `captureUpdate: CaptureUpdateAction.NEVER`):
  **FAIL** — `2 passed | 2 failed (4)`, with the *exact* real failure
  signatures already documented in `CONTROL_RESULTS.md`:
  - `bumps version/versionNonce...`: `AssertionError: expected 2 to be
    greater than 2` (version never bumped — element mutated in place, not
    via `mutateElement`).
  - `a single undo fully reverts the snap...`: `AssertionError: expected 20
    to be 13` (undo did not revert position — the mutation never reached
    the undo/redo stack because it wasn't captured via
    `CaptureUpdateAction.IMMEDIATELY`).
  This reproduces, byte-for-byte, the genuine test failures
  `CONTROL_RESULTS.md` reports were observed via real `vitest` execution
  during Phase 5 — the strongest empirical result in the R04 set.

---

## Summary

| Task | Positive | Negative | Discriminates functionally? |
|---|---|---|---|
| A (filename sanitization) | PASS (7/7) | PASS (7/7) | No — architecture check (AC2) catches the duplication |
| B (shape-area readout) | PASS (7/7) | PASS (7/7) | No — architecture check (AC2) catches the inline formulas (by design; "Dangerous Success" case) |
| C (hide-captions toggle) | PASS (4/4) | FAIL (0/4) | **Yes** — trap is provably unreachable from any menu |
| D (snap selection to grid) | PASS (4/4) | FAIL (2/4) | **Yes** — trap genuinely breaks undo and version-bumping |

All four scripts were run against a real `vitest` execution (no stubbing/
inference), against both control diffs, with the repository reset to a
clean state between every run and at the end.
