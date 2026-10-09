# R05-TC-GC-07

Condition: goga_native_architecture
Base tag: condition-c-r05-v1
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: False
Cost: $1.9679949
Duration: 257453ms, turns: 54

## Agent's own summary

# Change Plan

## Task Classification
**Feature** (net-new, additive service-discovery provider)

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `lib/promscrape` | `config.go`, `scraper.go` | Add `scaleway` import, `ScalewaySDConfigs` field, `mustStop` loop, `getScalewaySDScrapeWork` method, and a `scs.add("scaleway_sd_configs", ...)` dispatch entry — additive only, existing entries untouched |
| `lib/promscrape/discovery/scaleway` (new, non-cell package under the `lib/promscrape` cell's filesystem footprint) | `scaleway.go`, `api.go`, `scaleway_test.go`, `api_test.go` (new files) | New one-shot provider package implementing `targetLabelsGetter` |
| `lib/promscrape/discoveryutil` | none | Consumed read-only (`NewClient`, `ConfigMap`, `JoinHostPort`, `TestEqualLabelss`); no modification |
| docs (not a cell) | `docs/victoriametrics/sd_configs.md`, `docs/victoriametrics/changelog/CHANGELOG.md` | New provider list bullet + full section; one CHANGELOG `tip` entry |

## Root Cause Analysis
Not applicable in the bugfix sense — this is additive. Per the Investigation Report, VictoriaMetrics enumerates cloud-provider service discovery as a closed, fully-precedented set of seven touch points (package, `ScrapeConfig` field, `mustStop`, `get*ScrapeWork`, `scraper.go` dispatch, docs list+section, CHANGELOG). Scaleway support requires populating all seven with zero deviation from the pattern every existing provider (digitalocean/hetzner/vultr/etc.) already follows.

## Trace Summary
`-promscrape.config` YAML → `ScrapeConfig.ScalewaySDConfigs` (new field) → `scraper.go` scraperGroup ticks on `*scaleway.SDCheckInterval` → `cfg.getScalewaySDScrapeWork` → `getScrapeWorkGeneric` → `(*scaleway.SDConfig).GetLabels(baseDir)` → per-zone `GET /instance/v1/zones/{zone}/servers` via a cached `discoveryutil.Client` → JSON decode → filter `state == "running"` → `addServerLabels` → `[]*promutil.Labels` → back into the untouched generic diff/relabel/scrape path. No existing call path is altered; a new independent branch is added at each dispatch point.

## Change Strategy
1. **`lib/promscrape/discovery/scaleway/api.go`** — package-level `configMap = discoveryutil.NewConfigMap()`; `apiConfig{client *discoveryutil.Client, port int, projectID string}`; `newAPIConfig`/`getAPIConfig` mirroring `digitalocean`'s structure exactly (hardcoded `apiServer = "https://api.scaleway.com"`, `port` defaults to 80); `getServers(getAPIResponse func(string) ([]byte, error), zones []string, projectID string) ([]server, error)` iterating zones, building path `/instance/v1/zones/<zone>/servers` with `?project=<id>` appended when set, concatenating decoded results (mirrors digitalocean's `getDroplets` closure-based shape — no `httptest`, consistent with the simpler of the two exemplar conventions actually used in this codebase); `parseAPIResponse`.
2. **`lib/promscrape/discovery/scaleway/scaleway.go`** — `SDCheckInterval` flag; `SDConfig{Zones []string \`yaml:"zones"\`, ProjectID string \`yaml:"project_id,omitempty"\`, Port int \`yaml:"port,omitempty"\`, HTTPClientConfig promauth.HTTPClientConfig \`yaml:",inline"\`, ProxyURL *proxy.URL \`yaml:"proxy_url,omitempty"\`, ProxyClientConfig promauth.ProxyClientConfig \`yaml:",inline"\`}`; `server` struct (`ID, Name, CommercialType, State, Zone string`; `Tags []string`; `PublicIP *publicIP \`json:"public_ip"\`` nullable; `PrivateIP *string \`json:"private_ip"\`` nullable); `listServersResponse{Servers []server}`; `GetLabels(baseDir)` = get `apiConfig` → `getServers` → filter `state=="running"` → `addServerLabels`; `MustStop` deletes from `configMap`.
3. **`addServerLabels(servers []server, defaultPort int) []*promutil.Labels`** — `__address__` = public IP if non-nil else private IP if non-nil else skip (no usable address ⇒ instance omitted, same "skip when no address" discipline `digitalocean` uses for droplets with no v4 network), joined via `discoveryutil.JoinHostPort`; `__meta_scaleway_instance_id`, `__meta_scaleway_instance_name`, `__meta_scaleway_instance_state`, `__meta_scaleway_instance_commercial_type`, `__meta_scaleway_instance_zone`, `__meta_scaleway_private_ip`, `__meta_scaleway_public_ip`; `__meta_scaleway_instance_tags` only when `len(Tags) > 0`, comma-bracketed (`,tag1,tag2,`) matching `digitalocean`/`vultr` convention.
4. **`lib/promscrape/discovery/scaleway/scaleway_test.go`** — `TestAddServerLabels` via `discoveryutil.TestEqualLabelss`, table cases: (a) running instance, both public+private IP, tags present; (b) running instance, public IP nil / private IP only; (c) running instance, no tags (label absent, not empty-string); (d) mixed input list containing a `state != "running"` instance filtered out earlier in `GetLabels` (tested by asserting `addServerLabels` receives only pre-filtered running instances — filtering itself is asserted via a small `TestGetLabelsFiltersNonRunning`-style unit on the filter step, or inline by constructing the pre-filter slice test at the `GetLabels`-adjacent filter function if factored out as its own testable function, e.g. `filterRunning(servers []server) []server`).
5. **`lib/promscrape/discovery/scaleway/api_test.go`** — `TestParseAPIResponse` (one fixture JSON matching ground-truth shape → expected `listServersResponse`) and `TestGetServers` (fake `getAPIResponse` closure keyed by zone-specific path, returning per-zone canned JSON, asserting concatenation across ≥2 zones) — mirrors `digitalocean/api_test.go` exactly, no real network calls, no `httptest` (keeps parity with the simpler exemplar).
6. **`lib/promscrape/config.go`** — import added alphabetically (`puppetdb` → `scaleway` → `vultr`); `ScalewaySDConfigs []scaleway.SDConfig \`yaml:"scaleway_sd_configs,omitempty"\`` field added directly after `PuppetDBSDConfigs` (before `StaticConfigs`); `mustStop` loop added after the `PuppetDBSDConfigs` loop, before `VultrSDConfigs`; `getScalewaySDScrapeWork(prev []*ScrapeWork) []*ScrapeWork` added adjacent to `getPuppetDBSDScrapeWork`/`getVultrSDScrapeWork`, structurally identical to `getDigitalOceanDScrapeWork`.
7. **`lib/promscrape/scraper.go`** — import added; one `scs.add("scaleway_sd_configs", *scaleway.SDCheckInterval, func(cfg *Config, swsPrev []*ScrapeWork) []*ScrapeWork { return cfg.getScalewaySDScrapeWork(swsPrev) })` line inserted alphabetically between the `puppetdb_sd_configs` and `vultr_sd_configs` lines.
8. **`docs/victoriametrics/sd_configs.md`** — one bullet in the top enumeration (alphabetically between `puppetdb_sd_configs` and `static_configs`) and one `## scaleway_sd_configs` section (alphabetically positioned the same way) following the `digitalocean`/`vultr` section template: intro sentence, commented YAML config example (all fields), `__address__` derivation paragraph, meta-label bullet list, refresh-interval closing sentence citing `-promscrape.scalewaySDCheckInterval`.
9. **`docs/victoriametrics/changelog/CHANGELOG.md`** — one `FEATURE:` bullet under `## tip`, phrased like neighboring entries, linking to the new docs anchor.

## Specification Impact
No CODEMANIFEST body-level entry requires editing: `lib/promscrape/CODEMANIFEST`'s `registry_dispatch` usage text is already generic ("ScrapeConfig embeds one `[]SDConfig`-shaped slice field per discovery provider ... ~22 provider fields ... Every provider except kubernetes and http implements ... `targetLabelsGetter` ... dispatched uniformly by `getScrapeWorkGeneric` ... its own `SDCheckInterval` flag"). Scaleway becomes the 23rd conforming provider without changing the shape this text describes. During **Manifest Reconciliation** (pipeline step 7) this text should be re-verified for continued accuracy (e.g., updating the "~22" count if the manifest author wants it exact) — flagged as a candidate touch-up, not a required rewrite, since the usage is deliberately illustrative rather than exhaustive.

## Usage Impact
`lib/promscrape/discoveryutil`'s `shared_helper_role` usage already generalizes over "consul, docker, ec2, gce, hetzner, nomad, ..." — Scaleway fits this description without edits (its `Client`/`ConfigMap`/`JoinHostPort` usage is identical in shape to the providers already named). No usage file requires modification; existing usage recipes remain fully valid for consumers.

## Compatibility Verification
**Backward compatible.** All changes are additive: new package, new struct fields, new flag, new dispatch-table entry, new docs section. No existing exported identifier, file path, struct field, YAML key, or function signature is altered or removed. No existing test fixture or behavior changes. Confirmed against all six Breaking Change Policy questions in the Investigation Report — all answered NO.

## Test Strategy
- **Unit, label-building** (`scaleway_test.go`): `TestAddServerLabels` — deterministic, no I/O, covers public+private IP combinations, tag presence/absence, and non-running-instance exclusion, following `discoveryutil.TestEqualLabelss` convention used by every sibling provider.
- **Unit, API layer** (`api_test.go`): `TestParseAPIResponse` (JSON→struct fidelity) and `TestGetServers` (multi-zone fetch/concatenation using a fake `getAPIResponse` closure) — no real Scaleway API access, consistent with the ticket's "recorded/fake API responses" requirement and with `digitalocean/api_test.go`'s established pattern in this codebase.
- **No changes needed** to `lib/promscrape/config_test.go` or `scraper_test.go` — neither file enumerates providers exhaustively (confirmed via `grep` finding zero digitalocean/vultr references in `config_test.go`), so no existing test requires updating for the new field/flag.
- **Build/vet verification**: `go build ./...` and `go vet ./lib/promscrape/...` after implementation to catch import-ordering or unused-symbol issues before manifest reconciliation.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Alphabetical-ordering drift in `config.go`/`scraper.go` (misplacing `scaleway` relative to `puppetdb`/`vultr`) causing review friction, not a functional bug | Low | Low | Insert precisely per the exemplar line numbers identified in investigation (config.go:340/432, scraper.go:150) |
| `Zones` field required-but-empty misconfiguration silently producing zero targets instead of a clear error | Medium | Low | `newAPIConfig`/`GetLabels` returns an explicit error when `len(sdc.Zones) == 0`, matching Vultr's `missing bearer_token` explicit-error precedent |
| Null `public_ip`/`private_ip` JSON fields mis-decoded as empty struct instead of nil, producing bogus empty-string addresses | Medium | Medium | Use pointer types (`*publicIP`, `*string`) for nullable JSON fields per ground-truth response shape, and unit-test the nil case explicitly |
| Docs section omitted from the top bullet list while the `##` section is added (or vice versa), leaving an inconsistent doc | Low | Low | Single edit step touches both the bullet list and the section together; verified by grep for `scaleway` in the doc file post-edit |

**Do you approve the plan? Proceed to implementation?**
