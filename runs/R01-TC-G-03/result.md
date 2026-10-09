# R01-TC-G-03

Condition: goga
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Cost: $1.280262
Duration: 246745ms, turns: 42

## Agent's own summary

# Change Plan

## Task Classification
**Extension** — net-new `IProtection` handler added to an existing extension-point cell. No existing code is modified.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `freqtrade/plugins/protections` | `max_consecutive_losses_protection.py` (new), `CODEMANIFEST` (append entry) | New `MaxConsecutiveLosses(IProtection)` class + one new body entry documenting it |
| Docs (non-cell) | `docs/includes/protections.md` | Add `MaxConsecutiveLosses` to the available-protections list, its own subsection, and mention in the combined example |
| Tests (non-cell) | `tests/plugins/test_protections.py` | Add `MaxConsecutiveLosses` to `AVAILABLE_PROTECTIONS`, add per-pair/global/threshold-not-met/cooldown-expiry test cases |

No changes to `freqtrade/persistence`, `freqtrade/exchange`, `freqtrade/plugins` (manager), or `freqtrade/resolvers` — all confirmed generic over any `IProtection` subclass.

## Root Cause Analysis
None of the four existing protections (`CooldownPeriod`, `StoplossGuard`, `LowProfitPairs`, `MaxDrawdown`) inspect trade *sequence* — they evaluate aggregate sums/counts within a time window or just the single latest trade. There is no handler that reacts to an unbroken run of losing trades, which is exactly the operational gap costing users money (bot keeps re-entering a pair after N losses in a row).

## Trace Summary
`FreqtradeBot.handle_protections` → `ProtectionManager.stop_per_pair`/`global_stop` → loops over all configured `IProtection` handlers generically → on lock, `PairLocks.lock_pair(...)` → RPC `PROTECTION_TRIGGER(_GLOBAL)` message to Telegram/webhook. This entire path is handler-agnostic, so the new class needs no wiring beyond existing itself and being named in a strategy's `protections` config list (`ProtectionResolver` loads by class name dynamically). Critical constraint: `Trade.get_trades_proxy` returns an **unsorted** list — the new handler must sort by `close_date` before walking the streak (established pattern: `CooldownPeriod` does the same via `max(..., key=lambda t: t.close_date)`).

## Change Strategy

1. **New file** `freqtrade/plugins/protections/max_consecutive_losses_protection.py`:
   - Class `MaxConsecutiveLosses(IProtection)`, `has_global_stop = True`, `has_local_stop = True`.
   - `__init__`: reads `max_allowed_consecutive_losses` (int, default 3) and `only_per_pair` (bool, default `False`, disables `global_stop` — mirrors `StoplossGuard._disable_global_stop`) from `protection_config`. Reuses base-class `stop_duration`/`stop_duration_candles`/`lookback_period`/`lookback_period_candles` — no new duration knobs invented.
   - Shared private method `_max_consecutive_losses(date_now, pair, side) -> ProtectionReturn | None`:
     - Fetch trades via `Trade.get_trades_proxy(pair=pair, is_open=False, close_date=look_back_until)` (pair is `None` for the global case, matching `StoplossGuard`'s `_stoploss_guard(date_now, None, side)` pattern).
     - Sort by `close_date` ascending; if fewer trades exist than the configured threshold, return `None` early.
     - Walk from the end (most recent) backwards, counting trades with `close_profit is not None and close_profit < 0`; stop at the first non-loss.
     - If streak count `>= max_allowed_consecutive_losses`: build `ProtectionReturn(lock=True, until=self.calculate_lock_end(streak_trades), reason=self._reason(streak_count))`, where `streak_trades` is just the trades in the streak (so the lock's `until` is anchored to the last losing trade's close time, consistent with other handlers).
   - `global_stop`: returns `None` if `only_per_pair`, else calls `_max_consecutive_losses(date_now, None, side)`.
   - `stop_per_pair`: calls `_max_consecutive_losses(date_now, pair, side)`.
   - `short_desc()` and `_reason()` follow the exact string style of `StoplossGuard`/`LowProfitPairs` (so RPC/Telegram messages read consistently with existing protection-trigger notifications).
2. **CODEMANIFEST**: append `"IProtection::MaxConsecutiveLosses()"` body entry (same shape as the existing `StoplossGuard` entry), documenting purpose, config knobs, and the sort-before-walk algorithm requirement.
3. **Docs**: add a `#### Max Consecutive Losses` subsection to `docs/includes/protections.md`, add to `### Available Protections` bullet list, and add one entry to the combined example strategy at the bottom.
4. **Tests**: add `MaxConsecutiveLosses` to `AVAILABLE_PROTECTIONS`, add scenarios: (a) per-pair lock triggers after N consecutive losses, (b) a win breaks the streak so no lock, (c) global lock triggers across pairs, (d) `only_per_pair=True` suppresses global lock, (e) lock expires automatically after `stop_duration` elapses (existing `PairLocks` behavior, exercised through this handler).

## Specification Impact
`freqtrade/plugins/protections/CODEMANIFEST` body section gains one new type entry (`IProtection::MaxConsecutiveLosses()`), styled identically to the existing `IProtection::StoplossGuard()` entry. Header (`Imports`/`Usages`/`Annotations`) is unchanged — the new class needs no imports beyond what the cell already imports (`LocalTrade`, `timeframe_to_minutes`, both inherited via `IProtection`), and the existing `extension_point` annotation already covers how to add a handler. Footer unchanged (no reason to alter `Author`/`CreatedAt`/`Description` — this is an incremental addition, not a rewrite of the cell's purpose).

## Usage Impact
None. No `.usages/*.md` files exist for this cell or project-wide, and this addition doesn't introduce one (task doesn't require new consumer-facing practice docs beyond the standard `docs/includes/protections.md`, which is the project's existing operator-facing documentation channel, not a Goga `.usages` practice file).

## Compatibility Verification
**Backward compatible.** No existing class, function, signature, file path, or CODEMANIFEST entry is modified. All changes are additive (new file, new class, new manifest body entry, new doc subsection, new test cases, one additive line in `AVAILABLE_PROTECTIONS`). Existing protections' behavior, existing tests, and existing manifest guarantees are untouched.

## Test Strategy
Follow `tests/plugins/test_protections.py`'s existing pattern (uses `generate_mock_trade(...)` + `get_patched_freqtradebot` + asserts on `PairLocks.is_pair_locked`/`is_global_lock` and log messages via `log_has_re`):
- **Per-pair trigger**: N mock losing trades (in order) for one pair with `max_allowed_consecutive_losses=N` → pair gets locked.
- **Streak broken by a win**: N-1 losses then a win then losses again (total losses ≥ N but not consecutive) → no lock, proving it's streak-based not aggregate-based (this is the core differentiator from `StoplossGuard`).
- **Threshold not met**: fewer consecutive losses than configured → no lock.
- **Global trigger**: consecutive losses across different pairs → global lock (all pairs), when `only_per_pair=False`.
- **`only_per_pair=True`**: consecutive losses across pairs do not trigger a global lock, but still lock the specific pair.
- **Cooldown auto-expiry**: after `stop_duration` elapses, pair/global lock no longer active (reuses existing `PairLocks` TTL mechanism — a lightweight assertion, not new logic to test in depth since it's inherited from `calculate_lock_end`/`PairLocks`).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Relying on `get_trades_proxy`'s return order (silently wrong streak) | Medium (easy to forget given other handlers don't need to sort) | High (silently wrong lock decisions) | Explicit `sorted(trades, key=lambda t: t.close_date)` in implementation; covered by a test with intentionally out-of-order mock trade creation if feasible |
| `close_profit` is `None` for some closed trades (edge case) causing `TypeError` on `< 0` | Low | Medium (crash during protection evaluation) | Guard with `close_profit is not None` before comparison, matching defensive style already used in `LowProfitPairs` |
| Config key collision/naming confusion with `trade_limit` | Low | Low (operator confusion, not a bug) | Use distinct `max_allowed_consecutive_losses` key (matches `max_allowed_drawdown` convention) instead of overloading `trade_limit` |
| Docs/test drift if `AVAILABLE_PROTECTIONS` list or combined example isn't updated | Low | Low (cosmetic/test gap) | Explicitly included as a change-strategy step, not left implicit |

---

Do you approve the plan? Proceed to implementation?
