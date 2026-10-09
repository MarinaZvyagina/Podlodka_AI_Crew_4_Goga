# RESTRUCTURE_REPORT.md — R05 (VictoriaMetrics/VictoriaMetrics) Condition C

Sixth repository restructured for Condition C, and the largest by cell count so far: 55 cells (9
originally documented + 46 new), versus R01's 21 or R04's 6. Go, 120.1k LOC.

## Scope-expansion decision

Phase 8's `SCOPE.md` explicitly disclosed that the ~47 real subdirectories under
`app/vminsert`/`app/vmagent`/`app/vmselect` (wire-format ingestion handlers, the PromQL/Graphite
query engines, result fan-out, etc.) were left undocumented for one-time-preparation-cost reasons —
a real, acknowledged tension with Goga's `location:` rule. Presented with this tradeoff, the user
explicitly chose to expand scope and fully formalize it rather than preserve the disclosed
exclusion (unlike R04, where the analogous `packages/excalidraw` root/scene/data cut was kept as
a disclosed exclusion). This makes R05 the first Condition C repository where the restructured
scope is **larger** than what Condition B's static docs covered, not merely more architecturally
correct within the same scope — a deliberate, explicit divergence from the "same scope, different
correctness" comparison principle used for R01/R03/R04/R06/R07, made with the user's informed
consent to the cost/scope tradeoff.

## Scale: 46 new cells across 5 families

| Family | New cells | Character |
|---|---|---|
| `app/vminsert` | 18 | Ingestion fan-in: mostly 1-file, 1-2-export wire-format protocol handlers (`InsertHandler`); `common` (4 files, shared `InsertCtx`) is the exception |
| `app/vmagent` | 17 | Same shape as vminsert, forwarding instead of storing; `remotewrite` (6 files) is the substantial exception |
| `app/vmselect` | 8 | Query-serving; `promql` (15 files), `prometheus` (13 files), `graphite` (18 files) carry real query-engine logic, not thin handlers |
| `lib/storage` | 2 | Real, algorithmically-documented nested storage subsystems (`metricsmetadata`: sharded LRU eviction; `metricnamestats`: fill-until-full tracking) |
| `lib/promscrape` | 1 | `discoveryutil` — shared HTTP-client/caching helpers for the (mostly out-of-scope) service-discovery backend family |

**0 hidden** across all 55 cells — matching R03/R01/R04's "framework/application surface is
legitimately public" pattern. Facade completion also touched the 4 original cells needing no new
nested cells (`lib/mergeset`, `lib/promrelabel`, `app/vmstorage`, `lib/storage` itself): 3, 6, and
13 genuinely-missing exports respectively were found and declared, plus 6 missing declarations
(`Tag`, `TagFilter`, `TimeRange`, `NewSearchQuery`, `MarshalMetricNameRaw`, `TSDBStatus`) surfaced
only once the new `app/vmselect` cells' real Imports needed them — closed centrally during
reconciliation rather than by the original per-cell agents, since they belonged to cells outside
each agent's assigned scope.

## Zero circular dependencies — verified via `go list`, not grep

Full detail in `CYCLE_FIXES.md`. Unlike every prior repo in this study (which relied on `grep`
for cross-cell import scanning), R05's scale motivated using Go's own `go list -f
'{{.ImportPath}}|{{join .Imports ","}}'` across all 8 target package trees, producing a
compiler-verified exact import graph, fed into a real DFS cycle detector. Result: a clean DAG, 0
cycles among all 55 cells.

## Two `goga lint` tool limitations found at this scale (both confirmed, both worked around)

1. `import_has_valid_from_path` false positives when linting a single cell without full-project
   context — the same limitation documented in every prior repo; resolved by linting from the
   project root.
2. **New to this study**: `import_has_not_duplicate` compares pre-alias source names rather than
   resolved `AS` aliases, only surfaced because R05 is the first repo with enough sibling cells
   sharing identical real Go identifiers (9+ wire-format packages each exporting `InsertHandler`)
   to trigger it. Independently discovered by two separate agents, empirically confirmed (valid,
   unique aliases still trip the check), and resolved by formally importing only forest-wide-unique
   names while disclosing the rest in prose via an explicit `aliasing_limit` Usages entry — an
   honest tool-gap disclosure, not a content gap.

## Process notes

- 7 parallel agents handled the 46-new-cell creation + facade completion, split by ownership
  boundary to avoid write conflicts: `app/vminsert` and `app/vmagent` (each a single agent owning
  both its 17-18 new cells and its own parent manifest); `app/vmselect`'s 8 new cells split
  across 3 read-only sub-agents (promql+prometheus; graphite+graphiteql;
  netstorage+stats+searchutil+querystats) that reported their required parent Imports back rather
  than editing the shared parent file themselves; `lib/storage`'s 2 new cells + parent (1 agent);
  `lib/promscrape/discoveryutil` + facade completion of `lib/mergeset`/`lib/promrelabel`/
  `app/vmstorage` (1 agent, bundled for efficiency given their small individual size).
- The orchestrating session merged the 3 vmselect sub-agents' reports into `app/vmselect`'s parent
  manifest directly (33 imported symbols, each cross-checked against `main.go`'s real
  `package.Identifier` usage via grep, not trusted from the sub-agents' own summaries), and closed
  the `lib/storage`/`app/vmstorage` declaration gaps (6 types) that the vmselect/graphite agent
  flagged as needed-but-missing in cells outside its own assigned scope.
- Multiple agents independently flagged fake `<system-reminder>`-styled text embedded in tool
  output during this work (consistent with the pattern observed in R03/R04/R07) — each correctly
  identified it as injected content rather than genuine harness messages and disregarded it.

## Hard gate: build + test

- `go build ./...`: clean, 0 errors.
- `go test ./...`: **129/129 real Go test packages passed** (identical count on a from-scratch
  unmodified-commit comparison run). The only failures (97 sub-tests, all within one package,
  `apptest/tests`) are pre-existing and unrelated to this restructuring: that end-to-end suite
  requires race-instrumented binaries (`victoria-metrics-race`, `vmstorage-race`, etc.) built by a
  separate `make apptest-legacy`-family target first, not by a bare `go test ./...` invocation —
  confirmed identical on the untouched original commit (same 97 failures, same "no such file"
  errors) via direct side-by-side comparison, not merely inferred.

## Control re-certification

All 8 of Phase 5's control diffs (`tasks/R05/controls/*.diff`) applied cleanly against the
restructured commit. 5 of ~24 validator scripts hardcoded the original base-commit SHA and needed
adapted copies (`architecture_v2/R05/validators_adapted/`, matching the SHA-substitution pattern
used for R06). **All 4 tasks discriminate correctly, matching Phase 5's original certification
exactly** — including a genuine, pre-existing discrepancy in Phase 5's own `CONTROL_RESULTS.md`
found during recertification: Task A's negative control is documented there as passing its
functional check "by design," but it actually fails functionally (an `unknown action
"trim_space"` parse error) — confirmed identical on the untouched original commit via
side-by-side diff-application, i.e. a stale note in the original documentation, not a
restructuring artifact. This makes Task A's negative control discriminate even more strongly than
originally documented (both functional and 3/4 architecture checks fail), not a discrimination
failure.

| Task | Positive: functional | Positive: all AC | Negative: functional | Negative: ≥1 AC fails |
|---|---|---|---|---|
| A | PASS | PASS (4/4) | FAIL* | Yes (3/4 FAIL — AC1-AC3) |
| B | PASS | PASS (4/4) | PASS | Yes (3/4 FAIL) |
| C | PASS | PASS (4/4) | FAIL | Yes (4/4 FAIL) |
| D | PASS | PASS (4/4) | PASS | Yes (2/4 FAIL — AC1, AC2) |

*See note above — Phase 5's own docs expected PASS here; actual behavior (both original and
restructured commit) is FAIL, a documentation staleness unrelated to this restructuring.

## Artifacts

- Restructured commit: `1afc7bb270a2529639eef177b9c75d549d3169f4`, tagged `condition-c-r05-v1`
  in the shared base clone (`benchmark-scratch/repos/R05`).
- `architecture_v2/R05/CYCLE_FIXES.md` — full detail on the `go list`-based cycle analysis and
  both `goga lint` tool limitations.
- `architecture_v2/R05/validators_adapted/` — 5 SHA-adapted validator scripts + fixtures.
- The 55 cells' `CODEMANIFEST` files live directly in the restructured commit.
