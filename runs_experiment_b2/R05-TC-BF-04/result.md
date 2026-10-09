# R05-TC-BF-04

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $4.703806349999999
Duration: 606043ms, turns: 89

## Agent's own summary

Everything is clean, built, and tested. Here's a summary of the implementation:

## Summary

Added Scaleway Instance discovery (`scaleway_sd_configs`) as a new service-discovery provider, following the exact conventions of the existing `lib/promscrape/discovery/*` providers (closest template: `vultr`).

**New package** `lib/promscrape/discovery/scaleway/`:
- `scaleway.go` — `SDConfig` (secret_key, zone, project, organization, port + standard HTTP/proxy client options), `-promscrape.scalewaySDCheckInterval` flag (default 30s), `GetLabels`/`MustStop`, and label construction (`__meta_scaleway_instance_{id,name,hostname,zone,state,type,project_id,organization_id,public_ipv4,private_ipv4,tags}`)
- `api.go` — builds the Scaleway API client, validates the mandatory `secret_key`, injects the `X-Auth-Token` auth header (Scaleway's real auth scheme, not `Authorization: Bearer`) via the existing `GetAPIResponseWithReqParams` callback extension point
- `instance.go` — Scaleway Instances API v1 client (`GET /instance/v1/zones/{zone}/servers`) with page/per_page pagination
- Full unit test coverage using mocked HTTP servers (no real API calls): config validation, auth header, pagination, label mapping

**Wired into the existing registry** (`lib/promscrape/config.go`, `lib/promscrape/scraper.go`) exactly like every other provider — alphabetically ordered struct field, `mustStop` loop entry, `getScalewaySDScrapeWork` dispatcher, and `scs.add(...)` registration — so it refreshes on its own interval without a vmagent restart, same as all siblings.

**Docs**: added a `scaleway_sd_configs` section to `docs/victoriametrics/sd_configs.md` (with config example and meta-label reference), a changelog entry, and kept the three generated `*_common_flags.md` files in sync with the new flag's help text.

Caught and avoided a latent nil-map panic bug present in the vultr provider (`var qp url.Values; qp.Set(...)`) by properly initializing `url.Values{}` in the new code — didn't touch vultr itself since that's out of scope for this ticket.

Verified via `goga schema`/`goga lint` that this follows the already-documented `registry_dispatch`/`provider_registry_pattern` architecture (kubernetes cell's CODEMANIFEST), confirmed `go build ./...`, `go vet`, and `go test ./lib/promscrape/...` all pass clean.
