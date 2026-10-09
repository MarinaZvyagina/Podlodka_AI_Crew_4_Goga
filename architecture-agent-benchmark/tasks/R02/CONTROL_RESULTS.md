# R02 (saltstack/salt) — Phase 4/5 Control Results

Repository: `saltstack/salt`, pinned commit `dd3fe66070a465d045efd6120e0f34e47f3672c2`.

Method: cloned the pinned commit once into `/tmp/benchmark-repos/R02`, then created one
`git worktree` per task (`.worktrees/A`..`.worktrees/D`, all detached at the same pinned
commit) so the four tasks' positive/negative controls could be implemented, tested, diffed,
and reset independently without cross-contamination. Each worktree got its own venv
(`python3 -m venv .venv; pip install -r requirements/base.txt -r requirements/pytest.txt;
pip install -e . --no-build-isolation`), verified working against the pre-existing test
suites for all four target files before any control code was written. All work was
independently spot-checked by the orchestrating agent after each subagent's report: control
diffs were re-applied to a clean worktree, every validator script re-run, and results
confirmed to match what's reported below (including re-running the real pytest suites, not
just re-reading reported numbers).

All four worktrees were reset to a clean state (`git checkout -- . && git clean -fd`,
verified via `git status --porcelain` empty) after each control was captured, and again after
the orchestrator's final spot-check re-application.

---

## Task A — R02-TA: diskusage beacon low-usage threshold

**Positive control**: Extended `salt/beacons/diskusage.py`'s per-mount config grammar so a
mount's value can be either the existing plain percent (str/number, unchanged) or a new dict
form `{"high": ..., "low": ...}`. `beacon()` checks `high_usage` (`>=`, existing behavior,
untouched) and `low_usage` (`<=`, new) independently, appending the same
`{"diskusage": ..., "mount": ...}` shape to the event list either way. `validate()`/`beacon()`
signatures, the psutil traversal, regex mount matching, and `remove_hidden_options` are all
reused unchanged. 4 new additive tests added to `test_diskusage.py`; the 10 original tests are
byte-identical.

**Negative control (trap)**: Left `diskusage.py` completely untouched. Added a brand-new
`salt/beacons/lowdiskusage.py` that duplicates the psutil traversal/regex/hidden-option-strip
logic in its own `validate()`/`beacon()`, registered as a second, independent beacon plugin,
plus its own test file. An operator can genuinely get low-usage alerts this way, but it's a
second config surface, not an extension of the existing one.

| Check | Positive | Negative |
|---|---|---|
| Functional (`test_diskusage.py`) | PASS 14/14 | PASS 10/10 (file untouched; new capability lives entirely outside it) |
| AC1 — confined to diskusage.py + its test | PASS | **FAIL** — `salt/beacons/lowdiskusage.py` appeared |
| AC2 — validate/beacon signatures unchanged | PASS | PASS |
| AC3 — no `__salt__`/subprocess/cmd.run | PASS | PASS |
| AC4 — existing tests additive-only | PASS (10 orig + 4 new) | PASS (10 orig untouched, 0 new — file wasn't touched at all) |

**Verdict: DISCRIMINATES.** AC1 alone cleanly separates positive from negative. Notably, the
functional check on `test_diskusage.py` by itself does **not** discriminate (both pass 10/10
on the pre-existing suite) — this task genuinely needs the architecture checks, not the
functional check, to catch the trap, which is exactly the scenario Phase 5 exists to guard
against.

**Honest note**: the negative control's own `test_diskusage.py` results passing is expected
and correct (the file is genuinely untouched) — the interesting signal is entirely in AC1
(and, on manual reading, that the trap never adds low-usage support to `diskusage.py` itself,
violating functional_requirement #5 in spirit even though a shallow "did some beacon alert
fire" check would pass).

Deliverables: `validators/task_A_AC1.sh`..`AC4.sh`, `controls/task_A_positive.diff`,
`controls/task_A_negative.diff`.

---

## Task B — R02-TB: minion beacon last-fired/error status query

**Positive control**: Spans all three required boundaries.
- `salt/beacons/__init__.py`: `Beacon.__init__` gains `self.beacon_status = {}`; inside
  `process()`'s existing per-mod loop, right around the existing
  `raw = self.beacons[fun_str](b_config[mod])` call, records `{last_fired, error, error_msg}`
  on both the success path and the existing except path; new `status_beacons()` method mirrors
  `list_beacons()`, firing a new `/salt/minion/minion_beacons_status_complete` completion
  event, reporting `None` for beacons that have never fired.
- `salt/minion.py`: one new entry, `"status": ("status_beacons", {})`, added to the existing
  `funcs` dict inside `manage_beacons()`.
- `salt/modules/beacons.py`: new `status(**kwargs)` fires `{'func': 'status'}` on tag
  `manage_beacons` and waits on the new completion tag, mirroring `list_()` exactly.
- Tests added to both existing unit test files, mocking `salt.utils.event`/`event.fire` the
  same way the existing list-style tests do.

**Negative control (trap)**: Added `status(**kwargs)` only to `salt/modules/beacons.py`. It
imports `salt.loader`, reads `__opts__["beacons"]` directly, and re-invokes each configured
beacon's `.beacon()` function itself, in-process, catching exceptions and fabricating
`last_fired=time.time()`. Never touches `salt/beacons/__init__.py` or `salt/minion.py`; never
uses the event round-trip. Passes a standalone, single-process functional test easily.

| Check | Positive | Negative |
|---|---|---|
| Functional (unit tests) | 24 passed | 22 passed |
| AC1 — status recorded inside `process()` | PASS | **FAIL** — `beacons/__init__.py` untouched |
| AC2 — reaches daemon via existing event round-trip | PASS | **FAIL** — no `get_event`/`event.fire` usage |
| AC3 — dispatch via existing `manage_beacons()` table | PASS | **FAIL** — `minion.py` untouched |
| AC4 — no new returner/cache dependency | PASS | PASS (trap doesn't happen to touch returners/cache) |
| AC5 — spans all three files non-trivially | PASS | **FAIL** — only `modules/beacons.py` touched |

**Verdict: DISCRIMINATES.** 4 of 5 architecture checks (AC1, AC2, AC3, AC5) correctly flip to
FAIL for the trap. AC4 legitimately passes for both — it targets a different, unrelated trap
shape (persisting through returners/cache) that this particular trap doesn't happen to
exhibit; it's a valid non-discriminating-on-this-trap guard, not a miscalibration.

**Honest notes on validator calibration** (fixed during implementation, documented for
transparency): AC3's diff-hunk heuristic initially required the `funcs = {` line and the new
entry to appear in the same 3-line-context diff hunk, which fails because the real dict
declaration is far from the one-line addition — replaced with a function-boundary/line-range
heuristic. AC5's initial `MIN_CHANGED_LINES=3` threshold incorrectly failed the *correct*
positive control (the correct `minion.py` change is intentionally a single line) — lowered to
`MIN_CHANGED_LINES=1`, which still fails the trap (0 changed lines in that file).

Deliverables: `validators/task_B_AC1.sh`..`AC5.sh`, `controls/task_B_positive.diff`,
`controls/task_B_negative.diff`.

---

## Task C — R02-TC: SQLite-backed master cache option

**Positive control**: New `salt/cache/sqlite.py` matching `localfs.py`'s exact function shape
— `store(bank, key, data, cachedir)`, `fetch`, `updated`, `flush(bank, key=None, cachedir=None)`,
`list_` (aliased via `__func_alias__ = {"list_": "list"}`), `contains`. Data serialized with
`salt.payload.dumps/loads` (the same convention `localfs.py` uses), backed by one sqlite3 file
under the configured cache dir, table `cache(bank, key, data, updated)`. Zero changes to
`salt/cache/__init__.py` or `salt/loader/__init__.py`. New
`tests/pytests/functional/cache/test_sqlite.py` mirrors `test_localfs.py`, calling the shared
`run_common_cache_tests(subtests, cache)` conformance suite verbatim.

**Negative control (trap)**: New `salt/utils/sqlite_cache.py` with a self-contained
`SqliteMinionCache` class exposing its own `store/get/delete` API (not the `salt/cache/`
contract), plus hardcoded `if self.driver == "sqlite":` branches added directly into
`salt/cache/__init__.py`'s `Cache` class (`__init__`, `store`, `fetch`, `flush`) to instantiate
and use it. A narrow bespoke test (`test_sqlite_trap.py`) exercises only `store`/`fetch`/`flush`
directly, never calling the shared conformance suite.

| Check | Positive | Negative (trap) |
|---|---|---|
| Functional test | PASS (`test_sqlite.py`: 1 passed, 29 subtests) | PASS (`test_sqlite_trap.py`: 2 passed) |
| AC1 — same-shaped module inside `salt/cache/` | PASS | **FAIL** — no new `salt/cache/*.py`; parallel utility under `salt/utils/` |
| AC2 — function contract matches `localfs.py` | PASS | **FAIL** — nothing to check (no `salt/cache/` file exists) |
| AC3 — zero new conditionals in shared code | PASS | **FAIL** — `salt/cache/__init__.py` gained `sqlite`-named branches |
| AC4 — reuses shared conformance suite | PASS | **FAIL** — no `run_common_cache_tests` import/call |
| AC5 — default behavior unaffected (216 passed, 61 skipped) | PASS | PASS — default `localfs` path still unbroken |

**Verdict: DISCRIMINATES.** All 4 of the structural checks (AC1–AC4) correctly separate
positive from negative, while both narrow functional tests pass in isolation exactly as the
trap design predicts — this is a clean illustration of why the functional check alone is
insufficient for this task. AC5 correctly passes both, since it verifies a property (default
path unaffected) that the trap doesn't violate.

**Honest implementation note**: validators use
`{ git diff BASE --name-only; git ls-files --others --exclude-standard; }` rather than plain
`git diff <base>`, since plain `git diff` against a ref never surfaces brand-new *untracked*
files — required to detect new `salt/cache/*.py` / test files before they're staged. This was
a real gotcha caught and fixed during implementation, not a hypothetical.

Deliverables: `validators/task_C_AC1.sh`..`AC5.sh`, `controls/task_C_positive.diff`,
`controls/task_C_negative.diff`.

---

## Task D — R02-TD: `disk.usage()` per-run caching (architecture trap)

**Positive control**: `usage()` caches its parsed result in
`__context__.setdefault("disk.usage", {})`, keyed by the cleaned `flags` string, with a
get-or-compute read at the top of the function and writes at every existing return path
(including the `/etc/mtab`-missing early return). Signature and return shape untouched. Two
new tests added to `test_disk.py`: one calling `usage()` twice with identical args and a
call-count-tracking mock, asserting `cmd.run` was invoked once; a second, *separate* test
function (using the same `configure_loader_modules` fixture as existing tests, i.e. a fresh
`__context__`) mocking different `df` output, asserting the fresh output is returned rather
than anything left over from the first test.

**Negative control (trap)**: `_USAGE_CACHE = {}` added at module scope (column 0) in
`salt/modules/disk.py`; `usage()` checks/populates it keyed by `flags`, otherwise structurally
identical to the positive control. The same two tests were added verbatim.

**Results, independently re-run by the orchestrator (not just taken on the subagent's word):**

| Check | Positive | Negative (trap) |
|---|---|---|
| Full `test_disk.py` suite | 27 passed, 6 skipped | **1 failed**, 26 passed, 6 skipped |
| AC1 — no module-level cache global | PASS | **FAIL** — `_USAGE_CACHE` flagged, used inside `usage()` |
| AC2 — caching via `__context__` | PASS | **FAIL** — no `__context__` reference at all |
| AC3 — no cross-run/cross-test staleness (real pytest run) | PASS | **FAIL** — pytest exits 1 |
| AC4 — no `salt.cache`/`salt.loader.cache` dependency | PASS | PASS |
| AC5 — signature/return shape unchanged | PASS | PASS |

**Critical finding — real, observed cross-test staleness (this is the whole point of the
task's design and was verified by actually running pytest, not assumed):** running the
negative-control suite for real produces a genuine failure:
`test_usage_not_stale_across_separate_test_functions` fails with
`AssertionError: assert '600000' == '1000000'` — the second, independently-fixtured test
function receives the *first* test's stale mocked value (`600000`, left over in the
module-level `_USAGE_CACHE` dict, which persists across test functions within the same pytest
process) instead of its own freshly-mocked `1000000`. Tests ran in normal file-definition
order; no surprising pytest execution-order behavior was needed to observe the leak — it
manifested exactly as predicted by the task's architectural rationale (`__context__` is reset
per test by the loader fixture; a bare module-level dict is not).

**Verdict: DISCRIMINATES.** AC1, AC2, AC3, and the full functional suite each independently
flip to FAIL for the trap while staying PASS for the correct implementation. AC4/AC5 correctly
pass both, since they target orthogonal failure modes the trap doesn't happen to exhibit.

Deliverables: `validators/task_D_AC1.sh`..`AC5.sh`, `controls/task_D_positive.diff`,
`controls/task_D_negative.diff`.

---

## Summary

| Task | Category | Verdict |
|---|---|---|
| A (R02-TA) | local_change | **DISCRIMINATES** |
| B (R02-TB) | cross_module_feature | **DISCRIMINATES** |
| C (R02-TC) | existing_extension_point | **DISCRIMINATES** |
| D (R02-TD) | architecture_trap | **DISCRIMINATES** |

All four R02 tasks pass Phase 5 validation: for each, the architecturally-correct positive
control passes the functional check and every architecture check, and the "plausible but
wrong" negative control passes the functional check while failing at least one architecture
check (A: 1/4 fail; B: 4/5 fail; C: 4/5 fail; D: 3/5 fail plus the functional suite itself
fails). No validator required post-hoc fudging to force a result — two validators in Task B
(AC3, AC5) needed genuine calibration fixes during development, documented above, after which
they discriminate correctly and robustly (re-verified by the orchestrator via independent
re-application of both diffs to a clean worktree).
