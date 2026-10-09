# CYCLE_FIXES.md — R01 (freqtrade/freqtrade)

Unlike R06 (etcd, 0 cycles) and R03 (nestjs, 1 cycle, purely declarative fix), freqtrade's real
cross-cell import graph contains **5 apparent cycles** among the 8 documented cells, discovered
via relative-import analysis (`grep` for `from freqtrade.<cell>` across every top-level `.py`
file per cell, cross-referenced against the other 7 documented cells).

## 1. `configuration ↔ exchange` — real cycle, fixed by splitting a leaf cell

- `exchange/exchange.py` did a module-level `from freqtrade.configuration import
  remove_exchange_credentials`.
- `configuration/configuration.py` did a function-local (lazy) `from freqtrade.exchange.check_exchange
  import check_exchange` — with the source's own comment: `# Import check_exchange here to
  avoid import cycle problems`, confirming freqtrade's own maintainers already knew about this
  cycle.

**Fix (real code motion, zero behavior change):** `configuration/config_secrets.py`
(`sanitize_config`, `remove_exchange_credentials` — already self-contained, depending only on
`freqtrade.constants`) was moved into its own subpackage, `configuration/config_secrets/`, with
an `__init__.py` re-exporting both names so every existing import path
(`from freqtrade.configuration.config_secrets import ...` and the barrel-level
`from freqtrade.configuration import ...`) keeps working unchanged. `exchange/exchange.py`'s
import was updated to `from freqtrade.configuration.config_secrets import
remove_exchange_credentials` (the more precise, now-correct dependency).
`configuration → exchange` (the lazy `check_exchange`/`timeframe_to_seconds`/
`available_exchanges`/`MAP_EXCHANGE_CHILDCLASS` references) is accepted as-is and deliberately
**not** formalized as a CODEMANIFEST Import (described in prose only) — declaring it would
recreate the cycle, and this direction was already the "minor" side (a handful of narrow,
deliberately-lazy call sites, not a load-bearing architectural dependency).

## 2. `exchange ↔ resolvers` — real cycle, accepted via non-formalization (no code motion)

- `resolvers/exchange_resolver.py` does a module-level `from freqtrade.exchange import
  MAP_EXCHANGE_CHILDCLASS, Exchange`.
- `exchange/exchange_utils.py`'s `list_available_exchanges` (used only by the `freqtrade
  list-exchanges` CLI command and one REST API endpoint — confirmed via `grep`, not part of
  freqtrade's core trading path) does a function-local `from
  freqtrade.resolvers.exchange_resolver import ExchangeResolver`.

**Fix:** unlike case 1, the offending symbol on the "thin" side isn't cleanly separable into its
own leaf without either moving `list_available_exchanges` out of `exchange_utils.py` (a file with
many other, non-cyclic exchange-enumeration helpers) or moving `MAP_EXCHANGE_CHILDCLASS`/`Exchange`
out of `exchange` itself (both are central to the cell, not separable). Given this reference is a
single, narrow, informational-CLI-only call site, it is deliberately **not formalized** as a
CODEMANIFEST Import — described in prose in `exchange`'s documentation instead. This mirrors the
same judgment call already made and disclosed for R03's `router/interfaces` (which also chose not
to formalize one narrow cross-reference to avoid recreating a cycle).

## 3. `strategy ↔ resolvers` — not a real architectural cycle, accepted via non-formalization

- `resolvers/strategy_resolver.py` does a module-level `from freqtrade.strategy.interface import
  IStrategy` — the main, load-bearing direction.
- `strategy/interface.py` has exactly one function-local import,
  `from freqtrade.resolvers.freqaimodel_resolver import FreqaiModelResolver`, guarded by the
  source's own comment `# Import here to avoid importing this if freqAI is disabled` — this is
  about *optional-subsystem loading* (freqAI, an entirely separate, non-documented subsystem of
  this repository), not a genuine mutual architectural dependency between `strategy` and
  `resolvers`.

**Fix:** not formalized as a CODEMANIFEST Import (this one reference is to `freqaimodel_resolver`
specifically, a resolver for the out-of-scope freqAI subsystem, not to `resolvers`' documented
spine). No code motion needed or attempted.

## 4. `strategy ↔ optimize` — real cycle, fixed by splitting a leaf cell (like case 1)

- `optimize/backtesting.py` does module-level `from freqtrade.strategy.interface import
  IStrategy` and `from freqtrade.strategy.strategy_wrapper import strategy_safe_wrapper` — the
  main, load-bearing direction (backtesting needs to run a real strategy).
- `strategy/hyper.py` and `strategy/parameters.py` did **module-level, non-lazy** imports of
  `HyperoptTools`/`HyperoptStateContainer` from `freqtrade.optimize.hyperopt_tools` — a real,
  hard dependency, not a deliberately-lazy workaround like cases 1-3.

**Fix (real code motion):** `optimize/hyperopt_tools.py` (and its own sole dependency,
`optimize/hyperopt_epoch_filters.py` — confirmed to depend on nothing beyond
`freqtrade.exceptions`, and used by nothing else in the repo except `hyperopt_tools.py` itself)
were both moved into a new subpackage, `optimize/hyperopt_tools/`, with an `__init__.py`
re-exporting `HyperoptTools`, `HyperoptStateContainer`, `hyperopt_serializer` — the existing
`from freqtrade.optimize.hyperopt_tools import HyperoptTools`-style imports in `strategy/hyper.py`
and `strategy/parameters.py` continue to resolve unchanged. `strategy` now depends on
`optimize/hyperopt_tools` (a leaf with zero dependency on `strategy` or the parent `optimize`),
while `optimize` (parent) still depends on `strategy` — no more cycle. One further narrow
reference inside the moved `HyperoptTools.get_strategy_filename` static method (a function-local
`from freqtrade.resolvers.strategy_resolver import StrategyResolver`) would, if formalized,
recreate a *different* cycle (`optimize/hyperopt_tools → resolvers → strategy →
optimize/hyperopt_tools`) — deliberately left non-formalized in `optimize/hyperopt_tools`'s own
CODEMANIFEST, same judgment as cases 2-3.

Separately, `optimize/space/` (already a real subdirectory under `optimize`, confirmed to have
zero dependency on `strategy` or any other documented cell) is also split into its own leaf cell
— required regardless of the cycle, since a real subdirectory-with-code under a documented cell
always needs its own CODEMANIFEST per Goga's `location` rule; `strategy/parameters.py`'s
`with suppress(ImportError): from freqtrade.optimize.space import (...)` block now references
this new leaf cell.

## 5. `plugins ↔ resolvers` (via `plugins/pairlist`/`plugins/protections`) — not a real cycle

- `plugins/pairlistmanager.py`/`plugins/protectionmanager.py` (top-level files of the *parent*
  `plugins` cell) import `PairListResolver`/`ProtectionResolver` from `freqtrade/resolvers`.
- `resolvers/pairlist_resolver.py`/`resolvers/protection_resolver.py` import
  `IPairList`/`IProtection` from `freqtrade/plugins/pairlist`/`freqtrade/plugins/protections` —
  the *child* cells, already independently documented since Phase 8, not the same node as the
  parent `plugins` cell in Goga's flat cell graph.

**No fix needed** — `plugins`, `plugins/pairlist`, and `plugins/protections` are three distinct,
independently-documented cells. The real graph is a linear chain (`plugins → resolvers →
plugins/pairlist`, `plugins → resolvers → plugins/protections`), not a cycle between any two of
the same cell. All edges declared normally.

## Summary of code motion

Two real, minimal, behavior-preserving file relocations were performed (both confirmed
zero-diff for every consumer via the build+test hard gate — see RESTRUCTURE_REPORT.md):
- `configuration/config_secrets.py` → `configuration/config_secrets/config_secrets.py` (+
  `__init__.py` re-export)
- `optimize/hyperopt_tools.py` + `optimize/hyperopt_epoch_filters.py` →
  `optimize/hyperopt_tools/{hyperopt_tools,hyperopt_epoch_filters}.py` (+ `__init__.py`
  re-export)

Three real cross-cell references were deliberately left undeclared (described in prose,
disclosed here) rather than formalized as CODEMANIFEST Imports, since formalizing any of them
would recreate a cycle and none represent the main, load-bearing direction of their respective
relationship: `exchange → configuration` (lazy, `check_exchange` et al.),
`exchange.list_available_exchanges → resolvers.ExchangeResolver` (a single CLI-listing utility),
`strategy.interface → resolvers.freqaimodel_resolver` (optional freqAI-subsystem loading), and
`optimize/hyperopt_tools.get_strategy_filename → resolvers.StrategyResolver` (a single static
method's narrow lookup).
