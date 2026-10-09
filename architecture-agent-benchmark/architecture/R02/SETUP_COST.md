# SETUP_COST.md — R02 (saltstack/salt)

## initial_generation_time

Active tool-call work spanned roughly **10:40–11:10 MSK (≈ 30 minutes)** on 2026-08-26 for the
full pipeline: verifying the pinned commit/clean working tree, running `goga init`
(non-interactive, `language: python`), loading the `goga-cell`/`goga-cookbook`/`goga-lang-disp`/
`goga-cell-python` DSL skill files directly (the Skill tool did not surface `goga-cell`/
`goga-cookbook`/`goga-lang-disp` by exact name in this session — same operational note as the R01
run — so their `SKILL.md`/`dsl.md` files were read directly instead), dispatching one
foreground and one background source-reading pass over the real salt codebase (`salt/loader/*`,
representative files across `modules`/`states`/`runners`/`returners`/`cache`/`grains`/`utils`,
`salt/minion.py`, `salt/master.py`), authoring the ~950-line `docs/arch/architecture-overview.md`
plan (9 cells, written incrementally: one `Write` for the skeleton, then one `Edit` per cell,
per the amendment's guidance — no transport failures were encountered this run), materializing it
by hand into 9 real `CODEMANIFEST` files (the `goga-apply`/`goga-cells-by-brainstorm` Skill tool
invocations were not attempted directly — the plan was instead materialized by writing each
cell's content straight to its real directory, per the amendment's documented fallback), 1 round
of scripted `goga lint` correction, `goga schema` verification, and `goga contract` drift
spot-checks on 3 cells (5 entities total).

## manual_correction_time

A single scripted pass (~3 minutes of the ~30-minute total): a Python script parsed the full
`goga lint` error list into `(cell, invalid_link_string)` pairs and mechanically stripped the
backtick pairs around each exact invalid string in its cell's `CODEMANIFEST`, converting them to
plain prose. No hand-editing of individual annotation text was needed beyond this scripted pass.

## number_of_manual_corrections

- **Lint correction rounds: 1** (`goga lint` was run 2 times total):
  1. Initial `goga lint` on the freshly materialized 9-cell forest: **309 errors**, all of one
     rule type: `annotation_links_exists` — invalid backtick cross-references. Root cause:
     annotations were written with backticks around nearly every code-like term for readability
     (dict keys like `` `name` ``/`` `changes` ``/`` `result` ``/`` `comment` ``, sibling method
     names like `` `store` ``/`` `fetch` ``/`` `flush` ``, file names like `` `data.py` ``, dotted
     expressions like `` `salt.loader.returners` ``, literal values like `` `True` ``/`` `False`
     ``, and cross-cell prose like `` `minion_mods` ``/`` `states` `` referenced from the root
     `salt` cell without those routine names being formally imported) — none of which are valid
     backtick link targets per the DSL (only: a signature parameter within its own annotation, a
     same-document declared Entity/Routine/imported-Type name, or a `Usages`/`Imports.Usages`
     practice key). This matches the exact failure mode documented in `PROTOCOL.md`'s Amendment 1
     from the R01 run.
  2. A script extracted the distinct `(cell, invalid_link_string)` pairs directly from the lint
     output (309 errors → 227 distinct strings across the 9 cells) and stripped the backtick pair
     around each exact string in its cell's file (converting `` `foo` `` → `foo`, plain prose).
     Re-lint: **0 errors** — no second manual pass was needed this run.
- **Contract-drift corrections: 0.** `goga contract` surfaced findings (see below) but none
  required editing the CODEMANIFEST content — the discrepancies found were either cosmetic
  (internal default-argument details omitted, as expected for a public-contract-only description)
  or a tool-extraction limitation (see below), not errors in what was documented.

## artifact_size

- **9 CODEMANIFEST files** (one per documented cell: `salt`, `salt/loader`, `salt/modules`,
  `salt/states`, `salt/runners`, `salt/returners`, `salt/cache`, `salt/grains`, `salt/utils`)
- **823 total lines** (`wc -l` across all 9 files in the deliverable directory)
- Cell sizes range from 51 lines (`salt/returners`) to 187 lines (`salt/loader`, the largest —
  documents 3 entities and 7 factory routines, reflecting its role as the actual architectural
  spine)
- No `.usages/` files were created — every practice/convention note used the DSL's **inline**
  form embedded directly in each cell's `Annotations`/method annotations (per `goga-cookbook`'s
  guidance: inline is appropriate when a practice is short and specific to one cell); no `Usages`
  directive was declared in any cell at all, so there is no separate `.usages/*.md` artifact count
  and no `.goga/usages/` project-level practice file either.

## contract_drift_findings

`goga contract --lang python` was run against 4 cells (`salt/loader`, `salt/cache`,
`salt/modules`, `salt/states`) — 5 entities and 7 routines total — to compare CODEMANIFEST
signatures against the real tree-sitter-extracted implementation:

- **`salt/loader`** — near-perfect match on all 7 factory routines (`minion_mods`, `states`,
  `runner`, `returners`, `utils`, `grains`, `cache`) and all 3 entities (`LazyLoader`,
  `LoaderContext`, `NamedLoaderContext`). Only cosmetic drift: `minion_mods`'s real signature
  also has a deprecated `initial_load=False` parameter (its own docstring says "Deprecated
  flag! Unused."), correctly omitted from the CODEMANIFEST; `LoaderContext.__init__`'s real
  signature has an internal `loader_ctxvar=loader_ctxvar` default not exposed in the
  CODEMANIFEST's zero-argument constructor signature (an internal wiring detail, not part of the
  type's meaningful public contract). Two methods (`LazyLoader.__getitem__`,
  `LazyLoader._process_virtual`) and one property (`Cache.modules`, see below) showed
  `"implementation": null` in the contract tool's output despite being directly verified as real,
  correctly-signatured code by reading `salt/loader/lazy.py` (`__getitem__` at line 514,
  `_process_virtual` at line 1342) — apparently a tool-extraction limitation with Python dunder
  methods, leading-underscore "private" methods, or `@cached_property`-decorated attributes
  (`Cache.modules` is a `@cached_property`), not a documentation error.
- **`salt/cache`** — `Cache`'s 5 public methods (`store`/`fetch`/`flush`/`list`/`contains`) matched
  the real implementation exactly. `LocalFSBackend` (the mutation-notation-modeled default
  driver) showed every method as `"implementation": null` — expected and correct, not a drift
  finding: `LocalFSBackend` intentionally documents `salt/cache/localfs.py`'s plain module-level
  functions as a DSL *mutation* of `Cache` (a same-shape concretization reached through dynamic
  `LazyLoader` dispatch, not Python inheritance), so there is no literal `class LocalFSBackend`
  for the contract tool's class-signature extractor to find — this is the intended, disclosed
  reading of the mutation notation per `goga-cell/dsl.md`'s "Mutation may be realized through: ...
  Adapter pattern ... Any other strategy" clause, not an implementation gap.
- **`salt/modules` and `salt/states`** — **the one genuinely notable finding of this drift check.**
  All 5 documented routines (`salt/modules`: `__virtual__`, `get_hash`, `ping`, `run`;
  `salt/states`: `installed`, `managed`) came back from `goga contract` matched against the
  *wrong* file's same-named function: e.g. `ping`'s `"implementation"` was
  `(host, timeout=False, return_boolean=False)` — that is `salt/modules/network.py`'s ICMP
  `ping`, not `salt/modules/test.py`'s zero-argument `ping()` that the CODEMANIFEST's `location:
  test.py` actually points to. Root-cause check: `grep -l "^def ping("` across `salt/modules/*.py`
  finds **7** files defining a top-level `ping` function (`test.py`, `test_virtual.py`,
  `network.py`, `win_network.py`, `junos.py`, `nxos.py`, `napalm_network.py`); `installed`/
  `managed` are defined in **11**/**13** different `salt/states/*.py` files respectively. `goga
  contract` appears to resolve a routine by bare function name across every file in the cell's
  directory rather than honoring the CODEMANIFEST's own `location:` field, so in a directory with
  267 (or 133) files and heavy name reuse across unrelated plugin files, it silently picks an
  unrelated same-named function instead of the one actually documented. This is a **real
  limitation of the drift-checking tool specific to large, flat, name-colliding plugin
  directories** — precisely the "organic/medium modularity" characteristic this repository was
  selected to represent — not an error in the CODEMANIFEST content itself: the documented
  signatures for `cmdmod.run`, `test.ping`, `file.get_hash`, `states/pkg.py`'s `installed`, and
  `states/file.py`'s `managed` were independently verified accurate by directly reading those
  exact files (see the source line numbers cited during authoring) both before and after this
  check. No correction was made to any CODEMANIFEST as a result, since the content was already
  correct; this finding is recorded here as a tooling caveat for anyone relying on `goga contract`
  against similarly-shaped flat, high-file-count, name-colliding directories elsewhere in the
  benchmark.

## maintenance_steps

N/A — one-time freeze, not yet exercised. Per `PROTOCOL.md` §6, this CODEMANIFEST forest is
frozen as-is for the duration of `benchmark-v1` and is not regenerated if salt or Goga change
mid-benchmark.
