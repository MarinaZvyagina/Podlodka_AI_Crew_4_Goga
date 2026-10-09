# R05-TC-BF-09

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $5.384067599999999
Duration: 951456ms, turns: 103

## Agent's own summary

## Summary

Added `scaleway_sd_configs` service discovery support, following the exact conventions used by the neighboring `vultr`/`digitalocean`/`openstack` providers in `lib/promscrape/discovery/`:

- **New package** `lib/promscrape/discovery/scaleway/` (`scaleway.go`, `api.go`, `instance.go` + tests) — queries the Scaleway Instance API v1 `List servers` endpoint per zone, paginating via `total_count`, authenticating with the `X-Auth-Token` header (Scaleway's actual auth scheme, mirrored from how `openstack`'s SD does custom-header auth), and supports `secret_key` (mandatory), `zone` (default `fr-par-1`), `project_id`/`organization_id` filters, `port`, plus the standard `proxy_url`/HTTP client options every other SD config gets.
- Only `running` instances are emitted as targets; each carries `__meta_scaleway_instance_{id,name,zone,state,type,hostname,arch,boot_type,organization,project,public_ip,private_ip,ipv6,tags}` labels, satisfying the ticket's minimum label set. `__address__` prefers the public IP, falling back to the private IP.
- Wired into `lib/promscrape/config.go` and `scraper.go` alphabetically (between `puppetdb` and `vultr`), so it refreshes on its own interval (`-promscrape.scalewaySDCheckInterval`, default 30s) without a vmagent restart, same as every other cloud SD.
- Unit tests use a local `httptest` mock server (no real API calls) covering config validation, pagination, HTTP failure, and label generation (including skip-if-stopped and public→private IP fallback cases).
- Documented in `docs/victoriametrics/sd_configs.md` (new `## scaleway_sd_configs` section + TOC entry), added a changelog entry, and added the new `-promscrape.scalewaySDCheckInterval` flag to the three common-flags doc dumps (verified against real `-help` output from a locally built `vmagent` binary).
- Verified: `go build ./...`, `go test ./lib/promscrape/...` (all packages, including the new one), and `goga lint` (0 errors) all pass.

One incidental finding, out of scope for this change: `lib/promscrape/discovery/vultr/api.go` (and likely `linode`) call `qp.Set(...)` on a nil `url.Values` when any optional filter field is set — this panics at runtime (confirmed with a quick repro). I avoided that pattern in the new Scaleway code but didn't touch the existing vultr/linode code since it wasn't part of this ticket; worth a follow-up fix.
