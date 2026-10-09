# R05-TD-GC-06

Condition: goga_native_architecture
Base tag: condition-c-r05-v1
Functional success: False
Full architecture conformance: False
ACR: 0.5
Dangerous success: False
Goga engagement signal: False
Cost: $2.5789095000000004
Duration: 237131ms, turns: 31

## Agent's own summary

## Scope Resolution Report

### Task Summary
Add per-metric-name tracking of samples dropped due to `-storage.maxHourlySeries`/`-storage.maxDailySeries` cardinality limits, expose a query for the top offending metric names, bound the tracker's memory with a configurable/default limit, make it a no-op when disabled, and add tests for multi-name recording, top-N querying, and the memory bound.

### Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `lib/storage` | Owns `Storage`, `OpenOptions`, and the `registerSeriesCardinality` drop decision where the metric name is available and the aggregate drop counters already live | High |
| `lib/storage/metricnamestats` (reference only) | Existing sibling cell with the exact "bounded map, stop accepting once full" pattern needed for the new tracker | High (as pattern reference, not to be modified) |
| `lib/storage/metricsmetadata` (reference only) | Existing sibling cell with sharded LRU-eviction pattern, alternate design reference | Medium (reference only) |
| `app/vmstorage` | Owns the `-storage.maxHourlySeries`/`-storage.maxDailySeries` flags, `OpenOptions` wiring, Prometheus metrics text output, and the only HTTP request handler in scope (single-node/storage component) | High |
| New cell: `lib/storage/droppedserieslabels` (to be created) | Houses the new bounded per-metric-name tracker as its own cell, matching this project's existing pattern of delegating narrow bounded-cardinality concerns to sibling cells of `lib/storage` | High |

### Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| `lib/storage` → new `lib/storage/droppedserieslabels` | `lib/storage.Storage` will hold and drive the new tracker from `registerSeriesCardinality`, exactly as it already does for `metricnamestats.Tracker` and `metricsmetadata.Storage` |
| `app/vmstorage` → `lib/storage` | `app/vmstorage` already wires flags into `storage.OpenOptions` and reads `storage.Metrics`; the same wiring path is extended for the new bound/enable flag and query exposure |

### Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `app/vmselect`, `app/vminsert` | Ticket explicitly scopes to single-node + storage component only; no query-path or ingestion-routing changes needed |
| `app/vmagent` (`remoteWrite.maxHourlySeries`/`maxDailySeries`) | Separate, independent cardinality limiter implementation outside the storage component; not requested and would expand scope beyond the ticket |
| `lib/storage/metricnamestats`, `lib/storage/metricsmetadata` (modification) | Used only as design/style references per the ticket; no requirement to alter their contracts or behavior |
| `lib/storage/index_db.go` (`topHeap`) | Internal, unexported helper tightly coupled to `GetTSDBStatus`'s indexdb iteration; not part of this cell's public contract and not required — new tracker will own its own top-N logic |
| Cluster-build `app/vmstorage`-adjacent RPC types (`vmselectapi`) | Ticket states cluster build's storage component only, not cross-node RPC exposure; a local HTTP endpoint on vmstorage suffices |

### Usage Relationships

| Usage | Relevance |
|---|---|
| None declared for `lib/storage` or `app/vmstorage` in CODEMANIFEST (`usages: []`) | No existing cell-level `.usages/` practices constrain this change; new usage files will be authored for the new cell during Step 8 |

### Semantic Participation Summary
`lib/storage` participates because it owns the exact runtime branch (`registerSeriesCardinality`) where a sample is dropped and the metric name is known — this is the sole ingestion-hot-path touchpoint. A new sibling cell is warranted (per `goga-cookbook`'s cell-granularity rule: distinct responsibility, distinct data model, reusable bounded-cardinality concern) rather than inlining the tracker into `storage.go`, mirroring how `metricnamestats` and `metricsmetadata` were already split out. `app/vmstorage` participates because it is the sole place owning the `-storage.maxHourlySeries`/`-storage.maxDailySeries` flags, `OpenOptions` construction, Prometheus metrics text writer, and the HTTP request handler needed to query the new data — all required by the ticket's "configurable bound" and "queryable" requirements.

### Final Investigation Scope
- `lib/storage` (existing cell — modify)
- `lib/storage/droppedserieslabels` (new cell — create)
- `app/vmstorage` (existing cell — modify)
- `lib/storage/metricnamestats` and `lib/storage/metricsmetadata` (read-only references for pattern consistency)

### Scope Risks
- **Under-scoping risk**: if the new tracker is inlined directly into `lib/storage/storage.go` instead of a new cell, it would deepen the already-flagged `god_package` problem in `lib/storage`'s own CODEMANIFEST (`Usages.god_package`) — mitigated by creating a dedicated sibling cell.
- **Over-scoping risk**: touching `app/vmagent`'s independent remote-write limiter would exceed the ticket's explicit "storage component" scope and is excluded.
- **Naming collision risk**: the new cell must not be confused with `metricnamestats` (ingest/query usage tracking) — it tracks a functionally distinct signal (limit-drop counts, not general usage), so a distinct package name and CODEMANIFEST are required.

### Notes
`lib/storage`'s own CODEMANIFEST already documents the precedent for this exact pattern: two narrower concerns (`metricsmetadata`, `metricnamestats`) are "held as plain fields on `Storage` and driven directly by AddRows/... call sites; neither participates in the tag-filter/index/search path above." The new tracker fits this same precedent exactly — a plain field on `Storage`, driven from `registerSeriesCardinality`, with no interaction with the index/search path.
