# R01-TC-GC-05

Condition: goga_native_architecture
Base tag: condition-c-r01-v1
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: False
Cost: $1.0559745
Duration: 162301ms, turns: 37

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add a new risk-control handler to freqtrade's protection extension-point chain that locks a pair (or, in a global variant, all pairs) from new entries after N consecutive losing trades in a row — as opposed to existing handlers that key off stoploss-exit-reason counts (`StoplossGuard`) or cumulative profit (`LowProfitPairs`). The streak threshold and cooldown duration must be configurable per protection instance (per strategy, since protections are configured via `IStrategy.protections`), and the resulting lock must flow through the existing `PairLocks`/`ProtectionManager` mechanism so it auto-expires and is auto-surfaced via the existing `PROTECTION_TRIGGER`/`PROTECTION_TRIGGER_GLOBAL` RPC messages.

## Candidate Cells
| Cell | Reason | Priority |
|---|---|---|
| `freqtrade/plugins/protections` | Owns `IProtection` contract and all concrete handlers (`StoplossGuard`, `CooldownPeriod`, `LowProfitPairs`, `MaxDrawdown`); new handler is added here | High |
| `freqtrade/plugins` | Hosts `ProtectionManager`, which calls `stop_per_pair`/`global_stop` on every registered protection — verify no change needed | Medium (verify-only) |
| `freqtrade/resolvers` | Hosts `ProtectionResolver`, which dynamically loads protection classes by name from the protections directory | Medium (verify-only) |
| `freqtrade/persistence` | Supplies `Trade`/`LocalTrade` and `PairLock`/`PairLocks`, the data source and lock storage the new handler reads/writes through the same API as existing handlers | Medium (dependency-only, no change) |
| `freqtrade/strategy` | Hosts `IStrategy.protections: list` — the per-strategy config surface the user configures the new handler through | Low (verify-only, no change expected) |

## Included Dependencies
| Cell | Behavioral Relevance |
|---|---|
| `freqtrade/persistence` | New handler must call `Trade.get_trades_proxy(...)` exactly as `StoplossGuard`/`LowProfitPairs` do, and reuse `IProtection.calculate_lock_end` (built on `LocalTrade.close_date`) to compute lock expiry — this is how "auto-resume after cooldown" is achieved for free |
| `freqtrade/exchange` (`timeframe_to_minutes`) | Already consumed by `IProtection.__init__` for lookback/stop-duration-in-candles support; new handler inherits this via the base class, no direct use needed |

## Excluded Dependencies
| Cell | Exclusion Reason |
|---|---|
| `freqtrade/plugins` (`ProtectionManager`) | Confirmed by reading `freqtradebot.py::handle_protections` — it calls `stop_per_pair`/`global_stop` polymorphically on every configured `IProtection` and fires RPC messages generically based on the returned `ProtectionReturn`, regardless of concrete class. No new dispatch logic needed. |
| `freqtrade/resolvers` (`ProtectionResolver`) | `load_protection` resolves classes dynamically by class name scanned from `plugins/protections/`; confirmed no static registration list (e.g. no `AVAILABLE_PROTECTIONS` constant) exists anywhere in `freqtrade/constants.py`. A new class file is auto-discoverable with zero resolver changes. |
| `freqtrade/strategy` | `protections: list = []` on `IStrategy` is an untyped/unvalidated list of dicts (method name + free-form config); confirmed no schema enum restricts which protection method names are legal. No change needed for per-strategy configurability — it already exists generically. |
| `freqtrade/rpc` / `freqtrade/enums` (not goga cells) | `RPCMessageType.PROTECTION_TRIGGER(_GLOBAL)` and Telegram/webhook handling of it are already wired generically in `freqtradebot.py`/`telegram.py`/`webhook.py` off `ProtectionReturn`, not off protection class identity. Confirmed via grep — these are plain (non-cell) modules outside the goga architecture and require no edits. |
| `freqtrade/configuration` | Deprecated top-level `protections` config key is unrelated legacy handling; not part of this feature's config path (per-strategy `protections` list is the active path). |

## Usage Relationships
| Usage | Relevance |
|---|---|
| `freqtrade/plugins/protections/.usages/*` | None currently exist (empty `usages: []` in schema) — no consumer practice file to reconcile beyond the cell's own `CODEMANIFEST` extension_point annotation, which already documents "subclass IProtection, register in config" and needs no semantic change, only its enumerated handler list updated |

## Semantic Participation Summary
Only `freqtrade/plugins/protections` participates behaviorally — it is where the new type is declared, and where the CODEMANIFEST body must gain a new type entry (mutation form `IProtection::<NewClassName>`) consistent with the four existing entries. All other candidate cells were traced and confirmed to already generically support an arbitrary new `IProtection` subclass with no code changes: `ProtectionManager`/`freqtradebot.py` dispatch polymorphically, `ProtectionResolver` loads by filename/class scan, `IStrategy.protections` accepts free-form config, and the RPC/Telegram notification path fires off the return value, not the class identity.

## Final Investigation Scope
- `freqtrade/plugins/protections` (primary — new file + CODEMANIFEST update)
- `freqtrade/plugins/protections/CODEMANIFEST` (manifest reconciliation target)
- `tests/plugins/test_protections.py` (non-cell, test coverage)
- `docs/includes/protections.md` (non-cell, user-facing docs)

## Scope Risks
- **Under-scoping risk**: if the new handler needs a distinct lock-side/only_per_side nuance or a different `_reason()` wording convention than `StoplossGuard`, that's contained entirely within the new file — low risk.
- **Over-scoping risk avoided**: initial hypothesis included `freqtrade/resolvers`, `freqtrade/constants` (schema), and an RPC/telegram cell; investigation (grep + read) confirmed all three require zero changes, so they were excluded rather than speculatively touched.
- **Naming collision risk**: must pick a class name that doesn't collide with existing protection class names and reads unambiguously as "consecutive losses" vs. `StoplossGuard`'s stoploss-exit-reason semantics (candidate: `MaxConsecutiveLosses`, consistent with `MaxDrawdown` naming style).

## Notes
- The four existing handlers already establish the exact pattern to replicate: `__init__` reads config knobs via `protection_config.get(...)`, `short_desc()`, a private `_reason()`, a private evaluation method taking `date_now` (+ `pair`/`side` as applicable), and thin `global_stop`/`stop_per_pair` wrappers gated by `has_global_stop`/`has_local_stop`.
- "Consecutive losses" specifically requires evaluating trades in *close-date order* and counting a losing streak from the most recent trade backward, stopping at the first winner — this differs algorithmically from all four existing handlers (none currently implement streak/ordering logic) and is the one genuinely new algorithm this change introduces.
