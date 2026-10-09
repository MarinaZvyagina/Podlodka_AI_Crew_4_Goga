# R05-TC-BF-01

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: True
Cost: $2.5912413
Duration: 427799ms, turns: 80

## Agent's own summary

# Change Plan

## Task Classification
**Feature** (additive extension) — adding a new Prometheus-compatible service-discovery provider to `lib/promscrape`, exercising an existing, documented extension point (`registry_dispatch`). No existing behavior is modified.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `lib/promscrape/discovery/scaleway` (new) | `scaleway.go`, `api.go`, `instance.go` (new) | New package implementing `SDConfig`, `SDCheckInterval`, `GetLabels`, `MustStop` for Scaleway Instance discovery |
| `lib/promscrape` | `config.go` | Add import, `ScalewaySDConfigs` field on `ScrapeConfig`, `mustStop()` loop entry, `getScalewaySDScrapeWork` method |
| `lib/promscrape` | `scraper.go` | Add import, `scs.add("scaleway_sd_configs", *scaleway.SDCheckInterval, ...)` |
| `lib/promscrape` | `CODEMANIFEST` | Bump the approximate provider count in the `registry_dispatch` usage prose |
| docs | `docs/victoriametrics/sd_configs.md` | Add intro bullet + `## scaleway_sd_configs` section (styled after `## vultr_sd_configs`) |
| docs | `docs/victoriametrics/changelog/CHANGELOG.md` | Add `tip` FEATURE entry |

## Root Cause Analysis
No Scaleway discovery code exists anywhere in the repository (confirmed via exhaustive grep and `goga schema`). The gap is closed by adding a new sibling provider package conforming exactly to the shape already used by `vultr`, `digitalocean`, `hetzner`, `ovhcloud`, etc., and wiring it into the three fixed registration points `lib/promscrape` requires of every one-shot-poll provider.

## Trace Summary
`Init()` → `scs.add("scaleway_sd_configs", *scaleway.SDCheckInterval, …)` → periodic `Config.getScalewaySDScrapeWork(prev)` → generic `getScrapeWorkGeneric(...)` (untouched) → `scaleway.SDConfig.GetLabels(baseDir)` → Scaleway Instance API (zone-scoped, `X-Auth-Token` auth) → `[]*promutil.Labels` → `[]*ScrapeWork`. Teardown via `mustStop()` → `scaleway.SDConfig.MustStop()` → cached HTTP client released.

## Change Strategy
1. **New package `lib/promscrape/discovery/scaleway`**:
   - `scaleway.go`: `SDCheckInterval` flag (`-promscrape.scalewaySDCheckInterval`, default 30s), `SDConfig` struct (`Project` (`project_id`), `Organization` (`organization_id`), `Zone` (default `fr-par-1`), `Endpoint` (`api_url`, default `https://api.scaleway.com`), `SecretKey *promauth.Secret` (mandatory, sent as `X-Auth-Token`), `NameFilter`, `TagsFilter`, `Port` (default 80), plus standard `HTTPClientConfig`/`ProxyURL`/`ProxyClientConfig`), `GetLabels`, `MustStop`, `getInstanceLabels`.
   - `api.go`: `apiConfig` + `configMap`-cached `newAPIConfig` (validates `SecretKey`, applies zone/port/endpoint defaults, builds `discoveryutil.Client`, encodes optional filter query params).
   - `instance.go`: `Server`/`ServerIP`/`ServerIPv6` response types matching the Scaleway Instance API `GET /instance/v1/zones/{zone}/servers` shape, `getInstances` with page/per_page pagination, request-scoped `X-Auth-Token` header via `GetAPIResponseWithReqParams`.
   - Labels emitted (prefix `__meta_scaleway_instance_`): `id`, `name`, `hostname`, `zone`, `status` (API `state`), `type` (API `commercial_type`), `tags` (comma-joined), `private_ipv4`, `public_ipv4`, `public_ipv6`, `project_id`, `organization_id`. `__address__` prefers `private_ipv4:port`, falls back to `public_ipv4:port`; instances with neither are skipped (mirrors `digitalocean`'s `continue`-on-no-IP behavior).
2. **`lib/promscrape/config.go`**: add import (alphabetical, between `puppetdb` and `vultr`), `ScalewaySDConfigs []scaleway.SDConfig` field (alphabetical, between `PuppetDBSDConfigs` and `StaticConfigs`), `mustStop()` loop entry, `getScalewaySDScrapeWork` method calling `getScrapeWorkGeneric(..., "scaleway_sd_config", prev)`.
3. **`lib/promscrape/scraper.go`**: add import + one `scs.add(...)` line (alphabetical position, same pattern as every sibling).
4. **`lib/promscrape/CODEMANIFEST`**: bump `~22 provider fields` → `~23 provider fields` in the `registry_dispatch` usage text (only textual drift fix; algorithm description itself is unchanged).
5. **Docs**: mirror the `vultr_sd_configs` section verbatim in structure (config example, address rule, meta-label list, refresh-interval note), add intro-list bullet.
6. **Changelog**: one `FEATURE` bullet under `tip`, referencing `vmagent`.

## Specification Impact
Only `lib/promscrape/CODEMANIFEST`'s `registry_dispatch` **Usages** text changes (one word: provider count `~22` → `~23`). No type signature, algorithm annotation, or `Imports`/body section changes — the manifest's `Init`/`Stop`/`RequestHandler` contracts already generically cover "every configured discovery-provider type" and require no edit.

## Usage Impact
No `.usages/*.md` files exist for `lib/promscrape` or any discovery sibling package (confirmed via `goga schema` — only `kubernetes` carries a CODEMANIFEST, and it has no `.usages` either per the schema dump). No usage-recipe files require updates. The only "usage impact" is the inline `registry_dispatch` usage text noted above.

## Compatibility Verification
**Backward compatible.** All changes are additive: new package, new struct field (appended, `omitempty`), new methods, new loop/dispatch entries appended after existing ones, one non-semantic word change in manifest prose. No existing function signature, file path, output format, or manifest guarantee changes. No existing test is modified.

## Test Strategy
New tests only, under `lib/promscrape/discovery/scaleway/`:
1. `scaleway_test.go` — `TestGetInstanceLabels`: table-driven, verifies full label mapping (including tag-join formatting, private-IP-preferred `__address__`, public-IP fallback, and skip-when-no-IP), styled after `vultr_test.go`.
2. `api_test.go` — `TestNewAPIConfig_Failure` (missing `secret_key` → error) and `TestNewAPIConfig_Success` (defaults applied: zone `fr-par-1`, port `80`, endpoint `https://api.scaleway.com`), styled after `vultr`/`ovhcloud`.
3. `mock_server_test.go` + a pagination test — `httptest.Server` returning fixed JSON fixtures across 2 pages (first page full `per_page`, second page partial) to verify the pagination loop terminates correctly, the `X-Auth-Token` header is sent with the configured secret, and query filters (`project`, `tags`) are encoded — styled after `vultr`'s cursor-pagination test but adapted to page/per_page. No real Scaleway API is contacted.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Field/label naming diverges from what Scaleway users expect (no upstream Prometheus scaleway_sd_config present in this repo/vendor to copy verbatim) | Medium | Low (cosmetic; relabel_configs still works) | Use Prometheus's well-known real-world field names (`project_id`, `secret_key`, `zone`, `name_filter`, `tags_filter`, `api_url`) and a `__meta_scaleway_instance_*` label prefix, consistent with this repo's own `__meta_<provider>_instance_*` convention (vultr) |
| Secret token leakage in logs/config dumps | Low | High | Use `*promauth.Secret` (redacting type) for `SecretKey`, never a plain `string`, matching `ec2.SecretKey`/`ovhcloud.ApplicationSecret` precedent |
| Pagination loop fails to terminate on malformed/empty API responses | Low | Medium | Terminate strictly on `len(resp.Servers) < per_page`, tested explicitly with a 2-page mock fixture |
| Alphabetical-insertion merge conflicts if this lands alongside other SD additions | Low | Low | Out of scope for a solo change; standard risk accepted for this codebase's convention |

---

Do you approve the plan? Proceed to implementation?
