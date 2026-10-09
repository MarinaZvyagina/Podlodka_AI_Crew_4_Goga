# R01-TB-BF-09

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: False
Cost: $2.0601009
Duration: 434254ms, turns: 53

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add a configurable, per-strategy exposure cap that limits the fraction of tradable capital that may be committed to a single "underlying currency" (grouped by each open trade's pair quote currency, via the existing `Exchange.get_pair_quote_currency`) across all simultaneously open trades, enforced through the single shared sizing-validation path (`Wallets.validate_stake_amount`) so live/dry-run and backtest see identical accept/resize/skip decisions for the same config and open-trade state.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| freqtrade/strategy | New per-strategy configurable attribute lives on `IStrategy`, the documented strategy contract | High |
| freqtrade/resolvers | `StrategyResolver.load_strategy`'s config-override wiring is the established mechanism for making a new `IStrategy` attribute config-overridable | High |
| freqtrade/persistence | `Trade`/`LocalTrade.get_trades_proxy` is the read dependency used to enumerate open trades identically in both modes | Medium (dependency only, unmodified) |
| freqtrade/exchange | `Exchange.get_pair_quote_currency` is the read dependency used to derive the grouping key | Medium (dependency only, unmodified) |
| freqtrade/optimize | Owns `Backtesting`, one of the two callers into the (undocumented) `Wallets.validate_stake_amount` path | Low — call site unchanged |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| freqtrade/persistence | `Trade.get_trades_proxy(is_open=True)` (already exported: `Trade`, `LocalTrade`) is the exact mechanism `Wallets` already relies on elsewhere (`_update_dry`, `total_open_trades_stakes`) to see live-DB trades or backtest in-memory trades interchangeably. The new exposure-cap logic reuses this, not a new dependency shape. |
| freqtrade/exchange | `Exchange.get_pair_quote_currency(pair)` (existing method on the documented `Exchange` type) supplies the "underlying currency" grouping key for both currently-open trades and the candidate pair. No new method needed. |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| freqtrade/optimize | `Backtesting`'s documented methods (`backtest`, `backtest_one_strategy`, `init_backtest`, `reset_backtest`, etc.) and its call into `get_valid_entry_price_and_stake` do not change signature or behavior text — the cap is enforced entirely inside `Wallets.validate_stake_amount`, which `Backtesting` already calls with the same arguments as today. No manifest-relevant text in this cell describes stake-sizing internals, so nothing here needs to change. |
| freqtrade/plugins, freqtrade/plugins/pairlist, freqtrade/plugins/protections, freqtrade/data | No behavioral, data-flow, or manifest participation in stake sizing or the currency grouping. Pairlist filtering (which enforces single quote-currency-equals-stake_currency for *whitelisted* pairs) is a pre-existing, unrelated invariant — it does not gate what currencies *already-open* trades can be grouped by, and is out of scope to touch. |
| freqtrade/configuration | `Configuration`/config-file loading cell is generic plumbing; the new config key needs no special handling there beyond the existing generic pass-through, and its own CODEMANIFEST doesn't enumerate individual config keys. |

## Usage Relationships

| Usage | Relevance |
|---|---|
| `dynamic_loading` (freqtrade/resolvers) | Documents how `StrategyResolver` turns a config name into a live `IStrategy` instance; the new attribute is added via the resolver's existing (undocumented-in-manifest, code-level) attribute-override list, which the `dynamic_loading` practice text doesn't need to change since it operates at the class-loading level, not per-attribute. |
| `lifecycle_hooks` (freqtrade/strategy) | Not directly relevant — the new attribute is a plain configuration value, not a lifecycle hook. |

## Semantic Participation Summary
- **freqtrade/strategy**: participates because the cap is, by requirement, "configurable per strategy" — it must be expressible as an `IStrategy` class attribute the way `stoploss`/`minimal_roi`/`max_open_trades`-style settings are, even though `max_open_trades` itself isn't currently listed as a manifest property (inconsistent granularity already exists there; the manifest reconciler step will decide whether the new attribute needs a property entry).
- **freqtrade/resolvers**: participates because `StrategyResolver.load_strategy` owns the only place config values get merged onto strategy attributes; this is pure code-level wiring addition (new tuple in the existing `attributes` list), not a change to the resolver's documented method signature or behavior text.
- **freqtrade/persistence** and **freqtrade/exchange**: participate only as unmodified read dependencies whose existing documented types/methods (`Trade`/`LocalTrade` trade proxy, `Exchange.get_pair_quote_currency`) are consumed as-is.
- **freqtrade/wallets.py** (`Wallets.validate_stake_amount`, undocumented — no cell owns it) is where all new *behavior* lives. It is in-scope for implementation but has no CODEMANIFEST to reconcile since it was never a documented cell.
- **freqtrade/config_schema/config_schema.py** and **freqtrade/constants.py** are in-scope for implementation (schema validation for the new config key) but are undocumented plumbing files, not cells.
- **freqtrade/freqtradebot.py** and **freqtrade/optimize/backtesting.py**: explicitly *not* touched — this is the crux of the "identical live/backtest behavior" requirement. Both already call `Wallets.validate_stake_amount` with the same argument shape; putting the new logic entirely inside that one shared method is what guarantees parity without duplicating logic in two call sites.

## Final Investigation Scope
1. freqtrade/wallets.py (primary implementation target, undocumented cell)
2. freqtrade/strategy (IStrategy attribute — documented cell, in scope)
3. freqtrade/resolvers (StrategyResolver override wiring — documented cell, in scope)
4. freqtrade/persistence (dependency, read-only — `Trade`/`LocalTrade.get_trades_proxy`)
5. freqtrade/exchange (dependency, read-only — `Exchange.get_pair_quote_currency`)
6. freqtrade/config_schema/config_schema.py + freqtrade/constants.py (undocumented plumbing, in scope for schema validation)
7. freqtrade/freqtradebot.py + freqtrade/optimize/backtesting.py — included in investigation *only* to confirm the call sites truly need zero changes (verification, not modification)

## Scope Risks
- **Under-scoping risk**: if the investigation step finds `Wallets.validate_stake_amount`'s current signature can't cleanly carry the extra state needed (e.g., strategy reference, or a way to know this is a position-adjustment vs. new entry) without a signature change, that would ripple into both `freqtradebot.py` and `backtesting.py` call sites, expanding scope. Must confirm during investigation that `self._config` + `Trade.get_trades_proxy` + the existing `pair`/`trade_amount` parameters are sufficient.
- **Over-scoping risk**: being tempted to also update `freqtrade/plugins/pairlist` (since it's the other place "currency" concepts appear) — explicitly excluded above since whitelist quote-currency filtering is an unrelated, pre-existing invariant not part of this feature's contract.
- **Manifest risk**: `freqtrade/strategy` CODEMANIFEST's `IStrategy` properties list is not exhaustive today (omits `max_open_trades`, `position_adjustment_enable`, etc.) — the manifest-reconciler step must make a consistent call on whether the new attribute gets a property entry, rather than the implementer deciding ad hoc.

## Notes
- `freqtrade/wallets.py` and `freqtrade/freqtradebot.py` are both real, heavily-used modules with no CODEMANIFEST coverage — this is a pre-existing documentation gap, not something this change should silently "fix" by inventing a new cell (out of scope: the task only asks for the exposure-cap feature, not for closing unrelated documentation gaps).
- The grouping key decision (pair quote currency via `Exchange.get_pair_quote_currency`) was made during preliminary investigation, not during this scope-resolution step; the investigation step should re-verify this is the correct, minimal concept rather than accepting it uncritically.
