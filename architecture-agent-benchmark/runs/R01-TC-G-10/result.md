# R01-TC-G-10

Condition: goga
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Cost: $0.7615878
Duration: 130456ms, turns: 36

## Agent's own summary

Good — no JSON schema constrains protection config fields. Scope is confirmed tight to the protections cell + tests + docs. Producing the Scope Resolution Report:

# Scope Resolution Report

## Task Summary
Add a new `IProtection` handler to `freqtrade/plugins/protections/` that locks trading after N *consecutive* losing trade closes in a row (streak reset by any winning close), supporting both per-pair (`stop_per_pair`/`has_local_stop`) and bot-wide (`global_stop`/`has_global_stop`) modes, each with a configurable streak-length threshold and a configurable `stop_duration`/`stop_duration_candles` cooldown, following the exact conventions of the sibling handlers (`StoplossGuard`, `LowProfitPairs`, `CooldownPeriod`, `MaxDrawdown`) in that cell.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `freqtrade/plugins/protections` | Owns `IProtection`, `ProtectionReturn`, and all concrete protection handlers — the new class is added here | High |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| `freqtrade/persistence` | New handler reads closed trades via `Trade.get_trades_proxy`/`LocalTrade` to evaluate the loss streak, identical to sibling handlers |
| `freqtrade/exchange` | `IProtection.__init__` already resolves `stop_duration`/`lookback_period` via `timeframe_to_minutes`; no new usage needed beyond what the base class provides |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `freqtrade/plugins` (`ProtectionManager`) | Loads handlers generically by class name via `ProtectionResolver`; no code change needed to register a new handler — confirmed no protection class names are referenced outside `plugins/protections` |
| `freqtrade/resolvers` (`ProtectionResolver`) | Purely dynamic class-name loader; behavior-agnostic to which concrete `IProtection` subclasses exist |
| `freqtrade/optimize` (backtesting) | Consumes `ProtectionManager`/`IProtection` polymorphically; no drawdown/streak-specific coupling to change |
| `freqtrade/strategy` | Only supplies the `protections` config list to `ProtectionManager`; no schema enforcement of specific field names found (`grep` confirmed no JSON-schema/constants validation restricts protection config keys beyond `ProtectionManager.validate_protections`, which is generic to `stop_duration`/`lookback_period`/`unlock_at`) |

## Usage Relationships

| Usage | Relevance |
|---|---|
| `freqtrade/plugins/protections` cell's own `extension_point` annotation (in its CODEMANIFEST) | Directly describes how to add a new protection handler — must be followed exactly |
| `docs/includes/protections.md` | Not a cell/CODEMANIFEST-governed usage file, but user-facing documentation listing all available protections and their config knobs — must be updated per existing task requirements (parity with sibling protections' doc sections) |
| `tests/plugins/test_protections.py` | Test file exercising all sibling protections with shared fixtures (`_build_backtest_dt`-style trade construction, `pytest.mark.parametrize` patterns) — new tests must follow this file's existing conventions |

## Semantic Participation Summary
Only `freqtrade/plugins/protections` has true behavioral participation: it is where the new `IProtection` subclass is authored, where its config knobs are parsed, and where its lock decision (`ProtectionReturn`) is computed and returned. `persistence` and `exchange` participate only as already-established dependencies consumed through the existing `IProtection` base class and `Trade` proxy — no new coupling is introduced. `ProtectionManager`/`ProtectionResolver`/backtesting participate at runtime only through the pre-existing generic dynamic-loading and polymorphic-dispatch mechanism, which requires zero code changes to support a new handler — this is precisely the "extension point" the cell's CODEMANIFEST documents. Documentation (`docs/includes/protections.md`) and tests (`tests/plugins/test_protections.py`) are non-cell artifacts that still fall within the task's explicit scope.

## Final Investigation Scope
- `freqtrade/plugins/protections/` (primary — new file, CODEMANIFEST update, `.usages` if applicable)
- `tests/plugins/test_protections.py` (test coverage)
- `docs/includes/protections.md` (user-facing docs)

## Scope Risks
- **Under-scoping risk**: none identified for runtime wiring — `ProtectionManager`/`ProtectionResolver` genuinely need no changes since they load handlers by class name string from user config alone.
- **Over-scoping risk**: it would be tempting to touch `ProtectionManager` or `ProtectionResolver` "for completeness," but that would violate the "extension point" contract already documented in the cell's CODEMANIFEST and add unrelated diff — explicitly excluded.
- **Naming collision risk**: must pick a class name that doesn't collide with existing protections and reads clearly for both modes (e.g. `StoplossGuard` reuses one class for global/local via a config flag `only_per_pair`) — the new handler should follow that same one-class-two-modes pattern rather than two separate classes, per sibling convention.

## Notes
No `.goga/config.yml` exists in this project (confirmed via `goga config language` → "not found"), so there are no project-wide base usages/annotations to load; only the cell's own CODEMANIFEST conventions apply. The `freqtrade/plugins/protections/CODEMANIFEST` already anticipates this exact feature, explicitly listing "consecutive losses" in its cell-level `Annotations` description as a category of risk-control handler this cell is meant to hold.
