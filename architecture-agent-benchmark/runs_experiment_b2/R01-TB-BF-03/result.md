# R01-TB-BF-03

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: True
Cost: $2.6294138999999994
Duration: 579719ms, turns: 61

## Agent's own summary

# Change Plan

## Task Classification
**Feature** (additive, opt-in safety-limit extension) — no existing behavior changes unless a user explicitly sets `max_currency_exposure < 1`.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `freqtrade/wallets.py` (undocumented) | `wallets.py` | New param on `validate_stake_amount`; new private helper computing/clamping currency exposure; new `_local_log` message |
| `freqtrade/freqtradebot.py` (undocumented) | `freqtradebot.py` | One new keyword arg at the existing `validate_stake_amount` call site |
| `freqtrade/optimize` | `backtesting.py` | One new keyword arg at the existing `validate_stake_amount` call site |
| `freqtrade/strategy` | `interface.py` | New `IStrategy` class attribute `max_currency_exposure: float = 1.0` |
| `freqtrade/resolvers` | `strategy_resolver.py` | New `("max_currency_exposure", 1.0)` entry in the attribute-override list |
| `freqtrade/config_schema/config_schema.py` (undocumented) | `config_schema.py` | New schema property, mirroring `position_adjustment_enable` |
| — | `docs/configuration.md` | New documentation entry |
| — | `tests/test_wallets.py` | New/extended test coverage |

## Root Cause Analysis
Gap, not defect: `Wallets.validate_stake_amount` bounds a single trade's stake against balance and exchange min/max, but has no notion of cross-trade, cross-pair capital concentration in a shared underlying (base) currency. Both runtime entry points (`freqtradebot.execute_entry`, `Backtesting.get_valid_entry_price_and_stake`) already converge on this one method with identical argument shapes, so the gap can be closed once, at the shared choke point, guaranteeing live/backtest parity by construction rather than by convention.

## Trace Summary
`StrategyResolver.load_strategy` (config load, once) → `strategy.max_currency_exposure` always populated as `float`. At entry-sizing time, either `freqtradebot.execute_entry` (live/dry-run) or `Backtesting.get_valid_entry_price_and_stake` (backtest) calls `wallets.validate_stake_amount(..., max_currency_exposure=self.strategy.max_currency_exposure)`. Inside, after existing min/max-stake reconciliation, a new clamp step resolves the pair's base currency via `exchange.get_pair_base_currency`, sums open-trade `stake_amount` sharing that currency via `Trade.get_trades_proxy(is_open=True)` (already live/backtest-agnostic), and clamps the return value down (never raises). The clamped value flows back to `execute_entry`/`_enter_trade`, both of which already no-op silently on `0`.

## Change Strategy
1. **`freqtrade/strategy/interface.py`**: add `max_currency_exposure: float = 1.0` next to `max_open_trades`/`position_adjustment_enable` (~line 79 or ~118), with a one-line comment stating it's the fraction of tradable capital allowed in one underlying currency.
2. **`freqtrade/resolvers/strategy_resolver.py`**: append `("max_currency_exposure", 1.0)` to the `attributes` list (~line 82, after `max_open_trades`). No other resolver logic needs to change — `_override_attribute_helper` and `_normalize_attributes` already handle arbitrary numeric attributes generically.
3. **`freqtrade/config_schema/config_schema.py`**: add a `max_currency_exposure` property (near `position_adjustment_enable`/`max_entry_position_adjustment`, ~line 863-881): `type: "number"`, `minimum: 0`, `maximum: 1`, `description` ending in `__IN_STRATEGY`. Do not add to any `SCHEMA_*_REQUIRED` list.
4. **`freqtrade/wallets.py`**:
   - Add private helper, e.g. `_get_currency_exposure_limit(self, pair: str, max_currency_exposure: float) -> float`, returning the max stake still allowed for `pair`'s base currency given already-open exposure.
   - Extend `validate_stake_amount` signature with `max_currency_exposure: float = 1.0`. After the existing `if stake_amount > max_allowed_stake: ... stake_amount = max_allowed_stake` block, add: if `max_currency_exposure < 1`, compute the currency-specific ceiling and clamp `stake_amount` further downward, logging a distinct message (naming the currency and the configured percentage) via `self._local_log(...)` whenever the ceiling actually reduces the value — whether to a smaller positive number or to `0`.
   - Guard the whole block behind `if stake_amount and max_currency_exposure < 1:` so the default (`1.0`) and the "nothing to trade" early-return path are untouched, preserving today's behavior byte-for-byte when the feature is not configured.
5. **`freqtrade/freqtradebot.py`** (~line 1209-1215) and **`freqtrade/optimize/backtesting.py`** (~line 1111-1117): add `max_currency_exposure=self.strategy.max_currency_exposure` to the existing `wallets.validate_stake_amount(...)` calls. No other lines in either method change.
6. **`docs/configuration.md`**: add a short entry next to `tradable_balance_ratio`/`amend_last_stake_amount` explaining the setting, its default (disabled, i.e. `1.0`), and that it is strategy-configurable.

## Specification Impact
- `freqtrade/strategy` CODEMANIFEST: `IStrategy`'s documented property set gains one new property (`max_currency_exposure -> float`). No existing property/method annotation is altered; this is a pure addition consistent with the cell's documented role ("The strategy contract... plus hyperopt-parameter support").
- `freqtrade/resolvers` CODEMANIFEST: no signature-level change to `StrategyResolver`'s documented type surface (the attribute list is an internal implementation detail, not a documented method/property in the manifest); no manifest edit required beyond possible annotation note, to be assessed in Step 7 (Manifest Reconciliation).
- `freqtrade/optimize` CODEMANIFEST: no change to `Backtesting`'s documented public surface (`get_valid_entry_price_and_stake` is not itself a manifest-declared method in the current cell contract at the granularity checked); internal call now carries one more keyword argument to an undocumented dependency (`Wallets`), which is outside this cell's own contract boundary per the DSL's "contract boundary isolation" rule.
- `freqtrade/wallets.py`, `freqtrade/freqtradebot.py`, `freqtrade/config_schema/config_schema.py`: no CODEMANIFEST exists; nothing to reconcile for these files themselves (confirmed absent from `goga schema` cell list).

## Usage Impact
No `.usages/*.md` files exist for any affected cell (confirmed in Investigation). No usage-impact changes required.

## Compatibility Verification
**Backward compatible.** All changes are additive:
- New attribute (`max_currency_exposure`), default `1.0`, does not alter behavior for any strategy/config that doesn't set it.
- New method parameter with a default value; all existing call sites and tests (`tests/test_wallets.py:182-198`, 5 positional args) are unaffected.
- New schema property is optional, not in any required list.
- No renames, removals, or return-type/semantic changes to any existing function.
No STOP condition triggered.

## Test Strategy
Extend `tests/test_wallets.py`:
1. `max_currency_exposure=1.0` (default/unset) with all existing `test_validate_stake_amount` parametrized cases → identical results to today (regression guard, proves the new clamp is a true no-op by default).
2. Single open trade in currency X near the cap; new trade in same currency X requests more than remaining room → resized down to the remaining room, not to 0.
3. Cap already fully consumed by an existing open trade in currency X → new trade in currency X returns 0.
4. Two *different* pairs sharing the same base currency (e.g. `BTC/USDT` and `BTC/USDT:USDT` conceptually, or two mocked pairs both resolving to base `BTC`) — confirm exposure aggregates across pairs, not just same-pair, proving the "several pairs, same underlying currency" requirement.
5. A trade in a *different* base currency is unaffected by another currency's cap being fully used (proves the limit is per-currency, not global).
6. Mock `Trade.get_trades_proxy` and `Exchange.get_pair_base_currency` (or use existing fixture patterns already present in `test_wallets.py`) rather than requiring a live DB/backtest fixture, consistent with existing test style in this file.

Additionally, spot-check (read-only, no new test file needed unless a gap is found) that `tests/strategy/test_strategy_loading.py` / `tests/strategy/test_interface.py`'s existing generic attribute-override assertions (if parametrized over the `attributes` list) automatically pick up `max_currency_exposure` — if they iterate the list generically this needs no new test; if they hardcode each attribute name, add one line mirroring `max_open_trades`.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Double-counting the trade being position-adjusted (its own existing stake) when computing "room left," making the cap stricter than intended | Low | Medium | By design this is intentional and correct: the sum over open trades naturally includes the trade's pre-adjustment stake, and the parameter being sized is the *additional* stake being added — the cap already correctly limits (existing + addition) ≤ ceiling. Documented explicitly in code comment to prevent future "fix." |
| Performance: summing over all open trades on every entry-sizing call | Low | Low | `Trade.get_trades_amount_proxy(is_open=True)` is already called elsewhere per-entry (`wallets.py` `_update_dry`, `get_starting_balance`); open-trade counts are bounded by `max_open_trades`, so cost is negligible and consistent with existing patterns. |
| Floating-point edge cases producing a tiny negative "room" that should be treated as zero | Low | Low | Explicit `max(..., 0)` clamp in the helper, matching existing `_calculate_unlimited_stake_amount`/`_check_available_stake_amount` style. |
| Test file for `StrategyResolver` attribute coverage hardcodes attribute names and silently doesn't cover the new one | Medium | Low | Explicitly called out in Test Strategy as a spot-check item during Step 6. |
| `freqtrade/resolvers`/`freqtrade/optimize` CODEMANIFESTs contain stricter algorithm text than assumed, requiring a manifest edit in Step 7 | Low | Low | Deferred to Step 7 (Manifest Reconciliation) by design — this plan only asserts no *contradiction* was found at investigation-time granularity, not that zero manifest edits will occur. |

---

Do you approve this plan? Proceed to implementation?
