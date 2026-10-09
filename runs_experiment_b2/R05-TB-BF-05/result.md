# R05-TB-BF-05

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: False
Cost: $2.7609066
Duration: 560999ms, turns: 53

## Agent's own summary

# Change Plan

## Task Classification
**Feature** (net-new capability, additive to existing contract; not a bugfix or refactor).

## Affected Cells
| Cell | Files to Modify | What Changes |
|---|---|---|
| `lib/promscrape` | `config.go`, `targetstatus.go`, `scraper.go`, `CODEMANIFEST` | New global flag + per-job YAML override resolved onto `ScrapeWork`; atomic cross-mechanism cap check in `targetStatusMap.Register`; enforcement wiring in `scraperGroup.update()`; manifest annotations updated to document the new behavior |
| `lib/promscrape` (tests) | `config_test.go`, `scraper_test.go`, `targetstatus_test.go` | New table-driven cases per established idioms in each file |
| docs | `docs/victoriametrics/vmagent.md` (or wherever `-promscrape.seriesLimitPerTarget`/`series_limit` is documented) | Document the new flag/field per ticket's "documented way to configure" requirement |

No other cell requires modification (confirmed in Scope Resolution Report: `app/vmagent`/`app/victoria-metrics` are unaffected consumers).

## Root Cause Analysis
Not a defect — a missing safety net. `scraperGroup.update()` currently starts a scraper for every discovered target unconditionally; there is no per-job ceiling. The only existing state that aggregates active-target counts for a job across *all* discovery mechanisms is `tsmGlobal` (`targetStatusMap.upByJob`/`downByJob`), making it the sole correct integration point for a uniform, mechanism-agnostic cap.

## Trace Summary
`Init → runScraper → scrapeConfig.run (×23, one per mechanism) → scraperGroup.update(sws) → newScraper → tsmGlobal.Register(&sc.sw) → sg.wg.Go(sc.sw.run)`. The per-job resolved limit rides along on `ScrapeWork` (produced once per target in `swc.getScrapeWork()`, config.go:1364), exactly like `SeriesLimit`. Enforcement happens at the one point (`tsmGlobal.Register`) that already synchronizes state across every concurrently-running `scraperGroup`.

## Change Strategy

1. **`config.go`** — add flag and per-job override, resolve into `scrapeWorkConfig`, copy onto `ScrapeWork`:
   - New flag next to `seriesLimitPerTarget` (~line 57): `maxScrapeTargetsPerJob = flag.Int("promscrape.maxScrapeTargetsPerJob", 0, "...")`. Default `0` = unlimited.
   - New field on `ScrapeConfig` (~line 351, alongside `SeriesLimit *int`): `MaxScrapeTargets *int \`yaml:"max_scrape_targets,omitempty"\``.
   - In `getScrapeWorkConfig` (~line 1001, same pattern as `seriesLimit`): 
     ```go
     maxScrapeTargets := *maxScrapeTargetsPerJob
     if sc.MaxScrapeTargets != nil {
         maxScrapeTargets = *sc.MaxScrapeTargets
     }
     ```
     add `maxScrapeTargets` to the `scrapeWorkConfig{...}` literal.
   - New field on `scrapeWorkConfig` struct (~line 1067, next to `seriesLimit`): `maxScrapeTargets int`.
   - New exported field on `ScrapeWork` (scrapework.go, next to `SeriesLimit`): `MaxScrapeTargets int`. Copy it in the `sw := &ScrapeWork{...}` literal (config.go:1386, next to `SeriesLimit: seriesLimit`).
   - **Deviation from proposal**: `MaxScrapeTargets` must NOT be added to `ScrapeWork.key()` (scrapework.go:176-191) the way `SeriesLimit` is — including it in the key would make two otherwise-identical targets compare as different (and needlessly restart scrapers) merely because the job-wide cap changed, which is an aggregate/job-level property, not a per-target identity property. Confirmed this is safe to omit: `key()`'s own doc comment already excludes fields that aren't part of target *identity*.

2. **`targetstatus.go`** — atomic check-and-reserve plus new drop reason:
   - Change signature: `func (tsm *targetStatusMap) Register(sw *scrapeWork) bool`. Inside the existing `tsm.mu.Lock()`/`defer tsm.mu.Unlock()` block, before mutating `tsm.m`/`tsm.downByJob`: if `limit := sw.Config.MaxScrapeTargets; limit > 0 && tsm.upByJob[jobName]+tsm.downByJob[jobName] >= limit { return false }`; otherwise proceed exactly as today and `return true`.
   - Add `targetDropReasonTargetsLimit = targetDropReason("max_scrape_targets limit exceeded")` next to the four existing constants (~line 357).
   - No change needed to `Unregister`/`Update` — they operate only on targets that were successfully registered.

3. **`scraper.go`** — wire enforcement into `scraperGroup.update()` (~line 419-436):
   ```go
   for _, sw := range swsToStart {
       sc, err := newScraper(sw, sg.name, sg.pushData)
       if err != nil {
           logger.Errorf(...)
           continue
       }
       if !tsmGlobal.Register(&sc.sw) {
           sc.cancel()
           droppedTargetsMap.Register(sw.OriginalLabels, sw.RelabelConfigs, targetDropReasonTargetsLimit, nil)
           continue
       }
       sg.activeScrapers.Inc()
       sg.scrapersStarted.Inc()
       sg.wg.Go(func() {
           defer func() { close(sc.stoppedCh) }()
           sc.sw.run(sc.ctx.Done(), sg.globalStopCh)
           tsmGlobal.Unregister(&sc.sw)
           sg.activeScrapers.Dec()
           sg.scrapersStopped.Inc()
       })
       key := sw.key()
       sg.m[key] = sc
       additionsCount++
   }
   ```
   Confirmed via re-reading `newScraper` (client.go/scraper.go): `newClient` performs no goroutine spawn tied to `ctx` at creation time (only stores config for later per-request use), so `sc.cancel()` is not required to prevent a leak — but it is still correct defensive hygiene (releases the `context.WithCancel` resources immediately rather than leaving them to GC) and costs nothing, so it stays in the plan.
   - Rejected target is intentionally **not** added to `sg.m`, so the next poll cycle re-evaluates it fresh (consistent with existing sharding/relabeling drop semantics, which are also re-decided every poll).

4. **CODEMANIFEST** (`lib/promscrape/CODEMANIFEST`):
   - Extend `Init`'s algorithm step 3 to mention: "targets beyond a job's configured `max_scrape_targets` cap (global `-promscrape.maxScrapeTargetsPerJob` flag, overridable per job) are not started; they are tracked as dropped targets, visible on `/service-discovery` and via the per-job counts on `/targets`."
   - Extend `ScrapeWork` annotation to mention the new `MaxScrapeTargets` resolved field, consistent with how `SeriesLimit`/`metricRelabelConfigs` are already documented.
   - Extend `ScrapeConfig` annotation to mention `MaxScrapeTargets` alongside its existing per-job-override description.
   - No new type is declared — this is a documented extension of `Init`, `ScrapeWork`, `ScrapeConfig`, consistent with `goga-cookbook`'s guidance not to fragment one behavior across artificial new types.

5. **Docs** — add `-promscrape.maxScrapeTargetsPerJob` / `max_scrape_targets` next to the existing `series_limit` documentation, per ticket's explicit "documented way to configure" requirement.

## Specification Impact
- `Init` routine annotation (algorithm step 3): extended, not replaced — additive clause.
- `ScrapeWork` entity annotation: additive clause documenting the new resolved field, mirroring existing `SeriesLimit` documentation style.
- `ScrapeConfig` entity annotation: additive clause documenting the new per-job override field.
- No signature of any CODEMANIFEST-declared routine/method changes (no argument or return-type changes to `Init`, `CheckConfig`, `WriteServiceDiscovery`, etc.) — purely internal/behavioral extension plus one new documented struct field on two already-documented types.

## Usage Impact
No `.usages/*.md` files exist under `lib/promscrape/` today referencing `ScrapeWork`/`ScrapeConfig` construction details that would go stale — the cell's only usages are the header-level `registry_dispatch` inline usage, which describes the discovery-provider dispatch pattern and remains accurate (no provider package changes). No usage file edits required.

## Compatibility Verification
**Backward compatible.** Default flag value `0` reproduces today's unconditional-start behavior exactly (`limit > 0` guard is false). `targetStatusMap.Register`'s new `bool` return is additive — the sole existing caller in test code (`targetstatus_test.go:14`) already discards the return value, which Go permits. No public function signature used by `app/vmagent`/`app/victoria-metrics` changes.

## Test Strategy
- `config_test.go` (extend `TestScrapeConfigUnmarshalMarshal`-style / the `f(data, expectedScrapeWorks)` helper used for `series_limit`, ~line 1448-1470): add a case setting `*maxScrapeTargetsPerJob` and/or `max_scrape_targets: N` per job, asserting the resolved `ScrapeWork.MaxScrapeTargets` value — covers **default unlimited** and **per-job override resolution**.
- `scraper_test.go` (new test, sibling to `TestScraperReload`, using the same `newScraperGroup`/`sg.update(sws)` harness): 
  - Case A — job under the limit: N targets, cap > N → `len(sg.m) == N`, no new dropped-target entries.
  - Case B — job over the limit: N targets, cap < N → `len(sg.m) == cap`, and `droppedTargetsMap` (a fresh instance or `getTotalTargets()`/`getTargetsList()` filtered by `targetDropReasonTargetsLimit`) shows exactly `N - cap` entries for that job — this is the "visible in status output" assertion.
  - Case C — default/unlimited (cap `0`): N targets → all N started, matching today's behavior exactly (regression guard).
- `targetstatus_test.go`: extend/add a `TestRegisterRespectsMaxScrapeTargets`-style unit test calling `tsm.Register` directly (mirroring `TestWriteActiveTargetsJSON`'s literal `&scrapeWork{Config: &ScrapeWork{...}}` construction) to unit-test the boolean-return/limit logic in isolation from the scraper-goroutine machinery.

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Thrashing: which targets get excluded may vary poll-to-poll (Go map iteration order) when a job is persistently over its cap | Medium | Low | Matches existing, accepted behavior for sharding/relabeling drops; ticket does not require deterministic selection, only that the count is capped and visible |
| Test flakiness from `sg.update()` starting real scraper goroutines (`sc.sw.run`) against fake addresses | Low | Low | Existing `TestScraperReload` already does this safely; `sg.stop()`/`defer close(globalStopChan)` pattern reused verbatim |
| Forgetting to update `docs/` leaves the feature technically "undocumented" per ticket wording | Medium | Medium | Explicit doc step included in plan; flag's own `flag.Int` usage string plus YAML comment also self-documents via `--help` and CHANGELOG conventions |

---

Do you approve the plan? Proceed to implementation?
