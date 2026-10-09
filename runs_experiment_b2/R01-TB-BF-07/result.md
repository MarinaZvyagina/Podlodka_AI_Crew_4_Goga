# R01-TB-BF-07

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: True
Cost: $2.9929208999999997
Duration: 515522ms, turns: 57

## Agent's own summary

# Change Plan

## Task Classification
**Feature** (net-new, additive, opt-in capability).

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| *(undocumented)* | `freqtrade/wallets.py` | `Wallets.validate_stake_amount` gains a currency-exposure cap computation, folded into the existing `max_allowed_stake` derivation |
| freqtrade/strategy | `freqtrade/strategy/interface.py` | New `IStrategy` class attribute `max_currency_exposure: float | None = None` |
| freqtrade/resolvers | `freqtrade/resolvers/strategy_resolver.py` | New entry `("max_currency_exposure", None)` in the `attributes` list |
| *(undocumented)* | `freqtrade/config_schema/config_schema.py` | New `max_currency_exposure` schema entry (number, 0.0–1.0) |
| *(undocumented)* | `docs/configuration.md` | New table row + short explanatory subsection |
| *(undocumented)* | `docs/strategy-customization.md` | Mention alongside `max_open_trades` if that doc lists strategy-level sizing attributes (to confirm during implementation) |

No changes to `freqtrade/persistence`, `freqtrade/optimize`, or `freqtrade/exchange` code — all three are consumed read-only via already-existing, stable methods (`Trade.get_open_trades`, `Trade.safe_quote_currency`, `Exchange.get_pair_quote_currency`).

## Root Cause Analysis
Not applicable (feature, not bugfix). Summary of investigation: `Wallets.validate_stake_amount` is the single convergence point both `freqtradebot.py` (live/dry-run) and `freqtrade/optimize/backtesting.py` (backtest) already call for identical stake-sizing decisions (min stake, max stake, available balance). It already receives `pair` and holds `self._exchange`/`self._config`, so it can compute per-currency exposure with no new parameters and no new imports.

## Trace Summary
- Live: `FreqtradeBot.create_trade`/`execute_entry` → `get_valid_enter_price_and_stake` (`freqtradebot.py:1209-1215`) → `Wallets.validate_stake_amount`.
- Backtest: `Backtesting._enter_trade` → `get_valid_entry_price_and_stake` (`backtesting.py:1111-1117`) → `Wallets.validate_stake_amount`.
- Both pass identical arguments; the new logic executing inside the shared method guarantees identical live/backtest behavior by construction, not by parallel maintenance.

## Change Strategy

1. **`freqtrade/strategy/interface.py`**: add, near `max_open_trades: IntOrInf` (line 79):
   ```python
   # Maximum fraction of tradable capital that may be committed at once to trades
   # sharing the same underlying (quote) currency. None disables the cap.
   max_currency_exposure: float | None = None
   ```

2. **`freqtrade/resolvers/strategy_resolver.py`**: add `("max_currency_exposure", None)` to the `attributes` list (after `("max_open_trades", float("inf"))`, line 82). No changes needed to `_override_attribute_helper` (its existing None-default branch already handles this correctly) or `_normalize_attributes` (no type coercion needed beyond what Python already gives a float).

3. **`freqtrade/config_schema/config_schema.py`**: add, near `tradable_balance_ratio` (line 61-67):
   ```python
   "max_currency_exposure": {
       "description": (
           "Maximum fraction of tradable capital that may be committed at once to "
           "trades sharing the same underlying (quote) currency."
       ),
       "type": "number",
       "minimum": 0.0,
       "maximum": 1.0,
   },
   ```
   Add `"max_currency_exposure"` to whichever `properties` list(s) that schema section is nested under (confirm exact nesting — top-level config vs strategy-level in the schema, matching how `stake_amount`/`max_open_trades` are registered) during implementation.

4. **`freqtrade/wallets.py`** — `validate_stake_amount` (currently lines 410-459): insert the exposure-cap computation between the existing `max_allowed_stake`/`trade_amount` block (lines 425-429) and the `min_stake_amount` checks (line 431), so it feeds into the same downstream resize/skip branches:
   ```python
   max_currency_exposure = self._config.get("max_currency_exposure")
   if max_currency_exposure is not None:
       currency = self._exchange.get_pair_quote_currency(pair)
       current_exposure = sum(
           t.stake_amount
           for t in Trade.get_open_trades()
           if t.safe_quote_currency == currency
       )
       exposure_cap = self.get_total_stake_amount() * max_currency_exposure
       allowed_for_currency = max(exposure_cap - current_exposure, 0)
       if allowed_for_currency < max_allowed_stake:
           self._local_log(
               f"Stake amount for pair {pair} is capped by max_currency_exposure "
               f"for {currency}: {current_exposure:.8f} already committed, "
               f"limit is {exposure_cap:.8f} "
               f"({max_currency_exposure:.2%} of {self.get_total_stake_amount():.8f})."
           )
           max_allowed_stake = allowed_for_currency
   ```
   This deliberately reuses the *existing* `_local_log` call (same mechanism, same info level as the pre-existing "Stake amount... too big" message at line 454-458) so the reason surfaces identically to how other sizing decisions already surface — in the bot log for live/dry-run and in backtest's suppressed-but-identical `_local_log` call (consistent with how every other sizing message in this method already behaves in backtest: `_local_log` is a no-op-for-logging convenience wrapper in backtest mode, matching existing behavior for every other branch in this method — not a new inconsistency).
   Everything downstream (the `min_stake_amount > max_allowed_stake` → skip-to-0 branch, and the `stake_amount > max_allowed_stake` → resize-down branch) is untouched and automatically applies the new cap, exactly matching the task's "whichever is more consistent with how we already handle similar sizing limits" instruction.

5. **`docs/configuration.md`**: add a `max_currency_exposure` row to the parameters table (near `tradable_balance_ratio`/`amend_last_stake_amount`, lines 169-172) plus a short "Exposure limit per currency" subsection under "Configuring amount per trade" explaining the semantics with a worked example (mirroring the existing `tradable_balance_ratio` example style at lines 357-365).

## Specification Impact
**None.** Confirmed in Investigation: `freqtrade/strategy/CODEMANIFEST`'s `IStrategy` entry documents only a curated subset of properties (`minimal_roi`, `stoploss`, `timeframe`, `dp`, `wallets`) — sibling numeric/boolean config attributes (`max_open_trades`, `position_adjustment_enable`, `max_entry_position_adjustment`, `stake_amount`) are already absent by established precedent, so adding one more of the same kind introduces no drift. `freqtrade/resolvers/CODEMANIFEST`'s `StrategyResolver.load_strategy` is documented at the "find and instantiate the IStrategy subclass" level, with attribute-resolution mechanics treated as internal, undocumented implementation detail. No CODEMANIFEST body text requires edits.

## Usage Impact
**None.** `goga schema` confirms `"usages": []` for every affected cell — no `.usages/*.md` practice files exist to update.

## Compatibility Verification
**Backward compatible.** `max_currency_exposure` defaults to `None` in both `IStrategy` and `StrategyResolver`'s `attributes` list; the new block in `validate_stake_amount` is gated on `is not None` and is fully skipped when unset, leaving every existing call with existing arguments producing byte-identical behavior. No signatures change. No existing tests are expected to break.

## Test Strategy
- **`tests/test_wallets.py`**: new unit tests calling `Wallets.validate_stake_amount` directly with `config["max_currency_exposure"]` set, covering: (a) new trade fits under cap → unchanged stake; (b) new trade would exceed cap → resized down to remaining headroom; (c) headroom below `min_stake_amount` → trade skipped (returns 0), verifying it flows through the existing min-stake skip branch; (d) cap unset → identical behavior to current tests (regression guard); (e) position-adjustment (`trade_amount` set) case, verifying the trade's own already-open stake isn't double-counted.
- **`tests/optimize/test_backtesting.py`**: one integration-style test asserting a backtest run with `max_currency_exposure` configured produces entries/skips consistent with the same scenario driven through `Wallets.validate_stake_amount` directly — the parity check the task explicitly asked for.
- **`tests/strategy/test_interface.py`** or **`tests/resolvers/test_strategy_resolver.py`**: test that `max_currency_exposure` set via config overrides a strategy-level default, and that omitting it leaves it `None`, matching the `max_open_trades`-style precedence tests already present for sibling attributes.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Double-counting a trade's own stake during position adjustment, causing incorrect over-restriction | Low | Medium | `Trade.get_open_trades()` naturally includes the trade's pre-adjustment `stake_amount` once; the new `stake_amount` request is additive on top — verified analytically in Investigation (H4 rejected) and covered by a dedicated test |
| Divide against stale wallet totals if `get_total_stake_amount()` is expensive/stale under high-frequency calls | Low | Low | `get_total_stake_amount()` is already called elsewhere in the hot path (`get_available_stake_amount`) with no caching concerns previously raised; no new caching introduced, consistent with existing usage |
| Config schema placement mismatch (wrong nesting under strategy-level vs top-level schema) causing schema validation to reject valid configs | Low | Medium | Cross-check exact schema nesting of `max_open_trades`/`tradable_balance_ratio` in `config_schema.py` during implementation before adding the new key |
| Docs drift (new option undocumented) | Low | Low | `docs/configuration.md` edit included in this plan |

---

Do you approve the plan? Proceed to implementation?
