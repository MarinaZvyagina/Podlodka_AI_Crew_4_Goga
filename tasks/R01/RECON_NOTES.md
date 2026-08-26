# RECON_NOTES.md — R01 (freqtrade/freqtrade)

Note: this file was completed by the orchestrating session after the original recon agent (which produced all 8 task/metadata files) was cut off twice by a transport-level connection error immediately before writing this file. The evidence below is reconstructed from the agent's already-written `task_A-D.md` and `metadata_A-D.yaml`, which were read in full and are internally consistent (real file paths, real line numbers, cross-referenced abstractions).

Repository: `freqtrade/freqtrade`, pinned commit `936f28e28cbcd4e9e146cbc076c54933517a92eb`. Recon was performed via the GitHub API only (no local clone), consistent with the disk-space constraint given to the agent.

## Task A — Local Change: conflicting capital-sizing config detection

Grounded in `freqtrade/configuration/config_validation.py`'s existing `_validate_*(conf)` pattern (e.g. `_validate_unlimited_amount`, `_validate_trailing_stoploss`), aggregated by `validate_config_consistency()` (lines 73-99), and in the real precedence behavior of `available_capital` vs `tradable_balance_ratio` in `freqtrade/wallets.py`'s `get_starting_balance()`/`get_total_stake_amount()`. The task is a pure startup-validation addition, explicitly scoped away from `wallets.py`, `freqtradebot.py`, `exchange/`, `strategy/`, `optimize/`, `rpc/` (metadata `architectural_constraints` + `AC3`). No architectural boundary crossing is required or expected — correctly a Local Change.

## Task B — Cross-module Feature: per-underlying-currency exposure cap

Requires config-schema-level input (a new per-strategy limit), sizing logic that must apply consistently across both live/dry-run and backtest code paths, and visibility through the existing trade-entry-decision reporting surface — genuinely spanning configuration, sizing/risk logic, and the live-vs-backtest execution split that freqtrade explicitly warns about maintaining consistently (see the task prompt's own callout about features "quietly only work[ing] in one of those two modes"). This dual-path requirement is deliberately included because it is a realistic, freqtrade-specific way for an agent to accidentally wire a feature into only one of the two execution paths — a genuine cross-module correctness risk, not just a stylistic one.

## Task C — Existing Extension Point: consecutive-loss cooldown protection

**Verified extension point:** `IProtection` abstract base class, `freqtrade/plugins/protections/iprotection.py` (lines 25-143), with abstract methods `global_stop()` and `stop_per_pair()` returning `ProtectionReturn` (lines 17-22). Four real built-in implementations were confirmed as structural precedent: `cooldown_period.py`, `low_profit_pairs.py`, `max_drawdown_protection.py`, `stoploss_guard.py` — all in `freqtrade/plugins/protections/`. Dynamic loading is handled by `ProtectionResolver` (`freqtrade/resolvers/protection_resolver.py`), itself a thin subclass of the generic `IResolver` (`freqtrade/resolvers/iresolver.py`) — the same generic resolver mechanism reused across freqtrade (also used for strategy/pairlist resolution). Orchestration and persistence go through `ProtectionManager` (`freqtrade/plugins/protectionmanager.py`) and `PairLocks`/`PairLock` (`freqtrade/persistence/pairlock*.py`).

The task prompt (`task_C.md`) describes the desired behavior — track consecutive losses per pair and bot-wide, auto-expiring cooldown, configurable per strategy, visible through existing notification channels — entirely in user-facing terms. It never mentions "protection," "IProtection," "resolver," "plugin," "ProtectionManager," "PairLocks," or any class name. **Leak check: grepped `task_C.md` for `IProtection|ProtectionManager|ProtectionResolver|PairLock|stop_per_pair|global_stop` — zero matches.**

The plausible trap for this task is bolting a parallel, ad hoc pause mechanism directly into `freqtradebot.py` (e.g., a new dict tracking paused pairs) instead of authoring a new `IProtection` subclass — explicitly called out in `metadata_C.yaml`'s architectural constraints.

## Task D — Architecture Trap: short-lived price cache

Grounded in the real repeated-price-lookup pattern that occurs when a strategy's exit and entry logic both query current price for the same pair within a short window, and freqtrade's real exchange rate-limit sensitivity. The task explicitly separates live/dry-run behavior (where this matters) from backtest/hyperopt (which use historical candle data and are explicitly called out as out of scope, protecting against a trap where a naive cache implementation accidentally touches the backtest path). This is a direct, codebase-grounded instantiation of `Research.md`'s own canonical Architecture Trap example (cache added at the wrong layer, e.g. wrapping the low-level exchange call directly from a high-level orchestration point, versus behind whatever the exchange-access abstraction already is) — the exact abstraction boundary was left for the benchmark agent to discover, consistent with a Task D (not Task C) design.

## Leak-check summary across all four prompts

`task_A.md`, `task_B.md`, `task_C.md`, `task_D.md` were reviewed for internal identifiers (class names, file paths, method names, pattern names such as "protection," "resolver," "IStrategy," "IProtection," "config_validation," "ProtectionManager"). None appear — all four prompts are phrased purely in terms of observable user/trader-facing behavior, consistent with `Research.md` §22's good/bad example.

## Known limitation

Because this file was reconstructed post-hoc from the already-written task/metadata files rather than live during recon, it does not include additional code excerpts beyond what is already quoted inside `metadata_A-D.yaml`. Those metadata files remain the authoritative evidence trail (exact line numbers, exact function names) for each architectural claim made above.
