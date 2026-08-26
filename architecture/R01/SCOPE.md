# SCOPE.md — R01 (freqtrade)

## Method

Scope was decided from freqtrade's own module layout — directories at depth ≤ 3 under
`freqtrade/` (per `TREATMENT_DESIGN.md` §4) — verified by directly reading source files and by
repo-wide `grep` for `from freqtrade.<pkg> import ...` to confirm which directories are
genuinely load-bearing (i.e. actually depended upon by other parts of the codebase), not just
present. This was done **before** reading `tasks/R01/task_A.md`–`task_D.md` (see
`PLAUSIBILITY_CHECK.md` for the post-hoc self-check, performed only after this scoping and
authoring work was complete).

Candidate list from prior reconnaissance (`freqtrade/exchange`, `freqtrade/strategy`,
`freqtrade/optimize`, `freqtrade/plugins/pairlist`, `freqtrade/plugins/protections`,
`freqtrade/resolvers`, `freqtrade/rpc`, `freqtrade/freqai`, `freqtrade/configuration`,
`freqtrade/persistence`, `freqtrade/data`) was verified against `ls freqtrade/` and confirmed
accurate — these are exactly the top-level directories (plus a few purely-internal ones:
`enums`, `constants`, `exceptions`, `misc`, `util`, `wallets.py`, `mixins`, `leverage`,
`vendor`, `templates`, `system`, `ft_types`, `plot`, `loggers`, `config_schema` — all thin
utility/glue modules, not independent architectural components with their own multi-file
public surface).

## Cells covered (10) and why

| Cell | Evidence it's load-bearing |
|---|---|
| `freqtrade/persistence` | `Trade`/`Order`/`LocalTrade`/`PairLock` are imported by `commands`, `data`, `exchange`, `freqai`, `freqtradebot.py`, `leverage`, `optimize`, `plugins`, `rpc`, `strategy`, `util`, `wallets.py` — the single most widely-depended-upon domain model in the codebase. |
| `freqtrade/configuration` | `Configuration`/`TimeRange`/`setup_utils_configuration` are imported by `commands`, `optimize`, `exchange`, `freqai`, `rpc`, `data`, `plot`, `resolvers`. Must load before every other subsystem exists. |
| `freqtrade/exchange` | `Exchange` and timeframe helpers are imported by `plugins` (27 files), `data` (14), `optimize` (5), `strategy` (4), `rpc` (4), `resolvers`, `freqtradebot.py`, `configuration`, `persistence`, `freqai`, `commands`, `util`, `wallets.py`, `worker.py`, `plot`. The single most-depended-upon I/O boundary. |
| `freqtrade/data` (dataprovider.py only) | `DataProvider` is constructed in `freqtradebot.py`, `optimize/backtesting.py`; typed into `IStrategy.dp`; used by `plugins/pairlistmanager.py`, `rpc`, `freqai`, `plot`. |
| `freqtrade/plugins/pairlist` | A designed, `ABC`-based extension-point chain (`IPairList`, ~15 concrete filters), resolved dynamically by `resolvers/pairlist_resolver.py`; consumed by `plugins/pairlistmanager.py`, `commands`, `data/history`, `freqai`, `plot`. |
| `freqtrade/plugins/protections` | Same pattern for risk controls (`IProtection`, `StoplossGuard` et al.), resolved by `resolvers/protection_resolver.py`, consumed by `plugins/protectionmanager.py`. |
| `freqtrade/strategy` | `IStrategy` is the mandatory contract every user strategy implements; imported by `optimize`, `resolvers`, `plot`, `freqai`, `commands`, and freqtrade's own strategy templates. |
| `freqtrade/resolvers` | The generic dynamic-class-loading mechanism behind every "pluggable" cell above (`IResolver` + 6 concrete resolvers); imported by `freqtradebot.py`, `optimize`, `plugins`, `commands`, `rpc`, `exchange/exchange_utils.py`, `data/history`, `strategy/interface.py`. |
| `freqtrade/plugins` (root: `pairlistmanager.py`, `protectionmanager.py`) | The two manager objects that build and run the two extension-point chains above; imported by `freqtradebot.py`, `optimize/backtesting.py`, `rpc`. |
| `freqtrade/optimize` (backtesting.py, backtest_caching.py only) | `Backtesting` is freqtrade's simulation engine, composing exchange/strategy/persistence/resolvers/plugins/data; imported by `commands`, `rpc/api_server`, `optimize/hyperopt`, `optimize/analysis`. |

## Deliberately excluded / deprioritized

- **`freqtrade/rpc`** — real and substantial (Telegram/webhook/REST API/websocket notification
  layer), but it is an outward-facing control/notification plane, not part of the trading
  engine's structural spine: nothing in the ten cells above depends on `rpc` (the dependency
  edge runs the other way — `rpc` depends on `exchange`, `optimize`, `resolvers`, `plugins`,
  `persistence`). Two other genuine extension-point examples (`plugins/pairlist`,
  `plugins/protections`) and one dynamic-loading mechanism (`resolvers`) already give the
  forest real "pluggability" coverage without needing a third.
- **`freqtrade/freqai`** — a large, genuinely self-contained optional subsystem (only active
  when `freqai.enabled` is set); it is a *consumer* of `strategy`, `persistence`, `data`, and
  `resolvers` (via `FreqaiModelResolver`, mentioned in `freqtrade/resolvers`'s Description as an
  out-of-scope sibling), not something the rest of the spine depends on.
- **Sub-packages of `optimize`** (`hyperopt/`, `hyperopt_loss/`, `optimize_reports/`,
  `analysis/`, `space/`) and of `data` (`history/`, `converter/`, `btanalysis/`) — real
  components, but the CODEMANIFEST `location` constraint (files must sit at the same directory
  level as `CODEMANIFEST`, no subdirectory traversal) means each would need its own cell; given
  the "roughly 6-10 cells, not an exhaustive catalog" budget, only the top-level files directly
  in `optimize/` and `data/` were documented (`Backtesting`, `DataProvider`), which are the
  files everything else in the spine actually imports.
- **`freqtrade/configuration`, `enums`, `constants`, `exceptions`, `misc`, `util`, `mixins`,
  `leverage`, `ft_types`** below the ten — `configuration` was included (foundational, see
  table); the rest are thin, single-purpose utility modules with no independent multi-type
  public surface of their own, referenced only for a handful of shared value types (`Config`,
  `CandleType`, etc.) rather than being architectural components in their own right.

This scoping was performed and frozen before `tasks/R01/task_A.md`–`task_D.md` were read (see
`PLAUSIBILITY_CHECK.md`).
