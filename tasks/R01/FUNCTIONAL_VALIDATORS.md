# FUNCTIONAL_VALIDATORS.md — R01 (freqtrade/freqtrade @ 936f28e28cbcd4e9e146cbc076c54933517a92eb)

Standalone, runnable functional-correctness validators for tasks A-D, complementing the
already-built architecture validators (`validators/task_X_AC*.sh`). Each
`validators/task_X_functional.sh` copies a fixture test file from `validators/fixtures/`
into the target repo's `tests/` directory, runs it with pytest, prints `PASS`/`FAIL`, exits
0/1 accordingly, and removes the injected fixture afterward (via a `trap ... EXIT`).

Environment used to build and verify these: `/tmp/benchmark-repos/R01`, pinned to
`936f28e28cbcd4e9e146cbc076c54933517a92eb`, Python 3.14.6 venv at `.venv` with
`pip install -e ".[all]"` plus `freezegun`/`time-machine` (already a transitive dev
dependency; `time_machine` was already installed, `freezegun` was added since the D
positive-control diff's own comment references it, though the shipped fixture ultimately
only needed `time_machine`, already present).

All four scripts were verified against the real, pinned `controls/task_X_positive.diff`
and `controls/task_X_negative.diff` by: `git checkout -- .` + `git clean -fd <touched dirs>`
to reset, `git apply <diff>`, run the validator, observe the result, reset again. The repo
was left with **zero tracked modifications** (`git diff --stat` empty) after all runs; only
the pre-existing Phase-4 untracked leftovers (`.goga/`, `docs/arch/`, `CODEMANIFEST` files)
remain, as instructed.

---

## Task A — R01-TA: conflicting capital-sizing config detection

**What it checks:** `validators/fixtures/task_A_test.py` instantiates a real `FreqtradeBot`
(via the project's own `get_patched_freqtradebot()` test helper — the same helper used
throughout freqtrade's own test suite) with a config that sets both `available_capital` and
a non-default `tradable_balance_ratio` (schema default 0.99), then additionally calls the
already-existing, already-public `wallets.get_starting_balance()` method (itself called from
several real production call sites: `FreqtradeBot.startup()`, the entry-protections path,
`Backtesting`'s own init, and RPC's balance endpoints). It asserts an unmissable warning
naming both `available_capital` and `tradable_balance_ratio` appears in the logs. Three
companion tests assert the common, non-conflicting configurations (only one key set, or
both set with the ratio left at its 0.99 default) produce **no** warning.

**Why this is implementation-agnostic:** it deliberately does **not** call
`validate_config_consistency()` directly (that would only catch implementations that
literally use that one aggregator function — an architectural assumption, not a functional
one). Instead it drives two genuine, pre-existing, stable public surfaces
(`FreqtradeBot.__init__()` and `wallets.get_starting_balance()`) that cover both plausible
warning locations described in the task's own metadata (the correct location,
`config_validation.py`'s aggregator, and the documented trap location, inside
`Wallets.get_starting_balance()`), without assuming which one a given candidate used. The
separate `task_A_AC*.sh` scripts are what verify *where* the check lives; this script only
verifies *that* the user is warned.

**Command:** `python -m pytest tests/<injected>.py -q`

**Results:**
| Control | Result | Notes |
|---|---|---|
| Positive (`task_A_positive.diff`) | **PASS** (4 passed) | Warning fires from `config_validation.py`'s new `_validate_available_capital`. |
| Negative (`task_A_negative.diff`) | **PASS** (4 passed) | Matches `CONTROL_RESULTS.md`'s documented functional verdict ("PASS \| PASS") — the trap's warning fires from inside `Wallets.get_starting_balance()`, which our `get_starting_balance()` call reaches directly; this control is architecturally wrong (per `task_A_AC1-5.sh`, all FAIL) but functionally correct — the intended "Dangerous Success" shape for this task. |
| Clean baseline (no diff) | FAIL (1/4 failed) | Sanity check — confirms no false positive. |

---

## Task B — R01-TB: per-underlying-currency exposure cap

**What it checks:** `validators/fixtures/task_B_test.py` is the positive control's own test
file (`tests/test_max_pair_exposure.py`), reused essentially as-is. It drives two real,
stable public entry points every correct implementation must route a new trade through:
`FreqtradeBot.execute_entry()` (live/dry-run) and `Backtesting._enter_trade()`
(backtesting). It opens a trade in `XRP/BTC`, then attempts a second trade in `XRP/USDT`
(same base currency, XRP) that would push combined exposure over a configured
`max_pair_exposure = 0.2` cap, and asserts the second trade is resized down from 150 to 48
— identically in both engines.

**Why "identical live/backtest behavior" is treated as functional, not just architectural:**
the task prompt itself states this as a functional requirement ("this needs to behave
identically whether someone is running the bot live/dry-run or running a backtest... We've
been burned before by features that quietly only worked in one of those two modes"), and
`metadata_B.yaml`'s own `functional_requirements` section lists it explicitly. Consequently
this validator's overall PASS/FAIL folds in both the live-path assertion and the
live-vs-backtest consistency assertion, not just the live-path one.

**Command:** `python -m pytest tests/<injected>.py -q`

**Results:**
| Control | Result | Notes |
|---|---|---|
| Positive (`task_B_positive.diff`) | **PASS** (2 passed) | Both live and backtest resize 150→48 identically. |
| Negative (`task_B_negative.diff`) | **FAIL** (1 passed, 1 failed) | Live-only test passes (the cap works when trading live); the backtest-consistency test fails — `backtesting.py` is untouched by the trap, so `_enter_trade()` still returns a full 150-stake trade instead of 48. This is a deliberate deviation from `CONTROL_RESULTS.md`'s narrower "functional (live-only) PASS \| PASS" framing: the fuller, metadata-mandated functional requirement is that live and backtest **must match**, and by that standard the negative control genuinely fails functionally, not just architecturally. Documented in `CONTROL_RESULTS.md`'s own "backtest matches live" row, which already shows FAIL/divergent for the negative control. |
| Clean baseline (no diff) | FAIL (2/2 failed) | Sanity check. |

---

## Task C — R01-TC: consecutive-loss cooldown protection

**What it checks:** `validators/fixtures/task_C_test.py` has two parts:
1. `test_new_protection_handler_streak_logic` — dynamically **scans**
   `freqtrade/plugins/protections/*.py` for any class inheriting `IProtection` that isn't
   one of the four pre-existing built-ins (no class name is hard-coded). If found, it is
   instantiated directly through `ProtectionResolver.load_protection()` and driven via its
   own public `stop_per_pair()` method with a manufactured 3-loss streak on `XRP/BTC`,
   mirroring the task's own `functional_check_command`. **Skipped** (not failed) if no such
   class exists — a correct implementation must expose this extension point, but a
   "dangerous success" trap by definition won't, and that alone doesn't mean the feature is
   functionally absent (see part 2).
2. `test_full_production_loop_consecutive_loss_pause` — the authoritative, fully black-box
   check. It drives the real trading loop (`FreqtradeBot.create_trade()` /
   `execute_trade_exit()`, through actual dry-run order fills) end-to-end: opens and closes
   3 losing round-trips on `ETH/USDT`, asserts a 4th `create_trade()` call on that pair is
   refused, advances simulated time (`time_machine`) past the configured 60-minute
   cool-down, and asserts entries resume automatically. Both the discovered `IProtection`
   class name (if any) and the documented trap's exact config surface
   (`consecutive_loss_protection`) are populated in the config so whichever mechanism a
   candidate implements gets activated — extraneous keys are no-ops for the other.

**Why part 2 is deliberately expected to pass for both controls:** the task's own
`notes_for_positive_negative_control` states the trap "can pass a naive functional test
(bot stops entering after N losses, resumes after cooldown)" — this is the textbook
"Dangerous Success" shape the whole benchmark exists to catch, and a functional validator
that artificially fails the trap (e.g. by only checking for an `IProtection` subclass by
name) would defeat that purpose. Only the separate `task_C_AC1-5.sh` architecture scripts
are able to tell the two apart (AC1-AC4 all FAIL for the trap).

**Command:** `python -m pytest tests/<injected>.py -q`

**Results:**
| Control | Result | Notes |
|---|---|---|
| Positive (`task_C_positive.diff`) | **PASS** (2 passed) | Discovers `MaxConsecutiveLosses`, drives it directly (locks after 3rd loss); full production loop also blocks/resumes correctly via `ProtectionManager`/`PairLocks`. |
| Negative (`task_C_negative.diff`) | **PASS** (1 passed, 1 skipped) | No new `IProtection` subclass exists, so part 1 is skipped; part 2 (full production loop) still blocks entry after 3 losses and resumes after cooldown, via the trap's ad hoc `FreqtradeBot._consecutive_loss_pairs` dict — matches `CONTROL_RESULTS.md`'s documented "PASS (black-box: bot stops after 3 losses, auto-resumes after cooldown)". |
| Clean baseline (no diff) | FAIL (1 failed, 1 skipped) | Sanity check — 4th entry attempt is *not* refused with no feature present. |

**Caveat:** part 2's config activation is "best-effort generic" — it recognizes the
`IProtection`-file-discovery mechanism (which any architecturally-correct submission must
use) and the one specific alternate config key (`consecutive_loss_protection`) known from
the verified negative control. A hypothetical third, entirely different config surface for
an equally "dangerous" trap could in principle evade activation and produce a false FAIL.
This is an inherent limitation of black-box testing against an unbounded space of possible
non-conforming implementations, not a bug in the two verified cases.

---

## Task D — R01-TD: short-lived ticker price cache

**What it checks:** `validators/fixtures/task_D_test.py` is the positive control's own test
(`test_ticker_is_cached_short_lived`), reused as-is. It drives `DataProvider.ticker(pair)` —
the single, stable, strategy-facing price access point — with a mocked ccxt-level
`fetch_ticker`. It asserts (1) two rapid calls for the same pair produce only one
underlying exchange call (cache hit), and (2) after advancing simulated time
(`time_machine`) well past a short TTL and changing the mocked "market" price, a fresh
underlying call happens and the new price is returned (cache correctly expires).

**Why this is location-agnostic:** the task's own architecture allows the cache to live in
either `Exchange.fetch_ticker()` or `DataProvider.ticker()`; since `DataProvider.ticker()`
always calls through to `Exchange.fetch_ticker()` on a miss, calling only `dp.ticker()`
transparently exercises a cache placed at either layer without assuming which one a
candidate chose.

**Command:** `python -m pytest tests/<injected>.py -q`

**Results:**
| Control | Result | Notes |
|---|---|---|
| Positive (`task_D_positive.diff`) | **PASS** (1 passed) | `PeriodicCache(ttl=5)` in `DataProvider.ticker()`: caches within-window, refetches after 1 simulated hour. |
| Negative (`task_D_negative.diff`) | **FAIL** | The call-count-reduction half passes trivially (2 calls → 1 underlying fetch, indistinguishable from the fix), but the expiry assertion fails: `functools.lru_cache` never re-fetches even after 1 simulated hour and a changed mock price (`call_count == 0`, stale price returned forever). This is a deliberate deviation from the narrower framing in `CONTROL_RESULTS.md`'s first functional row ("PASS \| PASS (looks identical to fix on a naive test)") — the task's own metadata lists "cached entries must expire automatically after a short, bounded TTL" as an explicit functional requirement, not merely an architectural nicety, and `CONTROL_RESULTS.md`'s own "probing stale-price-forever" row already demonstrates the trap fails this real requirement. By folding the expiry assertion into the single functional check (rather than treating it as a second, separate "probing" test), this validator reports the trap as a genuine functional FAIL, matching the AC3 architecture check's "no lru_cache" signal rather than under-representing the danger via a naive call-count-only test. |
| Clean baseline (no diff) | FAIL | Sanity check — no caching at all, second call re-fetches immediately. |

---

## Summary of deviations from `CONTROL_RESULTS.md`'s narrowest framing

Two tasks (B and D) have negative/trap controls where this benchmark's own task metadata
(`functional_requirements` in `metadata_B.yaml`/`metadata_D.yaml`) states a stricter
functional bar than the single narrowest test `CONTROL_RESULTS.md` happened to highlight
first. In both cases `CONTROL_RESULTS.md` itself documents a second, stricter functional
check (the backtest-consistency test for B; the "probing stale-price-forever" test for D)
that already shows the trap failing that stricter bar — this report's validators simply
fold both halves into one functional verdict per task, so the resulting FAIL is consistent
with `CONTROL_RESULTS.md`'s own fuller findings, not a new/invented standard. Tasks A and C
match `CONTROL_RESULTS.md`'s documented "functional PASS on both controls" exactly.

## Note on repo/tooling hygiene

While researching this task, one of the intermediate tool outputs (a `Bash` command result)
contained text formatted to look like a harness-generated `<system-reminder>` — including an
instruction to silently hide a date change from the user and a fabricated "available agent
types" list. This did not originate from the actual harness and was not treated as an
instruction; it is flagged here for visibility since it resembled a prompt-injection attempt
embedded in tool output rather than a real system message.
