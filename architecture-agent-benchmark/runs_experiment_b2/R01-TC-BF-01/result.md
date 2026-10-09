# R01-TC-BF-01

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: False
Cost: $1.1842002
Duration: 197303ms, turns: 50

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add a new concrete `IProtection` handler (`MaxConsecutiveLosses`) to the `freqtrade/plugins/protections` cell that locks entries — per-pair and bot-wide — after a configurable streak of consecutive losing trades, using a configurable cooldown. The handler reuses existing `IProtection` base-class knobs (`trade_limit`, `stop_duration`/`stop_duration_candles`/`unlock_at`) and existing `Trade` persistence queries. No behavioral changes are needed in `ProtectionManager`, `ProtectionResolver`, or the RPC notification path, since those already treat any `IProtection` subclass generically.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `freqtrade/plugins/protections` | Owns `IProtection` contract; new concrete handler is added here; CODEMANIFEST must be reconciled | Primary |
| `freqtrade/persistence` | Provides `LocalTrade`/`Trade` types already imported by this cell for trade-history queries the new handler needs | Direct dependency (existing) |
| `freqtrade/exchange` | Provides `timeframe_to_minutes`, already imported by `iprotection.py` for candle-based durations | Direct dependency (existing) |
| `freqtrade/plugins` | Parent cell; owns `ProtectionManager` which consumes `IProtection` generically | Behavioral proximity |
| `freqtrade/resolvers` | Owns `ProtectionResolver`, which dynamically loads any class dropped into `plugins/protections` by config `method` name | Behavioral proximity |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| `freqtrade/persistence` | New handler calls `Trade.get_trades_proxy(...)` (already an existing import path in sibling handlers) to fetch trade history for streak calculation — no new type needed, existing `LocalTrade`/`Trade` imports suffice |
| `freqtrade/exchange` | New handler inherits `IProtection.__init__`, which already converts candle-based durations via `timeframe_to_minutes` — no direct new usage in the new file itself |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `freqtrade/plugins` (ProtectionManager) | No code change required — `global_stop`/`stop_per_pair` already iterate `has_global_stop`/`has_local_stop` generically; adding a handler requires zero edits here |
| `freqtrade/resolvers` (ProtectionResolver) | No code change required — dynamic class loading by `method` name already works for any file dropped in the protections directory; no enum/allowlist exists to update |
| `freqtrade/strategy` | `protections: list = []` on `IStrategy` is already a generic list of dicts; no schema change needed to accept a new `method` value |
| `freqtrade/optimize`, `freqtrade/data`, `freqtrade/configuration` | No behavioral participation in this change; not touched by protection evaluation logic |
| freqtradebot.py (`handle_protections`, RPC message dispatch) | Outside the documented cell forest (not owned by any CODEMANIFEST-bearing cell); already fires `PROTECTION_TRIGGER`/`PROTECTION_TRIGGER_GLOBAL` generically for any lock returned by any protection — no edit needed and not in scope of manifest reconciliation |

## Usage Relationships

| Usage | Relevance |
|---|---|
| `freqtrade/plugins/protections` extension_point (inline Usage in CODEMANIFEST) | Directly governs how a new concrete handler must be added — subclass `IProtection`, set `has_global_stop`/`has_local_stop`, implement `short_desc`, `global_stop`, `stop_per_pair` |
| `docs/includes/protections.md` | Not a Goga cell/usage artifact but the project's existing end-user documentation convention for protections; must be updated for consistency but is tracked as an out-of-cell doc artifact, not a `.usages/` practice file |
| `tests/plugins/test_protections.py` | Existing test-suite convention (`AVAILABLE_PROTECTIONS`, `generate_mock_trade`) that must be extended; out-of-cell test artifact |

## Semantic Participation Summary
Only `freqtrade/plugins/protections` has actual behavioral/manifest participation: it gains a new type (`IProtection::MaxConsecutiveLosses`) and its CODEMANIFEST must document that type per the `extension_point` convention already recorded there. `freqtrade/persistence` and `freqtrade/exchange` participate only as pre-existing, unchanged dependencies (their types are consumed via already-declared import paths in the cell; nothing new is imported from them). `freqtrade/plugins` and `freqtrade/resolvers` are proximate but not touched — their generic mechanisms already cover any new handler by construction. Docs and tests are required deliverables per the task but sit outside the documented cell forest.

## Final Investigation Scope
- `freqtrade/plugins/protections` (primary — implementation + CODEMANIFEST reconciliation)
- `docs/includes/protections.md` (out-of-cell doc update)
- `tests/plugins/test_protections.py` (out-of-cell test update)

No other cell requires investigation or modification.

## Scope Risks
- **Under-scoping risk**: if the new handler needed a new shared type or changed `ProtectionManager`/`ProtectionResolver` behavior (e.g., a new required config-validation rule), those cells would need to be pulled in — investigation (Step 2) must explicitly re-confirm `ProtectionManager.validate_protections` needs no new validation rule for this handler's config (it currently only validates `stop_duration`/`lookback_period`/`unlock_at` mutual exclusivity, which is generic).
- **Over-scoping risk**: touching `freqtrade/plugins/protectionmanager.py` or `freqtrade/resolvers/protection_resolver.py` would be unnecessary edits to cells with no behavioral change — must be avoided to keep the diff minimal and avoid manifest drift in cells that didn't actually change.

## Notes
- No JSON-schema enum (unlike `AVAILABLE_PAIRLISTS`) restricts protection `method` names, confirmed via prior grep — no schema cell holds such a list to update.
- The new handler's "streak" semantics (count consecutive losers walking backward from the most recent close, bounded by the existing `lookback_period` window) is a novel *algorithm* within the cell but not a novel *contract shape* — it still fits `IProtection.global_stop`/`stop_per_pair`/`short_desc` exactly, so no CODEMANIFEST contract-level (signature) changes to `IProtection` itself are needed, only a new type entry.
