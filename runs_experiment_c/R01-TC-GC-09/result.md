# R01-TC-GC-09

Condition: goga_native_architecture
Base tag: condition-c-r01-v1
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: False
Cost: $1.5950624999999998
Duration: 265221ms, turns: 50

## Agent's own summary

# Change Plan

## Task Classification
**Feature (extension)** — new `IProtection` concrete handler added to an existing extension-point cell; no existing type, signature, or behavior is modified.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `freqtrade/plugins/protections` | `max_consecutive_losses.py` (new), `CODEMANIFEST` | New `MaxConsecutiveLosses(IProtection)` class; new CODEMANIFEST type entry documenting it |
| `tests/plugins/test_protections.py` (non-cell) | same file | Add `"MaxConsecutiveLosses"` to `AVAILABLE_PROTECTIONS`; add new test functions |
| `docs/includes/protections.md` (non-cell) | same file | New subsection + top-list bullet documenting config/semantics |

No other cell changes: `ProtectionManager` and `ProtectionResolver` are confirmed generic (dynamic name-based loading, flag-driven dispatch) and require zero edits.

## Root Cause Analysis
Not a defect — the cell's own CODEMANIFEST already names "consecutive losses" as an intended risk-control category that was never implemented. Users currently have no way to detect a true win/loss streak (as opposed to `StoplossGuard`'s stoploss-exit-only count or `LowProfitPairs`' summed-profit check), forcing manual intervention after a bad streak.

## Trace Summary
`ProtectionManager.global_stop`/`stop_per_pair` (`protectionmanager.py:50-88`) → dispatch to handler based on `has_global_stop`/`has_local_stop` → handler returns `ProtectionReturn | None` → on lock, `PairLocks.lock_pair(pair_or_"*", until, reason, side)` persists the lock, which is the existing, unchanged notification/enforcement surface (already read by RPC/API/Telegram elsewhere in the bot). The new class plugs into this path exactly like `StoplossGuard` does today — no new wiring required.

## Change Strategy

1. **Create `freqtrade/plugins/protections/max_consecutive_losses.py`**:
   - `class MaxConsecutiveLosses(IProtection):` with `has_global_stop = True`, `has_local_stop = True`.
   - `__init__`: call `super().__init__(config, protection_config)`; read `self._trade_limit = protection_config.get("trade_limit", 2)` (streak threshold; default 2 losses, one lower than `StoplossGuard`'s default of 10 since a *consecutive* streak is a stronger/rarer signal than a raw count) and `self._only_per_side = protection_config.get("only_per_side", False)`.
   - Private helper `_streak_matches(pair: str | None, date_now: datetime, side: LongShort) -> ProtectionReturn | None`:
     - `look_back_until = date_now - timedelta(minutes=self._lookback_period)`
     - `trades = Trade.get_trades_proxy(pair=pair, is_open=False, close_date=look_back_until)` — `pair=None` naturally returns all pairs for the global-scope call, matching `StoplossGuard`'s own `_stoploss_guard(date_now, None, side)` precedent.
     - If `self._only_per_side`, filter `trades = [t for t in trades if t.trade_direction == side]` (same convention/order as `StoplossGuard`/`LowProfitPairs`).
     - Explicitly sort: `trades = sorted(trades, key=lambda t: t.close_date)` — required because `get_trades_proxy` is documented as unsorted.
     - Walk from the end (most recent) backwards, accumulating a `streak` list while `trade.close_profit is not None and trade.close_profit < 0`; stop at the first trade that fails this condition or once `len(streak) == self._trade_limit`.
     - If `len(streak) < self._trade_limit`: return `None`.
     - Else: `until = self.calculate_lock_end(streak)`; return `ProtectionReturn(lock=True, until=until, reason=self._reason(), lock_side=(side if self._only_per_side else "*"))`.
   - `short_desc()`: `f"{self.name} - Max Consecutive Losses Protection, locks pairs after {self._trade_limit} consecutive losses within {self.lookback_period_str}."` (mirrors `StoplossGuard`/`LowProfitPairs` phrasing).
   - `_reason()`: `f"{self._trade_limit} consecutive losses in {self._lookback_period} min, locking {self.unlock_reason_time_element}."` (mirrors `StoplossGuard._reason`).
   - `global_stop(date_now, side, starting_balance)`: `return self._streak_matches(None, date_now, side)`.
   - `stop_per_pair(pair, date_now, side, starting_balance)`: `return self._streak_matches(pair, date_now, side)`.
   - Include a `self.log_once(...)` call on lock, matching sibling handlers' logging convention (`logger.info` level), for observability parity.

   **Design call — `only_per_side`:** included. Justification: both handlers with an identical "scan closed trades, apply a stateful check" shape (`StoplossGuard`, `LowProfitPairs`) already expose this flag; `stop_per_pair`/`global_stop` already receive `side` as a mandatory parameter regardless, so supporting it costs one `if` and one constructor line, and omitting it would be an unexplained inconsistency with the two closest sibling handlers rather than a deliberate simplification.

2. **Update `freqtrade/plugins/protections/CODEMANIFEST`**: add one new body entry `"IProtection::MaxConsecutiveLosses()"` with `location: max_consecutive_losses.py` and an `annotations:` block matching the length/style of the existing `MaxDrawdown`/`StoplossGuard` entries — stating it locks trading (globally or per-pair) after `trade_limit` consecutive losing trades within the lookback window, resetting on any non-losing trade.

3. **Update `tests/plugins/test_protections.py`**:
   - Add `"MaxConsecutiveLosses"` to `AVAILABLE_PROTECTIONS` (line 15) — this list feeds `test_protectionmanager`, which will now also generically instantiate and sanity-check the new handler.
   - Add `test_max_consecutive_losses` (per-pair): generate N-1 losing trades for a pair → assert not locked; add one more losing trade reaching `trade_limit` → assert `stop_per_pair` locks; verify a winning trade before the streak resets the count (streak must not accumulate across a win).
   - Add `test_max_consecutive_losses_global`: same streak built across *different* pairs → assert `global_stop` locks all pairs, `stop_per_pair` for an unrelated third pair is unaffected by per-pair state but *is* affected by the global lock once set (mirrors `test_LowProfitPairs`'s global/per-pair interplay assertions).
   - Both tests use `generate_mock_trade(..., profit_rate=<0.9 or similar> )` for losses and `profit_rate=1.15` for the intervening win, following existing sign-convention usage in the file.

4. **Update `docs/includes/protections.md`**:
   - Add a bullet to the top protections list (after the `CooldownPeriod` bullet, alphabetically/logically grouped with the other trade-history-based guards): `` * [`MaxConsecutiveLosses`](#max-consecutive-losses) Stop trading if N consecutive losing trades occur, per pair or bot-wide. ``
   - Add a new `#### MaxConsecutiveLosses` subsection after the `LowProfitPairs` subsection (before "All protections can be combined..."), with a config example (`method`, `trade_limit`, `stop_duration`, `lookback_period`, `only_per_side`) and prose explaining the per-pair vs. global-stop distinction, matching the style/length of the `StoplossGuard`/`LowProfitPairs` subsections.

## Specification Impact
`freqtrade/plugins/protections/CODEMANIFEST` **Body** section gains exactly one new type declaration (additive). **Header** (`Imports`/`Usages`/`Annotations`) is unchanged — no new import is needed (the new class uses only `Trade`, already imported at the cell level via the existing `LocalTrade` import path and direct `freqtrade.persistence` import pattern used by sibling files, not a manifest-level `Imports` entry since concrete handler files import directly in Python, same as `StoplossGuard`/`LowProfitPairs` do today). **Footer** unchanged.

## Usage Impact
None. The cell declares no `Usages`/`.usages` practices (confirmed in Investigation Report), so there is nothing to reconcile at the usage layer.

## Compatibility Verification
**Backward compatible.** No existing file, class, method signature, or CODEMANIFEST entry is altered — only additive changes (new file, new CODEMANIFEST type entry, new test cases, new doc subsection). Existing tests, existing protection configs, and existing lock behavior are untouched. `AVAILABLE_PROTECTIONS` is extended, not restructured, so `test_protectionmanager`'s existing assertions continue to hold for all pre-existing handlers.

## Test Strategy
- **Regression safety**: existing `test_protectionmanager` continues to loop over `AVAILABLE_PROTECTIONS`, now including `MaxConsecutiveLosses`, exercising the generic `has_global_stop`/`has_local_stop is None-check` path for the new handler automatically.
- **New behavior coverage**:
  - Per-pair lock triggers exactly at `trade_limit` consecutive losses, not before.
  - A winning trade (`close_profit >= 0`) interrupts/resets the streak count (the core semantic differentiator vs. `LowProfitPairs`).
  - Global-stop triggers on a streak accumulated across different pairs (bot-wide semantics, not tied to one pair).
  - `only_per_side` filtering behaves like the analogous `StoplossGuard`/`LowProfitPairs` tests (parametrized `True`/`False`).
  - Trades outside `lookback_period` do not count toward the streak (consistent with sibling handlers' existing windowing tests).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `get_trades_proxy` returns unsorted trades, streak computed on wrong order | Medium (easy to overlook) | High (wrong lock decisions) | Explicit `sorted(trades, key=lambda t: t.close_date)` before streak walk, called out explicitly in implementation step |
| Off-by-one in "reaches `trade_limit`" boundary | Low | Medium | Dedicated boundary test (N-1 losses → no lock, Nth loss → lock) |
| `close_profit is None` for a closed trade (edge case) | Low | Low (would crash comparison) | Guard with `trade.close_profit is not None and trade.close_profit < 0` in the streak condition |
| New handler name collides with backtest reporting's unrelated `max_consecutive_losses` stat key | Very Low | Low | Different cell/namespace/construct kind (Python class vs. dict key in `optimize_reports`), confirmed no import path connects them |
| Doc/CODEMANIFEST drift after future edits (non-cell-governed docs/tests) | Low | Low | Will be checked in Drift Analysis (Step 9) despite not being CODEMANIFEST-enforced |

Do you approve the plan? Proceed to implementation?
