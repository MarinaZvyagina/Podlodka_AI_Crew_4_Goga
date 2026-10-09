# R01-TB-BF-08

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: False
Cost: $2.8650381
Duration: 568990ms, turns: 79

## Agent's own summary

Good, this confirms exact test file locations. Now producing the Change Plan.

# Change Plan

## Task Classification
**Type: feature** (new opt-in safety limit) with **extension** of an existing shared sizing mechanism (`Wallets.validate_stake_amount`). No refactor, no bugfix.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| freqtrade/strategy | `freqtrade/strategy/interface.py` | Add `max_currency_exposure: float \| None = None` class attribute to `IStrategy`, placed near `max_open_trades` |
| freqtrade/resolvers | `freqtrade/resolvers/strategy_resolver.py` | Add `("max_currency_exposure", None)` to the `attributes` list in `StrategyResolver.load_strategy` |
| freqtrade/persistence | *(none)* | Read-only consumer of already-documented `get_trades_proxy`/`stake_amount`; no manifest or code change |
| freqtrade/optimize | *(none)* | Confirmed parity holds through the existing shared call; no code change |
| *(non-cell)* | `freqtrade/config_schema/config_schema.py` | New optional `max_currency_exposure` schema property, no default, not in any required list |
| *(non-cell)* | `freqtrade/wallets.py` | Enforcement logic inside `Wallets.validate_stake_amount` |
| *(non-cell)* | `tests/test_wallets.py`, `tests/strategy/test_strategy_loading.py` | New/extended test coverage |
| *(non-cell)* | `docs/configuration.md` | New documentation entries |

## Root Cause Analysis
Not applicable (net-new feature, not a defect). Summary from Investigation: the single correct injection point is `Wallets.validate_stake_amount`, which every live/backtest × new-entry/DCA path already funnels through; the one required correction is reading the new config key via `.get(...)` rather than `[...]`, because — unlike `stake_amount`/`max_open_trades` — this key is intentionally optional and non-schema-required, so `StrategyResolver._override_attribute_helper` will leave it absent from `config` entirely when unset.

## Trace Summary
- Live new entry: `FreqtradeBot.create_trade` → `execute_entry` → `get_valid_enter_price_and_stake` → `Wallets.validate_stake_amount` (freqtradebot.py:1209)
- Live DCA: `check_and_call_adjust_trade_position` → `execute_entry(mode="pos_adjust")` → same call site
- Backtest new entry / DCA: `Backtesting._get_adjust_trade_entry_for_candle` → `Wallets.validate_stake_amount` (backtesting.py:1111)
- All four converge on one function body — a single edit there is sufficient and necessary for parity.

## Change Strategy

Implementation order (dependency-first):

1. **`freqtrade/config_schema/config_schema.py`** — add, right after `last_stake_amount_min_ratio` (~line 85):
   ```python
   "max_currency_exposure": {
       "description": (
           "Maximum fraction of total tradable capital that may be committed at once "
           "to positions sharing the same quote/underlying currency. Optional; unset "
           "means no cap."
       ),
       "type": "number",
       "minimum": 0.0,
       "maximum": 1.0,
   },
   ```
   No `default` key. Not added to `SCHEMA_TRADE_REQUIRED`, `SCHEMA_BACKTEST_REQUIRED(_FINAL)`, or `SCHEMA_MINIMAL_REQUIRED`.

2. **`freqtrade/strategy/interface.py`** — right after the `max_open_trades: IntOrInf` block (~line 78-79):
   ```python
   # Optional cap on capital exposure to a single underlying/quote currency; None disables it
   max_currency_exposure: float | None = None
   ```

3. **`freqtrade/resolvers/strategy_resolver.py`** — in the `attributes` list, immediately after `("max_open_trades", float("inf")),`:
   ```python
   ("max_currency_exposure", None),
   ```
   No change to `_override_attribute_helper` or `_normalize_attributes` — the existing `None`-default branch already does the right thing (verified in Investigation): config wins if set; else strategy's non-`None` value flows into config; else the key stays absent.

4. **`freqtrade/wallets.py`** — inside `validate_stake_amount`, after the existing `trade_amount` block and before the `min_stake_amount` checks:
   ```python
   max_currency_exposure = self._config.get("max_currency_exposure")
   if max_currency_exposure:
       currency = self._exchange.get_pair_quote_currency(pair)
       current_exposure = sum(
           t.stake_amount for t in Trade.get_open_trades() if t.safe_quote_currency == currency
       )
       exposure_headroom = max(
           max_currency_exposure * self.get_total_stake_amount() - current_exposure, 0
       )
       if exposure_headroom < max_allowed_stake:
           self._local_log(
               f"Exposure to {currency} would exceed max_currency_exposure "
               f"({max_currency_exposure:.2%}) for pair {pair}; "
               f"capping additional stake to {exposure_headroom}."
           )
           max_allowed_stake = exposure_headroom
   ```
   Placed so it participates in the same downstream min-stake-amount rejection branch and the same generic "too big, adjusting to {max_allowed_stake}" message that already exists — the new `_local_log` line adds the *why*, the existing code still owns the actual clamp-then-reject mechanics. No signature change to `validate_stake_amount`.

## Specification Impact
None of the four touched CODEMANIFEST files require edits:
- `freqtrade/strategy` — `IStrategy`'s documented property list is already non-exhaustive (omits `max_open_trades`, `trailing_stop`, etc. today); adding one more undocumented-at-that-granularity attribute does not contradict any annotation.
- `freqtrade/resolvers` — `StrategyResolver.load_strategy` is documented at the whole-method level ("find and instantiate... by name in config['strategy']"); its internal attribute-merge list is already abstracted away.
- `freqtrade/persistence` — only reads already-documented `get_trades_proxy` behavior; no new obligation added to that cell's contract.
- `freqtrade/optimize` — `Wallets` is not an imported type in this manifest and the `backtest()` annotation doesn't enumerate stake-sizing internals; unaffected.

This is a case where the correct manifest action is **no edit**, not a missed reconciliation — to be explicitly confirmed (not skipped) in the Manifest Reconciliation step.

## Usage Impact
None. `orm_pattern`, `dynamic_loading`, and `lifecycle_hooks` all remain valid as written — no usage recipe references stake-sizing or attribute-merge internals at the level being changed.

## Compatibility Verification
**Backward compatible.** When `max_currency_exposure` is absent from config (every existing strategy/config today), `.get(...)` returns `None`, the `if max_currency_exposure:` guard is falsy, and `validate_stake_amount` executes byte-for-byte the same as before. No signature, return type, file path, or manifest guarantee changes. Confirmed no breaking change per Investigation Report.

## Test Strategy
- **`tests/test_wallets.py`** — extend `validate_stake_amount` coverage:
  - regression: unset `max_currency_exposure` ⇒ identical result to current behavior (parametrize existing cases or add one explicit case)
  - resize-down: two pairs share a quote currency, one already open; opening/adding to the second beyond the cap gets clamped to the computed headroom
  - reject: clamped amount falls below `min_stake_amount` ⇒ returns `0` via the existing rejection branch
  - boundary: combined exposure exactly equals the cap ⇒ allowed (not rejected)
- **`tests/strategy/test_strategy_loading.py`** — mirror `test_strategy_override_max_open_trades` / `test_strategy_max_open_trades_infinity_from_*` with new `test_strategy_override_max_currency_exposure`-style cases: config overrides strategy; strategy value flows into config when config omits it; default stays unset (key absent from `config`, not merely `None`) when neither sets it — this last assertion specifically guards the `.get()` correction.
- **Parity test** — one test constructing two `Wallets` instances (`is_backtest=True` / default `False`) with identical injected trade/config state, asserting `validate_stake_amount` returns the same clamped value in both — directly guards the live/backtest consistency requirement called out by the user.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Using `self._config["max_currency_exposure"]` instead of `.get()` | Low (explicitly called out) | High — `KeyError` for every strategy that doesn't opt in, i.e. all existing users | Implementer must use `.get(...)`; test asserts key can be absent |
| Double-counting or under-counting exposure during DCA | Low (verified additive logic in Investigation) | Medium — wrong cap enforcement | Test case exercises DCA add specifically |
| New log line spamming backtest logs | Low — `_local_log` already suppresses non-`warning`/... in backtest mode via `self._is_backtest` | Low | No change needed; relies on existing suppression, verified in Investigation |
| Docs drift (forgetting to mention resize-vs-reject semantics) | Low | Low (cosmetic) | Explicit docs task in plan, reviewed at Reporting step |

---

Do you approve this plan? Proceed to implementation?
