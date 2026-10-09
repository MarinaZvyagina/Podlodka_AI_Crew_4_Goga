# R01-TB-BF-05

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: False
Cost: $2.3491545
Duration: 426864ms, turns: 70

## Agent's own summary

## Change Plan

### Task Classification
**Feature** (extension) — new opt-in per-strategy risk control; additive, default-off, no existing behavior altered.

### Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| freqtrade/strategy | `freqtrade/strategy/interface.py`, `freqtrade/strategy/CODEMANIFEST` | New `max_currency_exposure: float \| None = None` class attribute on `IStrategy`; manifest property entry added |
| freqtrade/resolvers | `freqtrade/resolvers/strategy_resolver.py` | New `("max_currency_exposure", None)` entry in the `attributes` override list |
| *(undocumented)* freqtrade/config_schema | `freqtrade/config_schema/config_schema.py` | New `max_currency_exposure` property in `CONF_SCHEMA["properties"]` |
| *(undocumented)* freqtrade/wallets | `freqtrade/wallets.py` | New `_get_currency_exposure_headroom(pair)` helper; `validate_stake_amount` folds it into `max_allowed_stake`; adds a distinguishing log line when it's the binding constraint |

No changes to `freqtrade/freqtradebot.py`, `freqtrade/optimize/backtesting.py`, `freqtrade/exchange/*`, or `freqtrade/persistence/*` — all required data (`pair`, `Exchange.get_pair_quote_currency`, `Trade.get_trades_proxy`) is already available inside `Wallets` unchanged.

### Root Cause Analysis
Not a defect — a gap. No mechanism today limits combined exposure to a shared underlying currency across simultaneously open trades. Investigation confirmed both live and backtest already funnel identically through `Wallets.validate_stake_amount(pair=, stake_amount=, min_stake_amount=, max_stake_amount=, trade_amount=)`, so a single, mode-agnostic fix point exists.

### Trace Summary
`execute_entry` (live) / `get_valid_entry_price_and_stake` (backtest) → `exchange.get_min/max_pair_stake_amount` → `custom_stake_amount` callback → `Wallets.validate_stake_amount(pair, stake_amount, min_stake_amount, max_stake_amount, trade_amount)`. `trade_amount` is `trade.stake_amount if trade else None` in both — `None` for new entries, the trade's current stake for position adjustments. `pair` is always available and unchanged by the new logic.

### Change Strategy

1. **`freqtrade/strategy/interface.py`** — add, adjacent to `max_open_trades: IntOrInf` (line 79):
   ```python
   max_currency_exposure: float | None = None
   ```
   with a doc comment mirroring `trailing_stop_positive`'s style (only if non-obvious — the name is largely self-documenting, so keep it to one line).

2. **`freqtrade/resolvers/strategy_resolver.py`** — add `("max_currency_exposure", None)` to the `attributes` list (after `("max_open_trades", float("inf"))` for grouping with sizing-related knobs). No change to `_override_attribute_helper` or `_normalize_attributes` needed — `None`-default semantics already handled generically (mirrors `trailing_stop_positive`).

3. **`freqtrade/config_schema/config_schema.py`** — add to `CONF_SCHEMA["properties"]`, near `tradable_balance_ratio`:
   ```python
   "max_currency_exposure": {
       "description": (
           "Maximum share of total tradable capital that may be committed at once "
           "to positions sharing the same underlying (quote/settlement) currency. "
           f"Unset (default) disables this check.{__IN_STRATEGY}"
       ),
       "type": "number",
       "minimum": 0.0,
       "maximum": 1.0,
   },
   ```
   Not added to any `SCHEMA_*_REQUIRED` list (optional, like `available_capital`).

4. **`freqtrade/wallets.py`** — core enforcement:
   - New method (placed near `validate_stake_amount`, before it):
     ```python
     def _get_currency_exposure_headroom(self, pair: str) -> float:
         """
         :return: Remaining stake amount that may be committed to `pair`'s underlying
             (quote/settlement) currency before exceeding `max_currency_exposure`.
             float('inf') if unset.
         """
         max_currency_exposure = self._config.get("max_currency_exposure")
         if not max_currency_exposure:
             return float("inf")
         currency = self._exchange.get_pair_quote_currency(pair)
         current_exposure = sum(
             t.stake_amount
             for t in Trade.get_trades_proxy(is_open=True)
             if self._exchange.get_pair_quote_currency(t.pair) == currency
         )
         cap_amount = self.get_total_stake_amount() * max_currency_exposure
         return max(cap_amount - current_exposure, 0.0)
     ```
   - Inside `validate_stake_amount`, after the existing `trade_amount` branch and before the `min_stake_amount`/`max_allowed_stake` comparisons:
     ```python
     exposure_headroom = self._get_currency_exposure_headroom(pair)
     if exposure_headroom < max_allowed_stake:
         self._local_log(
             f"Stake amount for pair {pair} is limited by the configured currency "
             f"exposure cap ({exposure_headroom} available), adjusting max stake accordingly.",
             level="debug",
         )
     max_allowed_stake = min(max_allowed_stake, exposure_headroom)
     ```
   - Everything downstream (min-stake skip, max-stake resize, `_local_log` calls) is **unchanged code** — it already operates on `max_allowed_stake`, so the existing "adjusting to X" / "ignoring possible trade" messages automatically reflect the new cap when it binds. The added debug line supplies the *why* without altering the existing info/warning-level messages' text or level (no behavior change for users who don't set the new config key, since `exposure_headroom` is `inf` and the `if` never fires).

**Correctness of aggregation**: for a new trade, `Trade.get_trades_proxy(is_open=True)` does not yet include it, so `current_exposure` sums only pre-existing trades; the cap check happens via `stake_amount > max_allowed_stake` further down in `validate_stake_amount`'s existing code, comparing the *proposed* stake against headroom — correct, no double counting. For a position adjustment, the trade being adjusted is already in the open set with its current `stake_amount`, so `current_exposure` already reflects it; `exposure_headroom` becomes "how much more can be added," and existing code compares `stake_amount` (the incremental add, per `trade_amount` semantics already established by the `max_stake_amount - trade_amount` line above it) against that headroom — correct.

### Specification Impact
`freqtrade/strategy/CODEMANIFEST`: add `max_currency_exposure` under `HyperStrategyMixin::IStrategy`'s `properties` block, styled like `stoploss`/`timeframe`:
```yaml
"max_currency_exposure -> float | None": |
  Maximum fraction of total tradable capital that may be committed at once to positions
  sharing the same underlying (quote/settlement) currency, set as a class attribute.
  `None` (default) disables the check.
```
Decision: **document it**, despite `max_open_trades` not being documented — this is new public surface being introduced now, and the manifest's own guidance ("Coverage is not necessarily exhaustive... directories without a CODEMANIFEST are simply undocumented") only excuses *pre-existing* gaps, not new ones we're authoring. No other CODEMANIFEST changes (no new types, no new Imports edges — `Exchange`/`Trade` are consumed via already-injected instances inside undocumented `wallets.py`, not via a new Import in a governed cell).

### Usage Impact
No `.usages/*.md` files exist yet for `freqtrade/strategy`; none reference `max_open_trades`-style attributes today, so none require updates. No new `.usages` file warranted — this is a single attribute addition, not a new consumption pattern.

### Compatibility Verification
**Backward compatible.** `max_currency_exposure` defaults to `None` at every layer (class attribute, resolver default, JSON-schema optional property). `_get_currency_exposure_headroom` returns `float("inf")` when unset, making `min(max_allowed_stake, inf) == max_allowed_stake` — a no-op. No existing call signature, return type, or log level changes for the pre-existing code paths.

### Test Strategy
- `tests/test_wallets.py`: new unit tests for `_get_currency_exposure_headroom` (multiple open trades same/different quote currency, position-adjustment case) and `validate_stake_amount` end-to-end with the cap set (skip case, resize case, disabled/default case unaffected).
- `tests/strategy/test_interface.py` or resolver tests: confirm `max_currency_exposure` round-trips through `StrategyResolver.load_strategy` (config override, strategy-attribute fallback, default `None`).
- Config schema: confirm a config with `max_currency_exposure: 1.5` (out of range) fails validation; `0.4` passes.
- No changes needed to backtesting/freqtradebot test suites structurally, but add one integration-style test asserting **live and backtest produce the same skip/resize decision** given identical open-trade state and the same config — directly verifying the task's cross-mode-parity requirement.

### Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `get_pair_quote_currency` returns `""` for an unknown/unlisted pair, silently grouping unrelated pairs under `""` | Low | Medium | Existing method already returns `""` as a documented fallback for missing market data; this class of pair would already fail earlier (min/max stake lookups raise `ValueError` on missing market) — no new failure mode introduced |
| Users confuse `max_currency_exposure` with per-pair `max_stake_amount` (exchange limit) | Low | Low | Distinct debug log message names the exposure cap explicitly, and schema description clarifies scope |
| Future inverse/coin-margined contract support changes "underlying currency" semantics (settle ≠ quote) | Low (not currently supported) | Low | `get_pair_quote_currency` is the single source of truth reused as-is; if inverse contracts are added later, only that one method's contract needs revisiting, not this feature |

---

Do you approve the plan? Proceed to implementation?
