# PLAUSIBILITY_CHECK.md — R05 (VictoriaMetrics/VictoriaMetrics)

## When this check was performed

`tasks/R05/task_A.md` through `task_D.md` were read for the first time **after** `SCOPE.md` was
written and frozen, and after all 9 CODEMANIFEST files were authored, materialized, linted
(0 errors after 2 correction rounds), and drift-checked via `goga contract` (8 corrections
across 3 spot-checked cells) — per the assignment's explicit ordering requirement. No content in
the architecture forest was revised in response to reading the tasks (see "Outcome" below).

## The four task prompts (quoted)

- **Task A**: add a relabeling action that "strip[s] leading and trailing whitespace from a
  label value," configured "via source label(s) and a target label" the same way existing
  value-transforming relabel rules are, working for both scrape-time and remote-write relabeling
  since "these share the same configuration format," with config-load-time validation
  "consistent with how other misconfigured relabeling rules are already rejected today."
- **Task B**: add a per-`job_name` cap on the number of active scrape targets, "regardless of
  which discovery mechanism produced those targets," off by default, with the affected jobs and
  excluded-target counts "visible... using the existing places where scrape target status is
  already reported."
- **Task C**: add a new service-discovery provider for Scaleway Instances, "the same way they
  already configure discovery for the cloud providers we support today, following existing
  conventions for naming, refresh interval, and error handling," with periodic refresh and
  standard token-based auth/proxy support "the way it does for our other cloud-provider
  integrations."
- **Task D**: when `-storage.maxHourlySeries`/`-storage.maxDailySeries` cause samples to be
  dropped, "record which metric name it belonged to and increment a per-name counter," exposed
  as a "top N metric names by drop count" query, with a "configurable or... sensible fixed
  default" memory bound and zero hot-path overhead when disabled.

## Term-level check: no task-specific vocabulary appears in the forest

Grepped all 9 CODEMANIFEST files (and this deliverable directory) for the task-specific terms
each prompt turns on: "trim"/"whitespace" (Task A), "target cap"/"runaway"/"SampleLimit"/
"SeriesLimit"/"LabelLimit" (Task B), "Scaleway" (Task C), "top N"/"offend"/"drop count"/
"metricnamestats"/"per-metric-name" (Task D) — **none** appear anywhere in the 9 CODEMANIFEST
files. (Two incidental, unrelated hits surfaced in `SETUP_COST.md` and `lib/storage`/
`app/vmstorage`'s real `topN`/`focusLabel` parameters of the pre-existing `GetTSDBStatus`/
`TSDBStatus` cardinality-diagnostic methods — a real, already-existing Go parameter name for an
unrelated feature, not a reference to Task D's "top N offenders" phrasing.) The forest never
says anything shaped like "add a trim action here," "cap targets per job," "add Scaleway
support," or "track drops per metric name" — every annotation describes what a real,
already-existing type/method/mechanism does today, in the codebase's own vocabulary (e.g.
`RelabelConfig`/`action_set`/`ParsedConfigs`, `ScrapeConfig`/`ScrapeWork`/`registry_dispatch`,
`SDConfig`/`GetLabels`/`provider_registry_pattern`, `Storage`/`OpenOptions`/`GetTSDBStatus`),
consistent with `TREATMENT_DESIGN.md` §4's required phrasing style.

## Where genuine overlap exists, and why it's expected rather than leakage

All four tasks touch functionality that lives near or inside cells this forest documents — this
is unavoidable and, per the treatment design, *intended*: a real architecture doc-set should
make a repository's existing extension points and conventions discoverable, and RQ7/RQ9 of the
benchmark specifically ask whether the Goga treatment changes existing-extension-point usage and
how the effect varies by task type. Providing accurate, task-agnostic documentation of a real
mechanism is not the same as hinting at a specific task built on top of it:

- **Task C ↔ `lib/promscrape/discovery/kubernetes`**: this is the closest overlap, comparable in
  kind to R01's Task C/`plugins.protections` finding. Task C's "add a Scaleway discovery
  provider following existing conventions" is a near-textbook new entry in the extension-point
  registry this cell documents by name: the `provider_registry_pattern` Usages entry spells out
  the exact shape a new provider must follow (`SDConfig` type + `GetLabels(baseDir string)
  ([]Labels, error)` method, registered as a new `[]SDConfig`-typed field on `lib/promscrape`'s
  `ScrapeConfig` struct, plus an `SDCheckInterval` flag) and names two other real siblings
  (`consul`, `ec2`, `gce`) that follow it — but it never mentions Scaleway, and Scaleway does not
  appear in the ~22-provider list the Usages entry enumerates (correctly, since the real
  pre-task codebase does not have it). This is Task C's category by design ("Existing Extension
  Point... prompt does not name it — agent must discover it or fail to"). Judgment call: kept
  as-is, since documenting this real extension point generically, including its exact
  registration mechanism, is precisely the discoverability the Goga condition is meant to test,
  not an accidental giveaway of Scaleway-specific content.
- **Task B ↔ `lib/promscrape`/`app/vmagent`**: the forest's `lib/promscrape` cell documents the
  real target-diffing loop (`scraperGroup`s polling per discovery-provider type, diffing against
  previous target sets) and the real existing status surface (`WriteHumanReadableTargetsStatus`,
  `WriteServiceDiscovery`, `WriteAPIV1Targets` — exactly "the existing places... scrape target
  status is already reported" Task B asks the new cap's effect to surface through) — but it does
  not mention target counts, caps, limits, or anything resembling a safety-net mechanism. This
  is architecturally useful, generic discoverability (where would an agent surface a new
  per-job status fact?) rather than a solution hint.
- **Task D ↔ `lib/storage`**: the forest's `OpenOptions` entity documents the real
  `maxHourlySeries`/`maxDailySeries` fields — necessarily, since these are the literal
  `-storage.maxHourlySeries`/`-storage.maxDailySeries` flags Task D's own ticket text names, and
  omitting real, load-bearing `Storage` startup configuration to avoid this overlap would have
  made the god-package documentation less honest, not more neutral. No mention is made of drop
  tracking, per-metric counters, or a top-N query — the forest documents that these limits
  *exist and are configured here*, not *what to do when they're hit*. `Storage`'s method list
  was deliberately kept to its main ingestion/search/deletion/snapshot surface and does not
  include the real (but task-irrelevant-to-hide) `metricsTracker`/`GetMetricNamesStats`/
  `ResetMetricNamesStats` fields/methods the research pass surfaced during source reading — these
  were left out of the authored CODEMANIFEST not because of Task D (they were never going to be
  central to a ~15-method representative subset of a 260-method god package regardless of any
  task list), but their absence is disclosed here for full transparency since they are the real
  feature closest in shape to what Task D asks for.
- **Task A ↔ `lib/promrelabel`**: weaker overlap than Task C's. The forest's `action_set` Usages
  entry lists the real, existing relabel actions (`replace`, `uppercase`, `lowercase`,
  `labelmap`, `hashmod`, etc.) and documents `RelabelConfig`'s real `sourceLabels`/`targetLabel`
  shape — the same source-labels-to-target-label configuration pattern Task A's requirements
  explicitly ask the new trim action to mirror — but no whitespace-trimming action, nor anything
  resembling one, is named or hinted at anywhere in the forest.

## Outcome

No revision was made to the architecture forest as a result of this check. The one genuine
close-overlap case (Task C / `lib/promscrape/discovery/kubernetes`'s `provider_registry_pattern`)
was judged, exactly as in the R01 precedent, to be the expected, in-scope operation of
documenting a real, load-bearing extension point — not task-specific hint content — and is
disclosed here explicitly rather than papered over, per `TREATMENT_DESIGN.md` §4's "independent
plausibility check" requirement. The `lib/storage`/`OpenOptions` overlap with Task D was judged
similarly unavoidable (the flags are named in the ticket itself) and is disclosed for the same
reason. If a stricter standard is wanted for future repositories in this benchmark, one option
would be to omit `OpenOptions`'s specific field list and describe it only as "startup tuning
knobs" in prose; this was not done retroactively here to avoid the appearance of hand-tuning the
artifact after seeing the task list, which itself would be a worse violation of the freeze
discipline than leaving an honestly-disclosed, architecturally-justified overlap in place.
