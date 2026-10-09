# R05-TB-BF-09

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: False
Cost: $3.1474979999999997
Duration: 595044ms, turns: 58

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add a per-`job_name` cap on active scrape targets, enforced uniformly across every service-discovery mechanism and `static_configs`, with a global default (off) plus per-job override, visible via existing target-status surfaces, for both vmagent and the single-node binary (they share `lib/promscrape`).

## Candidate Cells
| Cell | Reason | Priority |
|---|---|---|
| `lib/promscrape` | Owns `ScrapeConfig`, `ScrapeWork`, the scraper-group start/stop loop, and all `WriteXxxTargets*` status endpoints — the only cell where "job" and "active target count" are both known | High |
| `lib/promscrape/discovery/kubernetes` | Registry-dispatch exemplar; only contributes `SDConfig`/labels, never touches target counts or job-level caps | — (excluded) |
| `app/vmagent` | Consumes `lib/promscrape.Init`/`Stop` as a black box; no behavioral participation in target counting | — (excluded) |
| `app/victoria-metrics` (single-node) | Also composes `lib/promscrape` as a black box; benefits automatically since the cap lives in the shared cell | — (excluded, confirms requirement #4 is satisfied for free) |

## Included Dependencies
| Cell | Behavioral Relevance |
|---|---|
| `lib/promscrape` (self) | All enforcement, config parsing, and status rendering logic lives here |

## Excluded Dependencies
| Cell | Exclusion Reason |
|---|---|
| `lib/promscrape/discovery/*` (all ~22 providers) | Per `registry_dispatch`, every provider only supplies `GetLabels`/labels; the uniform choke point required by the ticket is `scraperGroup.update()` in `lib/promscrape/scraper.go`, common to every provider. Touching per-provider code would violate "uniform, not duplicated per-provider" and would be over-scoping. |
| `lib/promrelabel` | Only supplies `ParsedConfigs` used unchanged; no participation in count enforcement |
| `app/vmagent`, `app/victoria-metrics` | Black-box consumers of `Init`/`Stop`; no source change needed |

## Usage Relationships
| Usage | Relevance |
|---|---|
| `registry_dispatch` (inline usage in `lib/promscrape/CODEMANIFEST`) | Confirms all ~22 SD types + `static_configs` funnel through the same `scraperGroup`/`scrapeConfig` machinery in `scraper.go` — this is the evidence that a single choke point exists and is sufficient |

## Semantic Participation Summary
Only `lib/promscrape` participates behaviorally. `ScrapeConfig`/`scrapeWorkConfig` (config.go) must carry the resolved per-job limit; `scraperGroup.update()` (scraper.go) is the single point where every discovery type's newly-discovered targets are turned into running scrapers, so it is the only correct enforcement point; `targetStatusMap`/`droppedTargets` (targetstatus.go) already own per-job active/dropped accounting and all four status surfaces (`/targets`, `/service-discovery`, `/api/v1/targets`, `/metrics` via `vm_promscrape_scrape_pool_targets`), so extending them (not adding a parallel mechanism) satisfies the visibility requirement with minimal new surface.

## Final Investigation Scope
- `lib/promscrape/config.go`
- `lib/promscrape/scraper.go`
- `lib/promscrape/targetstatus.go`
- `lib/promscrape/CODEMANIFEST` (reconciliation only)
- Docs: `docs/victoriametrics/sd_configs.md`, `docs/victoriametrics/vmagent.md`, generated flag-list docs

## Scope Risks
- **Under-scoping risk**: if the check were placed inside `getScrapeWorkGeneric`/`appendScrapeWorkForTargetLabels` (per-SD-type code) instead of `scraperGroup.update()`, a job split across `static_configs` + `kubernetes_sd_configs` could exceed the cap because each SD type would only see its own slice of targets. Mitigated by anchoring enforcement in the shared `scraperGroup.update()`/`targetStatusMap.Register` path, which every SD type and `static_configs` already funnel through.
- **Over-scoping risk**: touching `ScrapeWork`'s `key()`/struct fields is unnecessary — the limit is a job-wide property, not a per-target scrape parameter — avoided by keeping the limit in `scrapeWorkConfig` (job-level) and `targetStatusMap` (global job accounting) only.

## Notes
No other cell's CODEMANIFEST needs modification; `ScrapeConfig`'s existing signature in the manifest is already a representative subset ("Use `SDConfig` from Imports as the representative shape... `registry_dispatch` lists the rest by name"), so adding one more optional field does not require a signature rewrite — only an annotation note.

---

# Investigation Report (condensed)

**Root cause / gap**: nothing currently limits how many `ScrapeWork` units per `job_name` actually get promoted to running scrapers. Discovery-side over-reporting (bad tag filter, too-broad catalog query) flows straight through `cfg.getXxxSDScrapeWork()` → `scraperGroup.update()` → `tsmGlobal.Register()` → goroutine-per-target, unbounded.

**Key trace**: `scraper.go:130-153` registers one `scrapeConfig`/`scraperGroup` per SD type (including `static_configs`), each independently polling `cfg.getXxxSDScrapeWork(swsPrev)` and calling `sg.update(sws)`. `scraperGroup.update()` (`scraper.go:372-446`) is the **only** place common to all of them where a new target is actually registered (`tsmGlobal.Register`, `scraper.go:427`) and a goroutine started. `targetStatusMap` (`targetstatus.go:94-184`) already tracks `upByJob`/`downByJob` per `jobNameOriginal` — a live, global, cross-SD-type count — which is exactly what's needed to gate admission. `droppedTargetsMap` (`targetstatus.go:336-432`) already renders "target discovered but not scraped, with a reason" on `/service-discovery`, `/targets`, and `/api/v1/targets`; it currently has reasons `relabeling`, `missing scrape URL`, `duplicate`, `sharding` — adding `target limit` is a same-shape extension, not a new mechanism.

**Confidence**: HIGH. No breaking change detected (see Compatibility Report below).

---

# Change Plan

## Task Classification
Feature (extension) — additive safety-net capability, default-off.

## Affected Cells
| Cell | Files to Modify | What Changes |
|---|---|---|
| `lib/promscrape` | `config.go` | New flag `-promscrape.maxScrapeTargetsPerJob` (default 0/unlimited); new `ScrapeConfig.MaxScrapeTargets` YAML field (per-job override); resolved into `scrapeWorkConfig.maxScrapeTargets`; new `Config.getMaxTargetsByJob()` helper |
| `lib/promscrape` | `targetstatus.go` | `targetStatusMap` gains `maxTargetsByJob` (config) + `truncatedByGroup` (live per-group-per-job truncation counts); `Register` becomes capacity-aware and returns `bool`; new `targetDropReasonTargetsLimit`; new per-job gauge `vm_promscrape_scrape_pool_targets{scrape_job=...,status="truncated"}` |
| `lib/promscrape` | `scraper.go` | `scraperGroup.update()`: track job of each unique discovered target; when starting a new scraper, honor `Register`'s admission decision; on rejection, record it in `droppedTargetsMap` (reason `target limit`) and in the live per-job truncated-count gauge |
| `lib/promscrape` | `CODEMANIFEST` | Annotate `Init`, `ScrapeConfig`, `WriteHumanReadableTargetsStatus`, `WriteServiceDiscovery`, `WriteAPIV1Targets` with the new capability; no signature changes |
| docs | `sd_configs.md`, `vmagent.md`, generated flag docs | Document `max_scrape_targets` YAML field, `-promscrape.maxScrapeTargetsPerJob` flag, and the status-page visibility |

## Root Cause Analysis
See Investigation Report above.

## Trace Summary
`cfg.getXxxSDScrapeWork` / `cfg.getStaticScrapeWork` (per SD type, config.go) → `scrapeConfig.run` (scraper.go) → `scraperGroup.update` (scraper.go, **single choke point**) → `tsmGlobal.Register` (targetstatus.go, **enforcement gate**) → goroutine started or target dropped into `droppedTargetsMap`.

## Change Strategy
1. `config.go`: add flag + YAML field + `scrapeWorkConfig.maxScrapeTargets` resolution (mirrors existing `seriesLimitPerTarget`/`SeriesLimit` global+override pattern) + `Config.getMaxTargetsByJob()`.
2. `targetstatus.go`: add `maxTargetsByJob`/`truncatedByGroup` fields to `targetStatusMap`; extend `registerJobNames` to accept the limits map (called from `config.go`'s two existing `tsmGlobal.registerJobNames(...)` call sites); change `Register(sw *scrapeWork) bool` to reject when `upByJob+downByJob >= limit`; add `setTruncatedCount`/`truncatedCountByJob`; add `targetDropReasonTargetsLimit`; extend `registerJobsMetricsLocked` with a third `status="truncated"` gauge (register + unregister paths).
3. `scraper.go`: in `scraperGroup.update`, record each unique discovered target's job while deduping; when admitting `swsToStart`, call `tsmGlobal.Register`; on `false`, register into `droppedTargetsMap` with `targetDropReasonTargetsLimit` and count it; after the loop, call `tsmGlobal.setTruncatedCount(sg.name, job, n)` for every job seen this cycle (so resolved truncation clears itself).
4. Reconcile `CODEMANIFEST` annotations only (no signature change).
5. Update docs.

## Specification Impact
- `Init(pushData)` annotation: algorithm step 3 ("start/stop individual per-target scrapers") gains a clause: target admission is capped per job via the resolved limit; excess targets are recorded as dropped rather than scraped.
- `ScrapeConfig` annotation: note the optional `max_scrape_targets` field and its fallback to the global flag.
- `WriteHumanReadableTargetsStatus` / `WriteServiceDiscovery` / `WriteAPIV1Targets` annotations: note that truncated-due-to-limit targets appear as dropped targets with reason `target limit`, and that `/metrics` exposes a per-job truncated gauge.

## Usage Impact
No `.usages/*.md` files exist under `lib/promscrape` today (`find` returned none besides the kubernetes discovery CODEMANIFEST). None are required: this is a same-shape extension of an existing, already-documented mechanism (`droppedTargetsMap` reasons, `vm_promscrape_scrape_pool_targets` gauge family), not a new consumer-facing pattern that needs a how-to-consume recipe.

## Compatibility Verification
Backward compatible. See Compatibility Report.

## Test Strategy
- `scraper_test.go`: extend/add a test using `newScraperGroup`+`sg.update` (existing pattern in `TestScraperReload`) with `static_configs` targets and a `max_scrape_targets` override: (a) job under limit → all targets active, 0 truncated; (b) job over limit → only N active, remainder visible via `droppedTargetsMap`/truncated count; (c) default (flag unset, no override) → unlimited, all targets active. Use unique random job names per subtest to avoid cross-test global-state interference (existing tests already do this for group names).
- `config_test.go`: verify `max_scrape_targets` YAML field resolves into `scrapeWorkConfig.maxScrapeTargets`, with global-flag fallback, mirroring the existing `seriesLimitPerTarget` test.

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Race between concurrent `scraperGroup`s (different SD types) both admitting targets for the same job | Medium | Low (soft cap could be exceeded by a handful) | `Register` performs the check-and-insert under `tsm.mu` in one critical section, so admission is atomically serialized across all groups |
| Truncated-count gauge goes stale if a job's excess targets stop being discovered entirely | Low | Low | Truncated count is recomputed (not incremented) every `update()` cycle per `(group, job)`; a job/group pair not seen this cycle is not touched, but any job still being discovered self-corrects to 0 once under budget — same staleness characteristic already accepted for `droppedTargetsMap`'s other reasons |
| Existing callers of `targetStatusMap.Register` break due to signature change (`void` → `bool`) | None | — | Single call site in the whole repo (`scraper.go:427`), confirmed by grep |

---

# Compatibility Report

## Checklist Results

### API Compatibility
| Question | Answer | Evidence |
|---|---|---|
| Function signature unchanged for existing callers? | YES | Only exported functions (`Init`, `WriteHumanReadableTargetsStatus`, `WriteServiceDiscovery`, `WriteAPIV1Targets`, `CheckConfig`, `WriteConfigData`) keep identical signatures. `targetStatusMap.Register` changes signature but is unexported with exactly one call site (`scraper.go:427`), updated in the same change. |
| Return type unchanged? | YES | No exported function's return type changes |
| Default parameter values preserved? | YES | New flag defaults to `0` = unlimited; new YAML field defaults to unset = falls back to global flag = unlimited |

### Semantic Compatibility
| Question | Answer | Evidence |
|---|---|---|
| Same arguments produce same behavior? | YES | With the flag at its default (`0`) and no `max_scrape_targets` override, `Register` always admits (limit check is `limit > 0 && ...`), so behavior for every existing config is byte-for-byte identical |
| Output format unchanged? | YES | JSON/HTML/plain-text schemas gain data (new gauge, new drop reason string, one more entry in existing arrays) but no field is renamed, removed, or retyped |
| File paths unchanged? | YES | No endpoint paths change |
| Error messages and codes unchanged? | YES | No existing error paths modified |

### Algorithmic Compatibility
| Question | Answer | Evidence |
|---|---|---|
| Manifest-defined algorithm steps preserved? | YES | `Init`'s documented 4-step algorithm (load config → start SD groups → diff/start-stop → scrape+push) is unchanged; the cap is an additional admission check inside step 3, not a reordering |
| Execution order unchanged? | YES | Deletions still happen before starts (unchanged); the only reordering is that `tsmGlobal.Register` now gates `sg.activeScrapers.Inc()`/goroutine start, which previously always happened — this only affects the *new*, previously-nonexistent, over-limit case |
| Side effects unchanged? | YES for default config | For any job under/without a limit, side effects (goroutine per target, metrics, log lines) are identical |

### Consumer Compatibility
| Question | Answer | Evidence |
|---|---|---|
| Existing tests pass without modification? | YES | `TestScraperReload` (scraper_test.go) never sets `max_scrape_targets` and stays under any default; `config_test.go` expected `ScrapeWork` structs are unaffected since the limit is not a `ScrapeWork` field |
| Usage recipes remain valid? | YES | No `.usages/*.md` exist for this cell; nothing to invalidate |
| Downstream consumers unaffected? | YES | `app/vmagent`, `app/victoria-metrics` call only `Init`/`Stop`/`CheckConfig`/`WriteConfigData`/the `WriteXxx` status functions — all signature-stable |

## Verdict
**COMPATIBLE**

## Breaking Change Details
None.

---

Given the plan is fully backward-compatible (default-off, additive), I'd like to proceed straight to implementation, testing, and manifest reconciliation unless you want to adjust the design first — in particular the choice to:
1. expose the per-job override as `max_scrape_targets` in `scrape_config` (mirroring `series_limit`/`sample_limit`), and
2. surface truncation via a reused `droppedTargetsMap` reason (`target limit`) *plus* a new `vm_promscrape_scrape_pool_targets{status="truncated"}` gauge per job.

Let me know if that matches your intent, or if you'd like a different config surface/visibility mechanism — otherwise I'll continue with implementation now.
