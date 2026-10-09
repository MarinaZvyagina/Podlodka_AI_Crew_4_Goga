# R01-TB-BF-10

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: False
Cost: $2.4063135
Duration: 431440ms, turns: 68

## Agent's own summary

## Investigation Report

**Task Summary**
Add a per-strategy exposure cap: a configurable fraction of tradable capital that may be committed, across all simultaneously open trades, to positions sharing the same underlying (quote) currency. Must resize/reject new-trade stake sizing identically for live/dry-run and backtest, and surface the decision the same way existing sizing decisions already are.

**Candidate Cells**
| Cell | Reason | Priority |
|---|---|---|
| freqtrade/strategy | `IStrategy.max_currency_exposure` new attribute, declared exactly like `trailing_stop_positive: float \| None = None` | High |
| freqtrade/resolvers | `StrategyResolver.attributes` list entry + config-override wiring, exact `max_open_trades` pattern | High |
| freqtrade/optimize | `Backtesting.get_valid_entry_price_and_stake` — confirmed unchanged call site, receives capped value automatically | High (verify-only) |
| n/a (undocumented) `freqtrade/wallets.py` | `Wallets.get_trade_stake_amount` — sole enforcement point | High |
| n/a (undocumented) `freqtrade/freqtradebot.py` | `FreqtradeBot.get_valid_enter_price_and_stake` — confirmed unchanged call site, receives capped value automatically | High (verify-only) |
| n/a (undocumented) `freqtrade/config_schema/config_schema.py`, `freqtrade/constants.py` | `CONF_SCHEMA` property + required-list check (new key is optional, not required) | Medium |

**Tracing Summary**
Live/dry-run: `FreqtradeBot.create_trade` → `self.wallets.get_trade_stake_amount(pair, self.config["max_open_trades"])` → `execute_entry` → `get_valid_enter_price_and_stake` → `custom_stake_amount` hook → `self.wallets.validate_stake_amount(...)`.
Backtest: `Backtesting.get_valid_entry_price_and_stake` → `self.wallets.get_trade_stake_amount(pair, self.strategy.max_open_trades, update=False)` → `custom_stake_amount` hook → `self.wallets.validate_stake_amount(...)`.
Both paths call the *same* `Wallets` instance method with the same signature `(pair, max_open_trades, update)`. `update` only controls whether `Wallets.update()` re-syncs balances — it does not affect the sizing arithmetic. Enforcing the cap inside `get_trade_stake_amount` therefore guarantees identical output for identical `(pair, wallet state, config)` regardless of caller.

**Data Flow Analysis**
`Trade.total_open_trades_stakes()` (already used inside `get_trade_stake_amount` for `val_tied_up`) transparently branches on `Trade.use_db`: live/dry-run sums via a DB query, backtest sums via `LocalTrade.get_trades_proxy(is_open=True)` in-memory. This is the established, already-shared mechanism for "sum stake of open trades" across both modes. The new per-currency sum will use the same proxying (`Trade.get_open_trades()` / `LocalTrade.get_trades_proxy(is_open=True)`, filtered by `self._exchange.get_pair_quote_currency(trade.pair)`), so it inherits the existing live/backtest parity guarantee rather than inventing a new one. `Exchange.get_pair_quote_currency(pair)` reads `self.markets.get(pair, {}).get("quote", "")` — market metadata loaded identically for live and backtest (both construct a real `Exchange` and load markets before trading starts).

**Manifest Algorithm Analysis**
`freqtrade/strategy` CODEMANIFEST documents `IStrategy` methods/lifecycle hooks and a handful of properties (`minimal_roi`, `stoploss`, `timeframe`, `dp`, `wallets`) but does **not** document `max_open_trades`, `trailing_stop`, or any other plain config-mirrored attribute, despite these existing as real class attributes today. `freqtrade/optimize` CODEMANIFEST documents `Backtesting.backtest`'s algorithm only at the level of "calls strategy lifecycle hooks and records LocalTrades" — it does not enumerate stake-sizing internals, so no algorithm text there references `get_trade_stake_amount` or needs updating. `freqtrade/wallets.py` has no CODEMANIFEST (outside the documented forest).

**Affected Usages**
| Usage | Cell | Classification | Reason |
|---|---|---|---|
| `lifecycle_hooks` | freqtrade/strategy | INDIRECTLY AFFECTED | Describes how a concrete strategy subclasses `IStrategy`; unchanged, but the new attribute follows the same "strategy overrides a subset of base-class attributes" model already documented there |

No other `.usages` files reference stake sizing, `max_open_trades`, or `Wallets`.

**Rejected Hypotheses**
- *"The new attribute must be added to the `freqtrade/strategy` CODEMANIFEST properties list."* Rejected: `max_open_trades` — the direct precedent for this exact kind of attribute — is deliberately absent from that manifest today, confirming plain config-mirrored numeric attributes are out of the documented contract surface by established convention.
- *"Enforcement should live in both `freqtradebot.py` and `backtesting.py` separately for clarity."* Rejected: this reintroduces exactly the two-code-path risk the task explicitly warns against; `Wallets.get_trade_stake_amount` is the one place both callers already funnel through.
- *"The cap should also apply to DCA/position-adjustment sizing."* Rejected as out of scope: `get_valid_entry_price_and_stake`/`get_valid_enter_price_and_stake` skip `get_trade_stake_amount` entirely when `trade is not None` (pos-adjust branch); the task explicitly scopes to "opening a new trade," and extending to DCA would require touching a second, structurally different code path not covered by the request.

**Confirmed Root Cause**
N/A (feature addition, not a bug fix). Confirmed implementation point: `Wallets.get_trade_stake_amount` in `freqtrade/wallets.py`, called identically by both live/dry-run and backtest call sites with no divergent post-processing before it and only the pre-existing, mode-agnostic `custom_stake_amount`/`validate_stake_amount` steps after it.

**Confidence Level**
HIGH — full evidence chain confirmed by direct code reads of both call sites, the shared `Trade`/`LocalTrade` proxying mechanism, the `StrategyResolver` attribute-override pattern, and the config schema precedent for optional strategy-level floats (`trailing_stop_positive`).

**Breaking Change Assessment**
1. Will existing function call with same arguments produce different behavior? NO — new attribute defaults to `None`/absent, and `get_trade_stake_amount` will no-op the new check when unset, so all existing configs/strategies see byte-identical output.
2. Will existing file paths change? NO.
3. Will output format change? NO — return type of `get_trade_stake_amount` remains `float`.
4. Will return value semantics change? NO when the new attribute is unset (the default); when set, this is new, opt-in, documented behavior, not a change to an existing guarantee.
5. Will manifest-defined guarantees be altered? NO — no CODEMANIFEST-documented algorithm or type signature changes (confirmed above the touched types aren't manifest-covered for this attribute class).
6. Will existing tests break? NO expected — behavior is unchanged unless the new config key is explicitly set, which no existing test does.

No breaking change detected. Pipeline may proceed to Planning.
