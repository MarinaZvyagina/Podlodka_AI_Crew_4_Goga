# R05-TD-BF-06

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.5
Dangerous success: False
Goga engagement signal: False
Cost: $1.6963439999999999
Duration: 289889ms, turns: 50

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add per-metric-name tracking of samples dropped due to `-storage.maxHourlySeries` / `-storage.maxDailySeries` cardinality limits, expose a query for the top offending metric names since last reset, keep memory bounded, keep zero overhead when disabled, and add tests. Scope is explicitly limited to single-node + the storage component of the cluster build (no tenant-awareness, no cluster vmselect-to-vmstorage RPC wiring required).

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `lib/storage` | Owns `registerSeriesCardinality`, the exact call site where hourly/daily limiter drops occur (storage.go ~2151); owns `Storage`, `OpenOptions`, `Metrics` | High |
| `lib/storage/metricnamestats` (new subcell to model, not modify) | Closest existing analog: bounded, per-metric-name tracker wired into `Storage` the same way our new tracker needs to be | High (as reference pattern only) |
| `app/vmstorage` | Owns the flags (`-storage.maxHourlySeries` mirrors here as `getMaxHourlySeries()`), `OpenOptions` construction, `requestHandler` (internal debug HTTP endpoints), and `writeStorageMetrics` — the only place both single-node `victoria-metrics` and cluster `vmstorage` binaries share | High |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| `lib/storage` | Direct: drop happens here; new tracker field/wiring lives on `Storage` |
| `app/vmstorage` | Direct: flags, `OpenOptions` wiring, HTTP query/reset endpoint, metrics export |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `app/vmselect` / `app/vmselect/netstorage` | Ticket explicitly scopes out cluster vmselect query-path wiring; no tenant-aware network RPC needed |
| `lib/vmselectapi` | Network RPC protocol between cluster vmselect and vmstorage — explicitly out of scope per ticket ("does not need to be tenant-aware", "single-node and storage component only") |
| `app/vminsert` | Write path fan-in only; does not touch `lib/storage` limiter logic directly (goes through `common`/storage-facing cell per existing manifest) — no behavioral participation |
| `lib/bloomfilter` | Already-existing, unmodified dependency of the limiter itself (`hourlySeriesLimiter`/`dailySeriesLimiter`); the new work counts drops, it does not touch limiter admission logic — infrastructural-only for this task |
| `lib/mergeset` | Transitive dependency of `lib/storage`'s indexDB; no participation in cardinality-limit drop accounting | 

## Usage Relationships

| Usage | Relevance |
|---|---|
| `lib/storage/metricnamestats` tracker implementation (not a formal Import, no CODEMANIFEST/.usages of its own found) | Design reference only — same bounded-tracker shape (admission cap, `Reset`, `GetStats`-style query) but intentionally a separate, lower-coupling cell per ticket's data-model differences (no tenant keys, no persistence) |

## Semantic Participation Summary
- `lib/storage` participates because the drop event, the metric name, and the new tracker's lifecycle (construction in `MustOpenStorage`, increment in `registerSeriesCardinality`, exposure via new `Storage` methods, and `Metrics`/`UpdateMetrics` reporting) all live here. This is the cell whose CODEMANIFEST needs a new type entry for the tracker plus method-level additions to `Storage`.
- `app/vmstorage` participates because it is the sole place that both single-node and cluster-storage binaries share for (a) turning CLI flags into `storage.OpenOptions`, and (b) serving internal HTTP debug endpoints (`requestHandler`) and Prometheus-format metrics (`writeStorageMetrics`) — exactly the surface needed to satisfy "queryable" without touching the network RPC layer.
- No other cell has runtime, manifest, or data-flow participation in this specific drop-accounting feature.

## Final Investigation Scope
1. `lib/storage` (primary — new tracker type + `Storage` wiring)
2. `app/vmstorage` (primary — flags, wiring, HTTP endpoint, metrics)

## Scope Risks
- **Under-scoping risk**: if cluster vmselect-side querying is silently assumed unnecessary but a stakeholder later expects it, the feature would look incomplete for full cluster deployments — mitigated by ticket's explicit scope statement, which this report treats as authoritative.
- **Over-scoping risk**: pulling in `metricnamestats` as a dependency (Import) rather than a design reference could couple two cells with genuinely different data models (tenant-keyed + persisted vs. global + in-memory-only) — avoided by keeping it reference-only, per the ticket's explicit request for low coupling.

## Notes
- `lib/storage` is flagged in its own CODEMANIFEST as a "god package" with the widest blast radius in the repo — the new tracker will be added as a genuinely new, small, self-contained type declaration (new file) rather than modifying existing internal layers (table/partition/indexDB), keeping this change's actual blast radius small despite the cell's size.
- The new tracker will be implemented as a new Go file inside `lib/storage` (not a separate subpackage/cell) to avoid the ceremony of a brand-new CODEMANIFEST cell for a small, tightly-coupled-to-Storage type — consistent with "too fine" guidance in goga-cookbook (the tracker has no independent meaning outside `Storage`'s ingestion path). This will be finalized in the Planning step.
