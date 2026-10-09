# R01-TC-BF-07

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: True
Cost: $1.0128363
Duration: 190062ms, turns: 44

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add a new `IProtection` handler (`MaxLosingStreak`) to the `freqtrade/plugins/protections` cell that locks a pair (or the whole bot) for a configurable cool-down once a configurable number of *consecutive* losing trades has occurred — as a streak, not a cumulative-profit or fixed-window count. It reuses the existing IProtection contract (`has_local_stop`, `has_global_stop`, `calculate_lock_end`, `stop_duration*`/`lookback_period*`/`unlock_at` knobs) so ProtectionManager, PairLocks (auto-expiry) and the RPC notification path (`PROTECTION_TRIGGER`/`PROTECTION_TRIGGER_GLOBAL`) require no changes — this is a pure extension-point addition plus its documentation/tests.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `freqtrade/plugins/protections` | Owns `IProtection` contract; new type is a concrete subclass added here | High |
| `freqtrade/persistence` | Provides `LocalTrade`/`Trade` used to read trade history (`close_profit`, `close_date`) for streak evaluation | Medium (dependency only, already imported by cell) |
| `freqtrade/exchange` | Provides `timeframe_to_minutes`, already imported by the cell for candle-based durations | Medium (dependency only, already imported by cell) |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| `freqtrade/persistence` | `Trade.get_trades_proxy(...)` is the data source the new handler queries to reconstruct trade order and detect the loss streak; `LocalTrade` is already a declared Import type in the manifest |
| `freqtrade/exchange` | `timeframe_to_minutes` already backs `stop_duration_candles`/`lookback_period_candles` in `IProtection.__init__`; the new subclass consumes these inherited knobs but adds no new import |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `freqtrade/optimize` (Backtesting) | Consumes `ProtectionManager` generically; no protection-specific code path to change — new handler is picked up automatically via existing dynamic loading, no behavioral participation required |
| `freqtrade/strategy` | `protections` property on `IStrategy` is an untyped `list` already; no schema/type change needed to accept a new `method` string |
| `freqtrade/resolvers` (ProtectionResolver) | Loads any class by name via reflection already; no registry list to update (confirmed: no `AVAILABLE_PROTECTIONS` constant exists in app code) |
| `freqtrade/rpc` (telegram/webhook/rpc_types) | `PROTECTION_TRIGGER(_GLOBAL)` handling is generic over any `ProtectionReturn`; no new message type or per-protection branch needed |
| `freqtrade/configuration` | No JSON-schema validation constrains `protections` list contents; nothing to update |

## Usage Relationships

| Usage | Relevance |
|---|---|
| `extension_point` (inline usage in `freqtrade/plugins/protections/CODEMANIFEST`) | Directly governs how to add a new handler — subclass `IProtection`, set flags, implement `short_desc`/`global_stop`/`stop_per_pair`, register by class name. The new type must be added consistent with this documented extension point |
| No cell-level `.usages/` directory exists under `freqtrade/plugins/protections/` | Confirms no consumer-facing usage docs need updates inside the cell; consumer-facing docs live at `docs/includes/protections.md` (non-cell) |

## Semantic Participation Summary
Only `freqtrade/plugins/protections` has behavioral participation — it is where the new class, its lock-decision logic, and its manifest entry live. `freqtrade/persistence` and `freqtrade/exchange` participate only as already-declared dependencies whose existing contracts (`Trade.get_trades_proxy`, `timeframe_to_minutes`) are consumed as-is, with no new obligations placed on them. All other cells in the schema (`optimize`, `strategy`, `resolvers`, `configuration`) interact with protections only through the already-generic `ProtectionManager`/`IProtection` contract and require zero changes — the extension point was explicitly designed for this kind of addition.

## Final Investigation Scope
- `freqtrade/plugins/protections` (primary — CODEMANIFEST + new implementation file)
- `freqtrade/plugins/protectionmanager.py` (read-only verification that no manager-level change is needed — it is outside the manifested cell boundary per schema but must be traced to confirm the contract assumption)
- Non-architectural, consistency-only artifacts outside the cell system: `tests/plugins/test_protections.py`, `docs/includes/protections.md`

## Scope Risks
- **Under-scoping risk**: if `ProtectionManager.validate_protections` or `freqtradebot.handle_protections` contained protection-name-specific branching, scope would need to expand — Investigation step must confirm this is not the case (initial read of `protectionmanager.py` shows validation is generic over `stop_duration*`/`lookback_period*`/`unlock_at` keys only, not protection-name-specific).
- **Over-scoping risk**: reconciling the pre-existing manifest drift (CooldownPeriod/LowProfitPairs/MaxDrawdown undocumented) is tempting to bundle in, but it is out of scope for this change — expanding it would violate "minimize scope." It should be noted as a Drift finding, not fixed here, unless the manifest reconciler step determines partial reconciliation is unavoidable to keep the manifest internally consistent when adding the new type.
- **Test/docs scope**: these are not cells and not manifest-governed, but the task's product requirement ("configurable per strategy," "visible through existing notification channel") is only verifiable end-to-end via tests — excluding them would leave the change unverified.

## Notes
- No new cell is warranted: this is strictly a new concrete type inside an existing, purpose-built extension-point cell — creating a new cell would violate "one responsibility zone — one cell" by fragmenting a cohesive protection-handler family.
- Confirmed via `goga schema` that `freqtrade/plugins/protections` has no children and its only declared dependencies are `freqtrade/exchange` (`timeframe_to_minutes`) and `freqtrade/persistence` (`LocalTrade`) — matching the Included Dependencies above.
