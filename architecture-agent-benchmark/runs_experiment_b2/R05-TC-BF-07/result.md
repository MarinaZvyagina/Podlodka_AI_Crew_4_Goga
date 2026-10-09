# R05-TC-BF-07

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $4.028929499999999
Duration: 640312ms, turns: 89

## Agent's own summary

Everything builds, vets, and tests clean, and `goga lint` reports no errors across all cells. Here's a summary of the implementation.

## Summary

Added Scaleway Instances service discovery to `lib/promscrape/discovery/scaleway/`, following the exact conventions of sibling providers (closest analog: `vultr`):

- **`scaleway.go`** — `SDConfig` (secret_key, project_id, zone, api_url, port, plus standard `HTTPClientConfig`/`proxy_url`/`ProxyClientConfig`), `GetLabels`/`MustStop`, and label construction (`__meta_scaleway_instance_{id,name,zone,region,type,state,arch,organization_id,project_id,private_ipv4,public_ipv4,tags}`).
- **`api.go`** — per-config API client via the shared `discoveryutil.ConfigMap`/`discoveryutil.Client`, defaulting zone to `fr-par-1` and API URL to `https://api.scaleway.com`.
- **`instance.go`** — paginated calls to the real Scaleway Instance API (`/instance/v1/zones/{zone}/servers`), authenticating via the `X-Auth-Token` header (Scaleway's actual auth scheme — not a generic bearer token) using `GetAPIResponseWithReqParams`.
- Unit tests (`api_test.go`, `instance_test.go`, `scaleway_test.go`, `mock_server_test.go`) using a local `httptest` mock server — no real API calls, covering success, pagination, error, auth-header, and label-mapping cases.

Wired into the discovery registry: `lib/promscrape/config.go` (`ScalewaySDConfigs` field, `mustStop`, `getScalewaySDScrapeWork`) and `lib/promscrape/scraper.go` (periodic refresh via `-promscrape.scalewaySDCheckInterval`, default 30s — no restart required).

Docs updated to match existing integrations: new `## scaleway_sd_configs` section in `docs/victoriametrics/sd_configs.md`, flag entries in the three `*_common_flags.md` files, and a CHANGELOG entry.

Per the ticket's instruction, I ran `goga schema`/`goga lint` before and after: the schema confirmed `lib/promscrape`'s documented `registry_dispatch` pattern already anticipates new providers plugging in this way (no new architectural cell needed), and I updated the stale provider counts/lists in `lib/promscrape/CODEMANIFEST` and `lib/promscrape/discovery/kubernetes/CODEMANIFEST` (22→23 providers, added "scaleway" to the enumerated list). Final `goga lint` is clean (9 cells, 0 errors), and `go build ./...`, `go vet ./...`, and `go test ./lib/promscrape/...` all pass.
