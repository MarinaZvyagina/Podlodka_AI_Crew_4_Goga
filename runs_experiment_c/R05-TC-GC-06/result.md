# R05-TC-GC-06

Condition: goga_native_architecture
Base tag: condition-c-r05-v1
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $4.551892799999999
Duration: 661474ms, turns: 102

## Agent's own summary

# Final Change Execution Report

**Task**: Add automatic scrape-target discovery for Scaleway Instances (`scaleway_sd_configs`) to `lib/promscrape`.

## What was added
- **`lib/promscrape/discovery/scaleway/`** (new package, uncelled — matches all sibling provider packages): `scaleway.go`, `api.go`, plus `scaleway_test.go`/`api_test.go`. Implements the standard `targetLabelsGetter` contract (`GetLabels`/`MustStop`), a `-promscrape.scalewaySDCheckInterval` flag, and calls the Scaleway Instances API (`GET /instance/v1/zones/{zone}/servers`, paginated) using the shared `lib/promscrape/discoveryutil.Client`/`ConfigMap`. Auth/proxy are handled entirely through the existing `promauth.HTTPClientConfig`/`proxy.URL` options (no new auth code needed — users pass `headers: ["X-Auth-Token: <secret_key>"]`, since Scaleway doesn't use the Bearer scheme).
- Discovered **running** Instances get labels: `__meta_scaleway_instance_id`, `_instance_name`, `_instance_status`, `_instance_type`, `_zone`, `_project_id`, `_public_ipv4`, `_private_ipv4`, `_tags`. `__address__` uses the public IP (falls back to private IP if none).
- **Wired into `lib/promscrape`**: `config.go` (`ScalewaySDConfigs` field, `mustStop` loop, `getScalewaySDScrapeWork`) and `scraper.go` (`scs.add(...)` polling registration) — purely additive, alphabetically placed alongside the other ~22 providers.
- **Refresh without restart** falls out of the existing polling mechanism (`SDCheckInterval` + `scs.add`), same as every other provider.
- **Tests**: fake/injected API responses only, no network — pagination, JSON parsing, and label-building (including edge cases: private-IP-only, stopped instances filtered out, no-IP instances skipped) all covered and passing.
- **Docs**: `docs/victoriametrics/sd_configs.md` (new `## scaleway_sd_configs` section + summary bullet), `CHANGELOG.md` (tip entry), and the three generated `*_common_flags.md` files.
- **CODEMANIFEST reconciliation**: updated `lib/promscrape/CODEMANIFEST` and `lib/promscrape/discovery/kubernetes/CODEMANIFEST` (the latter was a second, easy-to-miss enumeration of all sibling providers by name — caught during drift analysis) so the cell specifications stay accurate.

## Verification
`go build ./...`, `go vet ./...`, `gofmt -l` all clean; `go test ./lib/promscrape/...` passes across all 24 packages including the new one; `goga lint` from repo root reports **55 cells / 0 errors**. No breaking changes — every edit is additive.

## Note on the Scaleway API shape
I don't have live access to Scaleway's API to verify field names against a real response, so `scaleway.go`/`api.go` use the well-documented, stable Instance API v1 conventions (`X-Auth-Token` header, `/instance/v1/zones/{zone}/servers`, `commercial_type`, `public_ip.address`, `private_ip`, `state`). Worth a quick sanity check against a real Scaleway account before merging if precision matters here.
