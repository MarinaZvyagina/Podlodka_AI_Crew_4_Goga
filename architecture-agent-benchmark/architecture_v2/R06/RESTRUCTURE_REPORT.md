# RESTRUCTURE_REPORT.md — R06 (etcd-io/etcd) Condition C pilot

Per `TREATMENT_DESIGN_EXPERIMENT_B.md` §1 (Condition C — Goga-Native Architecture), etcd was
chosen as the pilot repository for real cell-facade-discipline restructuring, since it is the
smallest of the 10 study repositories (62.3k LOC) and already carries a complete, `goga
lint`-clean CODEMANIFEST forest from Phase 8.

## What "restructuring" turned out to mean in practice

Initial reconnaissance (see chat record) found that Goga's `location`/no-subdirectory cell rule
constrains only *declared* files, not full-directory coverage — meaning a codebase can satisfy
Goga's structural rules with zero code motion if a cell's declared facade already matches the
real, physical directory layout. A full audit of all 293 real exports across the 10 documented
cells found that Phase 8's manifests declared only 27 of them (9%) — the "spine" only, per
`architecture/R06/SCOPE.md`'s explicit non-exhaustive scope.

Given the user's explicit choice of "full facade discipline" over "just document everything,"
the actual work was:

1. **Classify** every one of the 293 real exports as either genuinely cell-internal (safe to
   hide) or genuinely used elsewhere in etcd's real codebase (must be declared), via repo-wide
   `grep`-based usage analysis (not the 10 cells alone — the full `go.etcd.io/etcd` tree,
   including `etcdctl/`, `etcdutl/`, `tools/`, `tests/`, `server/embed/`, `server/proxy/`, etc.).
2. **Hide** (unexport, lowercase-rename + fix all same-package references) the 50 exports
   confirmed to have zero usage outside their own cell.
3. **Declare** the remaining 243 in CODEMANIFEST, reading each symbol's real signature/behavior
   from source (not guessed) — 107 of these are in `client/v3` (etcd's public Go client library,
   where a wide surface is legitimate by design; declared in full rather than narrowed).

## Key finding: most "undeclared" exports were not undisciplined code

83% of the real export surface (243/293) is genuinely relied upon outside the 10 documented
cells, by etcd's wider ecosystem (its own CLI, `etcdutl`, hundreds of integration/unit tests, the
public client library). For a mature, 62k-LOC, widely-consumed real codebase, "facade discipline"
mostly means *completing the documentation of a legitimately wide contract*, not *shrinking the
contract* — only 17% (50/293) was genuinely hideable internal leakage. This is disclosed
explicitly rather than presented as if narrowing dominated the work.

## Process and verification

- **No circular dependencies** were found in the real (not just declared) package-level import
  graph among the 10 cells (`go list -f '{{join .Imports "\n"}}'` per cell, cross-referenced) —
  confirmed before any restructuring work began. See `CYCLE_FIXES.md` (empty — nothing needed
  fixing).
- Work was parallelized across 11 subagents (one per internal cell, plus 2 for `client/v3`'s
  larger symbol set), each confined to its own cell directory to avoid file conflicts, each
  independently verifying `goga lint` (0 errors), `goga contract <cell>` (no unexpected drift),
  `go build`/`go vet` for its own package.
- **One real coordination bug** was caught and fixed: two agents editing the same
  `client/v3/CODEMANIFEST` file concurrently would have raced; the second agent's launch was
  deliberately sequenced after the first's completion instead.
- **One symbol (`NewOp`, client/v3) was missed** during manual list-splitting between the two
  client/v3 agents and caught by a final full re-audit; added directly, not delegated.
- Two symbols (`HashByRev`, `Response` in `server/etcdserver`) were originally classified
  MUST-DECLARE based on a `grep -rl '\.$sym\b'` heuristic that turned out to produce a false
  positive (matching an unrelated same-named method on a different type) — the assigned agent
  caught this discrepancy independently, flagged it, and documented both anyway (harmless, since
  declaring something with no real external caller doesn't break anything — just slightly more
  conservative than strictly necessary).
- **`AutoWatchID`/`InvalidWatchID`** (two `client/v3` constants) were missed entirely by the
  initial audit (which only scanned `type`/`func` declarations, not `const`), surfaced by the
  `mvcc` agent's own cross-cell Import addition, and fixed directly as a final gap-closing step.
- **Final full-repo `goga lint`: 0 errors, 10/10 cells clean.**

## Hard gate: build + test

- `go build ./...` (entire 13-module go.work workspace): clean, 0 errors.
- `go vet ./...`: clean, 0 errors.
- Full `client/v3` module test suite: all packages pass.
- Full `server` module test suite (covers `auth`, `etcdserver`, `lease`, `storage/{backend,mvcc,
  schema,wal}`, all `etcdserver/api/*` subpackages): 31 packages, 0 real failures. One transient
  `TestHashKVWhenCompacting` timeout on the first full-package run was confirmed to be pre-existing
  flakiness (times out only under full-suite parallel load, not caused by these changes) — it
  passed cleanly in isolation both before and after restructuring, and passed cleanly on a repeat
  full-package run with no code changes in between.

## Control re-certification

All 8 of Phase 5's positive/negative control diffs for R06 (`tasks/R06/controls/*.diff`) were
re-applied against the new restructured base commit and re-validated with the repository's real
architecture/functional validators. **3 of 8 diffs required adaptation** (kept as separate copies
under `controls_adapted/`, originals in `tasks/R06/controls/` untouched and still valid for the
primary study's unmodified base commit):

- `task_B_positive.diff`, `task_B_negative.diff`: referenced the now-hidden `LeaseQueue` type
  (renamed `leaseQueue`) in an unrelated context line.
- `task_D_positive.diff`: referenced the now-hidden `SetScheduledCompact`/`UnsafeReadFinishedCompact`
  functions (renamed lowercase) in unrelated context lines.

**16 of ~20 architecture validator scripts** (`tasks/R06/validators/task_*_AC*.sh`) hardcode the
original base commit SHA for `git diff`-based change detection — all 16 were copied to
`validators_adapted/` with the SHA updated to the restructured commit
(`abe967acfac35ba278795c42e0a8968637594cef`), since diffing against the wrong base would show the
entire restructuring as "changed lines" and corrupt every range-overlap check. Functional
validators needed their `fixtures/` directory copied alongside them (initially missed, caught by
an all-8-controls functional FAIL that made no sense for known-good positive controls).

**Final re-certification result — all 4 tasks still discriminate correctly on the restructured
commit**, matching the original Phase 5 pattern:

| Task | Positive: functional | Positive: all AC | Negative: functional | Negative: ≥1 AC fails |
|---|---|---|---|---|
| A | PASS | PASS (5/5) | FAIL | Yes (2/5 FAIL, 1 MANUAL REVIEW) |
| B | PASS | PASS (5/5) | FAIL | Yes (3/5 FAIL) |
| C | PASS | PASS (5/5) | FAIL | Yes (3/5 FAIL) |
| D | PASS | PASS/MANUAL REVIEW (3 PASS, 2 MANUAL REVIEW) | FAIL | Yes (4/5 FAIL) |

One pre-existing (not restructuring-caused) validator quirk was found and confirmed identical on
the original, unmodified commit: `task_D_AC3.sh`/`task_D_AC5.sh` both look for the same fixture
path (`tests/integration/v3_range_caching_check_test.go`) that `task_D_positive.diff` itself
creates as part of its real implementation — running these ACs against an already-diff-applied
worktree always reports `MANUAL REVIEW REQUIRED: file already exists`, verified via a direct
side-by-side test against the pristine original commit + original diff (same result). This is a
pre-existing characteristic of these two validator scripts' fixture-naming, not something
restructuring introduced or something this pilot needed to fix.

## Artifacts

- Restructured commit: `abe967acfac35ba278795c42e0a8968637594cef`, tagged `condition-c-r06-v1`
  in the shared base clone (`benchmark-scratch/repos/R06`, same `.git` object database as the
  persistent base clone — survives cleanup of any `/tmp` scratch worktree).
- `architecture_v2/R06/CYCLE_FIXES.md` — empty; no real cycles found, nothing to fix.
- `architecture_v2/R06/controls_adapted/*.diff` — all 8 control diffs, 3 adapted for renamed
  identifiers, 5 copied unchanged.
- `architecture_v2/R06/validators_adapted/*.sh` + `fixtures/` — all validators, 16 adapted for
  the new base commit SHA, 8 copied unchanged, full fixtures directory copied alongside.
- The 10 cells' `CODEMANIFEST` files themselves, now facade-complete, live directly in the
  restructured commit (not duplicated under `architecture_v2/`) since they are real repository
  content, not benchmark scaffolding.

## Scope note

This report covers R06 only, per the user's explicit choice to pilot one repository fully before
deciding whether/how to scale to the remaining 9 (`TREATMENT_DESIGN_EXPERIMENT_B.md`'s cost
estimate flagged Signal-Android/Signal-iOS/salt as repositories where this kind of restructuring
is least likely to go smoothly, given their scale). No Condition C benchmark runs have been
executed yet against this restructured commit — that is the next step, pending a decision on
scaling.
