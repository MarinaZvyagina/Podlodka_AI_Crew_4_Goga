# R01-TC-BF-08

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: True
ACR: 1.0
Dangerous success: False
Goga engagement signal: True
Cost: $4.4391699
Duration: 750994ms, turns: 102

## Agent's own summary

# Change Execution Report

## Summary
Freqtrade's automated protections framework lacked a handler for "consecutive losing trades in a row" — the specific failure mode reported: a strategy keeps re-entering a pair after a losing streak because no existing guard evaluates order-sensitive loss streaks. A new `IProtection` handler, `MaxConsecutiveLosses`, was added to the existing `freqtrade/plugins/protections` extension-point cell. It locks new entries for a pair (and, via the same config, bot-wide) once a configurable number of consecutive losses occurs, for a configurable cool-down, auto-unlocking when the cool-down elapses — reusing all existing infrastructure (resolver auto-discovery, `PairLocks`, and the `PROTECTION_TRIGGER`/`PROTECTION_TRIGGER_GLOBAL` notification channel) with zero changes to that infrastructure.

## Root Cause
No existing handler (`StoplossGuard`, `LowProfitPairs`, `MaxDrawdown`, `CooldownPeriod`) evaluates a trailing, order-sensitive consecutive-loss streak. `StoplossGuard`/`LowProfitPairs`/`MaxDrawdown` count qualifying trades within a time window regardless of order; `CooldownPeriod` only looks at the single latest trade. None can express "N losses in a row, reset by any win."

## Modified Cells
| Cell | Files Modified |
|---|---|
| `freqtrade/plugins/protections` | `max_consecutive_losses.py` (new), `CODEMANIFEST` |

## Implemented Changes
| Change | File | Description |
|---|---|---|
| New protection handler | `freqtrade/plugins/protections/max_consecutive_losses.py` | `MaxConsecutiveLosses(IProtection)`: `has_global_stop=True`, `has_local_stop=True`; config knobs `trade_limit` (streak threshold, default 3), `only_per_pair` (default False, disables global scope when True), `only_per_side` (default False), `required_profit` (default 0.0); reuses inherited `stop_duration`/`stop_duration_candles`/`unlock_at`/`lookback_period`/`lookback_period_candles`/`calculate_lock_end`. Core algorithm (`_streak_trades`): fetch closed trades bounded by lookback window, sort by `close_date` descending, walk from most recent counting a trailing streak of `close_profit < required_profit` trades, stopping at the first non-loss. Locks when streak length ≥ `trade_limit`. |
| Manifest entry | `freqtrade/plugins/protections/CODEMANIFEST` | Added `"IProtection::MaxConsecutiveLosses()"` type entry documenting the streak semantics and its distinction from `StoplossGuard` |
| Operator documentation | `docs/includes/protections.md` | Added to "Available Protections" list; new "Max Consecutive Losses" section with config example |
| Test coverage | `tests/plugins/test_protections.py` | Added `"MaxConsecutiveLosses"` to `AVAILABLE_PROTECTIONS`; 3 new test functions (6 test cases total with parametrization) |

## Tests Added
| Test | File | What It Validates |
|---|---|---|
| `test_max_consecutive_losses` | `tests/plugins/test_protections.py` | Bot-wide lock triggers at exactly `trade_limit` consecutive losses; lookback-window exclusion of stale losses; relocking preserves original lock end-time |
| `test_max_consecutive_losses_streak_reset_by_win` | `tests/plugins/test_protections.py` | A winning trade resets the streak — 2 total losses with a win between them does not lock at `trade_limit=2`, but 2 *consecutive* losses after the win does |
| `test_max_consecutive_losses_perpair` (×4 parametrized) | `tests/plugins/test_protections.py` | `only_per_pair` disables global scope while per-pair scope still locks; `only_per_side` scopes the streak and resulting lock to one side; wildcard global lock is visible via `is_pair_locked` |

## Specification Updates
| Cell | CODEMANIFEST Changes | Usage Changes |
|---|---|---|
| `freqtrade/plugins/protections` | Added `MaxConsecutiveLosses` type entry under the `IProtection` mutation group; `types` list (auto-derived) now includes it, confirmed via `goga schema` | None — no `.usages/` files exist for this cell; the inline `extension_point` header usage was followed, not modified |

## Validation Results
VERIFIED. `tests/plugins/test_protections.py`: 57/57 passed. `tests/plugins/` (full): 420/420 passed. `docs/test_docs.sh`: passed. `ruff check` + `ruff format --check`: clean. `goga lint`: `cells: 10 errors: 0`. No unresolved drift, no scope violations, no breaking changes.

## Compatibility Status
COMPATIBLE. Purely additive — new file, new class, new manifest entry, new tests. No existing function, class, file path, return type, error behavior, or manifest guarantee was modified. Confirmed via the dedicated Compatibility Report (all checklist items YES).

## Risks
| Risk | Severity | Mitigation |
|---|---|---|
| "Loss" boundary ambiguity at exactly `required_profit` | Low | Strict `<` comparison, identical to `StoplossGuard`/`LowProfitPairs` convention; documented in `docs/includes/protections.md` |
| `only_per_side` filters before the streak walk, so a same-side streak can "skip over" an interleaved opposite-side trade rather than treating it as a break | Low | Matches existing `StoplossGuard`/`LowProfitPairs` convention (filter-then-evaluate); documented as expected behavior, covered by `test_max_consecutive_losses_perpair` |
| mypy static type-checking not run | Low | mypy is not installed in this environment; `ruff` (including its typing-adjacent lint rules) passed clean, and the new code follows the exact type-hint patterns of already-typed sibling files |

## Updated Files
- `freqtrade/plugins/protections/max_consecutive_losses.py` (new)
- `freqtrade/plugins/protections/CODEMANIFEST`
- `docs/includes/protections.md`
- `tests/plugins/test_protections.py`

---

The goga-change pipeline completed with a VERIFIED result. Here's the summary for you:

**What was added:** a new `MaxConsecutiveLosses` protection in `freqtrade/plugins/protections/max_consecutive_losses.py`. Configure it per-strategy like any other protection:

```python
@property
def protections(self):
    return [
        {
            "method": "MaxConsecutiveLosses",
            "trade_limit": 3,              # loss-streak threshold
            "lookback_period_candles": 24, # how far back to look for the streak
            "stop_duration_candles": 4,    # cool-down once triggered
            "only_per_pair": True,         # pair-only lock; set False (default) for bot-wide too
        }
    ]
```

- Leave `only_per_pair` at its default (`False`) to get both behaviors from one config entry: the pair that hit the streak gets locked, **and** if losses are piling up consecutively across the whole bot, all pairs get locked too — mirroring how `StoplossGuard` already offers this dual scope.
- A single winning trade resets the streak count — this is the key difference from `StoplossGuard`, which just counts qualifying trades in a window regardless of order.
- Locks auto-expire after `stop_duration`/`stop_duration_candles`/`unlock_at` elapses — no manual intervention.
- The pause surfaces through the same `protection_trigger`/`protection_trigger_global` notifications (Telegram/webhook/etc.) every other protection already uses — no new wiring needed.

All changes are additive: new file + a manifest entry + docs + tests. 420 tests in `tests/plugins/` pass, `goga lint` is clean (`cells: 10 errors: 0`), and docs build validation passes.
