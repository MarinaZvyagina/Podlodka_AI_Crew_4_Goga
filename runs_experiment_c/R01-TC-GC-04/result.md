# R01-TC-GC-04

Condition: goga_native_architecture
Base tag: condition-c-r01-v1
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: False
Cost: $1.0746086999999998
Duration: 167954ms, turns: 38

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add a new concrete `IProtection` handler (working name: `MaxLosingStreak`) to the `freqtrade/plugins/protections` cell that locks trading after a configurable number (N) of consecutive losing trades in a row, both per-pair (`stop_per_pair`) and bot-wide (`global_stop`). The streak threshold and cooldown duration must be configurable in the protection's config dict, alongside the pattern already used by sibling handlers. Non-cell artifacts (docs, tests) that enumerate/exercise sibling protections must be updated in parallel so the new handler is documented and covered like its siblings.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `freqtrade/plugins/protections` | Owns `IProtection` contract and all concrete handlers; new class is added here | High |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| `freqtrade/persistence` | Supplies `Trade.get_trades_proxy`/`LocalTrade` used to fetch closed trades and read `close_profit`/`close_date` to determine loss streaks — same data source as `StoplossGuard`/`LowProfitPairs` |
| `freqtrade/exchange` | Supplies `timeframe_to_minutes`, already consumed transitively via `IProtection.__init__` for `lookback_period_candles`; no new direct usage needed by the new handler itself |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `freqtrade/plugins` (ProtectionManager) | Dispatches any `IProtection` subclass dynamically by class name string from config; no code change required to register the new handler |
| `freqtrade/resolvers` (ProtectionResolver) | Loads protection classes by name via generic `IResolver.load_object`; no registry/enum to update |
| `freqtrade/rpc` | `RPCMessageType.PROTECTION_TRIGGER`/`PROTECTION_TRIGGER_GLOBAL` notifications are already emitted generically by `freqtradebot.handle_protections` for any `ProtectionReturn(lock=True, ...)`; no new notification code needed |
| `freqtrade/constants` | No `AVAILABLE_PROTECTIONS` enum or protections JSON-schema entry exists to update — protections config is validated only by `ProtectionManager.validate_protections` (generic, key-based, not name-specific) |

## Usage Relationships
No `.usages/*.md` files exist for this cell (only `CODEMANIFEST`); no cell-level practices to update. No project-level `.goga/usages/` practices apply (`goga config codemanifest.usages/.annotations` both returned "Option not found").

## Semantic Participation Summary
Only `freqtrade/plugins/protections` participates behaviorally — it is where the new type is declared, where the CODEMANIFEST contract lives, and where sibling classes (`StoplossGuard`, `LowProfitPairs`, `MaxDrawdown`, `CooldownPeriod`) establish the implementation pattern to follow. `persistence` and `exchange` are pre-existing, unmodified dependencies consumed exactly as sibling handlers already consume them — no new contract obligations on those cells. `docs/includes/protections.md` and `tests/plugins/test_protections.py` are outside the cell/manifest system (no CODEMANIFEST governs them) but must be updated per the task's explicit parity requirement with sibling handlers; they are tracked as auxiliary non-cell artifacts, not architectural scope.

## Final Investigation Scope
- `freqtrade/plugins/protections` (primary — CODEMANIFEST + implementation)
- Auxiliary (non-cell, no manifest governance): `docs/includes/protections.md`, `tests/plugins/test_protections.py`

## Scope Risks
- **Under-scoping risk**: none identified — the feature is fully self-contained in one cell by design (extension-point pattern documented in the cell's own `Annotations`).
- **Over-scoping risk**: mistakenly touching `ProtectionManager`/`ProtectionResolver`/`freqtradebot.py` — these require zero changes since dispatch is name-based and notification is generic; touching them would violate "minimize scope" and "never modify unrelated cells."
- **Naming collision risk**: the new config key for the streak threshold must not reuse `trade_limit` (already means "number of trades" for `StoplossGuard`/generic count, distinct semantics) — must pick a distinct, unambiguous key.

## Notes
CODEMANIFEST for this cell already anticipates this exact feature: its `Annotations` block for `IProtection` says the cell handles "drawdown, consecutive losses, low-profit streaks, cooldowns" — "consecutive losses" is explicitly named as an intended handler category not yet implemented. This confirms the addition is within the cell's own documented charter, not an architectural expansion.
