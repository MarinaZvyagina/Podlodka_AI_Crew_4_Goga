# R05-TC-BF-02

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: False
Cost: $2.8474214000000004
Duration: 421572ms, turns: 72

## Agent's own summary

# Change Plan

## Task Classification
**Feature / Extension** — purely additive: a new sibling discovery provider plugged into an already-documented, open-ended extension point (`lib/promscrape`'s SD-provider registry). No existing behavior is modified.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `lib/promscrape` | `config.go` | Add `scaleway` import; add `ScalewaySDConfigs []scaleway.SDConfig \`yaml:"scaleway_sd_configs,omitempty"\`` field to `ScrapeConfig` (alphabetically, between `PuppetDBSDConfigs` and `StaticConfigs`); add `getScalewaySDScrapeWork` dispatch method (alphabetically among the `get<Provider>SDScrapeWork` methods, between `getPuppetDBSDScrapeWork` and `getVultrSDScrapeWork`); add `sc.ScalewaySDConfigs[i].MustStop()` loop to `(sc *ScrapeConfig) mustStop()` (between the `PuppetDBSDConfigs` and `VultrSDConfigs` loops) |
| `lib/promscrape` | `scraper.go` | Add `scaleway` import; add `scs.add("scaleway_sd_configs", *scaleway.SDCheckInterval, ...)` line (between `puppetdb_sd_configs` and `vultr_sd_configs`) |
| `lib/promscrape/discovery/scaleway` (new) | `scaleway.go`, `api.go`, `scaleway_test.go`, `api_test.go` | New package implementing the standard one-shot-poll provider shape |
| `docs/victoriametrics` | `sd_configs.md` | New `## scaleway_sd_configs` section (alphabetically between `puppetdb_sd_configs` and `static_configs`) |
| `docs/victoriametrics/changelog` | `CHANGELOG.md` | New unreleased entry |

No CODEMANIFEST file is created or modified — `lib/promscrape/CODEMANIFEST`'s `registry_dispatch` usage already describes this exact extension point in open-ended terms and requires no textual update for one more conforming sibling (see Specification Impact below).

## Root Cause Analysis
N/A (feature addition, not a defect). Summary from Investigation: the registry has exactly four mechanical wiring sites in `lib/promscrape` (struct field, dispatch method, stop-loop entry, scraper registration) plus zero CODEMANIFEST obligations for the new leaf package itself, matching the pattern of all ~21 existing one-shot-poll siblings.

## Trace Summary
`ScalewaySDConfigs[i]` (YAML-parsed) → `getScalewaySDScrapeWork`'s `visitConfigs` closure → `getScrapeWorkGeneric` → `targetLabelsGetter.GetLabels(baseDir)` (structurally satisfied by `scaleway.SDConfig`) → `scaleway` package fetches paginated JSON from the Scaleway Instance API → returns `[]*promutil.Labels` → `appendScrapeWorkForTargetLabels` → `ScrapeWork`s surfaced via `scs.add`'s registered closure, polled independently on `*scaleway.SDCheckInterval`. On reload/shutdown, `Config.mustStop()` → `ScrapeConfig.mustStop()` → `ScalewaySDConfigs[i].MustStop()` releases the package's `discoveryutil.Client`.

## Change Strategy
1. **New package `lib/promscrape/discovery/scaleway`**:
   - `scaleway.go`: `SDCheckInterval` flag (`-promscrape.scalewaySDCheckInterval`, default 30s); `SDConfig` struct (`project_id` required, `zone`/`api_url`/`name_filter`/`tags_filter`/`port` optional, inline `promauth.HTTPClientConfig` + `proxy.URL` + `promauth.ProxyClientConfig`); `GetLabels`/`MustStop` methods; label-building function producing `__meta_scaleway_instance_*` labels + `__address__`.
   - `api.go`: `apiConfig`/`configMap` (via `discoveryutil.NewConfigMap()`), `newAPIConfig`/`getAPIConfig` (validates `project_id` non-empty, applies defaults, builds `discoveryutil.Client`), `getServers` (paginated GET against `/instance/v1/zones/{zone}/servers`), `parseAPIResponse`.
2. **Wire into `lib/promscrape`**: the four edits listed above, each copy-pasted from the immediately-adjacent alphabetical neighbor (`puppetdb`/`vultr`) with names substituted — zero deviation from established structure.
3. **Tests**: `scaleway_test.go` (label-building from parsed `server` structs, table-driven, using `discoveryutil.TestEqualLabelss` like `digitalocean_test.go`), `api_test.go` (`parseAPIResponse` against a raw JSON fixture; `getServers` pagination against a fake `getAPIResponse` closure — no network, no real API).
4. **Docs**: new section mirroring `digitalocean_sd_configs`' structure (intro + link to Scaleway's Instance API reference, YAML example, `__address__` explanation, meta-label bullet list, `SDCheckInterval` flag mention).
5. **CHANGELOG**: one line under the current unreleased heading, following the phrasing convention of prior SD-integration entries.

## Specification Impact
None. `lib/promscrape/CODEMANIFEST`'s `registry_dispatch` usage text ("ScrapeConfig embeds one `[]SDConfig`-shaped slice field per discovery provider... ~22 provider fields... Every provider except kubernetes and http implements... `GetLabels`... dispatched uniformly...") remains accurate: it is explicitly example-based and approximate ("~22", "e.g."), and scaleway conforms exactly to the described shape rather than deviating from it. This will be re-verified mechanically in the Drift Analysis / Manifest Reconciliation steps rather than assumed.

## Usage Impact
None. No `.usages/` file references the discovery-provider list exhaustively; `kubernetes/CODEMANIFEST`'s `provider_registry_pattern` usage is read-only precedent for shape, not a file requiring edits (it already documents kubernetes as *the exception*, which remains true).

## Compatibility Verification
**Backward compatible.** All edits are additive (new struct field with `omitempty`, new method, new loop iteration over a new empty-by-default slice, new file). No existing exported identifier, YAML key, method signature, or test fixture changes. Confirmed no existing test enumerates the closed set of SD provider types.

## Test Strategy
- **Unit, label-building**: verify `server` → `promutil.Labels` mapping (all `__meta_scaleway_instance_*` labels + `__address__` construction, including the public-IP-present and public-IP-absent/private-fallback cases) — mirrors `digitalocean_test.go:TestAddDropletLabels`.
- **Unit, response parsing**: verify `parseAPIResponse` against a realistic raw JSON fixture — mirrors `digitalocean/api_test.go:TestParseAPIResponse`.
- **Unit, pagination**: verify `getServers` correctly accumulates multiple pages via a fake `getAPIResponse` function keyed by requested path — mirrors `digitalocean/api_test.go:TestGetDroplets`.
- All tests use in-process fake data only; no real Scaleway API call, per the ticket's explicit requirement.
- Validate with `go build ./...` and `go test ./lib/promscrape/...` after implementation.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Missing the `mustStop()` wiring site (easy to overlook, not in the "obvious" two files) | Low (already identified in Investigation) | Medium (resource leak on config reload) | Explicitly included as edit #3 above; will be checked again in Manifest Reconciliation/Validation |
| Misplacing alphabetical ordering in `ScrapeConfig`/`scraper.go`/`mustStop()` | Low | Low (cosmetic/convention only, no functional break) | Copy exact insertion points identified in Investigation (`puppetdb` ↔ `vultr` boundary) |
| Incorrect assumption about Scaleway API JSON shape (hand-rolled, not using official SDK) | Low-Medium | Low (only affects real-world correctness, not tests, since tests use fake fixtures) | Field names cross-checked against upstream Prometheus's `discovery/scaleway` implementation before planning |
| Reviewer/goga expects a CODEMANIFEST for the new package | Low | Low (documentation-only disagreement, no functional risk) | Explicitly re-confirmed in Drift Analysis / Manifest Reconciliation per user's original instruction, not just assumed here |

---

Do you approve the plan? Proceed to implementation?
