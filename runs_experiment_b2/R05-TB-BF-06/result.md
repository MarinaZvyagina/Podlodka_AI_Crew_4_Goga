# R05-TB-BF-06

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: False
Cost: $2.7829778999999992
Duration: 431788ms, turns: 54

## Agent's own summary

# Change Plan

## Task Classification
**Feature** (additive, default-off safety-net capability)

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| lib/promscrape | config.go, scrapework.go, targetstatus.go, scraper.go, CODEMANIFEST | New global flag + per-job YAML field, admission-control truncation in the shared scraper-start funnel, new drop reason for visibility |
| (docs, non-cell) | docs/victoriametrics/sd_configs.md, docs/victoriametrics/vmagent.md | Prose documentation of the new `max_scrape_targets` option |

app/vmagent: **no files modified** — confirmed in Investigation (flags self-register via the `flag` package; status endpoints already call the unchanged-signature `WriteServiceDiscovery`/`WriteAPIV1Targets`/`WriteHumanReadableTargetsStatus`).

## Root Cause Analysis
Not a defect — a missing safety net. Today `scraperGroup.update` (scraper.go) admits every `*ScrapeWork` a discovery backend produces with no ceiling, so a misbehaving SD source (over-broad query, dropped tag filter) can make vmagent start scraping an unbounded number of targets for one job, starving CPU/memory for every other job on the instance. Investigation confirmed `scraperGroup.update` is the single, backend-agnostic point every SD mechanism's output passes through, and `tsmGlobal.upByJob`/`downByJob` (targetstatus.go) already aggregate active-target counts per job across all backends — both are ready-made for enforcing and reporting a cap without duplicating logic per SD type.

## Trace Summary
`runScraper` → per-discovery-type `scrapeConfig.run` (own goroutine/ticker) → `cfg.getXxxSDScrapeWork(prev)` → `sg.update(sws)` (scraper.go:372) → dedupe/diff → stop removed → **[new: `limitScrapeWorksByJob`]** → start `swsToStart` via `newScraper` + `tsmGlobal.Register`. Config resolution path: `parseData` → `getScrapeWorkConfig` (global-default-vs-per-job resolution, mirrors `MaxScrapeSize`/`SampleLimit`) → `sc.swc` → `swc.getScrapeWork` constructs each `*ScrapeWork` with the resolved limit attached.

## Change Strategy

1. **config.go** — add flag `maxScrapeTargetsPerJob` (default `0`, unlimited), `ScrapeConfig.MaxScrapeTargets` YAML field, resolve global-vs-per-job in `getScrapeWorkConfig`, thread through `scrapeWorkConfig.maxScrapeTargets` → `ScrapeWork.MaxScrapeTargets` in `swc.getScrapeWork`. Exactly mirrors the existing `MaxScrapeSize` plumbing — no new pattern introduced.
2. **scrapework.go** — add `ScrapeWork.MaxScrapeTargets int` field with a doc comment. Deliberately excluded from `key()`: confirmed by `TestScraperReload` that whole-job restarts already happen via `mustRestart`/`areEqualScrapeConfigs` on any config change, and the field has no effect on an already-admitted target's scrape behavior.
3. **targetstatus.go** — add `targetDropReasonTargetsLimit` constant (same shape as `targetDropReasonSharding`); add `activeTargetsCountByJob(jobName string) int` reusing `upByJob`+`downByJob` under the existing `tsm.mu` lock — no new state, no new lock.
4. **scraper.go** — add `limitScrapeWorksByJob`, reusing the existing `getSWSByJob` grouping helper from config.go. For each job with a positive effective limit, compute remaining budget against `tsmGlobal.activeTargetsCountByJob`, keep a deterministic (URL-sorted) prefix, register the remainder into the existing `droppedTargetsMap` with the new reason. Wire into `scraperGroup.update` after deletions settle, before new scrapers start — same lock ordering (`sg.mLock` → `tsmGlobal.mu`) already used one line later at the existing `tsmGlobal.Register` call, so no new deadlock surface.
5. **CODEMANIFEST** — update `ScrapeConfig`, `ScrapeWork`, `Init`, `WriteServiceDiscovery`, `WriteAPIV1Targets` annotations to describe the new field/behavior and where it surfaces.
6. **Tests** — extend `scraper_test.go` (or a new `_test.go` in the same package) using the `newScraperGroup`/`sg.update` harness from `TestScraperReload`, and `targetstatus_test.go`'s `newTargetStatusMap`/`droppedTargets` harness, for: under-limit (no-op), over-limit (truncated + visible), default-unlimited (no-op, explicit 0/unset).
7. **Docs** — add a `max_scrape_targets` block to `sd_configs.md` mirroring `sample_limit`.

## Specification Impact
- `ScrapeConfig` type annotation (config.go): add one line documenting `max_scrape_targets` (per-job override) and its relationship to the new global flag default.
- `ScrapeWork` type annotation (scrapework.go): add one line noting the resolved effective limit is carried per target for admission-control purposes only (not scrape behavior).
- `Init` algorithm (scraper.go): step 3 gains a clause — "...diff the newly discovered `ScrapeWork` set against the previous one, apply the configured per-job target cap (if any) by dropping excess newly-added targets, and start/stop individual target scrapers accordingly."
- `WriteServiceDiscovery` / `WriteAPIV1Targets` annotations (targetstatus.go): add a line noting targets dropped due to the per-job cap appear alongside other drop reasons (relabeling, sharding, duplicate) via the existing dropped-targets mechanism.

No section is removed or contradicted; all additions are strictly additive prose.

## Usage Impact
`registry_dispatch` (lib/promscrape's only declared Usage) describes the per-SD-backend dispatch registry and remains 100% accurate — the new logic sits downstream of that dispatch, in the shared consumer (`scraperGroup.update`), not in the registry itself. **No usage file edits required.** No cell imports this cell's usages in a way that references target-count behavior, so no consumer usage files need updates either.

## Compatibility Verification
**Backward compatible.** With the new flag at its default (`0`) and the new YAML field unset (`omitempty`), `getScrapeWorkConfig` resolves the effective limit to `0`, and `limitScrapeWorksByJob` treats `0` as unlimited and returns its input unchanged — byte-for-byte the same code path and behavior as before this change for every existing deployment. Verified against all 6 Breaking Change Policy questions in the Investigation Report: all NO.

## Test Strategy
Using existing harness patterns (`newScraperGroup`+`sg.update` from `TestScraperReload`; `newTargetStatusMap`/`droppedTargets{m: map[...]}` from `targetstatus_test.go`):
1. **Under limit** — job configured with `max_scrape_targets: 10`, discovery returns 5 targets → all 5 start, `droppedTargetsMap` gains zero entries with the new reason.
2. **Over limit** — job configured with `max_scrape_targets: 3`, discovery returns 10 targets → exactly 3 scrapers start (deterministic via URL sort), the other 7 appear in `droppedTargetsMap` with `targetDropReasonTargetsLimit`, and `tsmGlobal.activeTargetsCountByJob(job) == 3`.
3. **Default unlimited** — flag unset and YAML field unset, discovery returns a large target count (e.g. 500) → all start, no drops, matching pre-change behavior exactly (regression guard).
4. Optionally: two jobs in the same config, one over/one under, to confirm the cap is scoped per-job and doesn't cross-contaminate.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Concurrent `scraperGroup.update` calls for different discovery types serving the *same* job race on the admission check (TOCTOU on `tsmGlobal.activeTargetsCountByJob`), causing a small transient overshoot above the configured cap | Low (most jobs use one SD mechanism; only matters when a job mixes e.g. `static_configs` + `kubernetes_sd_configs` and both update simultaneously) | Low — bounded overshoot self-corrects on the next poll of either backend, and the feature is explicitly a best-effort safety net, not a hard multi-tenant guarantee | Document in the flag help text and CODEMANIFEST annotation that enforcement is best-effort across concurrently-polling discovery mechanisms for the same job |
| Lowering the limit via config reload doesn't retroactively stop already-running scrapers above the new limit | Medium (plausible operator action) | Low — matches existing precedent (`sample_limit`/`series_limit` also apply prospectively, not retroactively); next natural churn (target restart, discovery diff) will re-apply the cap | Document explicitly in flag help text: "does not retroactively stop already-running scrapers when the limit is lowered" |
| Adding a field to `ScrapeConfig`/`ScrapeWork` breaks strict YAML unmarshaling for configs that already use an unrelated field named `max_scrape_targets` | Very low | Low | `omitempty` + strict-mode unmarshal already covers this identically to every other optional field in the struct; no special handling needed |

---

**Do you approve the plan? Proceed to implementation?**
