# R01-TB-BF-06

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: False
Cost: $3.5985255
Duration: 597417ms, turns: 86

## Agent's own summary

# Change Plan

## Task Classification
Feature (net-new, opt-in risk-control capability). No bugfix, no refactor of existing behavior.

## Affected Cells
| Cell | Files to Modify | What Changes |
|---|---|---|
| freqtrade/exchange | `freqtrade/exchange/exchange.py` | Add `get_pair_underlying_currency(pair) -> str` method next to `get_pair_base_currency` (lines 577-583). No CODEMANIFEST change (sibling methods already undocumented). |
| freqtrade/resolvers | `freqtrade/resolvers/strategy_resolver.py` | Add `("max_underlying_currency_exposure", None)` to the `attributes` list (line 82, after `max_open_trades`). No CODEMANIFEST change (internal list, not manifest-tracked). |
| freqtrade/strategy | `freqtrade/strategy/interface.py` | Add `max_underlying_currency_exposure: float | None = None` class attribute (near `max_open_trades: IntOrInf` at line 79). No CODEMANIFEST change (sibling attributes already undocumented). |
| (non-cell) | `freqtrade/wallets.py` | Core enforcement in `validate_stake_amount`; new private helper for committed-stake-per-currency. |
| (non-cell) | `freqtrade/config_schema/config_schema.py` | New JSON-schema property. |
| (non-cell) | `docs/configuration.md` | New table row + short explanatory paragraph. |
| (non-cell, tests) | `tests/test_wallets.py`, `tests/exchange/test_exchange.py`, `tests/strategy/test_strategy_loading.py` | New/extended test coverage. |

## Root Cause Analysis
Net-new capability, not a defect. Investigation confirmed both live and backtest funnel every entry/position-increase through the single shared `Wallets.validate_stake_amount` chokepoint, making it the only insertion point that guarantees live/backtest parity by construction (shared code, not shared behavior re-implemented twice).

## Trace Summary
`execute_entry` (live: create_trade, DCA, bot-loop retry, RPC force-entry) and `_enter_trade` (backtest: all 3 loop call sites) both resolve to `get_valid_enter_price_and_stake`/`get_valid_entry_price_and_stake` → `Wallets.validate_stake_amount`. No bypass exists. `Trade.get_trades_proxy(is_open=True)` is symmetric by contract (DB query in live, `Trade.bt_trades` filter in backtest).

## Change Strategy

**1. `freqtrade/exchange/exchange.py`** — after `get_pair_base_currency` (line 583), add:
```python
def get_pair_underlying_currency(self, pair: str) -> str:
    """
    Return the currency a pair's exposure should be measured against for concentration-risk
    purposes: the settlement/margin currency for futures, falling back to the quote currency
    for spot (where there is no separate settle currency).
    """
    market = self.markets.get(pair, {})
    return market.get("settle") or market.get("quote", "")
```

**2. `freqtrade/resolvers/strategy_resolver.py`** — in the `attributes` list (line 58-83), add `("max_underlying_currency_exposure", None)` directly after `("max_open_trades", float("inf")),` (line 82). No other change needed — `_override_attribute_helper`'s existing `elif default is not None` branch is skipped for `None` default (matches existing pattern for optional-if-unset attributes, e.g. `stoploss`/`stake_amount` which also use `None` default), so absence stays absence, not coerced to a value.

**3. `freqtrade/strategy/interface.py`** — after `max_open_trades: IntOrInf` (line 79), add:
```python
    # Maximum fraction of tradable capital that may be committed at once to positions
    # sharing the same underlying (settle/quote) currency. None disables the check.
    max_underlying_currency_exposure: float | None = None
```

**4. `freqtrade/wallets.py`** — two changes:

a) New private helper, placed right before `validate_stake_amount` (before line 410):
```python
def _get_underlying_currency_committed_stake(self, pair: str) -> tuple[str, float]:
    """
    Sum of stake amounts currently committed to open trades sharing `pair`'s underlying
    currency (as returned by Exchange.get_pair_underlying_currency).
    """
    currency = self._exchange.get_pair_underlying_currency(pair)
    committed = sum(
        trade.stake_amount
        for trade in Trade.get_trades_proxy(is_open=True)
        if self._exchange.get_pair_underlying_currency(trade.pair) == currency
    )
    return currency, committed
```

b) Inside `validate_stake_amount` (lines 410-459), immediately after the existing:
```python
max_allowed_stake = min(max_stake_amount, self.get_available_stake_amount())
if trade_amount:
    max_allowed_stake = min(max_allowed_stake, max_stake_amount - trade_amount)
```
insert:
```python
max_underlying_currency_exposure = self._config.get("max_underlying_currency_exposure")
if max_underlying_currency_exposure is not None:
    currency, committed = self._get_underlying_currency_committed_stake(pair)
    currency_cap = self.get_total_stake_amount() * max_underlying_currency_exposure
    currency_headroom = max(currency_cap - committed, 0)
    if currency_headroom < max_allowed_stake:
        self._local_log(
            f"Underlying currency exposure limit reached for {pair}: "
            f"{committed:.8f} {self._stake_currency} already committed to {currency}-settled "
            f"trades, limit is {max_underlying_currency_exposure:.2%} of total capital "
            f"({currency_cap:.8f} {self._stake_currency}) - capping available stake to "
            f"{currency_headroom:.8f}.",
            level="info",
        )
        max_allowed_stake = currency_headroom
```
The rest of the method (min-stake skip check, max-stake resize, string/zero guard) is untouched — it already consumes `max_allowed_stake` generically, so it will naturally skip (if `currency_headroom < min_stake_amount`) or resize (otherwise) using its existing log lines, reusing infrastructure per the task requirement.

**5. `freqtrade/config_schema/config_schema.py`** — after `max_entry_position_adjustment` (lines 877-881), add:
```python
"max_underlying_currency_exposure": {
    "description": (
        "Maximum fraction of tradable capital that may be committed at once to positions "
        f"sharing the same underlying (settlement/quote) currency. {__IN_STRATEGY}"
    ),
    "type": "number",
    "minimum": 0.0,
    "maximum": 1.0,
},
```

**6. `docs/configuration.md`** — add a table row after the `last_stake_amount_min_ratio` row (line 172):
```
| `max_underlying_currency_exposure` | Maximum fraction of tradable capital that may be committed at once to positions sharing the same underlying (settlement/quote) currency, across all open trades. [More information below](#configuring-amount-per-trade). <br>*Not set by default (no limit).* <br> **Datatype:** Float (as ratio) between `0.0` and `1.0`.
```
Plus a short paragraph in the "Configuring amount per trade" section (after the `last_stake_amount_min_ratio` explanation, ~line 399) explaining the settle/quote-currency grouping and giving a one-line example (e.g., several BTC-settled futures capped at 50% combined).

## Specification Impact
None. No CODEMANIFEST in `freqtrade/exchange`, `freqtrade/resolvers`, or `freqtrade/strategy` requires modification — all three additions land in each cell's already-undocumented surface (verified in Investigation: manifests list curated subsets, and direct siblings of each new element are already absent from their respective manifests).

## Usage Impact
None. No `.usages` file in any of the three cells describes entry-sizing, attribute-override lists, or per-pair currency helpers; none require updates.

## Compatibility Verification
**Backward compatible.** `max_underlying_currency_exposure` defaults to `None` everywhere it's introduced (class attribute, resolver default, absent from config); the new block in `validate_stake_amount` is a no-op (`if max_underlying_currency_exposure is not None:`) unless a user explicitly opts in. All existing call signatures, return types, and log message formats for the untouched paths are preserved exactly.

## Test Strategy
- `tests/test_wallets.py`: add new parametrized case(s) alongside `test_validate_stake_amount`, mocking `Wallets.get_available_stake_amount`, `Wallets.get_total_stake_amount`, and `freqtrade.persistence.models.Trade.get_trades_proxy` (returning fake trades with `.pair`/`.stake_amount`) to cover: (a) cap not set → unchanged behavior (regression guard), (b) cap set, headroom ≥ requested stake → unchanged, (c) cap set, 0 < headroom < requested → resized down to headroom, (d) cap set, headroom ≤ 0 → trade skipped (returns 0), (e) position-adjustment case where the trade's own existing stake already counts toward `committed`.
- `tests/exchange/test_exchange.py`: unit test for `get_pair_underlying_currency` covering a futures market with `settle` set and a spot market without it (falls back to `quote`).
- `tests/strategy/test_strategy_loading.py`: new test mirroring `test_strategy_override_max_open_trades`, asserting config-set value overrides strategy attribute, and that an unset strategy/config leaves `max_underlying_currency_exposure` as `None` (not coerced).
- Run full `pytest tests/test_wallets.py tests/exchange/test_exchange.py tests/strategy/test_strategy_loading.py tests/test_freqtradebot.py tests/optimize/test_backtesting.py -q` to catch regressions in both call sites.

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Double-counting a position-adjustment trade's own stake when computing headroom | Low | Medium (over-restrictive sizing) | By design `committed` already includes the trade's current stake (it's one of the open trades), so headroom naturally represents only the *additional* room — verified by dedicated test case (e). |
| `market.get("settle")` returning `None` string-like sentinel instead of falling through | Low | Low | Use `or` (not `market.get("settle", market.get("quote"))`) so an explicit `None`/empty-string settle correctly falls back to quote. |
| Log message spam in tight backtest loops | Low | Low | Reuses `self._local_log`, which already no-ops at info level for backtest mode (`_is_backtest` gate) — no new spam risk beyond what existing sizing messages already produce. |
| Floating-point cap boundary flakiness in tests | Medium | Low | Use `pytest.approx` / generous headroom margins in new test cases, consistent with existing float-based wallet tests. |

---

Do you approve the plan? Proceed to implementation?
