# RESTRUCTURE_REPORT.md — R02 (saltstack/salt) Condition C

Eighth repository restructured for Condition C. 275.5k LOC, the largest Python repo in the study,
and — per explicit user decision — the largest single-repo full-completeness expansion in the
entire study: 5 of R02's 9 originally-documented cells were deliberately written in Phase 8 as
curated representative samples (`modules`: 3 of 267 files documented, `utils`: 5 of ~170,
`states`: 2 of 132, `runners`: 5 of 30, `grains`: 2 of 12) rather than complete facades, and this
restructuring brought all five to full completeness.

## Scope: 14 cells (9 original + 5 new nested)

The 9 originally-documented cells map 1:1 onto real Salt package directories (`salt` [root,
scoped to `minion.py`+`master.py`], `salt/loader`, `salt/modules`, `salt/states`, `salt/runners`,
`salt/returners`, `salt/cache`, `salt/grains`, `salt/utils`) — no physical file moves were needed;
this restructuring is CODEMANIFEST-only (confirmed via `git diff --stat` against the pinned
commit: zero `.py` files touched). Per the `location:`-rule precedent established in R05 (and
followed in R09), `salt/utils`'s 5 real subdirectories-with-code (`openstack/`, `validate/`,
`decorators/`, `dockermod/`, `pkg/`) were each formalized as their own nested cell — **14 cells
total**.

## Full-completeness expansion (the user's explicit decision)

Per the user's explicit choice — "Expand everything to full completeness," over the alternative
of preserving Phase 8's representative-sample philosophy — all 5 large cells were expanded to
document **every real, non-underscore top-level function/class**, not a curated subset:

| Cell | Files | Declarations after expansion |
|---|---|---|
| `salt/modules` | 266 | ~3,400 |
| `salt/utils` (+ 5 nested) | 172 (+ ~70 in nested) | 1,180 (+ ~68 in nested) |
| `salt/states` | 132 | 550 |
| `salt/runners` | 30 | 176 |
| `salt/grains` | 12 | 48 |

Facade rule verified directly from source rather than assumed: `salt/loader/lazy.py`'s
`LazyLoader` (`if attr.startswith("_"): continue`) confirms that for `modules`/`states`/
`runners`/`grains`/`returners`, every non-underscore top-level function/class is real,
dynamically-dispatched API — no separate external-usage check needed (unlike `salt/utils`, which
is consumed via ordinary static Python imports and so did need real usage verification per
function).

### Process: parallel batch agents + file-based handoff + custom merge tooling

Given the scale (hundreds of files, thousands of declarations), each of the 5 cells was split
into parallel batch agents (~15-30 files each), each writing its output to a dedicated temp file
rather than returning full content through the orchestrating session (necessary to keep the
session's own context bounded at this scale — not needed in any smaller prior repo). A custom
regex-based block-merger (not strict YAML parsing, since PyYAML's — and `goga lint`'s own
parser's — 1024-character simple-key limit is exceeded by several real Salt signatures, e.g.
`pip_state.py`'s `installed()` with ~50 parameters) merged each cell's batches, auto-disambiguating
cross-file name collisions (extremely common for `__virtual__()` gates and shared verbs like
`present`/`absent`) via module-stem prefixing (e.g. `rabbitmq_vhost.present(...)`).

A recurring fix pipeline (established on `salt/utils`, then reapplied identically to `states`/
`runners`/`modules`) converged each cell from thousands of lint errors to zero or near-zero within
2-4 passes: strip Python default-value clauses (unsupported DSL syntax) → bulk-remove invalid
backtick cross-references (2 passes typically needed, since removing an outer link can expose an
inner one) → add semantic labels to bare `-> None`/`-> bool`/etc. return types → spot-fix
structural errors (self-referencing/reversed `Base::Derived` mutations, oversized signatures
exceeding the tooling's line-length limit, invalid DSL fields).

**Final state — `goga lint .` (whole project): cells: 14, errors: 0.**

## Two real facade gaps found via whole-project lint (not single-cell)

`fopen` (`salt/utils/files.py`) and `is_windows` (`salt/utils/platform.py`) are both imported by
name in `salt/grains/CODEMANIFEST`'s own `Imports:` block, but neither had a corresponding routine
declaration in `salt/utils/CODEMANIFEST` — a real gap left by the full-completeness expansion's
batch split (each file's batch agent treated these two as already-covered by the old 5-sample
body, which was then fully replaced rather than merged). Only surfaced by `goga lint .` from the
project root (`import_type_exists` — declared imports must resolve to a real declared type in the
source cell), not by linting `salt/utils` alone. Fixed by adding both as proper routine
declarations. Full detail in `CYCLE_FIXES.md`.

## Real Python-import-graph cycle analysis: a genuine 11-cell SCC, disclosed

Unlike R05 (clean DAG, 0 cycles) and R09 (3 isolated bidirectional pairs), R02's real source-code
import graph — analyzed via Python's own `ast` module across all 662 tracked files, DFS cycle
detection — has a genuine 11-cell strongly-connected component centered on `salt/loader`'s
dynamic-plugin-loading-hub role and `salt/utils`'s bidirectionally-shared-toolbox role. This is
disclosed in full in `CYCLE_FIXES.md` rather than hidden: it reflects Salt's real, 15-year-old
dependency-injection-container architecture (the loader must reference every plugin category to
load it; plugin files reference the loader back for injected-context types; nearly everything
reaches into the shared `utils` toolbox, which itself reaches back into a handful of higher-level
cells for narrow reasons). `goga lint` itself does not check for cycles and reports 0 errors
project-wide — the SCC exists only in the real source graph, not as a formal two-cell DSL `Imports:`
conflict.

## Two confirmed `goga lint` tool limitations (same as every prior repo)

`import_has_valid_from_path` false positive when linting a single cell (e.g. `salt/states`,
`salt/modules`) out of full-project context — `salt/loader`'s `LazyLoader`/`NamedLoaderContext`
types report "not found on filesystem"; resolves to 0 errors when linting from the project root.

## Hard gate: build + test

- `pip install -e . --no-build-isolation --no-deps` (fresh venv, `pip install -r requirements/
  base.txt -r requirements/pytest.txt` first): succeeded cleanly, no dependency issues.
- Every restructured cell's package imports cleanly: `salt.modules.cmdmod`, `salt.states.pkg`,
  `salt.runners.jobs`, `salt.grains.core`, `salt.returners.local`, `salt.cache`, `salt.loader`,
  `salt.minion`, `salt.master`.
- `pytest tests/pytests/unit/` hit a pre-existing environment issue identical on both commits: a
  `pytest-system-statistics` 1.0.2 / pytest 8.4 incompatibility (`ValueError: Plugin already
  registered under a different name: sysstats-processes=None`, an `INTERNALERROR` that aborts the
  whole session before any test runs) and a pre-existing missing-optional-dependency collection
  error (`tests/pytests/unit/utils/test_vmware.py` — `NameError: name 'vim' is not defined`,
  `pyvmomi` not in `requirements/base.txt`/`requirements/pytest.txt`) — both confirmed identical,
  side-by-side, on the untouched original commit, not restructuring artifacts. Worked around with
  `-p no:system-statistics --continue-on-collection-errors`.
- Full run, side-by-side against the exact same commit's *unmodified* original checkout (separate
  venv, same flags): **23 failed, 8356 passed, 2720 skipped, 1 xfailed, 135 errors, 93 subtests
  passed** — identical counts on both. The 159 individual failing/erroring test IDs were diffed
  directly (not just counts): **byte-for-byte identical set** on both commits (PAM auth, etcd,
  gitfs, and network-dependent tests failing for pre-existing environment/dependency-availability
  reasons unrelated to this repo's architecture). Confirms zero regressions and zero incidental
  fixes from the restructuring.

## Control re-certification

All 8 of Phase 5's control diffs (`tasks/R02/controls/*.diff`) applied cleanly against the
restructured commit (no adaptation needed to the diffs themselves — no hardcoded base-commit SHAs
inside them, no renamed identifiers since 0 exports were hidden). 14 of ~22 functional validator
scripts hardcode the original base-commit SHA in their own scope-check logic (`BASE="dd3fe66..."`,
used to diff the working tree against the true pinned commit) and needed SHA-adapted copies
(`architecture_v2/R02/validators_adapted/`, matching the pattern used for R05/R06/R09) — without
this, the restructured commit's own CODEMANIFEST additions show up as "unexpected changes" in
scope checks that were never meant to catch documentation. **All 4 tasks discriminate correctly,
matching Phase 5's original certification exactly**:

| Task | Positive: functional | Positive: all AC | Negative: functional | Negative: ≥1 AC fails |
|---|---|---|---|---|
| A | PASS | PASS (4/4) | FAIL | Yes (1/4 FAIL — AC1) |
| B | PASS | PASS (5/5) | FAIL | Yes (4/5 FAIL — AC1, AC2, AC3, AC5) |
| C | PASS | PASS (5/5) | FAIL | Yes (4/5 FAIL — AC1, AC2, AC3, AC4) |
| D | PASS | PASS (5/5) | FAIL | Yes (3/5 FAIL — AC1, AC2, AC3) |

## Artifacts

- Restructured commit: `bdb21a0937cfb8556a92fc6257f8f3c08bc4c32d`, tagged `condition-c-r02-v1` in
  the shared base clone (`benchmark-scratch/repos/R02`).
- `architecture_v2/R02/CYCLE_FIXES.md` — full detail on the 11-cell SCC and the 2 facade-gap
  fixes.
- `architecture_v2/R02/validators_adapted/` — 14 SHA-adapted functional validator scripts.
- The 14 cells' `CODEMANIFEST` files live directly in the restructured commit (~50,500 total
  lines across all 14 files).
