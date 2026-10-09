# CONTROL_RESULTS.md — R04 (excalidraw/excalidraw)

**Note on provenance:** the original agent that implemented these controls was cut off by a connection error twice, immediately before writing this file (though all 16 validator scripts and all 8 control diffs it produced were saved successfully and are intact). Rather than resume a third time, the orchestrating session re-applied every diff directly against a clean checkout of the pinned commit (`/tmp/benchmark-repos/R04`, commit `e160ff7ba0641fba729c528482de5277ffb19c58`) and re-ran every validator script live — including real `vitest` executions where the validator itself runs tests — to obtain authoritative, freshly-executed pass/fail results. All test output below is real, not inferred from diffs.

## Task A — Local Change (filename sanitization)

**Positive control:** sanitization added once, as a single source of truth, in `packages/excalidraw/data/filename.ts` (new file), used by the export/save path.
**Negative control:** sanitization logic duplicated directly inside both `actionExport.tsx` and `filesystem.ts` instead of centralized.

| Check | Positive | Negative |
|---|---|---|
| AC1 (changes confined to packages/excalidraw) | PASS | PASS |
| AC2 (single source-of-truth sanitization) | PASS | **FAIL** (duplicated in 2 files) |
| AC3 (no new dependency added) | PASS | PASS |
| AC4 (types.ts untouched) | PASS | PASS |

**Verdict: DISCRIMINATES.** Positive 4/4, negative 3/4.

## Task B — Cross-module Feature (shape-area stats readout)

**Positive control:** area computation reuses `packages/element`'s `getElementShape()` / `packages/math`'s `polygonArea()` from the Stats component; no inline geometry formulas.
**Negative control:** Stats component reimplements area calculation inline (shoelace accumulation loop, hardcoded `Math.PI *` ellipse formula, hardcoded width×height formula) instead of reusing the existing geometry pipeline.

| Check | Positive | Negative |
|---|---|---|
| AC1 (area tests pass, incl. non-rectangular/closed shapes) | PASS (33/33 tests) | PASS (26/26 tests — the trap's ad hoc formulas happen to be numerically correct for the tested cases) |
| AC2 (no inline geometry formulas in Stats component) | PASS | **FAIL** (shoelace loop + hardcoded formulas found directly in `Stats/index.tsx`) |
| AC3 (no new cross-package imports) | PASS | PASS |
| AC4 (rotation-invariance holds) | PASS (14/14 tests) | PASS (7/7 tests) |

**Verdict: DISCRIMINATES.** Positive 4/4, negative 3/4. Notable: this is a case where the *functional* checks alone do not distinguish positive from negative (the trap's duplicated formulas happen to be correct) — only the architecture check (AC2, code reuse) catches it. This is a textbook "Dangerous Success" shape: functionally fine, architecturally duplicated logic that will drift from the real geometry pipeline over time.

## Task C — Existing Extension Point (hide captions toggle)

**Positive control:** implemented as a registered action (`register({...})` with `keyTest`/`checked`/`perform`) in `packages/excalidraw/actions/actionToggleCaptionsVisibility.tsx`, following the existing `actionToggleGridMode`/`actionToggleZenMode` pattern; new boolean lives on `AppState`.
**Negative control:** no registered action at all — a parallel keyboard-handling path added directly in `App.tsx` via a new `addEventListener("keydown", ...)`.

| Check | Positive | Negative |
|---|---|---|
| AC1 (registered action exists) | PASS | **FAIL** (no action registered) |
| AC2 (no parallel keyboard-handling path) | PASS | **FAIL** (new `addEventListener("keydown", ...)` in `App.tsx`) |
| AC3 (state lives on AppState, no separate context) | PASS | PASS |
| AC4 (toggle doesn't mutate element data) | PASS (4/4 tests) | PASS (4/4 tests) |

**Verdict: DISCRIMINATES.** Positive 4/4, negative 2/4 — caught precisely on the extension-point-bypass checks (AC1, AC2), which is exactly what this task type is designed to test.

## Task D — Architecture Trap (snap selection to grid)

**Positive control:** uses `scene.mutateElement()` and returns `captureUpdate: CaptureUpdateAction.IMMEDIATELY`, per the codebase's own documented undo semantics (`mutateElement.ts`'s doc comment, `actionAlign.tsx`/`align.ts` precedent).
**Negative control:** direct in-place property mutation (`mutable.x = snappedX`, etc.) bypassing `mutateElement()`, with no `captureUpdate` action returned.

| Check | Positive | Negative |
|---|---|---|
| AC1 (single undo fully reverts the snap) | PASS (1/1 test) | **FAIL** — real test failure: `expected 20 to be 13`, undo did not revert position |
| AC2 (no direct property assignment outside mutateElement.ts/Scene.ts) | PASS | **FAIL** (`mutable.x =`, `.y =`, `.width =`, `.height =` found directly in the action) |
| AC3 (version/versionNonce bumped on snapped elements) | PASS (1/1 test) | **FAIL** — real test failure: `expected 2 to be greater than 2`, version never bumped (element mutated in place, not via mutateElement) |
| AC4 (returns CaptureUpdateAction.IMMEDIATELY) | PASS | **FAIL** |

**Verdict: DISCRIMINATES strongly.** Positive 4/4, negative 0/4 — and two of the four checks are *observed test failures*, not just static grep evidence: the trap genuinely breaks undo (confirmed by running the actual test suite against it) exactly as the codebase's own `mutateElement.ts` doc comment warns. This is the strongest empirical result in the R04 set.

## Overall

All 4 R04 tasks discriminate correctly between their positive and negative controls, verified via live-executed `vitest` runs and validator scripts (re-run directly by the orchestrating session after the original agent was cut off twice at the report-writing step). Task D's negative control produced genuine, reproducible test failures rather than merely failing static architecture checks — the strongest form of evidence this benchmark can produce.
