# SETUP_COST.md — R01 (freqtrade)

## initial_generation_time

Active tool-call work spanned roughly **10:14–10:45 MSK (≈ 31 minutes)** on 2026-08-26 for the
full pipeline: reading `TREATMENT_DESIGN.md`/`GOGA_RESEARCH.md`/`PROTOCOL.md`, loading the
`goga-cell`/`goga-cookbook`/`goga-lang-disp`/`goga-cell-python` DSL skills, dispatching 8
parallel source-reading research passes over the real freqtrade codebase, authoring the
~1,300-line `docs/arch/architecture-overview.md` plan (10 cells), materializing it to 10
CODEMANIFEST files, 2 rounds of `goga lint` correction, `goga schema` verification, `goga
contract` drift spot-checks on 3 cells, and 2 post-hoc corrections from that drift check.

Caveat: this session experienced infrastructure-level connection interruptions during the
authoring step (the large single-file write was retried, then redone incrementally per cell via
separate `Edit` calls), so real wall-clock time for a human observer watching the terminal was
somewhat longer than the ~31 minutes of visible, successful tool-call activity reflected above;
the ~31 minutes figure is the productive-work estimate, not strictly the observer's stopwatch
time.

## manual_correction_time

Concentrated in two short passes, both within the session above (not separately timed, but a
few minutes of the total): one scripted pass fixing `From:` path resolution and stripping
invalid backtick cross-references, one small pass adding missing `import_is_used` references.

## number_of_manual_corrections

- **Lint correction rounds: 2** (`goga lint` was run 3 times total):
  1. Initial `goga lint` on the freshly materialized forest: **235 errors** across all 10 cells
     — three rule types: `annotation_links_exists` (197 — invalid backtick cross-references,
     e.g. referencing a sibling method's name, a CLI flag like `--config`, or a wildcard like
     `_process_*`, none of which are valid link targets per the DSL: only signature params,
     Imports/Usages, and same-document Entity/Routine names may be backtick-referenced),
     `import_has_valid_from_path` (29 — see finding below), `import_is_used` (9 — an imported
     type must be referenced by name at least once).
  2. **Root-cause finding:** `From:` paths in `Imports` are resolved by `goga lint` relative to
     the process's current working directory (confirmed by reading
     `goga/ast/rules/document/imports/rules.py`: `cwd = Path.cwd().resolve()`), i.e. the
     **project root**, not relative to the importing cell's own directory as one plausible
     reading of the DSL spec's prose ("relative to the working directory containing the
     CODEMANIFEST file") might suggest. All 29 `../exchange`-style relative paths were rewritten
     to project-root-relative paths (e.g. `freqtrade/exchange`). A scripted pass then stripped
     backticks from the ~150 distinct invalid link strings identified from the lint output
     (converting them to plain prose — sibling method names, CLI flags, wildcards, dotted
     `Type.method` expressions, tuples-as-prose, and cross-cell references to types that
     weren't formally imported). Re-lint: **9 errors** (`import_is_used` only, for 3 cells
     where the only backtick mention of an imported type had been a dotted expression like
     `PairListResolver.load_pairlist`, which doesn't count as a reference to the bare
     `PairListResolver` type). Added one clean standalone backtick reference per affected
     imported type in the relevant cell's Annotations. Re-lint: **0 errors**.
- **Contract-drift corrections: 2** (found via `goga contract`, see below), both in
  `freqtrade/persistence`: `Order.parse_from_ccxt_object` doesn't have an `is_open` parameter in
  the real implementation (removed from the CODEMANIFEST); `Trade.get_overall_performance`
  takes `start_date: datetime | None`, not `minutes: int | None` as originally documented
  (corrected).

## artifact_size

- **10 CODEMANIFEST files** (one per documented cell)
- **1,166 total lines** (`wc -l` across all 10 files in the deliverable directory)
- Cell sizes range from 57 lines (`freqtrade/data`) to 257 lines (`freqtrade/persistence`)
- No `.usages/` files were created — all practice/convention text used the DSL's **inline**
  `Usages` form (per `goga-cookbook`'s guidance: inline is appropriate when a practice is short
  and specific to one cell), so there is no separate `.usages/*.md` artifact count.

## contract_drift_findings

`goga contract --lang python` was run against 3 cells (`freqtrade/persistence`,
`freqtrade/exchange`, `freqtrade/resolvers`) to compare CODEMANIFEST signatures against the real
tree-sitter-extracted implementation:

- **`freqtrade/resolvers`** — near-perfect match on every method across `IResolver` and all 4
  documented concrete resolvers; only cosmetic drift (`Config`/`ExchangeConfig` internal type
  aliases shown as generic `dict[str, Any]` in the CODEMANIFEST, `cls`/default-value details
  omitted, as expected for a public-contract-only description).
- **`freqtrade/exchange`** — all `Exchange`/`ExchangeWS` methods and properties matched;
  cosmetic drift only (`Ticker`/`CcxtOrder`/`CandleType`/etc. internal type aliases shown as
  `dict[str, Any]`/`str`/`DataFrame`). One genuine gap (not miscoded, just incomplete):
  `get_tickers`'s real signature also accepts an optional leading `symbols: list[str] | None`
  parameter that the CODEMANIFEST omits — judged acceptable since it's an optional refinement
  parameter, not a load-bearing part of the contract, but noted here for transparency.
- **`freqtrade/persistence`** — found and fixed 2 genuine (non-cosmetic) errors, listed above
  under "Contract-drift corrections". After correction, re-verified clean. All other methods
  (`LocalTrade`, `Trade`, `Order`, `PairLock`, `PairLocks`, `CustomDataWrapper`, `KeyValueStore`)
  matched closely, again modulo internal-type-alias-vs-generic-type cosmetic differences (e.g.
  `KeyValueStore`'s `key`/`value` documented as `str`/`Any` vs. the real `KeyStoreKeys`/
  `ValueTypes` type aliases — an intentional simplification for public-contract legibility, not
  an error).

No drift was found that would materially mislead an agent about a cell's real public shape
after the two corrections above.

## maintenance_steps

N/A — one-time freeze, not yet exercised. Per `PROTOCOL.md` §6, this CODEMANIFEST forest is
frozen as-is for the duration of `benchmark-v1` and is not regenerated if freqtrade or Goga
change mid-benchmark.
