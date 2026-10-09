# R01-TB-BF-01

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: True
Cost: $1.7553279
Duration: 87591ms, turns: 19

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add a per-strategy configurable exposure cap: the maximum fraction of tradable capital that may be committed to simultaneously-open trades sharing the same underlying (base) currency. When a new trade would push combined base-currency exposure over the limit, it must be skipped or sized down, using the same logging visibility as existing stake-sizing decisions. The check must live in the single shared code path (`freqtrade/wallets.py`) that both the live/dry-run (`freqtradebot.py`) and backtesting (`freqtrade/optimize/backtesting.py`) entry flows already call, so behavior is identical in both modes.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| freqtrade/persistence | Owns `Trade`/`LocalTrade`, `safe_base_currency`, and the enumeration-of-open-trades pattern (`total_open_trades_stakes`) the new exposure sum must replicate | High |
| freqtrade/exchange | Owns `get_pair_base_currency`, the source of "underlying currency" grouping | High |
| freqtrade/optimize | Owns `Backtesting`, one of the two call sites that must observe identical behavior | High |
| freqtrade/strategy | Owns `IStrategy`, the per-strategy config surface the cap is configured through | Medium |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| freqtrade/persistence | Provides the data (open trades, stake amounts, base currency) the new exposure computation reads |
| freqtrade/exchange | Provides the base-currency resolution used to group trades into exposure buckets |
| freqtrade/optimize | Must continue to route through the same shared stake-sizing call, unaffected in its own contract but a behavioral consumer to verify |
| freqtrade/strategy | Config is read per-strategy; `IStrategy`'s documented contract may need to note the new limit is honored, if config-driven limits are already part of its documented behavior |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| freqtrade/plugins/protections | Different risk-control mechanism (post-close, stoploss-guard style); no data-flow or manifest overlap with pre-open sizing |
| freqtrade/plugins/pairlist | Enforces global single quote-currency already; no behavioral participation in per-trade sizing |
| freqtrade/resolvers | Only wires strategy/exchange/pairlist instances together; no sizing logic |
| freqtrade/configuration | Generic config file loading; the new key's validation lives in the undocumented `config_schema.py`, not this cell |
| freqtrade/data | `DataProvider` is OHLCV/informative-pair access, unrelated to capital sizing |

## Usage Relationships

| Usage | Relevance |
|---|---|
| None declared in any of the 10 cells (`goga schema` shows empty `usages: []` everywhere) | No `.usages` practice files exist yet to consult or update for this change |

## Semantic Participation Summary
- **freqtrade/persistence**: supplies the runtime data model (`Trade`/`LocalTrade`) the new check reads from — open trades, their `stake_amount`, and `safe_base_currency`. Any new aggregate query (e.g., "sum of stakes for base currency X") is a consumer of this cell's contract, not a change to it, unless a new helper (analogous to `total_open_trades_stakes`) is added there.
- **freqtrade/exchange**: supplies `get_pair_base_currency`, the sole mechanism by which "underlying currency" is determined. Pure consumption, no contract change expected.
- **freqtrade/optimize**: `Backtesting` is a behavioral witness — it must keep calling the same shared `Wallets` methods so the new cap applies identically. No new type/contract needed here unless the manifest's `Backtesting` annotations explicitly enumerate the sizing limits it respects (needs verification in investigation).
- **freqtrade/strategy**: `IStrategy` is where per-strategy config could either be read directly (`self.config.get(...)`, matching `tradable_balance_ratio`'s pattern) or promoted to a declared attribute (matching `max_open_trades`'s pattern). Investigation must determine which precedent applies before planning.

**Critical gap**: the component that must actually contain the new logic — `freqtrade/wallets.py` (`Wallets.get_trade_stake_amount`/`validate_stake_amount`) — is **not a documented cell** in the current architecture (10/10 cells lint clean, none is `wallets`). Likewise `freqtrade/freqtradebot.py` (live call site), `freqtrade/config_schema/config_schema.py` (new config key), `freqtrade/constants.py`, and `freqtrade/enums/` are all outside the documented spine. This is expected and acceptable per `goga schema`'s own description of `freqtrade/optimize` as composing "exchange, strategy, persistence, resolvers, plugins, and data" — wallets/bot orchestration is intentionally left as undocumented infrastructure around the documented spine.

## Final Investigation Scope
1. freqtrade/persistence (contract-governed — verify no changes needed beyond consumption)
2. freqtrade/exchange (contract-governed — verify no changes needed beyond consumption)
3. freqtrade/optimize (contract-governed — verify `Backtesting`'s documented annotations don't need updating to reflect the new limit)
4. freqtrade/strategy (contract-governed — verify `IStrategy`'s documented config-reading pattern)
5. freqtrade/wallets.py, freqtrade/freqtradebot.py, freqtrade/optimize/backtesting.py (implementation call sites), freqtrade/config_schema/config_schema.py, freqtrade/constants.py — undocumented infrastructure, investigated as plain code (no CODEMANIFEST governs them), changes here follow ordinary engineering review rather than manifest reconciliation.

## Scope Risks
- **Under-scoping risk**: if `IStrategy`'s CODEMANIFEST turns out to document config-driven sizing behavior (even implicitly via annotations), skipping manifest reconciliation there would leave the contract stale. Investigation step must explicitly check `IStrategy` annotations for this.
- **Over-scoping risk**: none of the four documented cells strictly require a *type-level* contract change (the new behavior is additive infrastructure, not a new/changed type in these cells) — pulling them further into planning as if they need modification would waste effort. They are included for **read/verification**, not edit, unless investigation finds otherwise.
- **Governance mismatch risk**: the bulk of the actual implementation (wallets.py, freqtradebot.py, backtesting.py, config_schema.py) sits outside any CODEMANIFEST. The `goga-change` pipeline's manifest/usage reconciliation steps (7–8) will have little or nothing to reconcile for those files; this is expected, not a pipeline failure, and must not be treated as a STOP condition.

## Notes
- The "underlying currency" grouping choice (base currency, not quote/settle) was already validated against the codebase during prior research: `freqtrade/exchange/exchange.py` rejects inverse contracts, and `freqtrade/plugins/pairlist/IPairList.py` enforces a single global quote currency — so quote/settle is constant bot-wide and base currency is the only varying, risk-relevant grouping key.
- No cell currently owns "wallets/stake-sizing" as a documented responsibility. If this feature is judged significant enough to warrant its own documented contract, that would be a `goga-brainstorm`/`goga-apply` architectural addition — out of scope for this `goga-change` maintenance pipeline, and not requested by the user's phrasing ("add support for this kind of exposure cap" reads as a maintenance change to existing behavior, not a new architectural cell).
