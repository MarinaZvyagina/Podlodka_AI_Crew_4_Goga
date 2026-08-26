# SETUP_COST.md — R05 (VictoriaMetrics/VictoriaMetrics)

## initial_generation_time

Active tool-call work spanned roughly **11:02–11:21 MSK (≈ 19 minutes)** on 2026-08-26 for the
full pipeline: reading `TREATMENT_DESIGN.md`/`PROTOCOL.md` (including Amendment 1), running
`goga init` for the golang project type, reading the `goga-cell`/`dsl.md`/`goga-cookbook`/
`goga-lang-disp`/`goga-cell-go` DSL skills directly (the Skill tool did not expose goga skills in
this session, consistent with Amendment 1's noted fallback), dispatching **9 parallel
source-reading research passes** over the real VictoriaMetrics codebase (`lib/storage`,
`lib/mergeset`, `lib/promscrape`, `lib/promscrape/discovery/kubernetes`, `lib/promrelabel`,
`app/vmagent`, `app/vminsert`, `app/vmselect`, `app/vmstorage`), authoring the ~1,155-line
`docs/arch/architecture-overview.md` plan (9 cells) incrementally (one `Write` for the skeleton,
then one `Edit` per cell, per Amendment 1's mitigation for large single-`Write` transport
failures — no transport failures were encountered this run), materializing it by hand into 9
`CODEMANIFEST` files (the `Skill`/`/goga:apply` invocation path was not attempted directly in
this session — the fallback hand-materialization procedure from Amendment 1 was used from the
start, reading `goga-apply`'s and `goga-cells-by-brainstorm`'s `SKILL.md` files directly), 2
rounds of `goga lint` correction, one `goga schema` verification, `goga contract` drift
spot-checks on 3 cells, and 3 post-hoc corrections from that drift check.

No infrastructure-level connection interruptions occurred during this run (unlike the R01
validation run, which experienced repeated transport failures on the large single-`Write` step —
avoided here by writing incrementally from the start per the amended protocol).

## manual_correction_time

Concentrated in two passes, both within the session above (not separately timed, but a
significant fraction of the total): one large pass fixing invalid backtick cross-references
(stripping backticks from CLI flags, HTTP paths, wildcard patterns, package-qualified dotted
expressions like `Storage.AddRows`, and cross-method references to sibling methods that are not
valid link targets per the DSL — only same-document top-level Entity/Routine names, imported
types, Usages keys, and a method's own signature parameters are valid targets), and one small
pass adding a missing `OpenOptions` type declaration to `lib/storage` (imported by
`app/vmstorage` but not yet defined) plus simplifying one nested-function-type signature that
failed `signature_is_valid`.

## number_of_manual_corrections

- **Lint correction rounds: 2** (`goga lint` was run 3 times total):
  1. Initial `goga lint` on the freshly materialized forest: **116 errors** across all 9 cells —
     three rule types: `annotation_links_exists` (114 — invalid backtick cross-references, the
     large majority of which were plain-English mentions of collaborating packages/functions/
     CLI-flags/HTTP-routes that were backticked out of habit despite this forest's deliberate
     choice not to declare formal `Imports` for the four `app/*` composition-root cells — see
     `architecture/R05/docs` note in the plan's Dependency Map — plus a handful of genuinely
     invalid dotted expressions like `Storage.AddRows`/`ParsedConfigs.Apply`/`SDConfig.MustStart`
     and cross-method references such as a property's annotation backticking a sibling method
     name), `import_type_exists` (1 — `OpenOptions` imported by `app/vmstorage` from
     `lib/storage` but not yet declared there), `signature_is_valid` (1 — a nested nameless
     function-type parameter `resetCacheIfNeeded: func(mrs: []MetricRow)` in `app/vmstorage`'s
     `Init` broke the `(...) -> ...` signature grammar).
  2. **Root-cause pattern confirmed by this run:** only four kinds of backtick targets are valid
     — (a) a same-document top-level `Entity`/`Routine` name (nested method/property names do
     **not** count, even within the same entity or from a sibling method's own annotation), (b)
     an imported `Type` from `Imports`, (c) a `Usages` key, (d) a signature parameter belonging
     to the exact node being annotated. Cross-method references (e.g. a property's annotation
     referencing a sibling method by name) and dotted `Type.method` expressions both fail even
     when both halves are independently valid identifiers. Fixed by either stripping backticks
     to plain prose or rephrasing as "this type's own X method" while keeping the type-name
     backtick. Re-lint: **2 errors** (both in `app/vmstorage`'s `VMStorage` entity-level
     annotation, referencing `VMInsertAPI`/`VMSelectAPI` package-level variables that are not
     declared types in this document). Stripped both. Re-lint: **0 errors**.
- **Contract-drift corrections: 3** (found via `goga contract`, see below): `lib/storage`'s
  `Storage.AddRows`/`RegisterMetricNames` documented as returning `err:error` when the real
  methods return nothing, and `SearchLabelNames`/`SearchLabelValues` missing a real `maxMetrics
  int` parameter; `lib/promscrape/discovery/kubernetes`'s `SDConfig.GetScrapeWorkObjects`
  documented as returning only `[]Any` when the real method returns `([]any, error)`;
  `app/vmstorage`'s `VMStorage.SearchMetricNames`/`DeleteSeries`/`TSDBStatus` documented with an
  invented `(tfss, deadline)` shape when the real methods take `(qt *querytracer.Tracer, sq
  *storage.SearchQuery, deadline)` (`TSDBStatus` also missing real `focusLabel`/`topN`
  parameters), and a `MustCreateSnapshot` method invented on `VMStorage` that does not exist
  there in the real source (snapshot administration is handled inline in `app/vmstorage/main.go`
  by calling the wrapped `Storage`'s own snapshot methods directly).

## artifact_size

- **9 CODEMANIFEST files** (one per documented cell)
- **995 total lines** (`wc -l` across all 9 files in the deliverable directory), **51,553 bytes**
- Cell sizes range from 58 lines (`app/vmagent`) to 220 lines (`lib/storage`, the god package)
- No `.usages/` files were created — all practice/convention text used the DSL's **inline**
  `Usages` form (per `goga-cookbook`'s guidance: inline is appropriate when a practice is short
  and specific to one cell), so there is no separate `.usages/*.md` artifact count.

## contract_drift_findings

`goga contract --lang golang` was run against 3 cells (`lib/mergeset`, `lib/storage`,
`lib/promscrape/discovery/kubernetes`, plus a follow-up check on `app/vmstorage` after the first
round surfaced a pattern worth re-checking elsewhere):

- **`lib/mergeset`** — near-perfect match on every method's parameter list; the only systematic
  "difference" is expected and documented in the DSL itself: Go constructors don't exist, so
  every Entity's own top-level signature (e.g. `Table(path, flushInterval, prepareBlock,
  isReadOnly)`) shows `implementation: "()"` because there is no single matching Go declaration
  — the real construction logic lives in the separately-documented `MustOpenTable` factory
  function, exactly as the language skill prescribes. Return-type "drift" is cosmetic:
  CODEMANIFEST's forbidden-pointer-and-tuple-label convention renders `() -> ([]int64, []byte,
  error)` as semantically-labeled single values, not a real mismatch.
- **`lib/storage`** — found and fixed 4 genuine (non-cosmetic) errors, listed above under
  "Contract-drift corrections" (`AddRows`, `RegisterMetricNames`, `SearchLabelNames`,
  `SearchLabelValues`). After correction, re-verified clean. All other methods across `Storage`,
  `Block`, `MetricName`, `MetricRow`, `TSID`, `SearchQuery`, `TagFilters`, `Search` matched
  closely, modulo the same expected constructor-signature and pointer-vs-bare-type cosmetic
  differences (e.g. `tfss: []TagFilters` vs. the real `[]*TagFilters`).
- **`lib/promscrape/discovery/kubernetes`** — found and fixed 1 genuine error
  (`GetScrapeWorkObjects` missing its real `error` return value). `MustStart`/`MustStop` matched
  exactly; `PrepareBlockCallback`-style function-type declarations
  (`ScrapeWorkConstructorFunc`) show `implementation: null` since a `type X func(...)` alias
  has no single call-site the contract-extractor resolves to — expected, not a drift signal.
- **`app/vmstorage`** — found and fixed 3 genuine errors on `VMStorage`
  (`SearchMetricNames`/`DeleteSeries`/`TSDBStatus`'s real `(qt, sq, ...)` parameter shape vs. the
  invented `(tfss, deadline)` shape I had originally written from the research report's
  higher-level description rather than the literal signature, and a `MustCreateSnapshot` method
  that does not exist on this type at all). After correction, re-verified clean.

No drift was found that would materially mislead an agent about a cell's real public shape after
the four rounds of correction above (4 in `lib/storage`, 1 in the kubernetes discovery cell, 3 in
`app/vmstorage` — 8 corrections total across the contract-drift pass).

## maintenance_steps

N/A — one-time freeze, not yet exercised. Per `PROTOCOL.md` §6, this CODEMANIFEST forest is
frozen as-is for the duration of `benchmark-v1` and is not regenerated if VictoriaMetrics or
Goga change mid-benchmark.
