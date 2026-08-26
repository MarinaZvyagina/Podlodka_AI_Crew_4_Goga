# R02 (saltstack/salt) — Functional Validators

Repository: `saltstack/salt`, pinned commit `dd3fe66070a465d045efd6120e0f34e47f3672c2`.

This document covers the **functional** correctness validators built to close the gap
identified before the 800-run benchmark: Phase 4 already produced runnable *architecture*
validators (`validators/task_X_AC*.sh`) for all four R02 tasks, but `functional_success` had
no executable check, only prose in each `metadata_X.yaml`'s `functional_check_command`. This
phase adds one standalone, runnable, implementation-agnostic script per task:
`validators/task_A_functional.sh` .. `task_D_functional.sh`, each backed by a pytest fixture
under `validators/fixtures/task_X_test.py`.

## Method

For each task:
1. Read `task_X.md`, `metadata_X.yaml` (`functional_requirements` / `functional_check_command`),
   and `CONTROL_RESULTS.md`'s account of what Phase 5 actually ran.
2. Wrote a pytest file that calls only the task's real public entry point(s) (`beacon()`/
   `validate()`, `Beacon.process()`, `salt.modules.beacons.*`, `salt.cache.factory()`,
   `salt.modules.disk.usage()`) — never an internal helper, attribute name, or file name specific
   to one candidate's implementation shape. Where the task's own grammar/naming is intentionally
   open (Tasks A and B), the validator auto-discovers the new surface (new config value shapes,
   new functions/attributes not present at the pinned base commit) rather than hardcoding one
   candidate's naming choice.
3. `validators/task_X_functional.sh <repo_path>` copies the fixture into the target checkout at
   a real test-discoverable path, runs `python -m pytest <path> -q` (using `<repo>/.venv/bin/python`
   if present), prints `PASS: ...` / `FAIL: ...`, and always removes the injected fixture
   (`trap cleanup EXIT`) regardless of outcome.
4. Verified against both `controls/task_X_positive.diff` (must produce a real,
   architecturally-correct implementation) and `controls/task_X_negative.diff` (the documented
   "plausible but wrong" trap), by applying each diff to the clean pinned-commit checkout at
   `/tmp/benchmark-repos/R02`, running the validator, and resetting (`git checkout -- .` +
   `git clean -fd` on the trap's new untracked files) before moving on. Actual observed pytest
   output is quoted below, not just re-stated pass/fail counts.

All four scripts leave the target repo byte-identical to how they found it: the only file they
ever write is the injected fixture, which is deleted in a `trap ... EXIT` regardless of the
pytest exit code.

---

## Task A — diskusage beacon low-usage threshold

**Script**: `validators/task_A_functional.sh` · **Fixture**: `validators/fixtures/task_A_test.py`
**Injected at**: `tests/pytests/unit/beacons/task_A_functional_test.py`

**What it checks**: calls `salt.beacons.diskusage.validate(config)` / `.beacon(config)` directly
(the exact generic contract `Beacon.process()` uses for any beacon module) with:
- Regression cases: plain percent string, bare number, regex mount matching, non-list config
  rejection — all pre-existing high-threshold behavior, re-verified independently rather than
  trusted from the candidate's own (possibly edited) `test_diskusage.py`.
- New capability: since the task text deliberately leaves the low-threshold config grammar open
  ("in some form that fits naturally"), the validator probes five plausible conventions
  (`{"low": "N%"}`, `{"low": N}`, `{"low": "N%", "high": "M%"}`, signed-percent-string `"-N%"`,
  signed-number `-N`) against `/mnt/tmp` (a mount whose stubbed usage is fixed at 50%) at a
  threshold that should fire (60) and one that should not (10), and accepts if **any** convention
  produces the documented fire-at-or-below / silent-above behavior.
- A high-threshold alert on a different mount must still fire "alongside" the new option.

**Positive control** (`controls/task_A_positive.diff`, dict `{"low": ..., "high": ...}` grammar):
```
.......                                                                  [100%]
7 passed in 1.05s
PASS: diskusage beacon supports a working low-usage alert threshold without regressing existing
high-usage behavior (task_A_functional).
```

**Negative control** (`controls/task_A_negative.diff`, brand-new `salt/beacons/lowdiskusage.py`,
`diskusage.py` untouched):
```
......F                                                                  [100%]
FAILED ...::test_low_usage_alert_threshold_supported
assert [] (no probed low-usage-threshold config convention worked)
1 failed, 6 passed in 1.06s
FAIL: task_A functional check failed ...
```

**Note on divergence from `CONTROL_RESULTS.md`**: that document reports the *pre-existing*
`test_diskusage.py` suite passing 10/10 unmodified for the trap (true — the file is untouched)
and states the functional check alone does *not* discriminate this trap. This validator does
discriminate, because it calls `diskusage.validate()`/`.beacon()` **with a low-threshold config**
directly, rather than merely re-running whatever suite ships in the file. Since
`functional_requirements` item 5 explicitly states "All new functionality is confined to
salt/beacons/diskusage.py", and the trap's low-usage capability lives entirely in a separate
file, `diskusage.py` genuinely has no working low-threshold support to find — a properly scoped
functional probe against the named target file necessarily reports that gap. `task_A_AC1.sh`
remains the authoritative architecture check for *why* (new file appeared under
`salt/beacons/`); this functional script independently corroborates the same conclusion from
observed behavior rather than a diff-shape rule.

---

## Task B — minion beacon last-fired/error status query

**Script**: `validators/task_B_functional.sh` · **Fixture**: `validators/fixtures/task_B_test.py`
**Injected at**: `tests/pytests/unit/task_B_functional_test.py`

**What it checks**, in two parts (both real public entry points named in the task's own
architectural constraints):
1. Drives the real `salt.beacons.Beacon.process()` evaluation loop with a beacon that succeeds,
   one that raises, and one that is configured but never invoked, then auto-discovers whatever
   *new* public attribute/method the candidate added to `Beacon` (diffed against the exact
   attribute/method set present at the pinned base commit) and checks it plausibly records a
   recent timestamp for the two that ran, a distinguishable error signal for the one that raised,
   and no fabricated timestamp for the one that never fired.
2. Auto-discovers whatever *new* function the candidate added to `salt/modules/beacons.py`
   (diffed against the pinned base commit's function set) and calls it with
   `salt.utils.event.SaltEvent.get_event` and `__salt__['event.fire']` mocked the same way Salt's
   own `test_list`/`test_add`/`test_delete` tests already do, feeding back a fabricated
   completion event under several plausible payload key names.

**Positive control** (`controls/task_B_positive.diff`): 
```
..                                                                       [100%]
2 passed in 2.05s
PASS: minion beacon status (last-fired/error, incl. never-fired) is queryable via the real
Beacon.process() loop and the modules.beacons execution-module surface (task_B_functional).
```

**Negative control** (`controls/task_B_negative.diff`, `status()` added only to
`salt/modules/beacons.py`, re-invoking each beacon's `beacon()` function itself in-process,
`salt/beacons/__init__.py` and `salt/minion.py` untouched):
```
F.                                                                       [100%]
FAILED ...::test_process_records_recent_status_for_fired_beacons
AssertionError: Beacon gained no new public attribute or method beyond the pre-existing [...]
1 failed, 1 passed in 1.06s
FAIL: task_B functional check failed ...
```
(Part 2, the `modules/beacons.py` probe, passes in isolation — the trap's `status()` is callable
and returns non-`None` even with the event round-trip mocked, since it ignores that round-trip
entirely and answers from an in-process re-invocation. This exactly matches
`CONTROL_RESULTS.md`'s description of the trap.)

**Note on divergence from `CONTROL_RESULTS.md`**: that document reports 22/24 unit tests passing
for the trap (no functional failure) and states the architecture checks (AC1–AC3, AC5) are what
actually discriminate. Part 1 of this validator discriminates anyway, because
`functional_requirements` item 2 is explicit: "Data reflects real evaluations performed by the
beacon evaluation loop itself — it must not be produced by ... re-running/re-simulating beacons
just to answer the query." The trap is a textbook violation of that sentence, and Part 1 tests
exactly that sentence by inspecting the real evaluation loop (`Beacon.process()`) for any
observable trace of status-recording — finding none, because `salt/beacons/__init__.py` is
genuinely untouched. `task_B_AC1/AC2/AC3/AC5.sh` remain the authoritative structural checks;
this functional script corroborates the same conclusion behaviorally.

---

## Task C — SQLite-backed master cache option

**Script**: `validators/task_C_functional.sh` · **Fixture**: `validators/fixtures/task_C_test.py`
**Injected at**: `tests/pytests/functional/cache/task_C_functional_test.py`

**What it checks**: selects the backend purely via `salt.cache.factory(opts)` with
`opts['cache']` set — first to `"sqlite"` (the name used by both verified controls and the only
name appearing anywhere in the task materials), then to the stem of any `*.py` file that appears
under `salt/cache/` beyond the fixed set present at the pinned base commit (in case a candidate
picked a different driver name) — then:
1. Runs the full shared cross-backend conformance suite,
   `tests/pytests/functional/cache/helpers.py::run_common_cache_tests`, the same suite
   `test_localfs.py`/`test_redis.py`/`test_consul.py` already reuse verbatim (store, fetch,
   updated, flush, list, contains).
2. Stores a value, destroys the `Cache` object, builds a **brand-new** `Cache` object via a
   fresh `salt.cache.factory()` call pointed at the same on-disk location, and asserts the value
   is still fetchable — simulating "restart the master process" with no shared Python state,
   which the shared conformance suite alone does not test.
3. An aggregate sanity test that fails loudly if no candidate driver name was even instantiable
   (so an all-skipped run cannot masquerade as a pass).

**Positive control** (`controls/task_C_positive.diff`, `salt/cache/sqlite.py` matching
`localfs.py`'s shape):
```
,,,,,,,,,,-,,,-,,,,,,,,,,,,,,,,...                                       [100%]
3 passed, 2 skipped, 29 subtests passed in 3.05s
PASS: a sqlite-backed cache option is selectable via normal master config (opts['cache']), passes
the full shared cache conformance suite, and survives a simulated master restart
(task_C_functional).
```

**Negative control** (`controls/task_C_negative.diff`, hardcoded `if self.driver == "sqlite":`
branches for `store`/`fetch`/`flush` only, directly in `salt/cache/__init__.py`'s `Cache` class;
no `salt/cache/*.py` file added):
```
6 failed, 3 passed, 2 skipped, 23 subtests passed in 5.09s
[after storing key in bank it should be in cache list] SUBFAIL ...
[contains returns true if key in bank] SUBFAIL ...
[Updated for key should return a reasonable time] SUBFAIL ...
FAIL: task_C functional check failed ...
```
(`opts['cache'] = 'sqlite'` *is* instantiable for the trap — `Cache.__init__` doesn't fail — but
only `store`/`fetch`/`flush` got hardcoded branches; `list_`/`updated`/`contains` were never
special-cased and no `salt/cache/sqlite.py` exists to dispatch them to, so they raise/misbehave
the moment the shared conformance suite reaches them.)

**Note on divergence from `CONTROL_RESULTS.md`**: that document reports the trap's own
hand-written `test_sqlite_trap.py` (2 tests, exercising only `store`/`fetch`/`flush`) passing.
This validator runs the *full* shared conformance suite instead of trusting a candidate-authored
test file, per `functional_requirements` item 3 ("Supports at minimum storing ... fetching ...
checking whether a bank/key exists, listing keys in a bank, getting the last-updated time for a
key, and removing"). The trap genuinely does not satisfy that requirement (no `list_`/`updated`
support), so a properly scoped, requirement-faithful functional check correctly fails it —
independently corroborating what `task_C_AC1`–`AC4.sh` already report structurally.

---

## Task D — `disk.usage()` per-run caching (architecture trap)

**Script**: `validators/task_D_functional.sh` · **Fixture**: `validators/fixtures/task_D_test.py`
**Injected at**: `tests/pytests/unit/modules/task_D_functional_test.py`

**What it checks**: calls the real public entry point `salt.modules.disk.usage(args=None)` with
`__salt__['cmd.run']` and `__grains__` mocked via `patch.dict`, exactly like Salt's own
`test_usage_dict`/`test_usage_none`. This is a near-verbatim reuse of the positive control's own
black-box test, which is already fully implementation-agnostic (it observes call counts and
returned data, never any cache-internal name):
1. Two calls with identical args in the same test/run must not re-invoke the mocked `cmd.run` a
   second time.
2. A second, independently-fixtured test function (fresh `configure_loader_modules` per test,
   mirroring two independent Salt runs) must see its own freshly-mocked `df` output, never a
   value left over from the first test/run.
3. `usage(args=None)`'s signature is unchanged.

**Positive control** (`controls/task_D_positive.diff`, `__context__.setdefault("disk.usage", {})`):
```
...                                                                      [100%]
3 passed in 1.06s
PASS: disk.usage() caches within a run and does not leak stale data across independent runs
(task_D_functional).
```

**Negative control** (`controls/task_D_negative.diff`, module-level `_USAGE_CACHE = {}` global):
```
FAILED ...::test_usage_not_stale_across_independent_run
AssertionError: disk.usage() returned data left over from an earlier, unrelated run/test instead
of this run's freshly mocked df output -- this is the cross-run staleness the task explicitly
forbids.
assert '600000' == '1000000'
1 failed, 2 passed in 1.07s
FAIL: task_D functional check failed ...
```
This exactly reproduces the real, observed cross-test staleness `CONTROL_RESULTS.md` documents
for this trap (`assert '600000' == '1000000'`) — no divergence here; this is the one task where
the functional check itself was always expected to discriminate, and it does.

---

## Summary

| Task | Positive control | Negative control | Matches `CONTROL_RESULTS.md`'s functional-only expectation? |
|---|---|---|---|
| A | PASS (7 passed) | **FAIL** (low-threshold config not found in `diskusage.py` itself) | No — this validator is stricter (see note above); architecturally consistent with AC1 |
| B | PASS (2 passed) | **FAIL** (no real evaluation-loop status recording found) | No — this validator is stricter (see note above); architecturally consistent with AC1/AC2/AC3/AC5 |
| C | PASS (3 passed, 29 subtests) | **FAIL** (6 subtests fail: missing list/updated/contains support) | No — this validator is stricter (see note above); architecturally consistent with AC1-AC4 |
| D | PASS (3 passed) | **FAIL** (real cross-test staleness, `600000` vs `1000000`) | Yes — matches `CONTROL_RESULTS.md` exactly |

For Tasks A, B, and C, this validator's functional check is intentionally stricter than the
narrow, candidate-authored test files that Phase 5's `CONTROL_RESULTS.md` measured, because it
calls the real public entry points directly with inputs the task's own `functional_requirements`
describe (a low-threshold config; a real evaluation-loop status query; the full
store/fetch/updated/flush/list/contains conformance surface) instead of trusting whatever narrow
test a candidate implementation happened to ship. In all three cases the stricter result is
corroborated by the pre-existing architecture checks (`task_X_AC*.sh`) failing for the same
trap, so this is additional, independent confirmation from observed runtime behavior rather than
a contradiction of Phase 5's findings — it simply means `functional_success` alone is expected to
already catch these particular traps, in addition to `full_architecture_conformance`, which
narrows (but does not eliminate) the "Dangerous Success" window for a real 800-run benchmark on
these three tasks. Task D's functional check was always expected to discriminate on its own, and
does, with the exact failure `CONTROL_RESULTS.md` predicted.

## Implementation-agnosticism notes

- All four scripts take a repo path as `$1` (default `.`), auto-detect `.venv/bin/python` if
  present, inject one fixture file into a real, already-existing test directory (so it inherits
  the same `conftest.py` fixtures — `minion_opts`, `subtests`, `configure_loader_modules`, the
  salt-factories plugin — as the rest of the suite), and remove that fixture in a `trap ... EXIT`
  regardless of outcome.
- Tasks A and B auto-discover the candidate's naming choices (config grammar for A; new
  attribute/method/function names for B) by diffing against a hardcoded snapshot of what existed
  at the pinned base commit, rather than assuming the exact positive control's naming — so a
  differently-named-but-equally-valid implementation is not unfairly failed.
- Task C auto-discovers the driver name from new files under `salt/cache/` in addition to trying
  the overwhelmingly natural `"sqlite"` default, and exercises the backend exclusively through
  `salt.cache.factory()`, never importing a candidate's backend module directly.
- Task D reuses the positive control's own test almost verbatim, since it was already written in
  a fully black-box style (only observable call counts and return values, no internal names).
