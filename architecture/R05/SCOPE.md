# SCOPE.md — R05 (VictoriaMetrics/VictoriaMetrics)

## Method

Scope was decided from VictoriaMetrics's own module layout — directories at depth ≤ 3 under the
repository root (`lib/...`, `app/...`), per `TREATMENT_DESIGN.md` §4 — verified by directly
reading source files in each candidate directory and by repository-wide `grep` of
`"github.com/VictoriaMetrics/VictoriaMetrics/..."` import statements to confirm which
directories are genuinely load-bearing (i.e. actually depended upon by other parts of the
codebase), not just present. This was done **before** reading `tasks/R05/task_A.md`–
`task_D.md` (see `PLAUSIBILITY_CHECK.md` for the post-hoc self-check, performed only after this
scoping and authoring work was complete).

Candidate list from the assignment's own reconnaissance pointers (`lib/storage`,
`lib/promscrape` + `lib/promscrape/discovery`, a representative selection of `app/` binaries,
`lib/promrelabel`) was verified against `ls lib/` (56 top-level packages) and `ls app/` (21
top-level binaries) and confirmed accurate as genuinely load-bearing candidates — not every
`lib/*`/`app/*` directory is: most of the 56 `lib/*` packages are thin, single-purpose utility
modules (`bytesutil`, `fasttime`, `timerpool`, `flagutil`, etc.) without independent multi-file
public surfaces of their own, and several `app/*` binaries (`vmalert`, `vmalert-tool`, `vmauth`,
`vmbackup`, `vmbackupmanager`, `vmctl`, `vmgateway`, `vmrestore`, `vmui`, `victoria-logs`,
`vl*` — the VictoriaLogs sibling product) are real but were deprioritized, see below.

## Cells covered (9) and why

| Cell | Evidence it's load-bearing |
|---|---|
| `lib/storage` | Confirmed god package: `Storage`/`MetricRow`/`MetricName`/`TSID`/`TagFilters`/`Search`/`Block`/`SearchQuery` are imported directly by `app/vmstorage`, `app/vminsert` (`common`, `influx`, `native`, `vmimport`), `app/vmselect` (`netstorage`, `promql`, `graphite`, `prometheus`), `app/victoria-metrics`, and `lib/protoparser/native/stream` — 33 non-test files repository-wide import it directly. The single most widely-depended-upon package in the codebase; has no outbound dependency on any `app/*` package. |
| `lib/mergeset` | Generic merge-sorted (LSM-tree-like) key-value engine. Exactly one production caller confirmed by grep (`lib/storage/index_db.go`, which builds the entire inverted index on top of one `mergeset.Table`) plus a config-only touch from `app/vmstorage` (cache-size flags) — a real, independently-testable low-level primitive `lib/storage` is built on, not storage-specific logic. |
| `lib/promscrape` | The Prometheus-compatible service-discovery + scraping engine; imported by all four binary `main.go`s (`app/vmagent`, `app/vminsert`, `app/vmselect`, `app/victoria-metrics`), primarily driven by `app/vmagent`. Directly imports and executes `lib/promrelabel`'s `ParsedConfigs.Apply` at scrape time — a real, load-bearing cross-cell dependency, not just a type reference. |
| `lib/promscrape/discovery/kubernetes` | Representative exemplar of the ~22-package service-discovery plugin registry under `lib/promscrape/discovery/` (azure, consul, consulagent, digitalocean, dns, docker, dockerswarm, ec2, eureka, gce, hetzner, http, kubernetes, kuma, linode, marathon, nomad, openstack, ovhcloud, puppetdb, vultr, yandexcloud) — a real, designed extension point (`targetLabelsGetter` interface + static struct-field registration in `lib/promscrape`'s `ScrapeConfig`). Chosen as the exemplar because it is both the largest single provider (2,914 of 12,477 total discovery-tree lines) and the architecturally distinct case (persistent watch vs. the ~20 siblings' one-shot poll), confirmed against `consul`/`ec2`/`gce` to verify the shared shape. |
| `lib/promrelabel` | Shared, cross-cutting relabeling engine. Confirmed by import-graph analysis (`grep -rl`) to be consumed identically by `lib/promscrape` (scrape-time relabeling), `app/vminsert/relabel` and `app/vmagent/remotewrite` (ingestion-time relabeling), `lib/streamaggr`, `app/vmalert`, and `app/vmselect`'s federate endpoint — the single implementation of Prometheus relabeling semantics used everywhere in the repository. |
| `app/vmstorage` | Confirmed via source reading to be the direct, thin network/admin-facing wrapper around one `lib/storage.Storage` instance (opens it, exposes `VMInsertAPI`/`VMSelectAPI`/`GetSearch`/`PutSearch` package variables, optionally starts a `vmselectapi` RPC server). In this pinned commit it is a library consumed by `app/victoria-metrics/main.go`, not its own `package main` — documented honestly as such rather than assumed. |
| `app/vminsert` | The write/ingestion-path fan-in boundary: ~16 sibling wire-format subpackages (promremotewrite, influx, graphite, opentsdb, opentelemetry, newrelic, datadog×3, zabbixconnector, csvimport, native, vmimport, prometheusimport) converge on `main.go`'s `RequestHandler`, normalize through `common.InsertCtx`, and commit via the storage-facing cell. |
| `app/vmselect` | The read/query-path boundary: Prometheus- and Graphite-compatible HTTP API surface, composing `promql` (expression evaluation) and `netstorage` (result fan-out, confirmed to call `lib/storage` types and the storage-facing cell's in-process facade in this pinned commit). |
| `app/vmagent` | The most-composed binary: an edge scrape/forward agent directly driving `lib/promscrape`'s lifecycle and, via its own `remotewrite` subpackage, `lib/promrelabel` — confirmed by reading `main.go`'s real 8-step initialization order (remotewrite before promscrape, wired via a callback). |

## Deliberately excluded / deprioritized

- **`app/vmalert`, `app/vmalert-tool`** — a real, substantial alerting/recording-rule evaluation
  engine, but it is a downstream *consumer* of `lib/promrelabel` (notifier/alert relabeling) and
  of the query APIs the cells above already document, not part of the ingest→store→query
  structural spine itself.
- **`app/vmauth`, `app/vmgateway`** — authentication/multi-tenancy proxies sitting in front of
  the cluster components; real but orthogonal to the core storage/scrape/query spine, and not
  imported by any of the nine documented cells.
- **`app/vmbackup`, `app/vmbackupmanager`, `app/vmrestore`, `app/vmctl`** — operational
  tooling (snapshot backup/restore, migration) built on top of `lib/storage`'s and `lib/backup`'s
  APIs; genuine but auxiliary to the always-running data-path components documented here.
- **`app/vmui`** — a bundled static frontend (served by `app/vmselect`, already noted in that
  cell's Annotations), not a Go architectural component of its own.
- **`victoria-logs`, `vlagent`, `vlinsert`, `vlogscli`, `vlogsgenerator`, `vlselect`,
  `vlstorage`, `lib/logstorage`** — VictoriaLogs, a sibling product sharing this repository and
  some low-level `lib/*` utility packages, but architecturally a separate ingest/store/query
  pipeline built on `lib/logstorage` rather than `lib/storage`; out of scope for a spine
  documenting the metrics product's own dependency graph.
- **The remaining ~50 `lib/*` packages** (`bytesutil`, `fasttime`, `flagutil`, `timerpool`,
  `envflag`, `httpserver`, `logger`, `memory`, `cgroup`, `fs`, `filestream`, `blockcache`,
  `bloomfilter`, `lrucache`, `workingsetcache`, `uint64set`, `decimal`, `regexutil`,
  `metricsql`-adjacent glue, etc.) — real, widely-used, but thin, single-purpose utility/infra
  modules with no independent multi-type public surface of their own, referenced by the
  documented cells (and each other) for shared low-level primitives rather than being
  architectural components in their own right. Two of the largest and most load-bearing of
  these (`lib/mergeset`, which underlies the storage engine, and `lib/promrelabel`, which is a
  genuine shared cross-cutting engine) were promoted into the forest because they clear the
  "distinct responsibility domain with a well-defined API boundary" bar; the rest do not.
- **The ~21 sibling packages of `lib/promscrape/discovery/kubernetes`** — real, independently
  documented conceptually via the `kubernetes` exemplar's `provider_registry_pattern` Usages
  entry (which names all of them and confirms the shared `SDConfig`/`GetLabels` shape against
  `consul`/`ec2`/`gce`), but not each given its own CODEMANIFEST cell — documenting all 22 would
  duplicate the same contract shape 21 more times without adding new architectural information,
  and would exceed the "roughly 6-10 cells, not an exhaustive catalog" budget.
- **Sub-packages of `app/vminsert`, `app/vmagent`, `app/vmselect`** (e.g. `common`, `relabel`,
  `remotewrite`, `netstorage`, `promql`, and the ~16 wire-format packages) — real components,
  but the CODEMANIFEST `location` constraint (files must sit at the same directory level as
  `CODEMANIFEST`, no subdirectory traversal) means each would need its own cell; given the
  "roughly 6-10 cells" budget, only the top-level `main.go`-resident entry points
  (`Init`/`Stop`/`RequestHandler`/`main`) of each binary were documented, with their real
  composition of these subpackages described in each cell's Annotations/Usages prose.

This scoping was performed and frozen before `tasks/R05/task_A.md`–`task_D.md` were read (see
`PLAUSIBILITY_CHECK.md`).
