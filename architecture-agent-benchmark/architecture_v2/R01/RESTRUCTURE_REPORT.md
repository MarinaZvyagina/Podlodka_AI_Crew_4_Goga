# RESTRUCTURE_REPORT.md — R01 (freqtrade/freqtrade) Condition C

Third repository restructured for Condition C, and the first with real, multi-cycle
architectural entanglement requiring genuine judgment calls rather than a single clean
declarative fix. Python, 44.8k LOC, 8 originally documented cells (Phase 8).

## Scope grew substantially once facade discipline was applied strictly

Unlike R06/R03, applying Goga's `location` rule strictly (every real subdirectory-with-code
under a documented cell needs its own CODEMANIFEST) surfaced **13 new nested cells**, not
1-3: `configuration/config_secrets`, `optimize/hyperopt_tools`, `optimize/analysis`,
`optimize/optimize_reports`, `optimize/space`, `optimize/hyperopt_loss`, `optimize/hyperopt`,
`data/converter`, `data/history`, `data/btanalysis`, `data/history/datahandlers` (the last one
found only during a final completeness pass, by a sibling agent flagging it rather than silently
absorbing it). Final cell count: 21 (8 original + 13 new). Total real exports audited: 236 (49
in the 8 original cells' remaining gaps + 187 across the 13 new nested cells) — **0 hideable**,
matching R03's pattern (this is a real trading-bot application, not a narrow internal service;
most of its surface is legitimately used across CLI commands, the live bot, backtesting, and
hyperopt).

## Five apparent circular dependencies — the first repository with real ones beyond a single easy case

Full relative-import analysis across all 8 original cells found 5 apparent cycles (vs. 0 in
etcd, 1 in nestjs). Per explicit user confirmation, all 5 were investigated and resolved rather
than left as disclosed exclusions. Full detail in `CYCLE_FIXES.md`; summary:

1. **`configuration ↔ exchange`** — real, with the source's own comment acknowledging it
   ("avoid import cycle problems"). Fixed by real code motion: `configuration/config_secrets.py`
   → `configuration/config_secrets/` (own subpackage, `__init__.py` re-export, zero behavior
   change, all existing import paths keep working).
2. **`exchange ↔ resolvers`** — real, but the offending reference (`list_available_exchanges`,
   used only by a CLI-listing command) isn't cleanly separable without disproportionate
   restructuring. Deliberately left non-formalized (described in prose, not declared as an
   Import) rather than forced through — an explicit, disclosed judgment call, not an oversight.
3. **`strategy ↔ resolvers`** — not a real architectural cycle on inspection: the "back" edge is
   a single, function-local, comment-guarded reference to the optional freqAI subsystem's
   resolver, not a genuine mutual dependency between the two documented cells. Non-formalized.
4. **`strategy ↔ optimize`** — real, with **module-level (non-lazy) imports on both sides** (the
   hardest case in this repo). Fixed by real code motion, same pattern as case 1:
   `optimize/hyperopt_tools.py` + its sole dependency `optimize/hyperopt_epoch_filters.py` moved
   into `optimize/hyperopt_tools/` (own subpackage, re-exported, zero behavior change).
5. **`plugins ↔ resolvers`** — not a real cycle at all on inspection: the two directions involve
   three *different* cells (`plugins` parent, `plugins/pairlist` and `plugins/protections`
   children, already independently documented since Phase 8), forming a linear chain, not a
   cycle between the same two nodes.

**Net result: 2 real, minimal, behavior-preserving file relocations; 3 cases resolved by
disclosed non-formalization rather than forced restructuring.** No case required rewriting
logic, changing a public signature, or any change visible to any consumer of these modules.

One subagent (assigned `optimize/hyperopt_loss`+`optimize/hyperopt`) proactively surfaced a
6th potential cycle question (does `optimize/hyperopt` importing `strategy` reintroduce a cycle
given `strategy` now depends on `optimize/hyperopt_tools`?) rather than resolving it
unilaterally, per explicit instruction to flag rather than decide. Traced by the orchestrating
session: no cycle exists — `hyperopt → strategy` and `hyperopt → optimize(parent) → strategy`
are both one-directional; `strategy`'s only outbound edge into the `optimize` family is the
already-independent leaf `optimize/hyperopt_tools`, which has no path back into `hyperopt` or
`optimize`. A second subagent (data/converter) independently flagged an analogous
`optimize ↔ data/btanalysis` reference (via `get_backtest_metadata_filename`) and, consistent
with the established precedent, described it in prose rather than formalizing it — logged here
for completeness even though it wasn't part of the original 5.

## Process

- Two cycle-breaking file relocations were performed directly by the orchestrating session
  (not delegated), given their higher risk — each verified for zero remaining dependents at the
  old path, correct `__init__.py` re-export coverage, and clean Python syntax before any
  documentation work proceeded.
- Remaining facade-completion work was split across 9 parallel subagents (exchange;
  configuration; optimize/hyperopt_loss+hyperopt; optimize/analysis+optimize_reports+space;
  persistence; data+converter; data/history+btanalysis; strategy; resolvers+plugins+protections+
  pairlist), each given precise symbol lists plus explicit instructions on which cross-cell
  references were deliberately non-formalized and why.
- Agents independently caught and corrected several inaccuracies in the orchestrating session's
  own symbol lists (7 names in the original `exchange` list didn't actually exist; `Trade` was
  already declared under mutation syntax, not missing; `optimize_reports` had 26 real exports,
  not the assumed 27) — each verified against real source rather than trusted blindly, consistent
  with this project's standing discipline.
- A `data/history/datahandlers` subdirectory (8 real exports: `IDataHandler` + 4 storage-format
  subclasses + 2 resolution routines) was found by one subagent during its own work but correctly
  left uncreated (out of its assigned scope) and flagged — completed directly by the
  orchestrating session afterward, including retrofitting a proper Import into `data/history`'s
  own manifest.
- Final full-repo `goga lint`: **0 errors across 21 cells.**

## Hard gate: build + test

- `pip install -e .` (fresh venv) hit an unrelated environment issue (a `joblib`/`cloudpickle`
  version incompatibility from installing latest dependency versions fresh) — confirmed via
  side-by-side testing to be pre-existing environment drift unrelated to the restructuring, not
  reproducible against the project's already-provisioned venv. Fixed by reusing the
  already-working `.venv` (hardlink-copied, `pip install -e . --no-deps`) instead of a fresh
  install, matching the primary benchmark harness's own `link_shared_deps` convention.
- Every restructured import path (`configuration.config_secrets`, `optimize.hyperopt_tools`,
  `optimize.hyperopt`, `optimize.space`, `data.history.datahandlers`, plus the untouched
  `exchange`/`strategy`) verified to import cleanly.
- Full `pytest tests/` run: **207 failed, 4191 passed, 35 skipped, 375 deselected** — run
  side-by-side against the exact same commit's *unmodified* original checkout (same venv):
  **identical counts, bit-for-bit** (`test_pip_audit.py` failures from no network access,
  several `freqtradebot`/DCA/stoploss-on-exchange tests failing for environment/version reasons
  unrelated to this repo's architecture). Confirms zero regressions and zero incidental fixes
  from the restructuring — pre-existing baseline noise, not this work's product.

## Control re-certification

All 8 of Phase 5's control diffs (`tasks/R01/controls/*.diff`) applied cleanly against the
restructured commit with no adaptation needed (no hardcoded base-commit SHAs in R01's
validators; no renamed identifiers since 0 exports were hidden). **All 4 tasks discriminate
correctly**:

| Task | Positive: functional | Positive: all AC | Negative: functional | Negative: ≥1 AC fails |
|---|---|---|---|---|
| A | PASS | PASS (5/5) | PASS | Yes (5/5 FAIL) |
| B | PASS | PASS (5/5) | FAIL | Yes (3/5 FAIL) |
| C | PASS | PASS (5/5) | PASS | Yes (5/5 FAIL) |
| D | PASS | PASS (6/6) | FAIL | Yes (1/6 FAIL) |

## Artifacts

- Restructured commit: `f1ea87edeb198bb6e53ec8accda10e2932f3bff6`, tagged `condition-c-r01-v1`
  in the shared base clone (`benchmark-scratch/repos/R01`).
- `architecture_v2/R01/CYCLE_FIXES.md` — full detail on all 5 cycles and the 6th flagged case.
- No `controls_adapted/`/`validators_adapted/` directories needed — all 8 original control diffs
  and all validator scripts worked unmodified.
- The 21 cells' `CODEMANIFEST` files live directly in the restructured commit.
