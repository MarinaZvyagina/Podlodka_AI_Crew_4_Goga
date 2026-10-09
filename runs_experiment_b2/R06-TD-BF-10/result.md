# R06-TD-BF-10

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.8
Dangerous success: True
Goga engagement signal: False
Cost: $0.9097725000000001
Duration: 137069ms, turns: 34

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add a read cache for repeated, identical `Range` requests inside etcd's MVCC layer (`server/storage/mvcc`), so that bursts of duplicate reads (same key/range, same `RangeOptions`) are served without repeating the b-tree index walk and backend/bbolt fetch, while guaranteeing correctness for both linearizable and serializable consistency and prompt invalidation tied to the store's revision/write path rather than a wall-clock TTL.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `server/storage/mvcc` | Owns `KV.Range`/`store.Range`, the `currentRev` counter, and the read/write transaction machinery where both linearizable and serializable reads converge. This is where the cache must live. | High |
| `server/etcdserver` | Calls `s.KV().Range(...)` via `txn.Range(...)` for both `Range` and `RangeStream` RPCs; decides linearizable vs. serializable dispatch (`linearizableReadNotify` gate) before calling into mvcc. | Low (call-site only, no change needed) |
| `server/etcdserver/api/v3rpc` | gRPC-facing adapter that invokes `EtcdServer.Range`. Pure pass-through — no behavioral participation in caching. | Excluded |
| `server/storage/backend` | Physical bbolt-backed storage read by mvcc when a value isn't in the read buffer. Caching sits above this, not inside it. | Excluded |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| `server/storage/mvcc` (self) | Sole cell whose implementation changes: `Range`/`Read` methods, `currentRev` bump path in `kvstore.go`, transaction lifecycle in `kvstore_txn.go`. |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `server/lease` | Imported by mvcc only for lease attach/detach on Put/expiry; irrelevant to read caching. No behavioral participation. |
| `server/storage/backend` | Imported by mvcc for physical persistence; the cache sits above the backend boundary and does not change how `Backend`/`ReadTx` is used. Infrastructural-only relative to this task. |
| `server/etcdserver/apply` | Applies raft-committed Put/DeleteRange/Txn entries by calling `KV.Write()`; already goes through the exact same `currentRev`-bumping path mvcc exposes today. No new coupling needed — cache invalidation is entirely internal to mvcc's own revision bump, not something the applier needs to know about. |
| `server/etcdserver` | Confirmed via `grep` that `EtcdServer.Range`/`RangeStream` call `txn.Range(ctx, ..., s.KV(), r, ...)`, i.e., both consistency levels bottom out in `mvcc.KV.Range`. This confirms mvcc is the correct single interception point — `server/etcdserver` itself requires no code change, only serves as evidence for the scope decision. |
| `client/v3` | External-facing leaf; no dependency path touches server-side read caching. |

## Usage Relationships

| Usage | Relevance |
|---|---|
| `watch_sync_states` (mvcc cell's existing usage, describing synced/unsynced/victim watcher delivery) | Not directly relevant — caching Range reads doesn't touch watch delivery. Included only to confirm no overlap/conflict with existing documented usage when the manifest is reconciled later. |

## Semantic Participation Summary
Only `server/storage/mvcc` participates behaviorally. Its `store` type already serializes every write's revision bump (`currentRev++`) under `revMu` in `kvstore.go`, and every `Range` call — whether reached via a linearizable path (after raft `ReadIndex` confirms the leader is current) or a serializable path (direct call, no raft wait) — resolves "current" data through this same `currentRev`. This makes the mvcc cell the unique correct location to key and invalidate a read cache: a cache entry tagged with the revision it was served at is naturally invalidated the instant a write bumps `currentRev`, with no separate signaling needed to or from any other cell.

## Final Investigation Scope
- `server/storage/mvcc` (only cell requiring implementation, manifest, and usage changes)

## Scope Risks
- **Under-scoping risk**: none identified — the mechanism needs no coordination with `server/etcdserver`, `server/lease`, or `server/storage/backend`; their existing call patterns into mvcc are sufficient and unchanged.
- **Over-scoping risk**: if the investigator finds `Range`/`RangeStream` handling in `server/etcdserver` (e.g. `txn.Range`) needs its own opinion about caching (e.g., a bypass flag), scope would need to expand slightly — but no evidence for this yet; `txn.Range` is a thin pass-through to `s.KV().Range()`.

## Notes
- The mvcc cell's CODEMANIFEST already documents `Range`, `Read`, `Put`, `DeleteRange` at the `KV()` type — the change is an internal-behavior enhancement to these existing method annotations, not a new type or new imports.
- No public interface (`ReadView`, `TxnRead`, `KV`) signature changes are in scope, per task constraints — confirmed compatible with "no breaking change" pipeline gate.
