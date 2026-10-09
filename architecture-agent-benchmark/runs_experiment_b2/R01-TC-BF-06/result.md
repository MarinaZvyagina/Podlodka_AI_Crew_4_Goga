# R01-TC-BF-06

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: True
Cost: $1.5239438999999997
Duration: 261269ms, turns: 45

## Agent's own summary

# Change Plan

## Task Classification
Feature (extension) — new concrete `IProtection` handler added to an existing, unmodified extension-point cell.

## Affected Cells
| Cell | Files to Modify | What Changes |
|---|---|---|
| `freqtrade/plugins/protections` | `max_consecutive_losses.py` (new) | New `MaxConsecutiveLosses(IProtection)` class implementing per-pair and bot-wide consecutive-loss detection |
| `freqtrade/plugins/protections` | `CODEMANIFEST` | Add new type entry documenting `MaxConsecutiveLosses`; add to cell-level `types` list |
| `tests/plugins/test_protections.py` (non-cell) | same file | Add `"MaxConsecutiveLosses"` to `AVAILABLE_PROTECTIONS`; add new test functions |
| `docs/includes/protections.md` (non-cell) | same file | Add to "Available Protections" list; add a documented section with config example |

## Root Cause Analysis
Not a defect. The bot has protections for stoploss frequency, low aggregate profit, drawdown, and post-exit cooldown, but none that key off an order-sensitive "N losses in a row" signal, per pair or bot-wide. The existing `IProtection` extension point (documented in the cell's `extension_point` usage) is designed exactly for adding such a handler without touching any other cell.

## Trace Summary
`freqtradebot.handle_protections()` → `ProtectionManager.stop_per_pair()`/`global_stop()` → iterates configured `IProtection` handlers → any `ProtectionReturn(lock=True, until, reason, lock_side)` → `PairLocks.lock_pair()` (persists lock + auto-expiry) → `freqtradebot` emits `RPCMessageType.PROTECTION_TRIGGER`/`PROTECTION_TRIGGER_GLOBAL` generically. All of this is reused unchanged; the new handler only needs to implement `short_desc`, `global_stop`, `stop_per_pair`, using base-class `calculate_lock_end()` for `until`.

## Change Strategy
1. **Implement `MaxConsecutiveLosses`** in `freqtrade/plugins/protections/max_consecutive_losses.py`:
   - `has_global_stop = True`, `has_local_stop = True`
   - `__init__`: reads `max_consecutive_losses` (int, default 3 — the streak threshold), `only_per_pair` (bool, default False — mirrors `StoplossGuard`'s toggle to disable the global check), `required_profit` (float, default 0.0 — a trade is "losing" when `close_profit < required_profit`)
   - Shared private method `_consecutive_losses(date_now, pair, side)`:
     - Fetch closed trades via `Trade.get_trades_proxy(pair=pair, is_open=False)` (no `close_date` filter — streak logic is order-based, not time-windowed, precedented by `CooldownPeriod`)
     - Sort by `close_date` ascending; if fewer trades exist than `max_consecutive_losses`, return `None`
     - Take the last `max_consecutive_losses` trades (most recent); if **all** have `close_profit is not None and close_profit < required_profit`, it's a triggering streak
     - On trigger: `log_once(...)`, compute `until = self.calculate_lock_end(recent_trades)`, return `ProtectionReturn(lock=True, until=until, reason=self._reason())`
     - Otherwise return `None`
   - `global_stop()`: if `only_per_pair` is set, return `None`; else call `_consecutive_losses(date_now, None, side)` (pair=`None` aggregates across all pairs, matching `StoplossGuard.global_stop` convention)
   - `stop_per_pair()`: call `_consecutive_losses(date_now, pair, side)`
   - `short_desc()`: one-liner naming the configured threshold, following sibling style
2. **CODEMANIFEST update**: add a `"IProtection::MaxConsecutiveLosses()"` type-mutation entry (same pattern as the existing `"IProtection::StoplossGuard()"` entry) with an annotation describing the consecutive-streak behavior (pair-level and bot-wide, `only_per_pair` toggle), and append `MaxConsecutiveLosses` to the cell-level `types` array.
3. **Docs update**: add a bullet under "Available Protections" and a new `#### Max Consecutive Losses` section with a config example (mirroring the `StoplossGuard`/`CooldownPeriod` section structure), explicitly noting it does not use `lookback_period` (like `CooldownPeriod`).
4. **Tests**: add `"MaxConsecutiveLosses"` to `AVAILABLE_PROTECTIONS`; add tests for: pair-level lock after N consecutive losses, no lock when a winning trade breaks the streak, bot-wide/global equivalent across different pairs, and `only_per_pair` disabling the global check — using the existing `generate_mock_trade` helper and `get_patched_freqtradebot` pattern.

## Specification Impact
`freqtrade/plugins/protections/CODEMANIFEST`:
- **Body**: new entry `"IProtection::MaxConsecutiveLosses()"` (type mutation, same form as `StoplossGuard`), `location: max_consecutive_losses.py`, annotation describing purpose and the `only_per_pair` toggle.
- **Header**: no change — no new imports/usages needed (same `LocalTrade`/`timeframe_to_minutes` imports already declared serve this new type too); `extension_point` usage already covers the recipe.
- **Top-level `types` array** (as seen via `goga schema`): append `"MaxConsecutiveLosses"`.
- Footer (`Author`/`CreatedAt`/`Description`) unchanged — manifest is being extended, not recreated.

## Usage Impact
No `.usages/` directory exists for this cell and none is being created — the existing inline `extension_point` usage in the CODEMANIFEST header already fully documents "how to add a new protection handler" and requires no wording change since this addition follows that recipe exactly. `docs/includes/protections.md` is user-facing product documentation (not a Goga `.usages` practice file) and will be updated as described above.

## Compatibility Verification
**Backward compatible.** No existing file is modified in a way that changes behavior: `CODEMANIFEST` gains a new, independent type entry; `docs/includes/protections.md` and `tests/plugins/test_protections.py` receive purely additive changes (new list entry, new test functions). No existing signatures, return semantics, file paths, or manifest guarantees change. Confirmed against Breaking Change Assessment in the Investigation Report (all six checks: NO).

## Test Strategy
Add to `tests/plugins/test_protections.py`:
- `test_MaxConsecutiveLosses_perpair`: generate N losing trades for a pair below threshold → no lock; add one more to reach threshold → pair locked, `PairLocks.is_pair_locked(pair)` true, global not locked; verify a winning trade inserted before reaching the threshold resets the streak (no lock).
- `test_MaxConsecutiveLosses_global`: generate consecutive losing trades across different pairs → `global_stop()` locks `"*"` once threshold reached; verify a winning trade among them (regardless of pair) breaks the bot-wide streak.
- `test_MaxConsecutiveLosses_only_per_pair`: with `only_per_pair=True`, confirm `global_stop()` never locks even after the bot-wide streak condition is met, while `stop_per_pair()` still locks the specific pair.
- Update `AVAILABLE_PROTECTIONS` list so `test_protectionmanager` (generic sanity test iterating all protections) exercises the new handler too.
Rationale: mirrors existing coverage depth for `StoplossGuard`/`LowProfitPairs` (per-pair, global, toggle) using the established `generate_mock_trade` fixture.

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Ambiguity in "losing trade" definition (strict `< 0` vs `< required_profit`) causing mismatch with user expectation | Low | Low | Default `required_profit=0.0` reproduces "any losing trade" exactly; knob is opt-in for stricter/looser definitions, consistent with `StoplossGuard`/`LowProfitPairs` convention |
| Unsorted `get_trades_proxy` result silently misordering the streak (off-by-one on which trades count as "most recent") | Medium | Medium | Explicit `sort(key=lambda t: t.close_date)` before slicing, following `CooldownPeriod`'s established pattern; covered by dedicated tests with distinct `min_ago_close` values |
| Reviewers expecting `only_per_side` parity with `StoplossGuard`/`LowProfitPairs` | Low | Low | Out of scope per user's request (not mentioned); omitting keeps the change minimal and avoids speculative scope creep flagged in goga-change invariants |

---

Do you approve the plan? Proceed to implementation?
