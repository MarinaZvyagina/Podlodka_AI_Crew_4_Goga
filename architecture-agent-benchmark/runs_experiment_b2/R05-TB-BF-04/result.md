# R05-TB-BF-04

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: True
Cost: $2.5974216
Duration: 488501ms, turns: 50

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add an operator-configurable cap on the number of scrape targets a single `job_name` may have actively running at once in `lib/promscrape`, enforced uniformly regardless of which service-discovery mechanism produced the targets, off by default, with excluded targets visible through the existing target-status reporting surfaces. This is a maintenance change to the existing `lib/promscrape` cell's contract (a new field on the exported `ScrapeWork` type plus new internal enforcement logic), not a new cell.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `lib/promscrape` | Owns `ScrapeConfig`/`ScrapeWork`, the registry-dispatch SD driver, the scraper-group lifecycle, and the target-status/dropped-targets reporting — every piece of the requested behavior lives here | High |
| `app/vmagent` | Consumer of `lib/promscrape.Init`; ticket explicitly names it as the primary target of the protection | Medium (verify-only) |
| `app/vminsert` (single-node binary's scrape path) | Also calls `lib/promscrape.Init`/`Stop` directly; ticket requires the cap to work for the single-node binary too | Medium (verify-only) |
| `app/vmselect` | Only wires debug endpoints (`/metric-relabel-debug`, `/target-relabel-debug`) into `lib/promscrape`; no target lifecycle involvement | Low (exclude) |
| `lib/promrelabel` | Supplies `ParsedConfigs` used inside `ScrapeWork`/dropped-target registration, already an existing dependency, unchanged by this task | Low |
| `lib/promscrape/discovery/kubernetes` (and 21 sibling discovery packages) | Supply raw target labels via the registry-dispatch pattern; the whole point of the fix is that none of them need to know about the cap | Low (exclude, confirms uniformity) |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| `lib/promrelabel` | `ParsedConfigs` type is passed unchanged into `droppedTargetsMap.Register(...)` for the new drop reason, exactly as it already is for `targetDropReasonSharding`/`targetDropReasonRelabeling`. No contract change needed on this cell. |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `app/vmselect` | Only forwards two unrelated debug endpoints into `lib/promscrape`; no participation in target discovery, scraping, or the new limit |
| `lib/promscrape/discovery/*` (all 22 provider packages) | Confirmed via `registry_dispatch` in the CODEMANIFEST and via grep that none contain target-count logic; they only implement `GetLabels`/`MustStart`. The cap must NOT be implemented per-provider — that would violate the "uniform regardless of discovery mechanism" requirement. Grepped `app/vmagent`, `app/victoria-metrics`, `app/vmselect`, `app/vminsert`, `app/vmstorage` for existing `maxScrapeTarget`/`targetsPerJob`/target-limit logic — none found, so no duplicate mechanism to reconcile with |
| `lib/storage`, `lib/mergeset`, `app/vmstorage` | No behavioral, data-flow, or manifest relationship to scrape-target discovery or lifecycle |

## Usage Relationships

| Usage | Relevance |
|---|---|
| None declared in `lib/promscrape/CODEMANIFEST` `Usages` section | The manifest currently has no `Usages` block to extend; new behavior will be captured via updated `annotations` on the `ScrapeWork` entity and possibly the `Init` routine, per DSL conventions (no new practice file is warranted for an internal safety-limit tweak) |

## Semantic Participation Summary
All requested behavior is realized entirely inside `lib/promscrape`:
- **Config resolution** (`config.go`): new global flag + per-`job_name` YAML override, resolved into `scrapeWorkConfig` and baked into every `ScrapeWork` via the single shared `getScrapeWork()` constructor that all 22+ discovery backends already route through — this is what gives the cap its "uniform regardless of discovery mechanism" property for free, without touching any discovery provider.
- **Enforcement** (`scraper.go`): `scraperGroup.update()` is the sole place where a discovered target becomes an active running scraper goroutine, and it already funnels through the shared `tsmGlobal` registry that aggregates active-target counts per job across every independently-polling discovery type. This is the only point in the codebase where "total active targets for job X, regardless of source" is knowable, making it the correct enforcement point.
- **Visibility** (`targetstatus.go`): the existing `droppedTargetsMap` + per-job `(active/total)` accounting already power `/targets`, `/service-discovery`, and `/api/v1/targets?state=dropped` for every other drop reason (relabeling, missing URL, duplicate, cluster sharding); adding one more `targetDropReason` constant reuses this without any template changes.
- `app/vmagent` and the single-node binary (via `app/vminsert`) require zero code changes — they inherit the behavior automatically because both call the unmodified `lib/promscrape.Init` entry point.

## Final Investigation Scope
- `lib/promscrape/config.go`
- `lib/promscrape/scrapework.go`
- `lib/promscrape/scraper.go`
- `lib/promscrape/targetstatus.go`
- `lib/promscrape/CODEMANIFEST`
- Associated `*_test.go` files in `lib/promscrape`
- Documentation: `docs/victoriametrics/sd_configs.md`, `docs/victoriametrics/vmagent.md`, `docs/victoriametrics/changelog/CHANGELOG.md` (doc-only, outside CODEMANIFEST contract scope but required by the ticket)

## Scope Risks
- **Under-scoping risk**: if the enforcement point were placed inside an individual discovery provider (e.g. only `kubernetes`) instead of the shared `getScrapeWork()`/`scraperGroup.update()` choke points, the cap would silently fail to apply uniformly — mitigated by keeping scope centered on `lib/promscrape`'s shared driver code, not any `discovery/*` package.
- **Over-scoping risk**: touching `app/vmagent` or `app/victoria-metrics` main.go directly would be unnecessary surface area since neither owns scrape-lifecycle logic; grep confirmed no duplicate mechanism exists there, so those cells are correctly excluded from the implementation scope (verification-only).
- **Boundary risk**: `lib/promrelabel`'s `ParsedConfigs` type is reused as-is (already an existing cross-cell dependency in the manifest); no new Import needs to be declared.

## Notes
- `goga schema` (already executed earlier in this session) confirms `lib/promscrape` is a documented cell with an existing CODEMANIFEST declaring `ScrapeWork`, `ScrapeConfig`, `Init`, and the `registry_dispatch` usage describing the exact registry-dispatch pattern this design relies on.
- No new cell, no new Import edges, and no new cross-cell contract are required — this is a pure in-cell extension (new struct field + new internal drop reason + new flag/YAML option), which keeps the change minimal per goga-cookbook's granularity guidance.
