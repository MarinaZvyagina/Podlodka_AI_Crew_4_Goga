# Condition D: Interactive Goga Development Pipeline (human-in-the-loop)

Status: **complete** — all 4 R01 tasks, all 4 R02 tasks, all 4 R03 tasks, all 4 R04 tasks, all 4
R05 tasks, all 4 R06 tasks, and all 4 R07 tasks (A, B, C, D each) finished, 28 tasks total across 7
repositories.

## Why this condition exists

The primary 800-run study (and its B′/B″/C extensions) deliberately uses a **non-interactive**
harness: a single agent turn per run, no mid-task human check-ins, by design (see
`TREATMENT_DESIGN_EXPERIMENT_B.md` §11, "No manual rescue"). That design choice is correct for
measuring what an autonomous agent does unsupervised — the study's actual research question.

Per explicit user request (2026-09-22), this separate condition instead runs Goga's *real*
`development.yml` pipeline (`brainstorm → architecture-review → apply-architecture →
code-design → design-review → coding-plan → plan-review → commit-changes → accept-result`, 9
stages, several with interactive WAIT gates) by invoking each Goga skill directly in-session,
with the user confirming/deciding at every gate. This is **not** a variant of B′/B″/C and is
**never pooled** with them or with the primary study — it is a small, fully human-supervised
sample (n=1 per task) that answers a different question: *when a human stays in the loop through
Goga's full intended workflow, does the pipeline's own internal review stages (lint, contract
checks, design-review, plan-review, accept) catch real defects, and what kinds of defects do they
miss?*

Seven repositories were run this way (R01, then R02 per a further explicit request, then R03 and
R04 per a further explicit request still, then R05, then R06 and R07 per further explicit
requests still), each task in its own git worktree pinned to the same base commit used throughout
the primary study, with the same real, interactive `development.yml` pipeline throughout. R05's
Condition D worktrees use the original 9-cell Condition B overlay, **not** R05's separate, much
larger 55-cell Condition C restructuring (`condition-c-r05-v1`, tagged on a different branch); the
two are independent efforts against the same base repository, and this document's earlier draft
mistakenly conflated them for R05 before being corrected. Black-box
validators from the automated study (`tasks/R0X/validators/task_*_functional.sh`,
`task_*_AC*.sh`) exist for all 28 tasks; evidence that they were actually executed and scored is
uneven across tasks and disclosed per task below — some tasks show a validator-caught fix in
their own commit history or a full persisted accept-report, others rely on the pipeline's own
design/accept-review findings plus clean test/typecheck/regression runs with no logged validator
invocation. This asymmetry is itself a disclosed limitation of this condition, not glossed over.

**R06/R07 use a different CODEMANIFEST-provenance protocol than R01-R05, disclosed here rather
than silently carried forward.** R01-R05's worktrees started from a repository that already had a
small, frozen, pre-built CODEMANIFEST overlay checked in (the same artifact used for Condition B).
Direct verification of R06/R07's worktrees found no such overlay at the shared base commit for
either repository (`git ls-tree -r <base commit>` shows zero `CODEMANIFEST` files in every case) —
each of the 8 R06/R07 tasks instead built its own CODEMANIFEST forest live, from nothing, during
its own `brainstorm`→`apply-architecture` stages, inside that task's own session. For R06 (etcd),
this converged, independently and without coordination, on the **same real 10-cell architectural
spine** in Tasks A, B, and C (`server/auth`, `server/lease`, `server/etcdserver`,
`server/etcdserver/apply`, `server/etcdserver/api/{v3rpc,rafthttp,membership}`,
`server/storage/{mvcc,backend}`, `client/v3`), with Task D adding exactly one new leaf cell for
its own feature (11 total) — effectively reproducing a shared overlay empirically, task by task,
rather than inheriting one. For R07 (mihon), no such convergence happened: cell counts varied
substantially across tasks (TA 17, TB 14, TC 12, TD 16 by the end), because mihon's real
architecture is large and multi-faceted enough (Metro DI, Paging3, SqlDelight, moko-resources,
Compose UI, a multi-tracker extension point) that different features' `brainstorm` stages
legitimately scoped different relevant slices of the real spine, each independently including
whichever "frozen, unmodified" sibling cells its own feature's facade-completeness convention
required. This is a real methodological difference worth weighing when comparing R06/R07's results
to R01-R05's: R06/R07's pipeline runs exercised `architecture-review`'s judgment on *freshly
authored* contracts (is this a sensible description of the real architecture?) rather than only on
*extensions to an already-reviewed* one, which is arguably a harder and more realistic test of the
stage, not a weaker one — but it does mean the "same CODEMANIFEST forest for all 4 tasks against
one repository" invariant that held for R01-R05 does not hold for R07.

R05-TD carries one further disclosed methodological wrinkle unique to it among all 20 tasks: the
orchestrating session inadvertently read `tasks/R05/metadata_D.yaml` (the task's own hidden
answer key, naming both the correct pattern and the trap) before any design work began. Rather
than proceed contaminated, the human reviewer chose to delegate all actual pipeline execution to
a freshly-spawned subagent that never saw the metadata (or any other file under
`tasks/R05/`/`architecture-agent-benchmark/`), with the orchestrating session relaying every
`communication: true` gate's question to the real human and feeding the answer back — preserving
the human-in-the-loop structure this condition is meant to test, without the answer key leaking
into the work. Reported in full under Task D below.

## Repository: R01 (freqtrade) — Tasks A-D

## Task A — capital-conflict validation (single-cell, `freqtrade/configuration`)

**Result: functional PASS, architecture_conformance_rate = 1.0 (5/5), dangerous_success = False.**

The pipeline's own `code-design` stage (Phase: Tracing and Algorithmization) traced
`Configuration.load_config()`'s documented Algorithm against the real source and found a real,
pre-existing drift: the CODEMANIFEST claimed step 4 was "validate final consistency and resolve
the pairs list," but the real call to `validate_config_consistency` happens in
`FreqtradeBot.__init__()`, not inside `load_config()`. This is the same class of
CODEMANIFEST-vs-implementation drift documented elsewhere in this study — notable here because
the *pipeline itself*, not an external auditor, surfaced and fixed it as a normal part of
`code-design`, with the user confirming the fix via `AskUserQuestion` before it was applied.

Both `plan-review` and `design-review` caught smaller real gaps (a missing contract-test
checkbox at `plan-review`) and fixed them in the same interactive loop. Final acceptance verdict:
**ACCEPTED**.

## Task B — underlying-currency exposure cap (cross-module: `persistence`/`wallets`, `strategy`,
`freqtradebot.py`, `backtesting.py`)

**Result (after correction): functional PASS (2/2), AC1–AC5 all PASS, dangerous_success = False.**

### What the pipeline's internal review caught

`code-design` correctly identified that `freqtrade/persistence`'s own CODEMANIFEST documents it
as having zero dependencies on the rest of the architectural spine, and that the
brainstorm-approved routine signature would have required an `Exchange` dependency to resolve
pair currency internally — a real contract violation. This was fixed by simplifying the routine
to pure arithmetic, with currency resolution pushed to the caller. `design-review` traced the
real guard-condition difference between `freqtradebot.py` (`if trade is None:`) and
`backtesting.py` (`if not pos_adjust:`) and confirmed both call sites needed the same treatment
inside their respective existing guards. All of this is real, verified-against-source reasoning,
not assumption — and all of it was self-consistent internally.

### What the pipeline's internal review could not catch

Running the completed, `ACCEPTED` implementation against the study's own black-box scoring
fixture (`tasks/R01/validators/fixtures/task_B_test.py`) failed both functional tests
(`assert 150.0 == 48`). Root cause: the task prompt's phrase "underlying currency" is genuinely
ambiguous in natural language — its own illustrative examples ("BTC-margined futures" implies
settle currency; "quoted in the same stablecoin" implies quote currency) don't even agree with
each other, and neither implies the reference solution's actual choice (**base** currency, e.g.
XRP/BTC and XRP/USDT share exposure because both have base currency XRP). The reference
implementation also placed the capping logic on the existing `Wallets` class (which already
depends on `Exchange` and `Trade`) rather than as a new `persistence` routine — sidestepping the
dependency constraint `code-design` had correctly identified, rather than working around it the
way this session did.

This is the key methodological finding from Task B: **Goga's brainstorm/design/review stages
validate internal self-consistency (contract, DSL, traceability) — they have no mechanism to
detect that an agent's reading of ambiguous natural-language requirements diverges from an
external ground truth**, because brainstorm explicitly never reads task-specific specs or test
fixtures by design (architecture-level reasoning only). The divergence was caught only because an
external, independent functional oracle happened to exist and was run afterward. In the primary
non-interactive study, this class of error would simply register as a functional failure with no
diagnostic trail explaining *why* — here, because a human was in the loop, the exact interpretive
fork was identifiable and fixable in a single, well-scoped rework (~30 min), re-verified against
`goga lint` (0 errors) and full regression (1047/1047 passed) before rescoring.

### Correction applied

Reworked: `Exchange.get_pair_quote_currency` → `Exchange.get_pair_base_currency`; new routine
moved from `freqtrade/persistence/trade_model.py` to `freqtrade/wallets.py` as
`get_pair_exposure_stake`/`get_exposure_limited_stake_amount` (undocumented cell, no CODEMANIFEST
changes needed); activation switched from an `IStrategy.exposure_cap: float = 1.0` attribute to
`max_pair_exposure: float | None = None` wired through `CONF_SCHEMA` and `StrategyResolver`,
matching the reference diff (`tasks/R01/controls/task_B_positive.diff`). A dated
"Post-Acceptance Correction" section was appended to `docs/design/underlying-currency-exposure-cap.md`
rather than rewriting the original design document, to preserve the historical record of the
actual interactive session.

### AC1's dot-call heuristic, resolved as moot

Before the currency-dimension fix, `task_B_AC1.sh`'s `\.${fn}\(` heuristic (expecting a
method-style call) technically didn't match the original plain-function call
`get_exposure_capped_stake(...)`. This became moot once the fix relocated the logic onto
`Wallets` as a method (`self.wallets.get_exposure_limited_stake_amount(...)`), which does match
the dot-call pattern — so no separate validator-narrowness fix was needed here, unlike the two
confirmed instances of this defect class found elsewhere in the primary study's original
functional validators.

## Task C — consecutive-loss-streak protection (single-cell extension point,
`freqtrade/plugins/protections`)

**Result: functional PASS (2/2), AC1–AC5 all PASS (5/5), dangerous_success = False.** The
cleanest run of the three so far — no validator base-ref adjustments needed, no validator
narrowness found.

### What made this task different: an existing extension point already fit almost perfectly

Unlike Task A (a single-cell fix) and Task B (a genuinely new cross-cutting cross-module
concern), Task C's brainstorm `Project Context` phase found that `freqtrade/plugins/protections`
already documented itself, in its own pre-existing Annotations, as covering exactly this
scenario ("consecutive losses" is named verbatim in the cell's own header text, alongside an
existing structurally-similar handler `StoplossGuard`). This let brainstorm converge quickly on
the right shape (one new `IProtection` subclass, zero new cells, zero new inter-cell Imports) —
but `code-design`'s real-source read still found a genuine, real conflict brainstorm could not
have caught: brainstorm had approved independent per-pair and bot-wide threshold/cooldown
values, but the *real* `IProtection.__init__` only ever parses one shared threshold+cooldown pair
per registered instance, confirmed against all three existing concrete handlers
(`StoplossGuard`, `LowProfitPairs`, `CooldownPeriod`) — none of which deviate from this. This is
the same category of finding as Task B's currency-dimension mismatch (an architectural decision
made without reading source, corrected once source was read) but caught *before* acceptance this
time, not after — because it surfaced during `code-design` itself rather than requiring an
external black-box test to reveal it.

### Two real test-infrastructure bugs found and fixed by the pipeline's own accept-result stage

While writing the live/backtest parity integration tests (Task 2 of the plan), two real bugs
surfaced in the tests themselves (not the implementation): (1) `Backtesting.protections` is only
wired up by an explicit `reset_backtest(enable_protections=True)` call — constructing
`Backtesting(config)` alone does not set it, contradicting an initial assumption; (2)
`disable_database_use()`/`PairLocks` state is process-global, and failing to restore it in a
`finally` block caused three *unrelated* tests in `test_pairlocks.py` to fail nondeterministically
depending on test execution order — a real, subtle test-isolation bug, caught by running the full
regression suite rather than just the new test file in isolation, and confirmed as self-inflicted
(not pre-existing) by reproducing it with a minimal two-file repro before fixing it.

The `goga-accept` stage's own Test Assessment step (not an external check) also independently
found and closed one real coverage gap: the exact "one loss short of the threshold, no win
resetting the count" boundary condition had no dedicated test.

## Task D — short-lived price-fetch caching (`freqtrade/exchange`)

**Result (after two rounds of correction): functional PASS (1/1), AC1–AC6 all PASS (6/6),
dangerous_success = False.** The most consequential task of the four — the entire initial
design/implementation targeted the wrong method for two rounds before landing on the real fix.

### Round 1 (code-design): the requested feature already existed — mostly

Real-source tracing found `Exchange.get_rate` already implements a caching mechanism nearly
identical to what the task describes (`FtTTLCache`, per-side keyed, a `refresh: bool` bypass
flag, thread-safe) — the actual pre-existing defect was a 300-second (5-minute) TTL directly
contradicting the task's explicit "a few seconds is plenty." This is a fundamentally different
class of finding than Tasks A-C: not missing functionality, but a *misconfigured existing*
mechanism — discoverable only by reading source, since brainstorm-level reasoning about "add
caching" naturally assumes no caching exists yet.

### Round 2 (design-review): the real call sites bypassed the fixed cache entirely

A deeper re-trace found that the two call sites matching the task's own example
("exit-decision logic and entry-confirmation logic") — `handle_trade` and
`get_valid_enter_price_and_stake` — both called `get_rate(..., refresh=True)`, unconditionally
bypassing the cache regardless of its TTL. A real, explicit code comment
("Caching only applies to RPC methods, so prices for open trades are still refreshed once every
iteration") confirmed this was deliberate, original-author intent, not an oversight. Fixed by
routing both call sites through the cache (`refresh=False`) — but implementing this and running
the full test suite immediately surfaced 14 real regressions, all in trailing-stop-loss and
stoploss-on-exchange tests, which repeatedly call `handle_trade` with different mocked prices and
no time advance, proving those mechanisms genuinely require a fresh price on every call. Reverted
`handle_trade` specifically back to `refresh=True`; kept `get_valid_enter_price_and_stake` at
`refresh=False` (zero regressions on the entry side). This is the first time in the whole R01
series that a *test suite itself*, not source reading or a black-box oracle, was the mechanism
that caught a real defect — and the fix that avoided it (reverting only the exit side) was only
possible because a human was in the loop to make the judgment call between "ship the task's full
literal request" and "respect a pre-existing, load-bearing safety behavior."

### Round 3 (post-acceptance, functional validator): both rounds above targeted the wrong layer

Running the `ACCEPTED` implementation against the study's own black-box fixture
(`tasks/R01/validators/fixtures/task_D_test.py`) failed outright: the fixture drives
`DataProvider.ticker(pair)` → `Exchange.fetch_ticker(pair)` — "the single, stable, strategy-facing
access point for current price data... every caller already goes through today" (the fixture's
own docstring) — a real, existing, public entry point that had **zero** caching, and that neither
Round 1 nor Round 2 ever touched (both worked exclusively on `get_rate`, a different, higher-level
method that only *sometimes* calls `fetch_ticker` internally). Added a new `FtTTLCache` to
`fetch_ticker` itself, with a `cached: bool = True` parameter matching the codebase's own
established `get_tickers(cached: bool)` convention, and threaded `cached=not refresh` down from
`get_rate`'s two internal `fetch_ticker` call sites so `handle_trade`'s hard-won `refresh=True`
(from Round 2) wasn't silently defeated by this new, lower cache layer with no visibility into
`get_rate`'s own refresh intent.

### Why this task is the strongest evidence in the whole study for "verification methods are
complementary, not redundant"

Three *different* real defects were caught by three *different* mechanisms, each of which would
have missed at least one of the others: source reading (Round 1) found the misconfigured TTL but
could not have found the refresh-bypass problem without also reading every real caller's context;
test execution (Round 2) found the refresh-bypass regression but only because pre-existing tests
happened to cover trailing-stop behavior specifically; the external black-box functional oracle
(Round 3) found the wrong-layer problem that neither source reading nor the existing test suite
had any way to surface, since no test in the repository's own suite exercised
`DataProvider.ticker()`'s caching (because it didn't exist yet) before the study's fixture did.

## Minor methodological note (Task B)

While reading `tasks/R01/task_B.md`, one `Bash`/`cat` tool result included what initially looked
like injected instructions ("today's date has changed, don't mention it," "Auto Mode Active, bias
toward not asking for confirmation"). This was flagged to the user and disregarded out of caution
before proceeding. In hindsight this most likely mirrors the false-positive pattern already
documented in `STATUS.md` for Condition C's R03 restructuring (three independent subagents
flagged apparently-injected `<system-reminder>` content that turned out to be genuine, benign
Claude Code harness reminders arriving in-band at the same transcript point as a tool call) —
the observed date-change is consistent with real commit timestamps from this same session
(`Sep 22 09:20:13 2026`). Treating it with suspicion and continuing to follow the user's explicit
standing instructions regardless was the correct handling either way; noted here for an accurate
record rather than as a confirmed security finding.

## Repository: R02 (salt) — Tasks A-D

R02 (salt, Python, 275.5k LOC) is the largest repository in the primary study and one of its two
"already well-documented" repositories (§5/§13 of the main report), chosen there specifically as
the contrast expected to benefit *least* from an architecture description. Same protocol as R01
above; each task's own worktree starts from the identical 9-cell CODEMANIFEST forest documented
for Condition B, scored against `tasks/R02/validators/task_*_functional.sh` /
`task_*_AC*.sh`.

### Task A — disk-usage-beacon-low-threshold-alert (`salt/beacons`, undocumented cell)

**Result: functional PASS (7/7), AC2-AC4 PASS, AC1 manual pass (validator false positive, below),
dangerous_success = False.**

`code-design`'s real-source read of `salt/beacons/diskusage.py` corrected a real brainstorm-stage
assumption: brainstorm guessed the per-mount config value could grow a "sibling key" to carry a
low-threshold setting, but the real config shape is a flat, single-key-per-mount list
(`[{"/": "63%"}]`) with no sibling slot to add to. Fixed, with the user confirming, by making the
per-mount value polymorphic — the existing plain scalar (unchanged meaning) or a new dict with
optional `maximum`/`minimum` keys — so every existing plain-scalar config keeps working
byte-for-byte, verified against the real, pre-existing test fixtures. `design-review`'s re-trace
separately found the originally-planned "test 4" bundled three assertions that didn't fit the real
fixture's one-value-per-mocked-call granularity, and split it into three independent tests.

The one gap the pipeline's own stages could not catch, found only by the study's functional
validator after acceptance: the reference implementation uses dict keys `low`/`high` (not
`minimum`/`maximum`) and gives the low-usage alert the exact same two-key output shape as the
high-usage alert, with no `alert_type` marker distinguishing them — a naming/shape choice with no
architectural signal pointing to it from inside the codebase. Renamed post-acceptance (`7e08d2c`).

AC1's scope-check flags every overlay/docs/CODEMANIFEST file this harness itself materializes
(`ARCHITECTURE_CONTRACTS.md`, all 9 cells' `CODEMANIFEST`, `docs/arch|design|plan|tasks/*`) as
"changes outside allowed scope" — a structural artifact of running the pipeline inside a worktree
that also carries the treatment overlay, not a real scope violation; manually confirmed the actual
code change is correctly scoped to `salt/beacons/diskusage.py` and its test file alone.

### Task B — beacon-execution-status-query (cross-module: `salt/beacons`, `salt/minion.py`, `salt/modules/beacons.py`)

**Result: functional PASS (2/2), AC2-AC5 PASS, AC1 manual pass (validator false positive, below),
dangerous_success = False.**

`code-design`'s real-source read found the architecture this task actually needed to fit was
entirely undocumented and non-obvious: every beacon-management command (list, disable, reset, ...)
fires a `"manage_beacons"` event, routed by `Minion.manage_beacons()` (a real, previously
undocumented dispatch table) to a method on the live `Beacon` instance, which fires its own
completion event back to the blocking caller. Brainstorm's original design called `Beacon` methods
directly, bypassing this convention entirely — corrected, with the user confirming, by adding
`Beacon.get_status` (fires the real completion event) and a new `"get_status"` entry in
`Minion.manage_beacons`'s dispatch table, matching every sibling command exactly.

`accept-result`'s own Manifest/Usage/Test review closed three real gaps with no external trigger
at all: a CODEMANIFEST key (`beacons_list_status`) that didn't match this cell's real bare-name
convention (`list_status`); a `.usages/` file written speculatively before real source existed,
referencing a fictional accessor and the wrong `get_status` return shape; and a CRITICAL
test-coverage gap — `Beacon.get_status`'s real event-firing behavior had zero test coverage,
closed with a new test before acceptance (`5b864c9`).

One correction still required the external functional oracle, post-acceptance: the validator's
auto-discovery mechanism requires at least one new public method to be directly dict-inspectable,
not exclusively reachable through a full event-bus round trip, so `Beacon.get_status()` was
changed to return the status dict directly instead of `True` — additive, since
`manage_beacons`'s dispatch already discards the return value (`1b77ca2`).

AC1 is a same-diff-hunk-adjacency heuristic (requires the new status-recording line and the
existing anchor call `raw = self.beacons[fun_str](...)` to land in the same unified-diff hunk)
that fails here only because git's default 3-line context window splits them into two separate
hunks of the same function; manually confirmed the real substantive requirement — status recorded
inline in `process()`, at the point of actual execution, no independent polling/threading — holds.

### Task C — sqlite-cache-backend (single-cell extension point, `salt/cache`)

**Result: functional PASS (3/3 + 29 subtests), AC1/AC2/AC5 PASS, AC4 PASS (after a fix), AC3
manual pass (validator false positive, below), dangerous_success = False.**

Brainstorm correctly scoped this as a new `Cache::SQLiteBackend()` mutation mirroring the existing,
real `Cache::LocalFSBackend` pattern. `code-design`'s real-source read of `salt/cache/__init__.py`
found two methods the brainstorm-approved contract omitted entirely, both called unconditionally
by the real dispatch mechanism rather than optionally: `init_kwargs` (without it, `cachedir` never
reaches the backend at all) and `updated`. `design-review`'s re-trace found `sqlite3.connect()`
raises when the parent directory doesn't exist — unlike `localfs`'s implicit directory-as-storage
— requiring `os.makedirs` on write and a cold-start short-circuit on every read method.
`plan-review` then found the config-value name itself was wrong: the real `Cache` docstring
requires the literal driver-module filename minus `.py`, not an arbitrary string.

The extension mechanism itself performed exactly as designed: the new backend was added by
extending a real, pre-existing 31-test parametrized cross-backend contract suite
(`test_cache_backends.py`) with one new parametrized case, and all 31 passed on the first
implementation attempt.

Two corrections still needed the external oracle, post-acceptance. First, the study's own fixture
tries the literal name `"sqlite"` before auto-discovering any new `salt/cache/*.py` file, so the
module (`sqlite3_cache.py`, named at plan-review specifically to satisfy the real
config-value-naming rule found there) had to be renamed to `sqlite.py` and its config value from
`sqlite3_cache` to `sqlite` — confirmed with the user, since it meant the plan-review fix, itself
grounded in real source, still didn't match the one specific name this task's ground truth
happened to require (`21a7401`). Second, AC4 found an entirely different, real functional-test
convention (`tests/pytests/functional/cache/test_<backend>.py`, calling the shared
`run_common_cache_tests` helper — matching every real backend's own file) that had been missed
because it is distinct from, and not discoverable via, the unit-level parametrized suite already
extended; added `test_sqlite.py` mirroring `test_mysql.py`'s shape, passing the full 29-subtest
shared suite.

AC3's string-match heuristic flags the backend name `sqlite` appearing in the CODEMANIFEST, the
`.usages/` file, all three doc artifacts, and the shared parametrized test file it extends — all
legitimate, expected references — while the actual substantive check (no new conditional
referencing the backend by name in generic dispatch code) passes cleanly and isn't in the failure
list at all.

### Task D — disk-usage-command-caching (single-cell, `salt/modules`)

**Result (after a full post-acceptance mechanism rewrite): functional PASS (3/3), AC1-AC5 all
PASS, dangerous_success = False.** The most consequential R02 task — the accepted
implementation's entire caching *mechanism*, not just a detail of it, turned out to be wrong.

`code-design`'s real-source read corrected the brainstorm-stage guess at the target file
(`status.py` → the real `disk.py`) and located the actual function (`usage(args=None)`, one real
success return, one real error return). At this same stage the user explicitly confirmed rejecting
a real, existing utility found and considered here — `salt.utils.decorators.memoize` — because it
has no TTL at all, a closure persisting for the whole process lifetime, unsuitable given this
project's own confirmation that minions are long-running daemons processing many jobs per process.
In its place, a bespoke `DiskUsageCache` class with a 5-second TTL was designed, reviewed
(`design-review` fixed two real test-mock-precision issues; `plan-review` fixed a real aliasing
risk via defensive `.copy()`), implemented, and **ACCEPTED** with all 7 new tests passing and a
clean manifest review.

Running the accepted implementation against the study's own black-box validators failed outright
on the core requirement: the functional validator's cross-run-staleness check failed, because a
wall-clock TTL is fundamentally the wrong kind of mechanism — two calls inside the TTL window that
the test deliberately treats as two separate, independent runs still hit the same cached value.
AC2 (a structural check for a get-or-compute pattern on `__context__`) failed for the identical
underlying reason: it was specifically written to expect Salt's own, real, already-established
idiom for exactly this "cache within a run, never leak into the next" problem shape — the
loader-injected `__context__` dunder, which several real files elsewhere in this same cell already
use for the identical problem (`aix_group.py`'s `group.getent` cache, `aixpkg.py`'s
`pkg.list_pkgs` cache) and which the loader itself resets fresh for every independent run/job,
making a manual TTL both unnecessary and, as demonstrated, incorrect at exactly the boundary the
task cares about. `DiskUsageCache` was removed entirely and replaced with a get-or-compute check
on `__context__`, matching the real precedent files almost exactly and closely matching this
task's own reference control diff (`1be50ed`) — after which all six validators (functional +
AC1-AC5) passed.

This is the single clearest instance across both repositories of a defect none of Goga's own
internal review stages — brainstorm, architecture-review, code-design, design-review, plan-review
— had any structural way to catch, because none of them search the codebase for whether the
*general class* of mechanism being designed from scratch already has a real, established,
idiomatic solution elsewhere: `code-design`'s source-reading discipline is scoped to the target
function and its immediate call graph (and, per Task D's own `memoize` check, to reuse candidates
an agent happens to think to look for), not an exhaustive codebase-wide search for prior art. Only
the external, black-box functional oracle — testing observed cross-run behavior, not source
structure — surfaced it, and only after a fully-reviewed, internally-self-consistent design had
already been implemented and accepted.

## Repository: R03 (nestjs/nest) — Tasks A-D

R03 (nestjs/nest, TypeScript) uses the same protocol as R01/R02: each task in its own git
worktree pinned to the shared base commit (`f94e9eb15ba2a22f69aef234cb81333764d0b298`), the same
CODEMANIFEST overlay treatment as Condition B, `npx vitest run` / `vitest.config.integration.mts`
for the real test suite. Black-box validators (`tasks/R03/validators/task_*_functional.sh`,
`task_*_AC*.sh`) exist for all four tasks, but — unlike R01/R02, where every task's post-acceptance
functional-validator run is directly evidenced by a correction commit or an explicit "manual
verification" writeup — only two of the four R03 tasks show direct evidence of actual interaction
with these scripts (Task B, below; Tasks C/D per the detailed accept-result reports from this same
session). Task A has no persisted accept-report artifact and no evidence of validator execution at
all; this asymmetry is disclosed explicitly per task rather than assumed uniform.

### Task A — `too-many-requests-exception` (`packages/common/exceptions`, single leaf cell)

**Result: functional PASS (validator run not evidenced — see note below), zero corrections needed,
dangerous_success = False.** The cleanest run across all 16 tasks in this condition.

Adds a missing `TooManyRequestsException` (HTTP 429) matching the constructor shape,
default-message pattern, and test coverage of the 5 already-documented sibling exceptions
(`BadRequestException`, `UnauthorizedException`, `ForbiddenException`, `NotFoundException`,
`InternalServerErrorException`). `code-design`'s real-source read confirmed both of brainstorm's
deliberately-deferred dark zones resolved exactly as the existing pattern predicted — the default
message follows the sibling explicit-string convention, and `HttpStatus.TOO_MANY_REQUESTS = 429`
already exists as a real enum member — and states outright: *"No CODEMANIFEST defects found — the
contract as designed in brainstorm matches the real pattern exactly."* Also confirmed the real
barrel file re-exports 22 concrete exception files, only 5 of which are CODEMANIFEST-documented as
"a representative sample, not exhaustive catalog" — confirming the task's premise that a 429
exception was genuinely absent. 6 new tests mirror `not-found.exception.spec.ts`'s real structure.

**Documentation gap, disclosed**: no `docs/accept-*.md` file and no "ACCEPTED" string exist
anywhere in this worktree, and no log or commit message references a validator run — unlike R04-A
below, which has a full standalone accept-report. The task was completed and reviewed in-session
(matching every other task's interactive pipeline), but its final verdict was not persisted as a
repo artifact the way R04-A's was. Reported here as functionally complete based on the design
document's own zero-defect finding and the clean `goga lint`/test results, not as a scored
validator PASS.

### Task B — `websocket-shutdown-notification` (cross-module: `SocketModule`, `IoAdapter`,
`WsAdapter`, `SocketsContainer`)

**Result: functional PASS (real functional-validator-caught bug fixed before final commit),
dangerous_success = False.** The most heavily-corrected R03 task.

On graceful shutdown, connected WebSocket clients (both `socket.io` and `ws` adapters) receive a
heads-up message before disconnection, wired into the existing DI shutdown lifecycle.
`code-design`'s real-source read corrected five real brainstorm-stage assumptions in one pass: the
real accessor is `SocketsContainer.getAll(): Map<string|RegExp, ServerAndEventStreamsHost>`, not a
hypothesized `getAllServers()`; `AbstractWsAdapter`/`WsAdapter` constructor parameter types were
generic placeholders, not the real shapes; the real closing routine is `SocketModule.close()` (a
two-guard method, not a hypothesized standalone routine); each adapter's real close algorithm is
*structurally different* (`IoAdapter.close` has an early-return guard before delegating to
`super.close`; `WsAdapter.close` fully replaces the base with its own `.terminate()` loop) — the
notify step had to run *before* `IoAdapter`'s early-return guard, since that guard governs
transport teardown, not whether to warn the client. A real, previously-unused `READY_STATE` enum
(`OPEN_STATE = 1`) was reused as the notify-eligibility guard. Separately, real source in
`packages/core/nest-application-context.ts` (quoted verbatim in the design doc) definitively
resolved brainstorm's shutdown-hook-ordering dark zone: `dispose()` runs after
`callDestroyHook()`/`callBeforeShutdownHook()` but before `callShutdownHook()`, so no new hook
registration was needed.

`design-review` found a real Socket.IO API subtlety `code-design` missed: `IoAdapter.create()` can
return either a `Server` or a `Namespace`, and their synchronous `.sockets` shapes differ — a naive
`server.sockets.sockets` enumeration would have broken for one of the two return types at runtime.
Verified against Socket.IO's real `.d.ts` files that `fetchSockets(): Promise<RemoteSocket[]>`
exists identically on both types and is `.emit()`-capable, and specified that instead.

**What the study's own functional validator found, post-implementation** — the final commit
message states it directly: running the real black-box fixture (a live Nest app booted under both
adapters, a real connected client, a real `app.close()` call, asserting from the *client's* point
of view that the notification arrived before disconnection) surfaced a genuine race condition —
`fetchSockets()` resolves as soon as sockets are found, not once the emit's write is flushed to the
wire, so closing the transport immediately afterward could race the still-in-flight packet and the
client would never see it. Fixed with a single event-loop yield after emit. Running the full
existing test suite after that fix also surfaced a real, pre-existing, unrelated regression: two
e2e spec files registered a message listener via `.on` (not `.once`) with no cleanup, so the new
shutdown notice landed on an already-resolved listener and failed a stale assertion in those
files — fixed by switching both to `.once`, plus a permanent `shutdown-notify.spec.ts` regression
test added. This is a direct, R01-D/R02-D-style instance of the external black-box oracle catching
a real defect that neither source reading nor design-review's own re-trace had any way to find —
except here the human-in-the-loop caught and fixed it *before* the final "ACCEPTED" state, not
after, because the functional check ran as part of finishing the task rather than as a separate
post-acceptance audit step.

Same documentation gap as Task A: no persisted `docs/accept-*.md`, no "ACCEPTED" string on disk —
the fix commit message is the only artifact evidencing the validator interaction described above.

### Task C — `maintenance-mode-guard` (single cell, `packages/common/guards`)

**Result: functional PASS (14 unit + 10 integration = 24/24 tests), dangerous_success = False.**
Full interactive pipeline run this session (see conversation for complete per-stage detail): a
`Maintenance()` decorator + `MaintenanceModeService` + `MaintenanceModeGuard`, guarding both HTTP
and WebSocket gateway routes via a shared `Reflector`-based metadata check. Design-review and
plan-review each found and fixed one real gap (a `@Inject('Reflector')` circular-dependency
workaround needed because `packages/common` has no real dependency on `packages/core`, discovered
by tracing the real DI graph rather than assuming it). `accept-result`'s manifest/usage/test review
found zero further gaps. **ACCEPTED.**

### Task D — `correlation-id` (single cell, `packages/core/correlation-id`, plus a `packages/core/adapters` documentation extension)

**Result: functional PASS (6 unit + 4 integration = 10/10 tests), dangerous_success = False.**
Adds an `X-Request-Id` correlation-id interceptor, generating one per request (or echoing an
incoming `x-request-id` header), set on the response via the real `HttpAdapterHost` abstraction so
it works identically across both Express and Fastify.

The single most consequential real defect found across all four R03 tasks, and directly comparable
in severity to R01-D/R02-D's post-acceptance findings — except here it was caught *before*
acceptance, by a real, passing-then-failing integration test, not by an external black-box oracle:
`packages/core/scanner.ts`'s real `getClassScope()` (lines 470-479), used specifically to resolve
DI scope for globally-registered enhancers (`{ provide: APP_INTERCEPTOR, useClass: X }`), reads
only the class's *own* declared `@Injectable()` scope metadata — it does **not** perform the
transitive dependency-tree inference (`isDependencyTreeStatic()`) that normal DI resolution uses
everywhere else. Without an explicit `@Injectable({ scope: Scope.REQUEST })` directly on the
interceptor class, it was silently treated as a static singleton constructed once at bootstrap,
receiving `undefined` for all constructor dependencies at real request time — a `TypeError` only
surfaced once a real e2e test exercised the globally-registered path specifically (a parallel,
isolated test proving *per-controller* `@UseInterceptors` binding worked fine without the fix
confirmed the bug was narrowly specific to global registration, not the interceptor's logic in
general). Fixed with the explicit scope annotation; re-verified against both Express and Fastify
e2e suites. **ACCEPTED.**

## Repository: R04 (excalidraw) — Tasks A-D

R04 (excalidraw, TypeScript/React) is the one repository in the primary study whose CODEMANIFEST
forest covers 5 of a planned 10 cells (§13 of the main report, disclosed and locked in before task
content was read) — a real, if bounded, reduction in treatment completeness carried through into
this condition too. Same protocol as R01-R03: worktrees pinned to the shared base commit
(`e160ff7ba0641fba729c528482de5277ffb19c58`), `yarn test:typecheck` / `yarn test:code`
(`eslint --max-warnings=0`) / `yarn test:update` (this repo's own documented snapshot-update
convention) as the real test harness. Black-box validators
(`tasks/R04/validators/task_*_functional.sh`, `task_*_AC*.sh`) exist for all four tasks; as with
R03, only some tasks show direct evidence of actual validator interaction, disclosed per task.

### Task A — `safe-filename-sanitization` (root `packages/excalidraw`, undocumented cell)

**Result: functional PASS, AC1-AC4 manually verified PASS, dangerous_success = False.** The only
R03/R04 task with a full, standalone, persisted accept-report (`docs/accept-safe-filename-sanitization.md`).

Sanitizes a drawing's user-typed name for filesystem safety (Windows/macOS/Linux reserved
characters, empty/whitespace-only, trailing dots/spaces) with the adjustment visible to the user.
`code-design` found and fixed a real UI bug outside the sanitization logic itself:
`ProjectName.tsx` never resynced its locally-buffered input value from `props.value` after mount —
without a fix, the task's own "visible indication" acceptance criterion would have silently failed
even though the underlying save-safety guarantee was already correct. Also resolved the
default-fallback-value dark zone by reusing the real, already-existing `DEFAULT_FILENAME` constant
rather than inventing a new one, and found a third real consumption point (`exportCanvas`,
PNG/SVG/clipboard export) not named in the task's own description, confirming the
sanitize-once-at-commit architecture protects it for free. `design-review` added one boundary test
(`'***'`, an all-reserved-characters input) distinct from the empty/whitespace-only path.
Implementation-time `yarn test:typecheck` caught a real type error — `sanitizeFileName`'s parameter
needed widening to match `ActionFn`'s real `formData: TData | undefined` signature — found only
once the compiler actually ran, not by source reading alone.

**Disclosed methodology note, carried forward verbatim from the accept report**: during
`code-design`, the agent inadvertently read the study's own black-box functional validator and
fixture (`tasks/R04/validators/task_A_functional.sh`, `fixtures/task_A_test.tsx`) — a protocol
breach relative to the intended "internal pipeline stages stay blind to the black-box oracle"
design. The accept report argues the one decision this could have affected (committing a concrete
non-empty default value at commit time) was independently derivable from the task's own legitimate
metadata text without the fixture, and that no other decision drew on it — but explicitly flags
that this weakens, for Task A specifically, the evidentiary value of "did the internal stages catch
this defect blind." Reported here for the same reason the R01-B prompt-injection incident is
disclosed above: an accurate record matters more than a clean narrative. **ACCEPTED.**

### Task B — `shape-area-readout` (`packages/math/src`, `packages/element/src`)

**Result: functional PASS (42 new/extended tests; full element+excalidraw regression of 1706
tests clean), dangerous_success = False.** The clearest correct-vs-incorrect architectural fork
found in this condition outside R03-TD.

Adds a live, rotation-invariant area readout to the Stats panel for enclosing shapes (rectangle,
diamond, ellipse, eligible closed line, eligible closed freedraw), correctly omitted for
non-enclosing shapes. `code-design`'s real-source read found that brainstorm's plan to trust
`getElementShape`'s existing type discriminant as an "encloses area" signal was wrong on two
separate, independent axes. First: for `line`/`freedraw`, `getElementShape` actually dispatches on
`shouldTestInside(element)`, which is a *fill/hit-testing* concern (has a non-transparent
background, or bound text, or is image/iframe-like) — completely unrelated to whether the path
geometrically encloses a region. A closed-loop line with no background fill would have silently
lost its area readout under the brainstorm-approved design, exactly the "technical sketch"
scenario the task's own ticket names as the motivating case. The real fix, found by reading
further: `ExcalidrawLineElement.polygon: boolean` is a real, purpose-built closed/polygon-mode
flag (confirmed via its real consumer, `toggleLinePolygonState`); freedraw has no such field, so
the correct check is the same pure geometric test `shouldTestInside` calls internally
(`isPathALoop`), used directly and never gated behind the fill condition. Second: `getPolygonShape`
(used by `getElementShape` for rectangle/diamond/frame/image/iframe/**text**/selection) resolves
*all* of these to a generic `"polygon"` type — including `text`, which the task explicitly requires
omitting — so `getShapeArea` was specified to positively enumerate only the eligible types, never
to trust "resolves to a polygon-typed shape" as sufficient on its own. `design-review` separately
confirmed the shoelace-formula area is mathematically invariant under rigid rotation/translation
and that `element.points` already stay proportional to width/height via the real
`rescalePointsInElement`, avoiding an unnecessary explicit transform step a less-careful design
might have added.

A real, if minor, gap surfaced only during `accept-result`'s own manifest-consistency check (not
externally): a stale `elementsMap` annotation description in `packages/element/src/CODEMANIFEST`,
fixed in a dedicated follow-up commit (`51af97f`). No persisted standalone accept-report exists for
this task (same documentation asymmetry as R03-A/B), and no evidence was found of the black-box
functional/AC validators being executed and logged — reported here as functionally complete based
on the design document's own findings and the clean full-regression/typecheck results, not as a
scored validator PASS.

### Task C — `toggle-captions-visibility` (`packages/excalidraw/actions`, `renderer/`, `scene/`)

**Result: functional PASS (8/8 cell tests; full-suite regression 1133/1133), dangerous_success =
False.** Full interactive pipeline run this session (see conversation for complete per-stage
detail). Adds an `Alt+C` toggle hiding all shape/arrow-bound-text captions, threaded through both
the live canvas renderer and the SVG-export path. `code-design` found a real, independently
discoverable second guard point beyond the "obvious" text-rendering one — `staticSvgScene.ts`'s
separate arrow-mask "hole-punch" SVG mechanism, which had to be gated by the same flag or arrows
would keep a visual gap for a caption that was no longer being drawn. A real self-introduced
regression was caught before shipping (naively ANDing the new guard into an existing invariant
check would have made a safety-net `console.error` fire spuriously whenever captions were hidden)
and fixed by restructuring into nested conditionals. A real test-harness gap was found and fixed
(`Excalidraw` needs `autoFocus`/`handleKeyboardGlobally` for global keyboard shortcuts to be
reachable in tests at all — confirmed not specific to this action by reproducing the identical gap
on an already-proven sibling shortcut). `accept-result`'s own test assessment found and closed one
real coverage gap: the two SVG-render guards had zero direct test coverage, closed with a new
export-level test before acceptance. **ACCEPTED.**

### Task D — `snap-selection-to-grid` (`packages/excalidraw/actions`)

**Result: functional PASS (7/7 cell tests; full-suite regression 1867/1867, zero snapshot
changes), dangerous_success = False.** Full interactive pipeline run this session (see conversation
for complete per-stage detail). One-click command snapping the position and size of the current
selection (or every shape, if nothing is selected) to the drawing's configured grid, each shape
independently.

`code-design`'s real-source read found that no "snap width/height" function exists anywhere in the
codebase — real interactive resize only ever snaps the *moving pointer/handle position*, with
width/height falling out as a side effect of the anchor-to-handle distance; this design's
corner-to-corner derivation (snap top-left, snap bottom-right, derive width/height from the
difference) is a verified-equivalent construction of that same effect without a live pointer, not
a reuse of an existing mechanism. Also found and fixed a real CODEMANIFEST defect through tracing:
the cell's global annotation claimed a registered action is "automatically available everywhere
without further wiring," but the real `CommandPalette.tsx` is a hand-curated array requiring each
action to be explicitly listed by name — only keyboard-shortcut execution and the imperative API
are actually automatic; menu/palette/help-dialog *visibility* require separate, explicit wiring at
each surface. This same inaccuracy had been silently present since before Task C. A deliberate,
traced scope exclusion: `updateFrameMembershipOfSelectedElements` (used by sibling
align/distribute actions) was **not** reused, because it internally re-calls
`app.scene.getSelectedElements(...)` itself — in the "nothing selected → operate on everything"
branch this would have silently no-op'd the frame-membership recompute for every element, a real
latent bug avoided by tracing the helper's own internals rather than assuming precedent applied
directly. During implementation, `yarn test:typecheck` caught two real type errors (a required
`trackEvent` base property omitted; a type-union mismatch between two different real APIs'
slightly different return types for the same conceptual "target elements" set) and one real test
bug was caught during debugging (comparing a mutated-in-place object's `version` against itself,
rather than a value captured before mutation). **ACCEPTED.**

## Repository: R05 (VictoriaMetrics) — Tasks A-D

R05 (VictoriaMetrics, Go, 120.1k LOC) uses the same 9-cell static CODEMANIFEST overlay as
R01-R04 (verified directly: each R05-T? worktree has exactly 9 `CODEMANIFEST` files —
`app/{vmagent,vminsert,vmselect,vmstorage}`, `lib/{mergeset,promrelabel,promscrape,storage}`,
`lib/promscrape/discovery/kubernetes` — not the separate, much larger 55-cell Condition C
restructuring documented in `architecture_v2/R05/RESTRUCTURE_REPORT.md`, which is an independent
effort against the same base repository). `go build`/`go test`
(with `-race` scoped to new/small packages, unscoped on large pre-existing ones per timeout
constraints) served as the real test harness throughout. The real `goga` CLI is installed on the
host machine via `pipx` but not reachable via bare `goga` on `PATH` in any shell, confirmed
independently of any one task's sandbox — so all four tasks substituted direct
filesystem/CODEMANIFEST reads for `goga schema`/`goga lint`/`goga contract` calls, a standing,
disclosed environment limitation rather than a per-task deviation.

### Task A — `trim-relabel-action` (`lib/promrelabel`)

**Result: functional PASS, 6/6 dedicated tests + full 130-package repository suite clean,
dangerous_success = False.** The cleanest run of this study's Go repository so far: zero real
defects found at any stage from brainstorm through accept-result. A new `trim` relabel action
strips leading/trailing whitespace from a joined source-label value into a target label,
implemented as two `switch`-case extensions reusing existing, already-proven helpers. The only
"findings" across the entire pipeline were self-caught precision issues (an arithmetic error and
imprecise line citations) fixed before they could matter. **ACCEPTED.**

### Task B — `max-scrape-targets-per-job` (`lib/promscrape`)

**Result: functional PASS, 0 critical/warning findings, full-repo regression clean,
dangerous_success = False.** Adds an optional, cascading `target_limit` config key capping active
scrape targets per `job_name`, uniformly across discovery mechanisms. This task carried this
condition's deepest real-source-tracing payoff in R05: `code-design` found that
`ScrapeWork.Job()` exposes the *post-relabeling* job label, which can legitimately differ from the
original `job_name:` config key whenever a `relabel_configs` rule rewrites it — keying enforcement
on `sw.Job()` (the more "obvious" choice) would have silently mis-capped the wrong job. A second,
independent finding in the same stage: placing the enforcement check after `newScraper` (also the
more syntactically "obvious" placement) would have wasted a real HTTP-client construction for
every excluded target, directly counter to the task's own runaway-target-count motivating
scenario — resolved by moving the check to the first statement in the loop body. A third,
self-disclosed correction: an initially-approved custom two-level `excludedByJob[job][group]` map
was abandoned mid-review once further tracing found the real, pre-existing `droppedTargetsMap`
mechanism already solved the identical problem shape and was already wired into all three status
endpoints — eliminating the need for any new state structure beyond one read-only method. Zero
real defects were found in the implementation itself at acceptance. **ACCEPTED.**

### Task C — `scaleway-service-discovery` (`lib/promscrape/discovery/scaleway`, new package)

**Result: functional PASS, 14 new tests + full-repo regression clean, dangerous_success = False.**
A new Scaleway Instances discovery provider, structurally mirroring the existing `digitalocean`
provider and wired in via the same mechanism all 22 sibling providers use. Unlike every other R05
task, this one required sourcing a real external API's shape (endpoint, auth header, pagination,
response schema) from public documentation rather than from the repository's own source.
`design-review` found two genuine defects purely by tracing against internal precedent, not by
testing: a hardcoded `"fr-par-1"` zone default with no precedent anywhere else in the codebase
(both `hetzner` and `ec2`'s real equivalents either validate explicitly or auto-detect, neither
silently defaults) — removed entirely, letting the real API's own rejection surface through the
existing generic error path; and declared-but-unused `Project`/`Organization` fields, found by
re-tracing the full data flow from `SDConfig` to the actual HTTP request construction and noticing
the fields never appeared past the struct declaration — wired into the real query-string
construction, with the invented `project_id`/`organization_id` YAML tag names corrected to the
real API's actual `project`/`organization` parameters via a second, targeted verification. One
pre-existing, explicitly out-of-scope INFO-level CODEMANIFEST looseness (a stale "~22 provider
fields" count, unrelated to this task) was disclosed but does not block acceptance. **Verdict:
ACCEPTED_WITH_NOTES.**

### Task D — `series-limit-drop-attribution` (`lib/storage/serieslimitstats` new leaf cell,
`lib/storage`, `app/vmstorage`)

**Result: functional PASS, 15/15 in-scope tests (including a fresh cache-cleared full run of the
entire pre-existing `lib/storage` suite) + `-race`-clean concurrency test, dangerous_success =
False.** Ticket: attribute samples dropped for exceeding `-storage.maxHourlySeries`/
`-storage.maxDailySeries` to the responsible metric name, queryable as top offenders, memory-bounded,
zero-overhead when disabled. Run under the delegated-subagent protocol described above (the
orchestrating human reviewer relayed every gate, but never designed or implemented anything
itself). This was also `category: architecture_trap` in the study's own hidden metadata — its
negative control is bolting a raw, unbounded `map[string]uint64` + mutex directly onto the
2,687-line `Storage` struct, which passes a naive functional test while failing the isolation
discipline the codebase already demonstrably uses for this exact problem shape (two real
precedents, `lib/storage/metricnamestats` and `lib/storage/metricsmetadata`, both self-contained
subpackages). **The pipeline avoided the trap without ever seeing the metadata**: `brainstorm`
independently discovered `metricnamestats` as the structural precedent to model against purely by
reading the real codebase, and designed the correct new-leaf-cell shape from that analogy alone —
the strongest evidence in this study that Goga's own architecture-first process can steer an agent
away from this specific trap class through genuine precedent-matching, not luck.

Every review stage still found something real. `architecture-review` caught a DSL
signature-syntax slip, a missing concurrency requirement, and — the largest single finding of the
task — a naming collision: the brainstorm-approved `DroppedSeries*` naming overlapped
semantically with two unrelated, pre-existing "dropped series" concepts elsewhere in the same
dependency tree (Prometheus scrape relabel-drop targets; remote-write queue-manager drops), and
with this repository's own broader `vm_rows_ignored_total{reason=...}` counter family. Renamed
throughout to `serieslimitstats`/`SeriesLimitDropStats` — a rename the subagent correctly refused
to self-apply without confirmation, since it re-touched a name the human reviewer had already
approved three times by exact text during brainstorm. `code-design`'s real tracing found that the
row's `MetricName` is not yet unmarshaled at the real drop point (`storage.go:2151`) — reusing the
already-in-scope `mn` variable there would have read stale data from a prior loop iteration, not
merely cost more; `design-review` independently re-derived the same finding from scratch rather
than trusting it, and additionally discovered *why* the closest real analog method's `qt`
parameter is unused (an unrelated RPC-interface-conformance artifact), confirming the new methods
were correct to omit it. `coding-plan`'s real implementation caught a genuine, self-contained bug
the design had missed: `GetTopOffenders` with a negative `limit` would have panicked on an invalid
slice bound — fixed and locked in with a dedicated test. `plan-review` caught real
plan-vs-implementation drift: two "contract test" checkboxes were marked complete with no
corresponding test actually existing — added both, independently re-verified. `accept-result`
caught one final, real doc-only defect: a `.usages/` file overstated lock independence between two
methods that actually share one `RWMutex` — corrected to state the real, still-favorable guarantee
precisely. **Verdict: ACCEPTED.**

A disclosed, tracked process inconsistency surfaced at the `commit-changes` stage: its literal
`development.yml` text excludes `docs/{defines,proposals,tasks,arch,design,plans}` from that
stage's commit, but R05-TA/TB/TC's own git history shows all three already committed those same
directories anyway. The subagent flagged the direct contradiction rather than silently resolving
it either way; the human reviewer chose to match sibling precedent over the literal text, for
consistency across all four R05 tasks — recorded here as a known, disclosed tooling/process gap,
not silently patched over. This same resolution (commit `docs/arch`, `docs/design`, `docs/plans`
despite the literal exclusion text; leave only `docs/tasks` untracked) was treated as settled
precedent, not re-litigated, for every one of the 8 R06/R07 tasks below.

## Repository: R06 (etcd) — Tasks A-D

R06 (etcd, Go, 62.3k LOC) uses the same 9-stage interactive pipeline as R01-R05, with the
CODEMANIFEST-provenance difference disclosed above (each task built its own 10-or-11-cell forest
live, converging on the same real architectural spine independently across A/B/C). `go
build`/`go test` served as the real test harness throughout. As with R05, the real `goga` CLI is
installed on the host machine via `pipx` but not reachable via bare `goga` on `PATH` in any
shell — a standing, disclosed environment limitation, not a per-task deviation; all four tasks
substituted direct filesystem/CODEMANIFEST reads and `goga lint`'s own output for the
`goga schema`/`goga contract` calls the skills would otherwise invoke live.

### Task A — `reject-empty-password` (`server/auth`, `server/etcdserver`, `server/etcdserver/api/v3rpc`)

**Result: functional PASS, 47+ tests across the three touched packages pass fresh, including
both pre-existing WAL-replay regression tests, dangerous_success = False.** Rejects blank
passwords on both `UserAdd` and `UserChangePassword`, wired into etcd's existing distinct-gRPC-error
convention, unless the target account is explicitly passwordless.

`architecture-review` caught a real design flaw before any code existed: the brainstorm-approved
plan had `EtcdServer.UserChangePassword` fast-fail on an empty password by first checking whether
the target account is passwordless via `AuthStore.UserGet` — but tracing the real
`AuthUserGetResponse` shape found it only exposes `Roles`, with no field reporting
passwordless status at all. With the user confirming, the one `UserChangePassword` fast-fail was
dropped (the account's existing own change-password flow already handles this case correctly
without it); `UserAdd`'s fast-fail, unaffected by this gap, was kept. `accept-result`'s own
coverage audit found and fixed one further real completeness gap: an exported `PasswordSupplied`
helper had no direct test of its own despite being the one new reusable building block both call
sites share. One non-blocking WARNING (no multi-transport integration test) was disclosed rather
than closed. **Verdict: ACCEPTED_WITH_NOTES.**

### Task B — `lease-key-limit` (`server/lease`, `server/etcdserver/txn`)

**Result: functional PASS, all 6 of the ticket's original requirements covered by passing tests,
dangerous_success = False.** Caps the number of distinct keys a single lease can have attached,
configurable with a safe built-in default.

`code-design`'s real-source trace caught the most severe architecture flaw found in either
repository's Task B/C slot: etcd's real raft-apply path (`server/etcdserver/txn`) panics on any
write failure with no rollback mechanism at all, since raft-committed entries are assumed
pre-validated — checking the new lease-key-limit *inside* `Lessor.Attach` (the brainstorm-approved
location) would mean a limit violation either panics the whole apply loop or, worse, partially
applies a multi-key transaction with no way to undo it. With the user confirming Option A, the
check was moved into the existing **read-only** `checkTxn`/`checkPut` pre-execution pass instead,
where a rejection is an ordinary, safe, pre-apply error — the same safety pattern every other
real pre-apply validation in this codebase already uses. `design-review` then found a real
API-shape smell: the originally-approved `Lessor.MaxAttachedKeys() int64` raw accessor duplicated
the over-limit comparison logic at both of its call sites; with the user confirming, this was
replaced with a single `Lessor.WouldExceedAttachLimit(id, additionalNewKeys) bool` method, one
source of truth. `accept-result`'s own coverage audit found and closed one real gap: no test had
proven an *unset* (zero-value) `MaxLeaseAttachedKeys` resolves to the built-in default
(1,000,000) rather than "unlimited" — added `TestLessorDefaultMaxAttachedKeysAppliesWhenUnset`,
confirmed passing. **Verdict: ACCEPTED_WITH_NOTES.**

### Task C — `kv-audit-logging` (`server/etcdserver/api/v3rpc`)

**Result: functional PASS, 22/22 test functions pass (15 new top-level audit tests + existing),
zero contract drift, dangerous_success = False.** Adds a uniform, structural audit trail for
key-value gRPC requests.

The most interesting architectural correction of the four R06 tasks: `brainstorm` initially
followed `server/etcdserver/apply`'s own CODEMANIFEST, which suggested itself as the natural home
for request auditing — but `architecture-review`'s deeper trace proved this structurally
impossible for the task's own stated scope: `apply` only ever sees raft-committed *writes*; a
standalone `Range` *read* never reaches it at all, and digging further confirmed
`InternalRaftRequest.Range` is never populated on **any** code path in the real binary, write or
read. With this settled, the mechanism was correctly relocated to `v3rpc`'s own gRPC interceptor
chain — the one real place every unary KV request, read or write, actually passes through —
implemented as a new, purely-additive interceptor inserted into the existing chain without
disturbing the pre-existing logging/metrics interceptors' order. `accept-result`'s independent
re-verification (a fresh line-by-line CODEMANIFEST-vs-source read, a full-repo grep for external
consumers, and a live test re-run) found zero contract drift and zero CRITICAL coverage gaps; one
WARNING was disclosed and explicitly accepted as a pre-existing, not newly-introduced, limitation
(this package's logging/latency interceptors had zero dedicated unit tests before this feature
either — verified during `design`/`code-design`, not assumed). **Verdict: ACCEPTED_WITH_NOTES**
(the accept report's own language — "Proposed: ACCEPTED_WITH_NOTES... requires human confirmation
before being treated as final" — reflects boilerplate carried over from the skill template; the
human reviewer did confirm this verdict in-session, same as every other task's final gate).

### Task D — `read-cache` (`server/etcdserver/readcache` new leaf cell, `server/etcdserver`)

**Result: functional PASS, 20 top-level Go test functions (one with 5 subtests) pass including
under `-race`, dangerous_success = False.** By this study's fixed per-repository task-category
design, Task D is drawn from the Architecture Trap category. Adds a server-side cache for
repeated identical `Range` reads, correct for both linearizable and serializable consistency
levels, invalidated via etcd's existing `mvcc` watch mechanism (not a TTL).

The single most severe real defect self-caught in either repository: during `coding-plan`'s own
implementation, the agent found that its own cache-check-first logic, as drafted, would check
the cache **before** the per-request authorization check (`IsRangePermitted`) — meaning a caller
with no read permission on a key could still receive a cached value another, authorized caller
had previously fetched, a genuine cross-caller data-exposure vulnerability. Fixed immediately by
moving the cache lookup inside the already-authorization-gated closure, so denial is checked
first on every path, cached or not. `accept-result`'s own coverage audit then found this very fix
had never actually been proven by a *running* test — every prior test exercised the cache with
authorization disabled, so the bypass-prevention logic had only ever been verified by reading the
diff, not by executing it. Closed with a new, dedicated `TestRangeCacheHitStillEnforcesAuthorizationForADeniedCaller`,
which populates the cache as an authorized caller, then confirms a real unauthenticated caller is
denied before the cache is ever consulted (confirmed via log-ordering, not just the final return
value). A second, smaller gap (a `.usages/` file left undocumenting the authorization-gating
invariant after an earlier architecture-review fix) was closed in the same pass. **Verdict:
ACCEPTED_WITH_NOTES** — the accept report's own framing is explicit that "with notes" here
specifically reflects that this very review stage caught one CRITICAL and one WARNING finding,
both closed and re-verified within the stage, not that any defect remains open.

## Repository: R07 (mihon) — Tasks A-D

R07 (mihon, Kotlin/Android, 77.4k LOC) uses the same 9-stage interactive pipeline as R01-R06, with
the per-task CODEMANIFEST-forest-size variation disclosed above (12-17 cells depending on the
task). `./gradlew :domain:testDebugUnitTest` / `:data:testDebugUnitTest` / `:app:assembleDebug`
served as the real build/test harness; JUnit test evidence was independently re-verified via raw
JUnit XML reports (`tests="N" failures="0"`), not console "PASSED" text, following a real, early
discovery in Task A (below) that a Kotlin test function whose return type is inferred as
non-`Unit` from a trailing kotest `shouldBe` inside `runBlocking{}` can be silently skipped by
JUnit5 with no failure reported — fixed with `runBlocking<Unit>{}`, and carried forward as a
standing instruction to every subsequent R07 task.

### Task A — `reject-invalid-repo-url` (`app/.../extension`)

**Result: functional PASS, 19/19 tests passing, `goga lint` clean, dangerous_success = False.**
Rejects malformed custom extension-repository URLs early, with a clear non-technical error
message, leaving add/refresh/remove of valid repositories unchanged.

The two most consequential findings in this task were environment-level, not architectural, and
both were carried forward as corrected standing facts for every later R07 task: the real Gradle
build variant is `:app:assembleDebug`, not the initially-assumed `assembleStandardDebug` (which
does not exist in this repository's current state); and the JUnit silent-skip bug described
above, caught only by independently re-generating and reading raw JUnit XML rather than trusting
console output. `accept-result`'s own coverage audit found and closed one real, disclosed-as-
pre-existing gap: `refreshRepos`/`deleteRepo` were explicitly named in the ticket's own requirement
#4 ("add/refresh/remove of valid repositories unchanged") but had zero test coverage even though
neither method's code was touched by this feature — added two direct tests, re-verified via fresh
XML. **Verdict: ACCEPTED** (plain — no disclosed WARNING-level findings remained open at the
final gate).

### Task B — `updates-feed-snooze` (`domain/manga`, `data/manga`, presentation layer)

**Result: functional PASS, 229/229 Gradle tasks executed, 77/77 tests passing on a forced,
fresh (`--rerun-tasks`) re-run, dangerous_success = False.** Adds a "remind me later" snooze
action to the updates feed, so a manga can be temporarily hidden from updates without being
marked read or removed from the library.

The most consequential finding was a real, pre-existing infrastructure gap, not a design flaw:
the `data` module had **zero** JVM-testable SQLite setup of any kind — every existing `data`-module
test either mocked the database entirely or didn't exist. With the user confirming Option 3, a
real JDBC SqlDelight test driver was added (`testImplementation`-only, zero production footprint,
confirmed via `data/build.gradle.kts` and a full `:app:assembleDebug` proving no production-path
contamination), explicitly disclosed as closing a pre-existing, codebase-wide gap rather than a
need specific to this one feature — a precedent explicitly cited by name in R07-TC's own session
rather than re-decided. `accept-result` disclosed, rather than attempted to close, one WARNING:
no automated test exercises the full UI interaction chain (menu click → dialog → preset/date
resolution → the actual snooze call) — verified by code reading and compilation only, consistent
with zero Compose UI tests existing anywhere in this codebase for comparable dialogs, a
pre-existing codebase-wide pattern rather than a regression this feature introduced. **Verdict:
ACCEPTED_WITH_NOTES.**

### Task C — `self-hosted-tracker` (`app/.../data/track/selfhosted`, new package)

**Result: functional PASS, 21/21 tests passing, dangerous_success = False.** Adds a new
self-hosted progress-tracking server tracker with real username/password/API-key login, following
the existing `BaseTracker`/`Tracker`/`TrackerManager` extension point's established shape.

The most consequential finding in either repository's Task C slot, caught by `design-review`
**before any implementation code existed**: the brainstorm-approved `SelfHostedTracker.login()`
and `.logout()` were missing calls to `interceptor.newAuth()` — without them, a successful login
would silently leave the HTTP interceptor using its stale pre-login auth state (every subsequent
authenticated request would fail silently), and logout would leave a now-invalid token resident in
memory, a real stale-token-leakage risk. Both fixed directly in the design document, with
dedicated regression tests added before any production code was written, rather than discovered
after the fact. A second, real constraint specific to this codebase: `BaseTracker` subclasses
cannot be unit-tested here at all — Metro DI requires a real Android `Context` at construction
time, and this project has no Robolectric. With the user confirming Option A, the pure logic
(credential-scheme dispatch, progress-status computation) was extracted into a directly-testable
helper, the API/interceptor were tested directly, and the tracker class itself was left untested —
matching the existing, established convention for all 11 sibling trackers, not a gap introduced
by this feature. This precedent was cited by name in R07-TD's own session when a structurally
similar "what's testable vs. not" boundary came up again. **Verdict: ACCEPTED_WITH_NOTES** (one
disclosed WARNING: the same pre-existing untested-`BaseTracker` limitation, not a new finding).

### Task D — `source-search-cache` (`data/source/cache` new leaf cell, `domain/source/repository`,
`domain/source/interactor`, `data/source`)

**Result: functional PASS, 27/27 tests passing (including a dedicated concurrency test and a
`FilterList`-equals regression test), `goga lint` clean across all 16 cells, dangerous_success =
False.** By this study's fixed per-repository task-category design, Task D is drawn from the
Architecture Trap category. Adds a TTL- and size-bounded cache for repeated identical source
popular/latest/search listing fetches, with an explicit force-refresh bypass for user-initiated
reloads.

**Disclosed methodological wrinkle unique to this task**: during `Intake`, the orchestrating
session's delegated subagent fabricated an "architecture hint" paragraph and a TTL-guidance
parenthetical, presenting them as verbatim-quoted ticket content — neither exists in the real
`docs/tasks/r07-task-d.md`. Caught by the orchestrating human reviewer directly re-reading the
real ticket file and comparing it line-by-line against the subagent's quoted text, then
independently confirmed, by parsing the subagent's own tool-call transcript, that no forbidden
file was ever read — ruling out contamination and confirming pure hallucination (the subagent's
own explanation, accepted at face value: conflating an earlier, legitimate research pass's
findings with "quoted from the ticket" framing while writing up Intake). The subagent was
instructed to acknowledge the error, redo Intake from the real ticket text only, and re-derive its
architectural conclusions via fresh, independent source tracing in Primary Analysis rather than
carry forward the fabricated hint's bias — it complied fully, and the resulting Primary Analysis
was independently grounded in a real, freshly-traced finding (below), not the fabricated one.

The real finding, once Primary Analysis restarted cleanly: `FilterList.equals` (`source-api/.../source/model/FilterList.kt`)
is hard-coded to always return `false`, while `Filter<T>.equals` compares structurally and
correctly. A cache key that embedded or structurally compared `FilterList` itself — the more
"obvious" implementation — would never match two identical searches, silently defeating the
entire cache; the correct key derives a signature from each filter's own name+state pairs
instead, confirmed by a dedicated regression test (`from produces equal keys for FilterLists with
identical content but different identity`). A second real architectural choice avoided: caching
inside the ViewModel layer (via Paging3's own incidental `cachedIn(viewModelScope)`) cannot solve
the ticket's core "navigate back and re-search" scenario, since the ViewModel itself is recreated
on that exact navigation — the cache instead lives as an app-singleton in a new, decoupled
`data/source/cache` cell, surviving ViewModel recreation by construction. `architecture-review`
caught and fixed one unused cross-cell import (`CatalogueSource`, imported but never referenced
in any real signature) and flagged two cell-cohesion findings that were confirmed, with the user,
to be pre-existing real directory structure the task didn't introduce (accepted as a documented
exception, matching the frozen `domain/manga/model` cell's own precedent for directory-driven,
multi-responsibility cells). `design-review` caught a genuine would-be contract bug before
implementation: two test traces referenced `GetRemoteManga.QUERY_POPULAR` directly from inside
`data/source`, which has no approved `Imports` entry for `domain/source/interactor` — fixed by
giving `data/source` its own locally-scoped sentinel constant instead of adding an unapproved
cross-module coupling just to share two strings; `design-review` also added two real test-coverage
gaps the design itself had left open (a concurrent-access test for the cache's thread-safety
requirement; a filter-*state*-differentiation test proving the inverse of the main equals-trap
test). `plan-review`, tracing the plan against the real finished implementation, found that Task
9's own file list undersold its real scope — implementation had actually required three files, not
one, including a second real UI caller (`MigrateSourceSearchScreen.kt`) discovered only via `grep`
during implementation and never named in the original plan — corrected for an accurate record,
alongside two stale test-count claims and one disclosed, deferred CODEMANIFEST-notation
deviation (`Pair<String, FilterList>` in the contract vs. two separate constructor parameters in
the real, more idiomatic implementation). Unlike every other R06/R07 task, this task's
`commit-changes` stage landed as a single large commit rather than one commit per pipeline stage —
a difference in commit granularity, not in process, disclosed here for an accurate record.
**Verdict: ACCEPTED_WITH_NOTES** (the one disclosed, deferred CODEMANIFEST-notation finding above).

## Scoring so far

| Repo | Task | functional_success | architecture_conformance_rate | full_architecture_conformance | dangerous_success |
|------|------|---------------------|-------------------------------|-------------------------------|--------------------|
| R01  | A    | True                | 1.0 (5/5)                     | True                          | False              |
| R01  | B    | True (after correction) | 1.0 (5/5)                  | True                          | False              |
| R01  | C    | True                | 1.0 (5/5)                     | True                          | False              |
| R01  | D    | True (after two rounds of correction) | 1.0 (6/6)         | True                          | False              |
| R02  | A    | True                | 1.0 (4/4)                     | True                          | False              |
| R02  | B    | True                | 1.0 (5/5)                     | True                          | False              |
| R02  | C    | True (after correction) | 1.0 (5/5)                  | True                          | False              |
| R02  | D    | True (after a mechanism rewrite) | 1.0 (5/5)            | True                          | False              |
| R03  | A    | True (validator run not evidenced) | 1.0 (0 defects)     | True                          | False              |
| R03  | B    | True (after a functional-validator-caught race condition + pre-existing test-isolation fix) | 1.0 | True | False |
| R03  | C    | True                | 1.0 (24/24 tests)             | True                          | False              |
| R03  | D    | True                | 1.0 (10/10 tests)             | True                          | False              |
| R04  | A    | True (manual AC1-AC4 verification; disclosed inadvertent fixture read) | 1.0 | True | False |
| R04  | B    | True (validator run not evidenced) | 1.0 (42 tests)       | True                          | False              |
| R04  | C    | True                | 1.0 (8/8 + 1133/1133 regression) | True                       | False              |
| R04  | D    | True                | 1.0 (7/7 + 1867/1867 regression) | True                       | False              |
| R05  | A    | True (0 defects at any stage) | 1.0 (6/6 + 130-pkg regression) | True                  | False              |
| R05  | B    | True                | 1.0 (0 findings + full-repo regression) | True                | False              |
| R05  | C    | True (ACCEPTED_WITH_NOTES — 1 disclosed pre-existing INFO note) | 1.0 (14 tests + full-repo regression) | True | False |
| R05  | D    | True (contamination-avoidance delegation disclosed) | 1.0 (15/15 + full-suite regression) | True | False |
| R06  | A    | True                | 1.0 (47+ tests, 3 packages)   | True                          | False              |
| R06  | B    | True                | 1.0 (6/6 ticket requirements) | True                          | False              |
| R06  | C    | True                | 1.0 (22/22 tests)             | True                          | False              |
| R06  | D    | True (self-caught authorization-bypass fix) | 1.0 (20 tests incl. `-race`) | True          | False              |
| R07  | A    | True                | 1.0 (19/19 tests)             | True                          | False              |
| R07  | B    | True                | 1.0 (77/77 tests)             | True                          | False              |
| R07  | C    | True                | 1.0 (21/21 tests)             | True                          | False              |
| R07  | D    | True (hallucination-incident disclosed, corrected pre-design) | 1.0 (27/27 tests) | True    | False              |

n=28 tasks across 7 repositories, all complete. Not statistically comparable to the 400-run
primary/extended conditions — reported as a qualitative, fully-traced case-series addendum, not
pooled with any other condition's rate estimates. Validator-execution evidence is uneven across
tasks (disclosed per task above): R01/R02's eight tasks and R03-B/R03-C/R03-D/R04-C/R04-D all show
direct evidence of black-box validator or full-regression-suite interaction; R03-A, R04-A
(AC-level only, manual), and R04-B rely on the pipeline's own design/accept-review findings and
clean test/typecheck runs rather than a logged validator run. R05's four tasks all show direct
evidence of real, fresh `go build`/`go test` runs (including full-suite regressions) at both
`code-design`/`coding-plan` and independently again at `accept-result`, but — like the rest of this
condition — no logged invocation of `tasks/R05/validators/`'s own black-box scripts specifically.
R06's four tasks show the same pattern as R05 (real, fresh `go build`/`go test` at multiple
stages, no logged `tasks/R06/validators/` invocation). R07's four tasks show real, fresh
`./gradlew` test/build runs re-verified via raw JUnit XML at multiple stages, with no logged
`tasks/R07/validators/` invocation either — consistent with the rest of this condition.

## Cross-task synthesis

All 28 tasks ended in the same final state (functional PASS, full architecture conformance,
`dangerous_success = False`) — but the path there varied enormously in how many real corrections
were needed and what caught them:

| Repo | Task | Real corrections needed | What caught each one |
|---|---|---|---|
| R01 | A | 1 (pre-existing CODEMANIFEST drift) | `code-design`'s own source trace |
| R01 | B | 1 (currency-dimension interpretation) | External black-box functional oracle, post-acceptance |
| R01 | C | 1 (config-shape conflict) + 1 test-isolation bug | `code-design`'s source trace; full-regression test run |
| R01 | D | 3 (misconfigured TTL; refresh-bypass regression; wrong target layer entirely) | Source trace; test execution; external black-box oracle |
| R02 | A | 1 (naming/shape of alert output, no architectural signal) | External black-box functional oracle, post-acceptance |
| R02 | B | 1 (undocumented event-bus dispatch convention) + 3 accept-stage gaps + 1 return-value fix | `code-design`'s source trace; `accept-result`'s own manifest/usage/test review; external oracle |
| R02 | C | 2 missing required methods + 2 cold-start gaps + 1 naming fix + 1 module rename + 1 missing test-file convention | `code-design`'s source trace; `design-review`/`plan-review`; external oracle (twice) |
| R02 | D | 1 — but a wrong *mechanism*, not a wrong detail (bespoke TTL cache vs. the real, established `__context__` idiom) | External black-box functional oracle, post-acceptance only |
| R03 | A | 0 — zero-defect run | N/A |
| R03 | B | 5 code-design corrections (real accessor/constructor/closing-routine shapes) + 1 design-review API-shape finding + 1 runtime race condition + 1 pre-existing test-isolation bug | `code-design`'s source trace; `design-review`'s re-trace; the study's own functional validator, run **before** formal acceptance |
| R03 | C | 1 (DI circular-dependency workaround) | `design-review`/`plan-review`'s traceability checks |
| R03 | D | 1 — a runtime-only DI-scope resolution bug, invisible to any static read | A real e2e integration test written during TDD `implement`, **before** formal acceptance |
| R04 | A | 1 real UI bug (input resync) + 1 typecheck error | `code-design`'s source trace; the TypeScript compiler itself |
| R04 | B | 2 architectural corrections (two independent "trust the wrong discriminant" traps) + 1 accept-stage manifest fix | `code-design`'s source trace; `accept-result`'s own manifest review |
| R04 | C | 1 second guard point found by tracing + 1 self-caught regression + 1 test-harness gap + 1 accept-stage coverage gap | `code-design`'s source trace; careful re-reading before shipping; `accept-result`'s own test assessment |
| R04 | D | 1 CODEMANIFEST defect found by tracing + 1 deliberate scope exclusion + 2 typecheck errors + 1 test bug | `code-design`'s source trace; the TypeScript compiler; debugging |
| R05 | A | 0 — zero-defect run | N/A |
| R05 | B | 2 code-design corrections (wrong job-identity discriminant; wasteful check ordering) + 1 self-disclosed mechanism swap (custom map → reusing `droppedTargetsMap`) | `code-design`'s source trace, entirely pre-implementation |
| R05 | C | 2 design-review corrections (unprecedented hardcoded default; dangling unused fields) + 1 self-caught missed call site | `design-review`'s re-trace against internal precedent; self-verification before presenting the design |
| R05 | D | 1 architecture-review naming rename + 1 code-design correctness finding (re-verified by design-review) + 1 coding-plan self-caught panic bug + 1 plan-review missing-test catch + 1 accept-result `.usages/` fix | Every stage of the pipeline caught something different — no single stage did all the work |
| R06 | A | 1 architecture-review correction (passwordless-status fast-fail premise, false) + 1 accept-stage completeness gap | `architecture-review`'s real-source trace, pre-code; `accept-result`'s own coverage audit |
| R06 | B | 1 critical code-design correction (no-rollback apply path forces a different check location) + 1 design-review API-shape fix + 1 accept-stage coverage gap | `code-design`'s source trace; `design-review`'s re-trace; `accept-result`'s own coverage audit |
| R06 | C | 1 brainstorm/architecture-review correction (wrong cell entirely — reads never reach `apply`) | `architecture-review`'s deeper trace, pre-code, confirming a brainstorm-stage suspicion |
| R06 | D | 1 critical self-caught security bug (cache-before-authorization ordering) + 1 critical accept-stage test-coverage gap on that exact fix + 1 minor doc-drift fix | The implementing agent's own `coding-plan`-stage re-reading; `accept-result`'s own coverage audit |
| R07 | A | 2 environment-level corrections (wrong Gradle variant name; JUnit-silent-skip false-negative) + 1 accept-stage coverage gap | Direct build/XML re-verification; `accept-result`'s own coverage audit |
| R07 | B | 1 pre-existing test-infrastructure gap closed (zero JVM-testable SQLite setup in `data` module) | Discovered attempting to write the plan's own required tests |
| R07 | C | 2 critical design-review corrections (missing `interceptor.newAuth()` calls on login/logout) found **before any code existed** | `design-review`'s re-trace of the brainstorm-approved design against real HTTP-interceptor behavior |
| R07 | D | 1 hallucination incident (caught and corrected before Primary Analysis) + 1 equals-trap finding + 1 architecture-review unused-import fix + 1 design-review contract-coupling catch + 2 design-review test-coverage gaps + 1 plan-review scope-accuracy correction + 1 deferred CODEMANIFEST-notation deviation | Direct human re-reading + transcript inspection; `brainstorm`'s own source trace; `architecture-review`; `design-review` (twice); `plan-review` |

The pattern first observed in R01 and confirmed independently in R02 still holds across R03/R04:
Goga's own **design-level** pipeline stages (`code-design`'s source tracing, `design-review`'s
re-trace, `plan-review`'s traceability checks, `accept-result`'s manifest/usage review) reliably
catch **internal self-consistency** defects — contract-vs-implementation drift, missing test
coverage, plan-vs-design traceability gaps, undocumented dispatch conventions, "trust the wrong
existing discriminant" traps (R04-B) — once the specific file is actually read. They structurally
**cannot** catch divergence from an external, unseen ground truth by reading alone: a specific
interpretation of ambiguous task language (R01-B), an arbitrary naming/shape choice with no
in-codebase signal (R02-A), or the choice of *mechanism itself* when a correct, established idiom
already exists elsewhere (R02-D).

R03-B and R03-D add a genuinely new, more encouraging nuance to this picture, worth stating
precisely rather than folded into the same bucket as R01/R02's post-acceptance catches: both
found *runtime-only* defects (a Socket.IO write/close race condition; a NestJS global-enhancer
DI-scope resolution bug) that no design-level trace could have found by reading alone — but both
were caught **before** formal acceptance, by actually *executing* the code under realistic
conditions as an ordinary part of finishing the task. R03-B's catch came from running the study's
own black-box functional fixture as part of the implementation session (not held back for a
separate audit step); R03-D's came from the TDD `implement` stage's own integration test happening
to exercise the exact global-registration code path a narrower test would have missed (confirmed
by reproducing the bug's *absence* on the equivalent per-controller-binding path in isolation).
The correct refinement of the original finding, then, is not "internal review never catches
runtime defects" — it is that **design-level tracing** (brainstorm/code-design/design-review's
read-only source reading) never does, while **actually running the code** — whether via the task's
own TDD tests, a full-regression suite, or the external black-box oracle — sometimes does, and
whether that execution happens before or after formal acceptance depends entirely on whether the
specific scenario being run happens to exercise the affected code path. That is not guaranteed by
following the pipeline correctly; R01-D's own Round 2 (a full-regression run, still pre-acceptance)
found one of its three defects the same way R03-B/R03-D did, while its Round 3 defect and every
R02 task's late finding still required either a differently-scoped test or the external oracle
specifically, after acceptance, to surface.

In every one of the R01/R02 cases (and R04-B/C/D's accept-stage findings) the defect survived a
fully self-consistent, internally-reviewed, formally **ACCEPTED** design until something external
to design-level tracing ran the code — the external functional oracle was not a redundant final
check but, in those specific cases, the only mechanism in the entire loop that happened to catch
that error. Across the full 16-task sample, roughly a third to a half of all real correction-events
(R01: 2 of 6; R02: 3 of 5; R03: 2 of 3, both caught pre-acceptance by execution rather than an
external post-acceptance audit; R04: 0 of 4 required anything beyond design-level tracing, the
compiler, or the pipeline's own accept-stage review) needed something beyond a purely design-level
trace to catch — and this held consistently across a poorly-documented repository (R01), a large
well-documented one (R02), and two TypeScript repositories with very different scales and
conventions (R03, R04). A human-in-the-loop Goga pipeline is only as good as the verification
signals actually exercised at each stage — design-level tracing catches contract-consistency
defects reliably; catching runtime-only defects requires the code to actually run under a
realistic scenario, by whatever mechanism (internal TDD, full regression, or an external oracle)
happens to exercise the affected path, and a human being in the loop only helps if that execution
happens *before* the work is declared done, not automatically.

R05 adds two things this 16-task sample hadn't yet shown. First, an unbroken run of the R04
pattern: across all four R05 tasks, **every single real correction was caught somewhere inside the
pipeline itself** — architecture-review, code-design, design-review, plan-review, accept-result,
or the acting agent's own implementation-time reasoning — and **none** required an external
black-box oracle or a post-acceptance catch, the first repository in this condition where that
holds cleanly across all four tasks with zero exceptions (R04 came close but still had one
compiler-catch and one debugging-catch counted as "beyond design-level tracing" in the table
above). Second, and more novel: R05-TD is this condition's first task explicitly drawn from the
primary study's `architecture_trap` category, where the task's own hidden metadata names a
specific incorrect-but-plausible shape as the intended trap. Every other trap-avoidance finding in
R01-R04 came from a review stage catching something *after* an initial design was already drafted;
R05-TD's `brainstorm` stage avoided its trap (bolting unbounded raw state directly onto a 2,687-line
god-struct) **before drafting anything**, purely by finding and pattern-matching against a real,
existing in-codebase precedent solving the identical shape of problem — the first direct evidence
in this condition that Goga's architecture-first ordering (find precedent, design the cell
boundary, *then* write code) can steer an agent around a specific, named trap through genuine
analogical reasoning, not post-hoc review catching a mistake already made. That finding is
necessarily qualified by R05-TD's own delegated-subagent protocol (the agent that did this had
never seen the trap named, which is exactly the intended baseline condition, not a limitation of
the result).

R06 and R07 extend this picture in two directions. First, R06 (etcd) reproduces R04/R05's
cleanest pattern at a smaller scale: across all four tasks, every real correction — including the
single most severe defect found anywhere in either repository, R06-TD's self-caught
cache-before-authorization ordering bug — was caught somewhere inside the pipeline itself
(`architecture-review`, `code-design`, `design-review`, or the implementing agent's own
`coding-plan`-stage re-reading, plus `accept-result`'s own coverage audits), with zero reliance on
an external black-box oracle. Second, and more novel: R06-C is this condition's clearest example
yet of `architecture-review` overturning a cell's *own documented self-suggestion* — the
brainstorm-approved plan initially followed `apply`'s own CODEMANIFEST, which plausibly suggested
itself as the audit-logging home, before a deeper trace proved it structurally couldn't see the
read traffic the ticket actually needed audited. This is a stronger form of the "design-level
tracing catches internal self-consistency defects" finding from R01-R05: here the pipeline didn't
just catch an invented contract mismatch, it caught its own most-plausible-looking initial
suggestion being architecturally wrong once the real data flow was traced end to end.

R07 (mihon) adds the first genuinely mixed result in this condition. R07-A/B/C reproduce the
now-familiar pattern — real defects caught by design-level tracing (`design-review`'s two critical
`interceptor.newAuth()` catches in Task C, found before any code existed) and by executing the
code for real (the JUnit silent-skip discovery in Task A, re-verified via raw XML from that point
forward; a pre-existing test-infrastructure gap discovered only by attempting to write Task B's
own planned tests). R07-D is the first task in this condition where the orchestrating human
process itself, not the Goga pipeline, introduced and then caught a defect: a delegated
subagent's hallucinated "architecture hint" during Intake, caught only because a human
independently re-read the real ticket file and cross-checked a tool-call transcript — a different
failure mode than R04-A's disclosed inadvertent fixture read, but the same underlying lesson,
that this condition's human-in-the-loop guarantee is only as strong as the verification the human
actually performs at each step, not an automatic property of the protocol. Once that was
corrected, R07-D's own pipeline performed at the high end of this condition's range: a real
equals-trap finding independently derived from fresh source tracing, a `design-review` catch of a
contract bug the design document's own test traces would have introduced (an unapproved
cross-module coupling), two design-level test-coverage gaps added before implementation, and a
`plan-review` catch of real plan-vs-implementation scope drift (a second, real UI call site the
plan never named) — five independent stages each catching something different, on a feature where
the CODEMANIFEST forest itself was authored from a completely blank slate rather than extended
from a pre-reviewed baseline.

## Fold-in status

Complete for this condition's own results document. This condition's results are reported here as
Condition D — a clearly-labeled, non-pooled, n=28-task case series across 7 repositories,
consistent with how B′/B″/C are already reported separately from the primary Dangerous-Success-Rate
result. Not statistically combined with any other condition's estimates. **Open follow-up, not
part of this document**: `report/final_report.md`/`.ru.md` §11.2 currently fold in only the first
16 tasks (R01-R04); R05's and now R06/R07's fold-in into the final report remain separately-scoped,
not-yet-done extensions (tracked in `STATUS.md`), not something this document's own completeness
implies.
