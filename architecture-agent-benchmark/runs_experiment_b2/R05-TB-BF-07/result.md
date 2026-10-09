# R05-TB-BF-07

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: False
Cost: $3.507456
Duration: 507130ms, turns: 61

## Agent's own summary

# Change Plan

## Task Classification
Feature (extension) — new opt-in safety-net capability added to an existing cell; no removal or redefinition of existing behavior.

## Affected Cells
| Cell | Files to Modify | What Changes |
|---|---|---|
| lib/promscrape | config.go | New global flag `-promscrape.maxScrapeTargetsPerJob`; new `ScrapeConfig.MaxScrapeTargets *int` YAML field (`max_scrape_targets`); effective-value resolution in `getScrapeWorkConfig`/`scrapeWorkConfig`; propagate into `getScrapeWork()`'s `ScrapeWork` literal |
| lib/promscrape | scrapework.go | New `ScrapeWork.MaxScrapeTargets int` field (excluded from `key()` — admission-control metadata, not per-target behavior) |
| lib/promscrape | targetstatus.go | New `targetDropReasonMaxScrapeTargets` drop reason constant; `targetStatusMap.Register` becomes cap-aware (atomic check-and-register under `tsm.mu`, returns `bool`) |
| lib/promscrape | scraper.go | `scraperGroup.update()`: when `Register` rejects a target due to the cap, register it via the existing `droppedTargetsMap.Register(...)` (same pattern as the existing duplicate-target case) and cancel its context instead of starting the scraper |
| lib/promscrape | config_test.go, scraper_test.go, targetstatus_test.go | New tests (see Test Strategy) |
| docs/victoriametrics | sd_configs.md, vmagent.md | Document `max_scrape_targets` scrape_config option and new flag, mirroring the existing `series_limit`/Cardinality-limiter documentation pattern |
| docs/victoriametrics/changelog | CHANGELOG.md (current year) | Changelog entry |

No changes to app/vmagent, app/victoria-metrics, or any `lib/promscrape/discovery/*` package — both binaries consume the new flag automatically via `flag` package registration, and the cap is enforced after all discovery mechanisms converge, so no provider-specific code is touched.

## Root Cause Analysis
No admission control exists before `scraperGroup.update()` starts a new per-target scraper goroutine; every discovered target for a job is scraped unconditionally, so a discovery-side blow-up becomes an HTTP-scrape blow-up. See Investigation Report for full evidence chain.

## Trace Summary
All discovery mechanisms → per-provider `ScrapeWork` lists → `scraperGroup.update()` (scraper.go) diffs against running scrapers → `tsmGlobal.Register()` (targetstatus.go) records each newly-started target, keyed by job name **across all scraperGroups**. This is the sole cross-mechanism, race-free, per-job aggregation point in the cell, and it already has a precedented "reject + report via `droppedTargetsMap`" pattern for the duplicate-target case at the exact same call site.

## Change Strategy
1. **config.go**: Add flag `maxScrapeTargetsPerJob = flag.Int("promscrape.maxScrapeTargetsPerJob", 0, "...")`. Add `MaxScrapeTargets *int `yaml:"max_scrape_targets,omitempty"`` to `ScrapeConfig`, mirroring `SeriesLimit *int`. In `getScrapeWorkConfig`, resolve `maxScrapeTargets := *maxScrapeTargetsPerJob; if sc.MaxScrapeTargets != nil { maxScrapeTargets = *sc.MaxScrapeTargets }`, store on `scrapeWorkConfig`. In `getScrapeWork()`, set `MaxScrapeTargets: swc.maxScrapeTargets` on the constructed `*ScrapeWork`.
2. **scrapework.go**: Add `MaxScrapeTargets int` field to `ScrapeWork` (next to `SeriesLimit`), with a doc comment. Deliberately NOT added to `key()` — the cap gates admission, not per-target scrape behavior, so a config change to only this value must not force-restart already-running scrapers for that job (unrelated targets in the same job aren't affected either).
3. **targetstatus.go**: Add `targetDropReasonMaxScrapeTargets = targetDropReason("target limit")`. Change `func (tsm *targetStatusMap) Register(sw *scrapeWork) bool`: under `tsm.mu`, if `sw.Config.MaxScrapeTargets > 0` and `tsm.upByJob[jobName]+tsm.downByJob[jobName] >= sw.Config.MaxScrapeTargets`, return `false` without registering; otherwise register as today and return `true`.
4. **scraper.go**: In `scraperGroup.update()`'s start loop, after `newScraper` succeeds, check `tsmGlobal.Register(&sc.sw)`'s return value; if `false`, call `droppedTargetsMap.Register(sw.OriginalLabels, sw.RelabelConfigs, targetDropReasonMaxScrapeTargets, nil)`, `sc.cancel()`, and `continue` (do not add to `sg.m`, do not increment counters, do not start the goroutine) — this makes the truncation self-healing: on the next discovery poll, the same still-excess target is re-evaluated against the (possibly now-changed) cap.
5. **Docs**: extend `sd_configs.md`'s scrape_config option reference with `max_scrape_targets`, and add a short section to `vmagent.md` (near "Cardinality limiter"/"Scraping big number of targets") explaining the flag, the YAML override, and where truncation is visible.

## Specification Impact
`lib/promscrape/CODEMANIFEST`:
- `Init`'s annotation step 3 ("diff the newly discovered ScrapeWork set... and start/stop individual target scrapers") gets a clarifying addition: admission is now bounded by an optional per-job cap, applied uniformly regardless of discovery mechanism.
- `WriteHumanReadableTargetsStatus` and `WriteServiceDiscovery` annotations get a one-line addition noting that targets dropped due to exceeding the per-job cap appear the same way already-dropped targets do (reused mechanism, not a new one).
- `ScrapeConfig` type annotation gets a one-line addition documenting the new `max_scrape_targets` field, mirroring how `SeriesLimit`/other per-job options are already referenced there (currently the manifest documents `jobName`/`kubernetesSDConfigs` explicitly as representative fields — this addition follows the same "representative option" style already used for `SeriesLimit` elsewhere in file... actually `ScrapeConfig`'s doc doesn't enumerate every option field explicitly, so no textual change strictly required there beyond ensuring `registry_dispatch`/algorithm text stays accurate). I will add a short annotation note for discoverability.

## Usage Impact
No `.usages/` directory currently exists for `lib/promscrape` (verified — cell has none yet). This change does not introduce a new consumer-facing API shape (no new exported functions/types beyond struct fields already covered by the existing `ScrapeConfig`/`ScrapeWork` manifest entries), so per goga-cookbook's guidance ("create/update a usage file... when an external consumer requires guidance on working with the cell's API") no new `.usages` file is warranted — the change is internal admission-control logic, not a new facade entry point. I will not fabricate a usages file for it.

## Compatibility Verification
**Backward compatible.** Default flag value `0` (unlimited) and default `ScrapeConfig.MaxScrapeTargets == nil` reproduce today's unconditional-start behavior exactly. `Register`'s new `bool` return is additive in Go (existing call sites/tests that ignore it keep compiling and behaving identically). No existing file paths, output formats, or manifest-declared guarantees change.

## Test Strategy
- **config_test.go**: extend the `getScrapeWork`-equivalence table test (or add a focused test) verifying `MaxScrapeTargets` is correctly resolved from the global flag and from the per-`scrape_config` `max_scrape_targets` override, including the "override to 0 restores unlimited" case (mirroring the existing `series_limit: 0` test at line ~1450).
- **scraper_test.go**: add a `TestScraperGroupUpdate_MaxScrapeTargets` (or extend `TestScraperReload`-style helper) covering the three required scenarios:
  1. Job under the limit → all targets started, none dropped.
  2. Job over the limit → only up to the cap started (`len(sg.m) == cap`), the rest visible via `droppedTargetsMap`/`tsmGlobal` with `targetDropReasonMaxScrapeTargets`.
  3. Default (`MaxScrapeTargets == 0`, unlimited) → all targets started regardless of count.
- **targetstatus_test.go**: unit test for `targetStatusMap.Register`'s new cap-aware branch directly (bypassing scraper.go), verifying the boundary condition (`n == cap` rejects, `n < cap` accepts) and that unlimited (`MaxScrapeTargets <= 0`) always accepts.

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Job spanning multiple discovery mechanisms could transiently exceed the cap slightly less precisely than a single-mechanism job (each mechanism's `sg.update()` call is a separate, only-mutex-serialized admission check) | Low (multi-mechanism single-job configs are rare) | Low — still bounded, just not perfectly tight in that edge case | Enforcement point (`tsmGlobal`, shared mutex) still gives an accurate, race-free count at each individual admission decision; document as a soft/eventually-consistent safety net, consistent with existing dropped-target semantics |
| Repeatedly re-registering the same excluded target into `droppedTargetsMap` every poll | None — by design | N/A | `droppedTargetsMap` already dedups by content hash (existing behavior for `sharding`/`duplicate` reasons); re-registration just refreshes, doesn't accumulate |
| New `Register` signature (added return value) missed at a future call site | Low | Low (compiler would need explicit check to break; ignoring is legal Go but a new call site might genuinely need to handle rejection) | Both existing call sites (`scraper.go`, `targetstatus_test.go`) are already accounted for in this plan |

---

Do you approve the plan? Proceed to implementation?
