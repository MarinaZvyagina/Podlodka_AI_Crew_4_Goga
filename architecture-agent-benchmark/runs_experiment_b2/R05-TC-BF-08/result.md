# R05-TC-BF-08

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $3.6402321000000013
Duration: 535364ms, turns: 88

## Agent's own summary

Everything is clean and formatted. Here's a summary of the work:

## Summary

Added `scaleway_sd_configs` service discovery support to `vmagent`/`vmsingle`, following the exact conventions established by the ~22 existing sibling providers under `lib/promscrape/discovery/` (confirmed via `goga schema`/`goga lint`, which document this as a registry-dispatch extension point with a shared `GetLabels(baseDir) ([]Labels, error)` + `MustStop()` contract).

**New package** `lib/promscrape/discovery/scaleway/`:
- `scaleway.go` — `SDConfig` (project/organization, secret_key, api_url, zones, port, standard HTTP client/proxy options) and the label-mapping logic.
- `api.go` — API client setup, zone iteration (defaults to all known Scaleway zones so instances stay discoverable even after a zone move, per the ticket's motivation), and page-based pagination against the Instances API, authenticating via the `X-Auth-Token` header (following the precedent set by `ovhcloud`/`hetzner` for non-Bearer auth schemes).
- Labels exposed: id, name, hostname, zone, instance type (commercial_type), state, project, organization, public/private IPv4, and tags — meeting the ticket's minimum bar.
- `scaleway_test.go`, `api_test.go`, `mock_server_test.go` — unit tests using an `httptest` mock server and fake JSON, no real API calls.

**Wiring** (matching every other provider):
- `lib/promscrape/config.go` — added `ScalewaySDConfigs` field, `mustStop` cleanup, `getScalewaySDScrapeWork`.
- `lib/promscrape/scraper.go` — registered the periodic poller via `scs.add("scaleway_sd_configs", *scaleway.SDCheckInterval, ...)`, giving it its own refresh interval without requiring a restart.

**Docs**: added a `scaleway_sd_configs` section to `docs/victoriametrics/sd_configs.md` and a changelog entry.

**Goga contracts**: kept the two CODEMANIFEST files that describe the provider-registry pattern (`lib/promscrape/CODEMANIFEST`, `lib/promscrape/discovery/kubernetes/CODEMANIFEST`) in sync with the new 23rd provider; `goga lint` passes clean.

Verified with `go build ./...`, `go vet ./lib/promscrape/...`, and `go test ./lib/promscrape/...` — all green.
