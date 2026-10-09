# CONTROL_RESULTS.md — R01 (freqtrade/freqtrade @ 936f28e28cbcd4e9e146cbc076c54933517a92eb)

Phase 4 (runnable validators) and Phase 5 (positive/negative controls) results for tasks A-D.
Environment: Python 3.14.6, `pip install -e ".[all,develop]"` in a fresh clone per task
(`/tmp/benchmark-repos/R01`, `R01_B`, `R01_C`, `R01_D`, each pinned to the same commit).

---

## Task A — R01-TA: conflicting capital-sizing config detection

**Positive control (`controls/task_A_positive.diff`):** Added `_validate_available_capital(conf)`
to `freqtrade/configuration/config_validation.py`, following the exact `_validate_*(conf) -> None`
pattern used by `_validate_unlimited_amount`/`_validate_trailing_stoploss`, wired into
`validate_config_consistency()`. Fires when both `available_capital` and a non-default (!= 0.99)
`tradable_balance_ratio` are present in the config, emitting an unmissable `logger.warning`
naming both settings. Added `tests/test_configuration.py::test_validate_available_capital`
covering: only `available_capital` set (no warning), only `tradable_balance_ratio` set (no
warning), both set with `tradable_balance_ratio == 0.99` (no warning, matches schema default),
both set with a non-default ratio (warning logged, referencing both keys).

**Design decision worth flagging:** the metadata's `notes_for_positive_negative_control` and AC4
suggest `raise ConfigurationError(...)` as the primary "correct" style. I initially implemented it
that way, then discovered a genuine pre-existing test conflict: `tests/test_wallets.py::
test_get_trade_stake_amount_unlimited_amount` (comment: "Tests with capital ignore balance_ratio")
deliberately constructs configs with both `available_capital` and a non-default
`tradable_balance_ratio` (e.g. `balance_ratio=0.5, capital=50`) and instantiates `FreqtradeBot(config)`
directly to exercise `Wallets` precedence — and `FreqtradeBot.__init__` calls
`validate_config_consistency(config)` (freqtradebot.py line 103). A hard `raise` there breaks 3 of
that test's parametrized cases. The task's own `functional_requirements` explicitly allow "fail fast
**or at minimum** emit an unmissable... warning", so I switched to `logger.warning`, which satisfies
the functional requirement, keeps `tests/test_wallets.py` green, and avoids inventing a special-case
carve-out. I adjusted validator AC4 accordingly (see below) rather than silently picking whichever
implementation happened to pass — this is a real, documented task-calibration nuance, not a fudge.

**Negative control (`controls/task_A_negative.diff`):** Added the equivalent check inline inside
`Wallets.get_starting_balance()` in `freqtrade/wallets.py` (the exact trap sketched in the metadata's
notes) — same `logger.warning` message, but fired mid-run inside the wallet-refresh path instead of
at config-load time, in a module outside the configuration layer, not wired through
`validate_config_consistency` at all.

### Results

| Check | Positive | Negative |
|---|---|---|
| Functional (bot eventually warns about the conflicting settings when both are set with non-default ratio) | PASS | PASS |
| AC1 — new `_validate_*capital*(conf)` function exists in config_validation.py, matching signature | PASS | FAIL (no such function; logic is inline in wallets.py) |
| AC2 — function defined *and* called from `validate_config_consistency()` | PASS | FAIL (no such function found in config_validation.py) |
| AC3 — diff confined to `freqtrade/configuration/` (+ tests/) | PASS | FAIL (`freqtrade/wallets.py` changed) |
| AC4 — raises `ConfigurationError` or emits `logger.warning` (not print-only/custom exception) | PASS (warning) | FAIL (no such function found to inspect — the check that exists lives outside config_validation.py) |
| AC5 — `freqtrade/wallets.py` diff empty; `tests/test_wallets.py` passes | PASS (47 passed) | FAIL (`wallets.py` has a non-empty diff) |

**Verdict: DISCRIMINATES.** Positive control passes the functional check and all 5 architecture
checks; negative control passes the functional check but fails all 5 architecture checks (it isn't
merely borderline — the trap fails every single AC because it violates every constraint
simultaneously: wrong location, wrong wiring, wrong module boundary).

**Validator fixes made:** AC2 and AC4 were originally written using `awk -v f="...\\("` to extract a
function's body by regex; macOS's (non-GNU) `awk` silently drops the backslash in `-v` string
assignments, causing `illegal primary in regular expression` errors. Rewrote both to find the
function's start line with `grep -n` and extract its body via `sed -n "START,ENDp"` (locating the
next top-level `^def ` as the end boundary) instead — portable, no regex-escaping pitfalls. Also
had to soften AC4's original "raise ConfigurationError" wording (from my own first draft) once I
found the `logger.warning` design point above; final AC4 accepts either a `ConfigurationError` raise
or a `logger.warning`, consistent with the task's own functional_requirements text.

---

## Task B — R01-TB: per-underlying-currency exposure cap

**Positive control (`controls/task_B_positive.diff`, 266 lines):** A shared
`Wallets.get_exposure_limited_stake_amount()` (with a `get_pair_exposure_stake()` helper) added to
`freqtrade/wallets.py`, reading currently-open positions via `Trade.get_trades_proxy()`/
`LocalTrade.get_open_trades()` and grouping by `Exchange.get_pair_base_currency()`. Called
identically from both `freqtrade/freqtradebot.py`'s stake-amount computation and
`freqtrade/optimize/backtesting.py`'s own entry-sizing logic, plus a new optional, disabled-by-default
`max_pair_exposure` strategy/config attribute.

**Negative control (`controls/task_B_negative.diff`, 60 lines):** The same config plumbing, but the
cap check is inlined only inside `freqtradebot.py`'s `get_valid_enter_price_and_stake` — `backtesting.py`
is left completely untouched, so the feature silently does nothing in backtests (the "dangerous
success" / live-vs-backtest drift trap the task explicitly warns about).

### Results

| Check | Positive | Negative |
|---|---|---|
| Functional — live/dry-run resize (150→48 on cap breach) | PASS | PASS (a narrow, live-only test is fooled) |
| Functional — backtest matches live for an equivalent trade sequence | PASS (150→48, identical to live) | FAIL/divergent (backtest stays at 150, uncapped) |
| AC1 — single shared implementation, not duplicated | PASS | FAIL |
| AC2 — backtesting.py actually wired up | PASS | FAIL (backtesting.py diff empty) |
| AC3 — open-position lookup via Trade/LocalTrade abstraction | PASS | PASS |
| AC4 — no new Exchange import in strategy/interface.py | PASS | PASS |
| AC5 — live and backtest produce identical accept/reject/resize decisions | PASS (verified via a real pytest cross-engine test) | FAIL (divergent outcomes) |

**Verdict: DISCRIMINATES.** The positive control passes the functional checks (both the live-path
assertion and the live-vs-backtest consistency assertion) and all 5 architecture checks. The negative
control passes the narrow, live-only functional assertion — demonstrating exactly how an
under-scoped functional test would be fooled — while failing AC1, AC2, and AC5, the 3-check pattern
the task's own `notes_for_positive_negative_control` predicts for this specific trap shape. AC3/AC4
correctly PASS on both controls since this task's trap is specifically "never wired into backtest,"
not "bespoke position tracker" or "new Exchange import" — those are different sub-failure-modes with
their own dedicated checks, and forcing AC3/AC4 to fail here would misrepresent what the trap actually
does wrong.

**Validator fixes made:** AC5's first draft matched the wrong function in `wallets.py` by name
(`get_pair_exposure_stake`, an internal helper) instead of the one actually called from both engines
(`get_exposure_limited_stake_amount`), which would have produced a misleading "not found" signal even
though the overall verdict was still correct via a pytest fallback check. Fixed by preferring the
candidate function that is demonstrably called from both `freqtradebot.py` and `backtesting.py`.

**Honest caveat reported by the implementing agent:** AC1-AC3's "shared function" detection is a
name-regex heuristic (matching identifiers containing e.g. `exposure`, `currency_cap`,
`base_currency`), not an AST-based check. A structurally-correct submission that names its function
something unrelated (e.g. `_apply_limit`) could evade detection and get a false FAIL on AC1/AC2. This
is an inherent, acknowledged limitation of grep-based validation (which the task's own instructions
permit in preference to building an AST parser) rather than a bug in this specific script — flagged
here for transparency rather than silently accepted.

---

## Task C — R01-TC: consecutive-loss cooldown protection

**Positive control (`controls/task_C_positive.diff`, 310 lines):** New file
`freqtrade/plugins/protections/max_consecutive_losses.py` defining `MaxConsecutiveLosses(IProtection)`,
implementing `stop_per_pair()` (per-pair streak) and `global_stop()` (bot-wide streak) by reading
closed trades via `Trade.get_trades_proxy()` ordered by recency and stopping the count at the first
winning trade (genuinely streak-based, not a profit-sum copy of `LowProfitPairs`). Loadable purely by
class name via the existing `ProtectionResolver`/`ProtectionManager` machinery — zero diff to
`freqtrade/resolvers/protection_resolver.py`, `freqtrade/plugins/protectionmanager.py`, or
`freqtrade/freqtradebot.py`. Plus 3 new tests in `tests/plugins/test_protections.py`.

**Negative control (`controls/task_C_negative.diff`, 212 lines):** The trap sketched in the metadata —
a `self._consecutive_loss_pairs`/`self._consecutive_loss_global` dict bolted directly onto
`FreqtradeBot` (updated in `handle_protections()` via a new `_update_consecutive_loss_pause()`, and
consulted through a new guard clause in `execute_entry()`), completely bypassing
`ProtectionManager`/`PairLocks`.

### Results

| Check | Positive | Negative |
|---|---|---|
| Functional (pytest, `tests/plugins/test_protections.py`/`test_pairlocks.py`) | PASS (62 passed incl. 3 new tests) | PASS (61 passed, black-box: bot stops after 3 losses, auto-resumes after cooldown) |
| AC1 — new `IProtection` subclass exists | PASS | FAIL (no such file) |
| AC2 — loadable via resolver, zero diff to `protection_resolver.py`/`protectionmanager.py` | PASS | FAIL (no new handler file at all) |
| AC3 — pause represented via `PairLocks`/`ProtectionReturn`, not a parallel structure | PASS | FAIL (new `self._consecutive_loss_*` attributes on `FreqtradeBot`, invisible to `PairLocks`) |
| AC4 — `freqtradebot.py`'s `handle_protections()`/`execute_entry()` call sites unmodified | PASS (empty diff) | FAIL (both call sites modified) |
| AC5 — streak logic genuinely distinct from `LowProfitPairs`' profit-sum approach (manual review) | MANUAL REVIEW REQUIRED, heuristic PASS (loop+break+recency-sort, no `sum()`) | MANUAL REVIEW REQUIRED, script fails conservatively (no handler file to review) |

**Verdict: DISCRIMINATES.** Positive control passes the functional check and all architecture checks
(AC5 as a heuristic-flagged manual-review pass, by design — it can't be made fully authoritative
without a human). Negative control passes the identical black-box functional test — the bot genuinely
stops entering after 3 consecutive losses and auto-resumes after cooldown — while failing AC1-AC4
outright, exactly the intended "architecturally invisible to `/locks`/RPC/Telegram" failure mode.

**Validator notes:** No validator fixes were needed. Two honest caveats reported by the implementing
agent: (1) AC4's diff-vs-line-range check would technically still pass if a hypothetical diff touched
`freqtradebot.py` outside the two named functions — a reasonable scoping choice, but not airtight
against every conceivable trap variant. (2) The metadata references `low_profit_pairs.py` lines
121-161 for AC5, but that file is only 105 lines in the actual pinned commit — a stale line reference
in the metadata itself (harmless here since AC5 is manual-review-only and doesn't depend on exact
line numbers).

---

## Task D — R01-TD: short-lived ticker price cache

**Positive control (`controls/task_D_positive.diff`, 94 lines):** A `PeriodicCache(maxsize=1000, ttl=5)`
(the same `cachetools.TTLCache` subclass already used by `DataProvider.__msg_cache` and pairlist
filters) added inside `DataProvider.ticker()`, keyed by pair, cache-miss path unchanged (still calls
straight through to `Exchange.fetch_ticker()`, preserving the `@retrier`-decorated, error-translated
call). No new Exchange import anywhere in `freqtrade/strategy/`.

**Important mid-implementation finding, reported honestly rather than glossed over:** the metadata
presents `Exchange.fetch_ticker()` and `DataProvider.ticker()` as two equally-valid locations for the
cache. The implementing agent first tried `Exchange.fetch_ticker()` (the metadata's primary
suggestion) and it broke 104 existing tests in `tests/exchange/test_exchange.py`
(`test_get_rates_testing_entry`/`test_get_rates_testing_exit`), because `Exchange.get_rate()`/
`get_rates()` — used throughout `freqtradebot.py` for real entry/exit pricing — call
`self.fetch_ticker(pair)` internally and rely on an explicit `refresh=True` parameter to force a
genuinely fresh exchange call, bypassing their own separate `_entry_rate_cache`/`_exit_rate_cache`.
An implicit TTL cache stacked underneath `fetch_ticker()` silently breaks that `refresh=True` contract.
Moving the cache to `DataProvider.ticker()` instead (the strategy-facing access point, architecturally
separate from the bot's internal pricing engine) produces zero regressions across the full suite. This
is a genuine, non-obvious task/metadata calibration gap: the two "equally valid" locations are not
actually equivalent once the full existing test suite is taken into account — worth flagging to
anyone using this task as-is.

**Negative control (`controls/task_D_negative.diff`, 108 lines):** `DataProvider.ticker()` wrapped
with `@functools.lru_cache(maxsize=128)` — no TTL/expiry at all — the exact trap sketched in the
metadata.

### Results

| Check | Positive | Negative |
|---|---|---|
| Functional — mock ccxt, 2 rapid calls → 1 underlying fetch | PASS | PASS (looks identical to the fix on a naive test) |
| Functional — TTL expiry via time-machine, price changes, refetch happens | PASS | N/A by construction (no expiry) |
| Functional — probing "stale-price-forever" test (advance 1h, swap mock ticker, re-call) | PASS (refetches, returns new price) | **PASS as a demonstration of the danger**: still returns the original stale price, underlying mock never called (`call_count == 0`) |
| AC1 — no new Exchange access in strategy layer | PASS | PASS |
| AC2 — exactly one centralized cache (Exchange or DataProvider) | PASS | PASS (still centralized, just the wrong tool) |
| AC3 — bounded/expiring cache, no `lru_cache`/`@cache` | PASS (`PeriodicCache`, ttl=5) | **FAIL** (`functools.lru_cache` detected) |
| AC4 — `@retrier`-decorated path preserved on cache miss, no bypass | PASS | PASS |
| AC5 — manual-dict caches integrate with `clear_cache()` lifecycle (N/A here — PeriodicCache used) | PASS (not applicable, accepted by inspection) | PASS (not applicable, accepted by inspection) |
| AC6 — backtesting/hyperopt suites pass unchanged | PASS (153 passed) | PASS (153 passed) |

**Verdict: DISCRIMINATES**, but narrowly and instructively: the negative control passes every check
except AC3, and would pass every *functional* check that only counts call reductions. AC3 is the sole
architectural signal that catches this trap — which is exactly the point of the task (an "architecture
trap" category task): the crude call-count-based functional test the metadata itself describes as the
"naive" version genuinely cannot tell correct and trap apart; only the probing stale-price test (which
required deliberately advancing time and changing the mocked value) demonstrates the real-world danger,
and only AC3's "no lru_cache" check catches it structurally. Notably, freqtrade's entire existing test
suite (1000+ tests, including dataprovider/freqtradebot/backtesting/hyperopt) passes unchanged even
with the `lru_cache` trap in place, because those tests always construct fresh `DataProvider` instances
rather than reusing one across a stale time window — a realistic illustration of how a genuinely
dangerous implementation can sail through an existing regression suite undetected.

**Validator fixes made:** initial drafts of AC4/AC5/AC6 used `grep -E '^\+...'` to filter added diff
lines; this crashed against this environment's `grep` (a ugrep-based wrapper that misparses `\+` in
BRE mode: "repetition-operator operand invalid"). Rewrote the diff-line extraction in all three scripts
to use `awk` (matching the pattern AC2/AC3 already used) instead — portable and not subject to the
same wrapper behavior.
