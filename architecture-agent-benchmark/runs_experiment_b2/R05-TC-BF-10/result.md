# R05-TC-BF-10

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: True
Cost: $2.3072499000000004
Duration: 309302ms, turns: 65

## Agent's own summary

# Change Plan

## Task Classification
**Feature (extension)** — additive integration following an established, documented registry pattern. No modification to existing behavior.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `lib/promscrape` | `config.go`, `scraper.go` | Add import, `ScalewaySDConfigs` struct field, `mustStop()` loop entry, `getScalewaySDScrapeWork` method (all in the alphabetical slot between PuppetDB and Static/Vultr); add `scs.add("scaleway_sd_configs", ...)` line in `scraper.go` (alphabetical slot between `puppetdb_sd_configs` and `vultr_sd_configs`) |
| `lib/promscrape/discovery/kubernetes` | `CODEMANIFEST` | Update `provider_registry_pattern` usage text: add `scaleway` to the enumerated sibling list, bump count from ~22 to ~23 |
| New non-cell package `lib/promscrape/discovery/scaleway` | `scaleway.go`, `api.go`, `scaleway_test.go`, `api_test.go`, `mock_server_test.go` (new files) | Implements `SDConfig`/`GetLabels`/`MustStop`/`SDCheckInterval` per the registry contract |
| `docs/victoriametrics/sd_configs.md` | new `## scaleway_sd_configs` section | Documentation, per ticket requirement, placed alphabetically between `puppetdb_sd_configs` and `static_configs` |
| `docs/victoriametrics/changelog/CHANGELOG.md` | one `FEATURE:` bullet under `## tip` | Changelog entry, matching the existing `linode_sd_configs` FEATURE entry style |

No other cell is touched.

## Root Cause Analysis
N/A (feature, not a defect). Summary: the extension point is fully generic and already proven by 22 precedents; adding Scaleway requires implementing the same `targetLabelsGetter` contract (`GetLabels`/`MustStop`) plus registering it identically to `digitalocean`/`vultr`/`linode`.

## Trace Summary
`runScraper` → `scs.add("scaleway_sd_configs", *scaleway.SDCheckInterval, cfg.getScalewaySDScrapeWork)` → `getScrapeWorkGeneric` → `scaleway.SDConfig.GetLabels(baseDir)` → `discoveryutil.Client` paginated GET against `{api_url}/instance/v1/zones/{zone}/servers?project=<id>` with `X-Auth-Token` header (set via a `linode`-style `GetAPIResponseWithReqParams` request-modifier, since `promauth.BearerToken` doesn't produce the right header scheme) → `[]*promutil.Labels` → `[]*ScrapeWork` → relabeling → scrape. Reload path: `cfg.mustStop()` calls `ScalewaySDConfigs[i].MustStop()`, releasing the cached `discoveryutil.Client` via the package-level `configMap`, exactly like every sibling provider.

## Change Strategy
1. **Create `lib/promscrape/discovery/scaleway/scaleway.go`**: package doc, `SDCheckInterval` flag (`-promscrape.scalewaySDCheckInterval`, default `30*time.Second`, matching vultr's/ovhcloud's cadence for a REST-poll provider), `SDConfig` struct (`ProjectID string` yaml:"project_id" — mandatory; `SecretKey *promauth.Secret` yaml:"secret_key" — mandatory; `Zone string` yaml:"zone,omitempty" default `fr-par-1`; `APIURL string` yaml:"api_url,omitempty" default `https://api.scaleway.com`; `Port int` yaml:"port,omitempty" default 80; inline `HTTPClientConfig`/`ProxyURL`/`ProxyClientConfig` for TLS/proxy support), `GetLabels`/`MustStop` methods, `server` JSON struct, `addServerLabels` building `__address__` + `__meta_scaleway_instance_{id,name,zone,state,commercial_type,project_id,public_ipv4,private_ipv4,tags}`.
2. **Create `lib/promscrape/discovery/scaleway/api.go`**: `configMap`/`apiConfig`/`newAPIConfig`/`getAPIConfig` (mirrors `digitalocean`/`vultr`), validates `SecretKey`/`ProjectID` are set, builds `discoveryutil.Client`, `getServers` paginating via `page`/`per_page`/`total_count` against `/instance/v1/zones/{zone}/servers`, injecting `X-Auth-Token` via a request-modifier callback passed to `GetAPIResponseWithReqParams` (linode's `regionFilterHeader` pattern).
3. **Wire into `lib/promscrape/config.go`**: import `.../discovery/scaleway`; add `ScalewaySDConfigs []scaleway.SDConfig `yaml:"scaleway_sd_configs,omitempty"`` field (alphabetical slot); add `for i := range sc.ScalewaySDConfigs { sc.ScalewaySDConfigs[i].MustStop() }` to `mustStop()`; add `getScalewaySDScrapeWork` method (alphabetical slot, mirrors `getPuppetDBSDScrapeWork`).
4. **Wire into `lib/promscrape/scraper.go`**: import `.../discovery/scaleway`; add `scs.add("scaleway_sd_configs", *scaleway.SDCheckInterval, func(cfg *Config, swsPrev []*ScrapeWork) []*ScrapeWork { return cfg.getScalewaySDScrapeWork(swsPrev) })` between the `puppetdb_sd_configs` and `vultr_sd_configs` lines.
5. **Tests**: `api_test.go` — pure-function pagination/JSON-parsing test (digitalocean-style injected `getAPIResponse func`) plus an `httptest`-backed `mock_server_test.go` + `scaleway_test.go` (vultr-style) exercising `GetLabels` end-to-end against a fake server, and a label-building unit test with a table of `server` fixtures → expected `promutil.Labels` (digitalocean/linode-style `TestEqualLabelss`).
6. **Docs**: add `## scaleway_sd_configs` section to `sd_configs.md` (config example, `__address__` explanation, full meta-label list, refresh-interval sentence) and one `FEATURE:` CHANGELOG bullet under `## tip`.
7. **Manifest reconciliation** (Step 7 of the outer pipeline, not here): update `lib/promscrape/discovery/kubernetes/CODEMANIFEST`'s `provider_registry_pattern` text.

## Specification Impact
- `lib/promscrape/CODEMANIFEST`: **no change** — `registry_dispatch` text remains accurate as-is (it already speaks generically of "~22 provider fields", which the manifest-reconciler will re-verify/bump if it treats that number as stale; otherwise left untouched since the sentence doesn't enumerate names).
- `lib/promscrape/discovery/kubernetes/CODEMANIFEST`: **`provider_registry_pattern` usage text edited** — add `scaleway` to the enumerated list, `~22` → `~23`. No signature/type/location changes; this cell's contract body (`SDConfig`, `ScrapeWorkConstructorFunc`) is untouched since kubernetes itself isn't modified.
- No new CODEMANIFEST is created for `lib/promscrape/discovery/scaleway`, consistent with all 21 other non-kubernetes sibling providers.

## Usage Impact
No `.usages/*.md` files exist for either affected cell (confirmed via `goga schema` — both report `"usages": []`). No usage-file impact. (Handled formally as a no-op in Step 8, not skipped.)

## Compatibility Verification
**Backward compatible.** All changes are additive: new optional YAML key (`scaleway_sd_configs`, `omitempty`), new struct field, new package, new doc section, new changelog bullet. No existing exported function signature, return type, file path, or manifest guarantee changes. Confirmed against the Breaking Change Assessment in the Investigation Report (all six questions answered NO).

## Test Strategy
- **Pagination/parsing**: feed synthetic multi-page JSON responses (`page`/`per_page`/`total_count`) into `getServers` via an injected response function; assert all pages are merged and no real HTTP call occurs.
- **Label building**: table-driven test over `server` fixtures (with/without public IP, with/without private IP, with/without tags) asserting the exact `__meta_scaleway_instance_*` label set, mirroring `digitalocean_test.go`/`linode_test.go` fixture style.
- **End-to-end `GetLabels`**: `httptest.Server` mock (vultr-style) returning fixed JSON, asserting `SDConfig.GetLabels` returns the expected `[]*promutil.Labels`, including the `X-Auth-Token` header being sent (assert via a handler that checks the request header, since the header-injection path is the one custom piece of this provider not already covered by a generic sibling test).
- No modification to any existing test file; no real network access anywhere.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Wrong alphabetical insertion point causes merge-style diff noise or misses the `static_configs`-is-last irregularity in `scraper.go` | Low | Low (cosmetic/review friction, no functional bug) | Insertion points already verified line-by-line against current file content in the Trace Report before writing code |
| `X-Auth-Token` header not actually applied due to using `BearerToken` instead of a custom header callback | Low (already designed around) | High (silent 401s in production) | Use the `linode`-proven `GetAPIResponseWithReqParams(path, modifyRequest)` pattern explicitly; cover with a header-assertion test |
| Scaleway API pagination shape (`page`/`per_page`/`total_count`) mismatched vs. real API in tests only, not validated against live API | Medium (no live API access per ticket constraint) | Medium (could misparse real responses) | Model fixtures on Scaleway's public API documentation shape (`servers`, `total_count`); keep parsing logic simple/tolerant (stop when `page*per_page >= total_count` or an empty page is returned) so minor shape drift degrades gracefully rather than crashing |
| Forgetting to update the kubernetes CODEMANIFEST's sibling-provider enumeration | Low | Low (doc drift only, not caught by `goga lint` since it's inline text not lint-checked structurally) | Explicit Step 7 in this pipeline handles it; scope resolver and investigator already flagged it twice |

---

Do you approve this plan? Proceed to implementation?
