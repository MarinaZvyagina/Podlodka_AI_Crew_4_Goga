# R01-TC-BF-10

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: True
Cost: $1.615899
Duration: 242495ms, turns: 50

## Agent's own summary

# Change Plan

## Task Classification
**Extension** — adding a new concrete extension-point handler to an existing, stable abstract contract. No existing type, signature, or behavior is modified.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `freqtrade/plugins/protections` | `max_consecutive_losses.py` (new), `CODEMANIFEST` (append entry) | New `IProtection` subclass; new documented type entry |
| *(companion, not a cell)* | `tests/plugins/test_protections.py` | New test coverage, extended `AVAILABLE_PROTECTIONS` and `test_protection_manager_desc` |
| *(companion, not a cell)* | `docs/includes/protections.md` | New "Available Protections" bullet + "#### Max Consecutive Losses" section |

## Root Cause Analysis
Not a defect — a documented gap. The cell's own `CODEMANIFEST` Annotations already list "consecutive losses" as an intended category (alongside drawdown, low-profit streaks, cooldowns) but no handler implements strict per-trade streak detection. `StoplossGuard` counts stoploss-tagged exits in a window; `LowProfitPairs` sums profit in a window; neither tracks an unbroken run of losses ending at the most recent trade.

## Trace Summary
`handle_protections()` in `freqtradebot.py:2454` (called after every trade close) → `ProtectionManager.stop_per_pair`/`global_stop` (`protectionmanager.py:52,69`) generically iterate `self._protection_handlers` → new handler's `stop_per_pair`/`global_stop` → `Trade.get_trades_proxy(...)` → `ProtectionReturn` → `PairLocks.lock_pair(...)` → `RPCProtectionMsg` → Telegram/webhook. This path is entirely handler-agnostic (confirmed in investigation); no code in this chain needs modification, only a new leaf class registered by file presence + `method` config string.

## Change Strategy
1. **`freqtrade/plugins/protections/max_consecutive_losses.py`** (new file) — implement `MaxConsecutiveLosses(IProtection)` per the settled design: `has_global_stop=True`, `has_local_stop=True`; `__init__` reads `trade_limit` (default 4), `only_per_pair` (default False), `only_per_side` (default False), `required_profit` (default 0.0); private `_max_consecutive_losses(date_now, pair, side)` fetches trades via `Trade.get_trades_proxy(pair=pair, is_open=False, close_date=look_back_until)`, applies `only_per_side` filter, **sorts by `close_date` descending** (the one behavior not present in sibling handlers, needed because `get_trades_proxy` returns unsorted results and streak order matters), walks from most recent accumulating a losing streak until a non-loss trade or exhaustion, returns `None` if `len(streak) < trade_limit`, else builds `ProtectionReturn` via `calculate_lock_end(streak)`; `global_stop` short-circuits to `None` when `only_per_pair`; `stop_per_pair` always delegates. `short_desc()` mirrors `StoplossGuard`'s tone.
2. **`freqtrade/plugins/protections/CODEMANIFEST`** — append one new entry, `"IProtection::MaxConsecutiveLosses()"`, in the same mutation form and annotation style as the existing `"IProtection::StoplossGuard()"` entry (`location: max_consecutive_losses.py`, short annotation referencing `extension_point` and describing the streak-lock behavior). No other section changes.
3. **`tests/plugins/test_protections.py`** — add `"MaxConsecutiveLosses"` to `AVAILABLE_PROTECTIONS`; add test functions for: streak building to threshold (locks at exactly `trade_limit`, not before), a winning trade breaking/resetting the streak, trades outside `lookback_period` not counting, `only_per_pair` disabling the global check (parametrized, mirroring `test_stoploss_guard_perpair`), `only_per_side` isolating long/short streaks; add one `short_desc` case to `test_protection_manager_desc`'s parametrize list.
4. **`docs/includes/protections.md`** — add a bullet under "Available Protections"; add a new "#### Max Consecutive Losses" subsection (prose + config example) in the same position/style as the other three; leave the combined "Full example of Protections" section's existing prose/code untouched (it is a demonstration of composability, not an exhaustive catalog — StoplossGuard/LowProfitPairs already each appear there in only some combinations; adding a 5th entry there is not required for documentation completeness and would risk unrelated churn in a walkthrough that's understood to be illustrative, not exhaustive).

**Order of edits:** implementation file → CODEMANIFEST → tests → docs. Verify after each of the first three with the tool most relevant to it (see below); docs are prose-only and self-verified by re-reading.

## Specification Impact
Only `freqtrade/plugins/protections/CODEMANIFEST` changes, and only additively: one new type entry appended after the existing `"IProtection::StoplossGuard()"` block. The `extension_point` Usages text and the `IProtection`/`ProtectionReturn` entries are untouched — the new handler is a textbook application of the already-written extension-point instructions, requiring no rewording of them.

**Pre-existing drift note (not in scope):** `goga schema` currently reports only `IProtection`, `ProtectionReturn`, `StoplossGuard` as this cell's types, even though `LowProfitPairs`, `MaxDrawdown`, `CooldownPeriod` are implemented and shipped. This is pre-existing manifest/implementation drift unrelated to this task — retroactively documenting those three is out of scope (would violate "minimize scope" and risk unrelated churn). This plan documents only the one entry it adds (`MaxConsecutiveLosses`), keeping the new code and its own manifest entry consistent, without attempting to fix the older gap. Flagging it here for visibility only.

## Usage Impact
No `.usages/` files exist for this cell (confirmed — only the inline `extension_point` usage in the CODEMANIFEST header, no `freqtrade/plugins/protections/.usages/` directory). No usage file changes required; the inline `extension_point` recipe already covers "how to add a new protection" and remains accurate verbatim for this addition.

## Compatibility Verification
**Backward compatible.** No existing file, function signature, return type, or manifest guarantee changes. `ProtectionManager`, `ProtectionResolver`, `IProtection`, `ProtectionReturn`, RPC message construction/formatting are all untouched. Existing protections' behavior, existing tests, and existing config files are unaffected — a strategy that doesn't list `"MaxConsecutiveLosses"` in its `protections` config sees zero behavior change.

## Test Strategy
Mirror the existing handler test patterns in `tests/plugins/test_protections.py` using `generate_mock_trade(...)` (already parametrizable by `pair`, `exit_reason`, `min_ago_open/close`, `profit_rate`, `is_short`):
- **Streak accumulates → locks exactly at `trade_limit`:** generate `trade_limit - 1` losing trades → assert not locked; generate one more losing trade → assert locked, `PairLocks.is_pair_locked`/`is_global_lock` true.
- **Win breaks the streak:** interleave a winning trade (`profit_rate > 1`) between losses → subsequent losses must restart the count from zero (not lock until `trade_limit` *new* consecutive losses accumulate after the win).
- **Lookback boundary:** a losing trade closed before `look_back_until` must not count toward or extend the streak (mirrors `test_LowProfitPairs`'s "closed too long ago" case).
- **`only_per_pair`:** parametrized True/False, asserting `global_stop()` is suppressed when True (mirrors `test_stoploss_guard_perpair`).
- **`only_per_side`:** parametrized True/False, asserting long/short streaks are independent when True.
- **`short_desc`:** one new case appended to `test_protection_manager_desc`'s parametrize list, asserting the exact rendered string.

Run: `pytest tests/plugins/test_protections.py -v` after implementation; `goga lint` after the CODEMANIFEST edit to confirm the new entry is well-formed and the cell stays internally consistent.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `get_trades_proxy` returns unsorted list, streak logic reads wrong order | Medium (easy to forget, no sibling handler needs it) | High — silently wrong lock decisions | Explicit `sorted(trades, key=lambda t: t.close_date, reverse=True)` before streak walk; covered by the "win breaks streak" test which fails loudly if order is wrong |
| Off-by-one in threshold comparison (`<` vs `<=` on `trade_limit`) | Low | Medium | Dedicated boundary test asserting no lock at `trade_limit - 1` and lock at `trade_limit` |
| Pre-existing manifest drift (LowProfitPairs/MaxDrawdown/CooldownPeriod undocumented) mistaken for something this change must fix | Low | Low (scope creep, not correctness) | Explicitly called out above as out of scope; only the new entry is added |
| Doc example in "Full example of Protections" section left inconsistent by omission | Low | Low (cosmetic) | Explicitly deferred by design — that section is illustrative/composable, not an exhaustive catalog; the new "#### Max Consecutive Losses" subsection with its own example is sufficient |

---

Do you approve this plan? Proceed to implementation?
