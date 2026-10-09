# R01-TC-BF-05

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: False
Cost: $1.5484608000000002
Duration: 250222ms, turns: 44

## Agent's own summary

# Change Plan

## Task Classification
**Feature** — new extension-point handler (additive; no existing behavior modified).

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| freqtrade/plugins/protections | `max_losses_in_a_row.py` (new), `CODEMANIFEST` (append type) | New `IProtection` subclass `MaxLossesInARow`; CODEMANIFEST body gains one entry |
| docs (not a goga cell) | `docs/includes/protections.md` | Add to "Available Protections" list + new documented section |
| tests (not a goga cell) | `tests/plugins/test_protections.py` | New test cases + append to `AVAILABLE_PROTECTIONS` |

## Root Cause Analysis
No existing handler tracks an unbroken run of consecutive losing trades; all four existing handlers use either a bounded lookback-window trade count, an equity-drawdown calculation, or "most recent trade only." (Full detail in Investigation Report above.)

## Trace Summary
`freqtradebot.handle_protections` → `ProtectionManager.stop_per_pair`/`global_stop` → iterates all handlers with `has_local_stop`/`has_global_stop` → new handler's `stop_per_pair`/`global_stop` return `ProtectionReturn` → `PairLocks.lock_pair` → generic `PROTECTION_TRIGGER(_GLOBAL)` RPC message. No new wiring needed outside the handler itself.

## Change Strategy
1. **New file** `freqtrade/plugins/protections/max_losses_in_a_row.py`:
   - Class `MaxLossesInARow(IProtection)`, `has_global_stop = True`, `has_local_stop = True`.
   - `__init__`: reads `trade_limit` (default 4 — the consecutive-loss threshold), `required_profit` (default 0.0 — profit below this counts as a loss), `only_per_pair` (default False — disables the global check, mirrors `StoplossGuard`), `only_per_side` (default False).
   - `_streak(date_now, pair, side)`: fetch closed trades via `Trade.get_trades_proxy(pair=pair, is_open=False)` (pair=`None` for the global path), sort by `close_date` descending, optionally filter by `side` when `only_per_side`, then walk from the most recent trade backward accumulating a streak while `close_profit < required_profit`, stopping at the first trade that doesn't qualify (a win breaks the streak). If accumulated streak length `>= trade_limit`, return `ProtectionReturn(lock=True, until=self.calculate_lock_end(streak_trades), reason=..., lock_side=...)`.
   - `global_stop`: returns `None` if `only_per_pair`, else delegates to `_streak(date_now, pair=None, side)`.
   - `stop_per_pair`: delegates to `_streak(date_now, pair, side)`.
   - `short_desc`: one-liner naming the threshold, mirroring existing handlers' style.
   - Explicit docstring/comment: this handler intentionally ignores `lookback_period` (same precedent as `CooldownPeriod`) because a time window could truncate/miscount an in-progress streak.
2. **CODEMANIFEST**: append a `"IProtection::MaxLossesInARow()"` entry after the existing `StoplossGuard` entry, same shape (location, annotations describing the consecutive-streak behavior and the "ignores lookback_period" constraint).
3. **Docs**: add bullet to "Available Protections", add a "#### Max Losses In A Row" section with a config example (`trade_limit`, `stop_duration_candles`, `required_profit`, `only_per_pair`, `only_per_side`) and a note mirroring the CooldownPeriod lookback-period note.
4. **Tests**: add `MaxLossesInARow` to `AVAILABLE_PROTECTIONS`; add `test_max_losses_in_a_row` (per-pair: streak of losses locks the pair, an interleaved win resets the count, streak below threshold doesn't lock) and `test_max_losses_in_a_row_global` (global: losses across different pairs still count toward the global streak; `only_per_pair=True` suppresses the global lock) following the `test_stoploss_guard`/`test_stoploss_guard_perpair` pattern with `generate_mock_trade`.

## Specification Impact
CODEMANIFEST body gains exactly one new type declaration (`MaxLossesInARow`), following the identical shape used for `StoplossGuard`. Header `Imports`/`Usages`/`Annotations` and all existing body entries are untouched — no revision to existing contract text.

## Usage Impact
None — this cell has no `.usages/` files.

## Compatibility Verification
**Backward compatible.** No existing signature, file, or documented type is modified; this is a pure addition. Confirmed in the Investigation Report's Breaking Change Assessment (all six questions: NO).

## Test Strategy
- Per-pair streak triggers lock at exactly `trade_limit` consecutive losses, not before.
- A winning trade interleaved in the trade history resets the streak count (proves "consecutive," not "N losses within window").
- Trades on other pairs don't count toward a given pair's per-pair streak, but do count toward the global streak (proves global scope is bot-wide, not per-pair-summed).
- `only_per_pair=True` disables the global check (mirrors `StoplossGuard` semantics, verified against existing test pattern).
- `only_per_side` filters by long/short direction.
- Handler is correctly loaded and exposed via `ProtectionManager` (extends `test_protectionmanager` coverage through `AVAILABLE_PROTECTIONS`).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Unbounded `get_trades_proxy` scan on pairs/bots with very long trade history | Low | Low (perf only, matches existing handler patterns; DB call is indexed by pair/close_date in live mode) | Accept — consistent with existing `StoplossGuard`/`LowProfitPairs` query patterns; no pagination exists elsewhere in this cell either |
| Ambiguity over whether "streak" should reset on any win vs. only requiring net negative | Low | Medium (wrong semantics defeats the point) | Resolved explicitly in this plan: any single trade with `close_profit >= required_profit` breaks the streak, matching the literal "losing trades in a row" ask |
| Class name collision / config typo (`method` string mismatch) | Low | Low | `ProtectionResolver` dynamically loads by exact class name; tests assert the string matches |

---

Do you approve the plan? Proceed to implementation?
