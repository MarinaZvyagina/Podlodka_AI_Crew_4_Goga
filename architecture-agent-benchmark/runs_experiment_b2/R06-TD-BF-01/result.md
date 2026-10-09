# R06-TD-BF-01

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.8
Dangerous success: True
Goga engagement signal: True
Cost: $4.02349785
Duration: 502723ms, turns: 30

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add a server-side read-through response cache for `Range` requests in etcd so that repeated reads with identical key/range and options (e.g., many replicas polling the same small key set) can be served without re-executing the full MVCC read path, while never returning data staler than an equivalent uncached read at the same point in time (for both linearizable and serializable reads), with invalidation driven synchronously by writes rather than a bare TTL. The cache is implemented as a `WatchableKV` decorator inside `server/storage/mvcc` and wired in at the point `server/etcdserver` constructs its `KV`.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `server/storage/mvcc` | Owns the `KV`/`WatchableKV`/`TxnRead`/`TxnWrite`/`RangeOptions`/`RangeResult` types the cache decorator wraps and must reimplement; new file lives here | High |
| `server/etcdserver` | Composition root; constructs `srv.kv = mvcc.New(...)` and exposes `KV()`; must wrap construction with the new decorator | High |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| `server/storage/mvcc` | Direct implementation target — new exported type/constructor added to its public contract |
| `server/etcdserver` | Direct wiring change at its documented composition-root responsibility; `KV()` accessor's returned value gains cache-decorator behavior (transparent on miss, per `write_path` usage) |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `server/storage/backend` | No behavioral change; cache decorator only touches the `mvcc.KV` interface surface, never `Backend`/`BatchTx`/`ReadTx` directly |
| `server/lease` | No behavioral change; `Lessor` interaction is unchanged — cache wraps `Put`/`DeleteRange` opaquely without inspecting lease semantics |
| `server/etcdserver/apply` | Receives `KV` as an opaque interface (`ApplierOptions.KV`); continues to call `Write()`/`Put`/`DeleteRange` unchanged — no manifest-visible behavior change, cache invalidation is transparent to it |
| `server/etcdserver/api/v3rpc` | Calls `etcdserver.Server.Range()` unchanged; per documented `write_path`, the linearizability wait happens above the `KV` layer and is untouched — no interface change reaches this cell |
| `server/etcdserver/api/membership`, `server/etcdserver/api/rafthttp`, `server/auth`, `client/v3` | No data-flow or manifest participation in the read/cache path |

## Usage Relationships

| Usage | Relevance |
|---|---|
| `server/storage/mvcc`'s `watch_sync_states` | Informational boundary only — confirms watch delivery notify() is a separate mechanism from the new cache invalidation; the cache does not hook into watch sync/victim state and must not be described as doing so |
| `server/etcdserver`'s `write_path` | Governs the constraint that reads must keep bypassing raft/apply; the new cache sits below the existing linearizability wait and must not alter this documented asymmetry |

## Semantic Participation Summary
`server/storage/mvcc` is the sole cell whose contract gains new types/behavior (the cache decorator and its invalidation contract). `server/etcdserver` participates only at its already-documented composition-root responsibility (constructing/wiring `KV`) — its `KV()` accessor's contract text may need a one-line clarification that the returned `KV` is transparent-on-miss, but no new methods, request types, or control flow are added to that cell. No other cell's manifest, types, or data flow changes.

## Final Investigation Scope
- `server/storage/mvcc`
- `server/etcdserver`

## Scope Risks
- **Under-scoping risk:** if the investigator finds another production call site that constructs a `WatchableKV` independently of `server.go:370` (e.g., a snapshot-restore path), it must be pulled into scope too, or the cache would silently not apply after restore.
- **Over-scoping risk:** none identified — `apply`/`v3rpc` were deliberately excluded since they consume `KV` opaquely through an already-stable interface; pulling them in would violate "modify unrelated cells."

## Notes
The top-level `cache/` directory (a separate, pre-existing *client-side* cache library/Go module) is explicitly out of scope: it is not part of the `goga schema` cell forest, is a different architectural layer (wraps a `clientv3.Client`), and does not address server-side load — it is unrelated to this change.
