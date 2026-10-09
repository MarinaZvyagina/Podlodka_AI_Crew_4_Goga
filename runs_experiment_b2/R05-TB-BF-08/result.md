# R05-TB-BF-08

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: False
Cost: $3.4544505000000005
Duration: 571934ms, turns: 59

## Agent's own summary

# Change Plan

## Task Classification
**Feature** (additive safety-net capability) — no existing behavior changes when the new configuration is left at its default (unlimited).

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `lib/promscrape` | `config.go` | New flag `-promscrape.maxScrapeTargetsPerJob`, new `ScrapeConfig.MaxScrapeTargets *int` YAML field, resolution into `scrapeWorkConfig.maxScrapeTargets`, propagation into `*ScrapeWork` |
| `lib/promscrape` | `scrapework.go` | New unexported `ScrapeWork.maxScrapeTargets int` field |
| `lib/promscrape` | `scraper.go` | Cap enforcement inside `scraperGroup.update`'s admission loop; per-group truncated-count reporting to `tsmGlobal` |
| `lib/promscrape` | `targetstatus.go` | New `targetDropReasonTooManyTargets`; new truncated-count tracking/accessors on `targetStatusMap`; new `status="truncated"` gauge in `registerJobsMetricsLocked`; new `truncatedCount` field on `jobTargetsStatuses` |
| `lib/promscrape` | `targetstatus.qtpl` (+ regenerated `targetstatus.qtpl.go`) | Truncation indicator on the `/targets` page (plain-text and HTML) |
| `lib/promscrape` | `config_test.go`, `scraper_test.go`, and/or `targetstatus_test.go` | New tests: under-limit, over-limit (truncated + visible), default-unlimited |
| `lib/promscrape` (docs, non-manifest) | `CODEMANIFEST` | Annotation updates on `Init`, `WriteHumanReadableTargetsStatus`, `WriteServiceDiscovery` describing the new admission/visibility behavior |
| repo root (non-code) | `docs/victoriametrics/sd_configs.md`, `CHANGELOG.md` | New `max_scrape_targets` YAML reference entry; changelog line if an unreleased section exists |

## Root Cause Analysis
`lib/promscrape` has no mechanism to bound how many targets a single `job_name` may have active, regardless of source. `scraperGroup.update` (scraper.go) admits every newly-discovered target unconditionally. Each of the ~23 discovery mechanisms runs its own independent `scraperGroup`, so no single provider's code path sees the job's total target count across all providers — only `targetStatusMap` (`tsmGlobal`) aggregates purely by `jobNameOriginal` across every group already, via `upByJob`/`downByJob`. This makes `tsmGlobal` the only existing structure with the cross-discovery-type visibility required to enforce a per-job cap uniformly.

## Trace Summary
- `getScrapeWorkConfig` (config.go) → `scrapeWorkConfig` → `swc.getScrapeWork` → `*ScrapeWork`: the single per-target construction path reached by every discovery mechanism (generic SD dispatch, kubernetes/http lifecycle callbacks, static/file_sd) — correct place to resolve and carry the cap value.
- `scraperGroup.update`'s `for _, sw := range swsToStart { ...; tsmGlobal.Register(&sc.sw); ... }` loop (scraper.go) — the single discovery-type-agnostic code path where admission happens; precedent already exists here for `droppedTargetsMap.Register(..., targetDropReasonDuplicate, ...)`.
- `targetStatusMap.upByJob`/`downByJob`, keyed only by `jobNameOriginal` — already cross-discovery-type aggregated; needs a read accessor, not new aggregation logic.
- `registerJobsMetricsLocked` — existing per-job gauge-pair registration pattern to extend with a third series.
- `/service-discovery` page already renders any `droppedTarget.dropReason` generically (no template change needed there); `/targets` page (`scrapeJobTargets`, `TargetsResponsePlain`) has no truncation indicator and needs new template fields.

## Change Strategy

1. **config.go — configuration surface**
   - Add flag: `maxScrapeTargetsPerJob = flag.Int("promscrape.maxScrapeTargetsPerJob", 0, "...")`, default `0` = unlimited, documented inline referencing `max_scrape_targets`.
   - Add `MaxScrapeTargets *int `yaml:"max_scrape_targets,omitempty"`` to `ScrapeConfig`, next to `SeriesLimit`.
   - Add `maxScrapeTargets int` to `scrapeWorkConfig`, next to `seriesLimit`.
   - In `getScrapeWorkConfig`, resolve exactly like `seriesLimit`: global default, overridden by non-nil per-job value; no negative/zero-guard needed beyond the existing `*int != nil` check (zero and negative both mean "use the resolved value as-is"; a job explicitly setting `max_scrape_targets: 0` is indistinguishable from "unset" under this pattern, which matches how `series_limit: 0` already behaves — this is an accepted, pre-existing pattern quirk, not a new inconsistency).
   - Add `maxScrapeTargets: swc.maxScrapeTargets` to the `*ScrapeWork` literal in `swc.getScrapeWork`.
   - No `__max_scrape_targets__` label override — this is a job-level admission policy, not a per-target scrape parameter; adding one would imply per-target semantics that don't exist for a cap enforced at the job level, and none of the requirements ask for it.

2. **scrapework.go — data carrier**
   - Add unexported field `maxScrapeTargets int` on `ScrapeWork`, next to `jobNameOriginal`. Unexported field is consistent with existing internal-only fields and is invisible to any external contract (confirmed: `ScrapeWork`'s CODEMANIFEST-documented `properties`/methods are all exported; per `goga-cell-go`, only exported identifiers belong in the manifest body, so this field requires no CODEMANIFEST body entry — only its behavioral consequence, described in `Init`'s annotation, needs mention). No change to `sw.key()` — the cap is an admission-time policy, not a target-identity attribute, so including it in the dedup key is unnecessary and would risk spurious scraper restarts if the cap value changes on reload.

3. **targetstatus.go — cross-group tracking, reporting, metrics**
   - Add `targetDropReasonTooManyTargets targetDropReason = "too many targets for job_name"` (or equivalent operator-readable string) next to the other reasons.
   - Add `truncated map[string]map[string]int` to `targetStatusMap` (group → job → count), initialized in `newTargetStatusMap`.
   - Add `countByJob(jobName string) int` (sum of `upByJob[jobName]+downByJob[jobName]`, under `tsm.mu`) for scraper.go to query current cross-group active count.
   - Add `setTruncatedCounts(group string, counts map[string]int)` — replaces `tsm.truncated[group]` wholesale under `tsm.mu`, called once per `scraperGroup.update` cycle so stale truncation entries are cleared automatically when a job's target set shrinks back under the cap.
   - Add `truncatedByJob(jobName string) int` — sums across all groups under `tsm.mu`, used by the new metric gauge and by `getTargetsStatusByJob`.
   - Extend `registerJobsMetricsLocked`: unregister the new gauge name alongside the existing up/down pair on job removal; register a third `metrics.NewGauge(vm_promscrape_scrape_pool_targets{scrape_job=%q, status="truncated"}, ...)` reading `tsm.truncatedByJob(jobNameLocal)` on job addition. This metric is independent of `droppedTargetsMap`/`-promscrape.dropOriginalLabels`, so it stays accurate even when original labels are dropped.
   - Extend `jobTargetsStatuses` with `truncatedCount int`; populate it in `getTargetsStatusByJob` from `tsm.truncatedByJob(jobName)` for each job (including entries that might otherwise be classified as "empty" if all their targets are truncated — verify against `getEmptyJobs` logic during implementation so a fully-truncated job doesn't disappear from the page).

4. **scraper.go — enforcement**
   - Inside `scraperGroup.update`, after `swsToStart` is computed and before the existing `for _, sw := range swsToStart { sc, err := newScraper(...); ... }` loop starts scrapers, insert a filtering pass:
     - Maintain a local `admittedCounts map[string]int` seeded lazily per job from `tsmGlobal.countByJob(job)`.
     - Maintain a local `truncatedCounts map[string]int` for this call.
     - For each `sw` with `sw.maxScrapeTargets > 0`: if `admittedCounts[job] >= sw.maxScrapeTargets`, register it as dropped (`droppedTargetsMap.Register(sw.OriginalLabels, sw.RelabelConfigs, targetDropReasonTooManyTargets, nil)`), increment `truncatedCounts[job]`, and exclude it from the set that proceeds to `newScraper`; otherwise increment `admittedCounts[job]` and let it proceed.
     - After processing, call `tsmGlobal.setTruncatedCounts(sg.name, truncatedCounts)` unconditionally (even if empty, to clear a previously-truncated state).
   - This preserves the existing dedup/stop/start ordering and only adds a filter stage; no change to `sg.m`, `additionsCount`/`deletionsCount` semantics for admitted targets.

5. **targetstatus.qtpl — human-readable visibility**
   - `TargetsResponsePlain`: append e.g. `, N truncated (over max_scrape_targets)` to the per-job summary line when `jts.truncatedCount > 0`.
   - `scrapeJobTargets`: add a warning-styled badge/span next to the up/total count when `jts.truncatedCount > 0`.
   - Regenerate `targetstatus.qtpl.go` via `qtc -dir=lib` (binary present at `$(go env GOPATH)/bin/qtc`), per the existing `Makefile` `quicktemplate-gen` target — do not hand-edit the generated file.
   - No changes to `discoveredJobTargets`/service-discovery template (generic drop-reason rendering already covers it).

6. **Tests** — see Test Strategy below.

7. **Docs** — add a `max_scrape_targets` block to `docs/victoriametrics/sd_configs.md` immediately after `series_limit` (or `sample_limit`), following the exact comment format of neighboring entries (default, override precedence, doc link). Check for a flags-documentation generator (e.g. a script under `docs/` or a `make` target that extracts `flag.*` calls) before deciding where the new CLI flag needs to be listed; if none exists, no separate flag-doc file needs hand-editing beyond the flag's own `flag.Int(...)` usage string (confirmed pattern: other `-promscrape.*` flags are documented only via their own usage strings plus prose in `vmagent.md`/`sd_configs.md`, not a separate generated flags table for promscrape flags specifically — verify during implementation).

## Specification Impact
- `Init`'s annotation gains one clause to its existing `Algorithm` step 3 ("diff... and start/stop individual target scrapers accordingly"): admission of new targets is now bounded per `job_name` by an optional configured cap, with excess targets recorded as dropped rather than started.
- `WriteHumanReadableTargetsStatus`'s annotation gains a clause noting the page now also surfaces per-job truncation counts when a job exceeds its configured cap.
- `WriteServiceDiscovery`'s annotation gains a clause noting truncated targets appear there via the existing dropped-target reporting mechanism, now including the new drop reason.
- No new `Imports`, no new top-level documented types, no signature changes to any documented routine/entity — all changes are internal-behavior additions to already-documented types (`Init`, `WriteHumanReadableTargetsStatus`, `WriteServiceDiscovery`) plus one internal struct field (`ScrapeWork.maxScrapeTargets`) that, being unexported, is not part of the manifest body per Go cell rules.
- `ScrapeConfig`'s existing manifest entry (documents `jobName`/`kubernetesSDConfigs` in its signature per the current CODEMANIFEST) does not need its signature rewritten — the DSL signature is illustrative of shape, not exhaustive of every field (consistent with how `SeriesLimit`/`SampleLimit`/`MaxScrapeSize` are not enumerated in the current signature either).

## Usage Impact
No `.usages/*.md` files exist for `lib/promscrape` today (confirmed: only `app/vmagent`'s own header `Usages.composition_root`, which is prose about initialization order and does not reference `lib/promscrape` internals in a way this change affects). No usage files require creation or modification — the change does not alter how any consumer calls `lib/promscrape`'s exported API (`Init`, `Stop`, `CheckConfig`, `WriteConfigData`, `WriteHumanReadableTargetsStatus`, `WriteServiceDiscovery`, `WriteAPIV1Targets`, `WriteTargetResponse` all keep identical signatures).

## Compatibility Verification
**Backward compatible.** With no `max_scrape_targets` set in any `scrape_config` and `-promscrape.maxScrapeTargetsPerJob` left at its default `0`, `sw.maxScrapeTargets` resolves to `0` for every target, the new filtering pass in `scraperGroup.update` is a no-op (`if sw.maxScrapeTargets > 0` guards it), `tsmGlobal.setTruncatedCounts` is called with empty maps, the new gauge reports `0` for every job, and no new `droppedTargets` entries are ever registered. All existing exported function signatures, JSON/HTML/plain-text output shapes, and manifest-documented algorithms are preserved for the default (unconfigured) case. No existing test is expected to observe any behavior difference.

## Test Strategy
Add to `lib/promscrape` test files, matching existing conventions found in `config_test.go`/`scraper_test.go`/`targetstatus_test.go` (exact file(s) to be finalized against actual existing test helpers in Step 6):
- **Under limit**: a job configured with `max_scrape_targets` greater than its discovered target count scrapes all of them; no drops registered, gauge reads `0`.
- **Over limit**: a job configured with `max_scrape_targets` less than its discovered target count ends up with exactly that many active/registered targets; the remainder are registered as dropped with `targetDropReasonTooManyTargets` and/or visible via the new `truncatedByJob`/gauge accessor.
- **Default unlimited**: a job with no `max_scrape_targets` set and the global flag at its default admits an arbitrarily large discovered target count unchanged, matching pre-existing behavior for jobs with no cap.
- Exercise at the layer(s) already testable without a live network/discovery backend — likely unit-level tests against `scraperGroup.update`/`targetStatusMap` directly (as `scraper_test.go`/`targetstatus_test.go` conventions dictate) rather than full end-to-end discovery, to keep tests deterministic and fast; final approach confirmed in Step 6 against actual existing test scaffolding.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Race between concurrent `scraperGroup.update` calls from different discovery types for the same job transiently over-admitting past the cap | Medium (inherent to the existing lock-free-across-groups architecture) | Low (self-corrects on next poll cycle; ticket explicitly frames this as a soft safety net, not a hard invariant) | Documented as expected soft-cap behavior in the flag's usage string and `sd_configs.md`; no new cross-group locking introduced (explicitly out of scope per Investigation) |
| A fully-truncated job (0 admitted, all discovered targets dropped) disappears from `/targets` page if `getEmptyJobs`/`getTargetsStatusByJob` classifies it as "empty" | Low | Medium (would hide the exact case operators most need to see) | Verify this interaction explicitly during implementation and testing; adjust `getTargetsStatusByJob`/`getEmptyJobs` if needed so a job with `truncatedCount > 0` is never treated as empty |
| `qtc`-regenerated `targetstatus.qtpl.go` diverges unexpectedly from hand-expected output (formatting/whitespace) | Low | Low | Regenerate via the documented `qtc -dir=lib` invocation (same as `make quicktemplate-gen`) rather than hand-editing; diff review before commit |
| New per-job gauge triples the metrics cardinality contribution of `registerJobsMetricsLocked` per job (up/down/truncated instead of up/down) | Low | Low (bounded by number of configured jobs, not target count — same order of magnitude as existing per-job metrics) | No mitigation needed; consistent with existing per-job metric design already in the codebase |

---

Do you approve the plan? Proceed to implementation?
