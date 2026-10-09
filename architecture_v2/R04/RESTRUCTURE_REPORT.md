# RESTRUCTURE_REPORT.md — R04 (excalidraw/excalidraw) Condition C

Fifth repository restructured for Condition C, and by far the largest single-cell facade job in
this study so far. TypeScript (Vite/Yarn monorepo), 106.5k LOC (5 originally documented cells,
Phase 8's deliberately-reduced scope from an original 10-cell plan — see `SCOPE.md`).

## Scope: 5 original cells + 1 new nested cell, matching Phase 8's own scope boundary

Condition C works within the SAME scope Condition B's static docs covered — the 5 cells Phase 8
deliberately chose (`common/src`, `math/src`, `fractional-indexing/src`, `element/src`,
`excalidraw/actions`) — not the 5 cells Phase 8 explicitly disclosed cutting for cost reasons
(`packages/excalidraw` root, `scene`, `data`, `utils`, `excalidraw-app`). Applying the
`location:` rule strictly within that scope surfaced **1 new nested cell**:
`packages/element/src/arrows` (a real, undocumented subdirectory with 6 real exports, consumed
only via `element/src/index.ts`'s barrel re-export).

## Facade audit: this repo's cells have very large real public surfaces

Unlike R06 (mostly-internal package, 50/293 hideable) or R07 (near-complete, 1 gap), R04's
documented cells are foundational, widely-depended-upon libraries within the monorepo — matching
R03's/R01's "framework/application surface is legitimately public" pattern, but at much larger
scale:

| Cell | Real exports | Declared after restructuring | Hidden |
|---|---|---|---|
| `common/src` | 313 | 109 (functions/classes; ~188 bare constants left undeclared, established policy) | 0 |
| `math/src` | 67 | 66 | 0 |
| `fractional-indexing/src` | 4 | 3 (1 genuinely unused even internally) | 0 |
| `element/src` (+ new `arrows`) | ~500 | ~360 | 0 |
| `excalidraw/actions` | ~100 | 11 (~90 `Action` instances intentionally left uncollected, documented in prose as a class) | 0 |

**0 hidden across all 5+1 cells.** `element/src` alone — the monorepo's "element & scene data
model" cell — has a real public surface (~500 exports) larger than R01's *entire* 21-cell
restructuring (236 exports). This is a real property of the codebase (a foundational library with
broad legitimate consumption across the app, action registry, and collaboration layers), not an
audit artifact — the facade-completion work for `element/src` alone consumed 4 parallel agent
passes (1 initial full-cell audit + 3 follow-up passes split across its ~50 source files) to
reach completeness.

## One real, disclosed circular dependency — not fixed, not hidden

`packages/common/src` and `packages/math/src` have a genuine two-way dependency (`math` pulls
`toBrandedType` from `common`; `common`'s `colors.ts`/`utils.ts`/`points.ts` pull several
runtime values and types back from `math`). Both cells are already minimal, single-purpose
leaves — neither splitting nor forced unidirectionality is a real fix here. Disclosed honestly in
prose in both cells' own Annotations rather than formalized as a lint-rejected two-cell `Imports`
cycle. Full detail in `CYCLE_FIXES.md`.

## A real production-methodology incident, caught and fully recovered

Mid-restructuring, a flat-directory backup of all 6 (identically-named) `CODEMANIFEST` files
silently overwrote 5 of the 6 files with only the last one surviving — an operator error, not a
tool or agent defect. Caught immediately via `ls`/`wc -l` sanity checks before any further work
proceeded. Recovery: `packages/element/src/CODEMANIFEST`'s full content was independently
recoverable from a merge-staging temp file that had not been touched by the incident;
`packages/fractional-indexing/src/CODEMANIFEST` was recoverable byte-for-byte from the original
Phase 8 archive (it had been left unmodified); `packages/common/src`, `packages/excalidraw/actions`,
and the new `packages/element/src/arrows` cell's manifests were genuinely unrecoverable and were
**redone from scratch** by 3 fresh parallel agents, re-auditing against real source exactly as the
first pass had. The redone work was cross-checked against the lost work's own summary reports for
consistency (declaration counts, specific symbol names) and found consistent. The restructured
commit was git-committed immediately after full recovery to eliminate any further loss risk before
proceeding to the hard gate.

A second, independent incident was caught during the hard gate: an intermediate `yarn
build:packages` run (to verify the build) left `dist/`/`types/` output directories inside several
`packages/*` folders; a subsequent `vitest run` picked up a duplicate, separately-instantiated
copy of a React Context module from the stale `dist/` output, causing 2 test files (10 tests) to
fail with a "tunnelsJotai is null" context-identity error. Diagnosed via a from-scratch
unmodified-commit comparison worktree (which passed 100%, twice), then bisected by temporarily
removing the CODEMANIFEST files entirely (tests *still* failed — proving the docs were not the
cause) and finally by removing the stray `dist/`/`types/` directories (tests then passed cleanly,
confirming the true cause). No repeat of this in the final, reported hard-gate run below.

## Hard gate: build + test

- `yarn build:packages` (builds `common`, `fractional-indexing`, `laser-pointer`, `math`,
  `element`, `excalidraw` via `tsc`): succeeded cleanly, `dist`/`types` output removed afterward
  before testing (per the incident above).
- Full `npx vitest run`: **122/122 test files passed, 1860/1908 tests passed** (47 skipped, 1
  todo) — identical to a from-scratch unmodified-commit run of the exact same suite (122/122,
  1860/1908), confirming zero regressions and zero incidental fixes from the restructuring.
- `goga lint .`: **0 errors across all 6 cells** (`common/src`, `math/src`,
  `fractional-indexing/src`, `element/src`, `element/src/arrows`, `excalidraw/actions`) — after
  resolving 247 lint errors during authoring, the overwhelming majority (244) being the same
  recurring invalid-backtick-cross-reference class seen in every prior repo in this study,
  resolved via a scripted bulk sweep (backtick removal for every reported invalid link string)
  plus a handful of hand-fixed structural issues (`-> this` needing a semantic label per Goga's
  syntax, one inline function-typed parameter needing a named type reference instead).

## Control re-certification

All 8 of Phase 5's control diffs (`tasks/R04/controls/*.diff`) applied cleanly against the
restructured commit with no adaptation needed — no hardcoded base-commit SHAs in any validator, no
renamed identifiers since 0 exports were hidden. One environment-only wrinkle: this machine's
shell has `FORCE_COLOR=3` set, which caused several validators' `node -e` sub-scripts to emit ANSI
color codes into values later compared as shell integers, producing spurious `FAIL`s on the very
first recertification pass; fixed by explicitly unsetting `FORCE_COLOR`/setting `NO_COLOR=1`
before invoking any validator — a local-machine artifact, not a restructuring defect. **All 4
tasks discriminate correctly, matching Phase 5's original certification exactly**:

| Task | Positive: functional | Positive: all AC | Negative: functional | Negative: ≥1 AC fails |
|---|---|---|---|---|
| A | PASS | PASS (4/4) | PASS | Yes (1/4 FAIL — AC2) |
| B | PASS | PASS (4/4) | PASS | Yes (1/4 FAIL — AC2) |
| C | PASS | PASS (4/4) | FAIL | Yes (2/4 FAIL — AC1, AC2) |
| D | PASS | PASS (4/4) | FAIL | Yes (4/4 FAIL) |

## Artifacts

- Restructured commit: `48370385731ae0ce7706c9542083a5e99845c720`, tagged `condition-c-r04-v1`
  in the shared base clone (`benchmark-scratch/repos/R04`).
- `architecture_v2/R04/CYCLE_FIXES.md` — full detail on the disclosed common↔math dependency.
- No `controls_adapted/`/`validators_adapted/` directories needed — all 8 original control diffs
  and all validator scripts worked unmodified (once the local `FORCE_COLOR` artifact was
  neutralized at invocation time, not by modifying the validators themselves).
- The 6 cells' `CODEMANIFEST` files live directly in the restructured commit.
