# R06-TD-BF-08

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.4
Dangerous success: False
Goga engagement signal: True
Cost: $3.4641336
Duration: 774241ms, turns: 57

## Agent's own summary

# Investigation Report

## Task Summary
Add caching to `server/storage/mvcc` so repeated `Range` reads with identical parameters are served without redoing the full kvindex/backend read, while guaranteeing (a) no client ever observes data staler than a live uncached read would have returned at request time — for both linearizable and serializable consistency — and (b) writes/deletes affecting a cached range invalidate it promptly rather than via a bare TTL, and (c) cache misses behave exactly as today.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `server/storage/mvcc` | Sole implementation target — owns `currentRev`/`revMu`, `storeTxnRead.Range`, `storeTxnWrite.End` | Primary |
| `server/etcdserver` | Verification-only: confirms `EtcdServer.Range` (v3_server.go:106-155) already funnels both `Serializable` and non-`Serializable` requests through the identical `txn.Range(ctx, s.Logger(), s.KV(), r, true)` call (line 149) after `LinearizableReadNotify` resolves (lines 138-144) — no code change needed here | Secondary |

## Tracing Summary
See Trace Report above (goga-change-tracer output). Key finding confirmed directly from `v3_server.go:106-155`: the linearizable/serializable branch (`if !r.Serializable { s.read.LinearizableReadNotify(ctx) }`) always completes *before* `txn.Range` is invoked, for both branches. Any cache consulted inside `txn.Range`'s downstream call (`mvcc.KV.Read(...).Range(...)`) therefore automatically inherits whichever consistency guarantee the caller already established — a linearizable request only reaches the cache-check after ReadIndex confirmation, a serializable request reaches it immediately. This is the structural reason placing the cache inside `server/storage/mvcc`, below this branch point, satisfies the "never staler for either consistency level" requirement without touching `server/etcdserver` at all.

## Data Flow Analysis
See Trace Report "Data Flow" section. The two load-bearing facts:
1. `*mvccpb.KeyValue` pointers returned in `RangeResult.KVs` are mutated in place by the caller (`txn/range.go:166-167`, `rr.KVs[i].Value = nil` for `KeysOnly`) — any cached copy must be deep-cloned on both store and retrieve to avoid cache corruption.
2. `s.currentRev`/`s.revMu` is the only existing point where read-snapshot revision and write-commit revision are synchronized — reusable as the race-fence for cache population, avoiding a new counter/lock.

## Manifest Algorithm Mapping
`server/storage/mvcc`'s CODEMANIFEST documents `KV.Range`/`KV.Read`/`KV.Write` purely by contract ("point-in-time reads ... over the revisioned key space"), per DSL rule that the specification "does not prescribe *how* to implement the code — only the expected contract." Internal caching is implementation detail not requiring a CODEMANIFEST edit, since no exported type/method signature changes and the point-in-time guarantee is preserved exactly (see Confirmed Root Cause below).

## Affected Usages

| Usage | Cell | Classification | Reason |
|---|---|---|---|
| `watch_sync_states` | `server/storage/mvcc` | NOT AFFECTED | Describes watcher synced/unsynced/victim classification for the watch subsystem; the planned change touches `storeTxnRead.Range` and `storeTxnWrite.End` only — it does not add, remove, or reclassify watchers, and does not touch `notify()`/`syncWatchers()`. |

No other usages exist for this cell (no `.usages/` directory present); no usages exist for `server/etcdserver` relevant to `Range` staleness semantics.

## Rejected Hypotheses

| Hypothesis | Evidence for rejection |
|---|---|
| Cache should live in `server/etcdserver/txn` (above mvcc), keyed on `pb.RangeRequest` | Rejected: would require a separate, newly-invented synchronization primitive to fence cache-population races against writes, since `txn` package has no access to `s.currentRev`/`s.revMu`. mvcc already owns the exact primitive needed (`revMu`), making a same-cell solution strictly simpler and race-free by construction. |
| A background watch-stream consumer can drive invalidation asynchronously | Rejected: `notify()` pushes to a buffered channel; a consumer goroutine draining it runs with a Go-scheduler-dependent delay relative to `End()` returning. This reopens exactly the race the task explicitly forbids ("relying on a short fixed expiration timer alone... is not acceptable" — the async-watch approach has the identical failure mode: a write can commit and return to its caller before invalidation is actually processed, letting a causally-later read observe stale cached data). Synchronous invalidation inside `End()`, under `revMu`, closes this gap. |
| Cache the `storeTxnWrite.Range` (embedded range-within-txn) path too | Rejected: that path must observe this txn's own uncommitted in-flight changes (Txn compare-and-swap / embedded range ops); it already has its own override (`kvstore_txn.go:189-195`) distinct from `storeTxnCommon.Range`. Caching it would risk serving cross-request-visible data for what must be txn-local, uncommitted state. Excluded from scope. |
| Return the cached entry's originally-stored `Rev` field on a hit | Rejected: would violate revision-monotonicity clients rely on (a live read at the current moment always reports `Header.Revision = tr.Rev()`, i.e. the store's revision *at the time of this read*, regardless of whether the specific queried key was the most recently modified key overall). Fix: always stamp `Rev` fresh from the serving read-txn's own `tr.Rev()`, both on hit and miss; do not persist/reuse the revision captured at population time for the response header. |

## Confirmed Root Cause
Not a bug fix — this is a new capability. Root requirement: repeated bursts of identical `Range` reads redo full kvindex+backend work with no way to short-circuit when nothing relevant has changed. Evidence chain: `rangeKeys` (kvstore_txn.go:73-152) always performs `kvindex.Revisions`/`kvindex.Range` plus, for non-`FastKeysOnly`, an `UnsafeRange` + `proto.Unmarshal` backend round-trip per key on every call, with no memoization at any layer between `v3rpc.Range` and here.

## Confidence Level
**HIGH** — every claim above is backed by direct file:line evidence from the current HEAD (`kvstore_txn.go`, `kvstore.go`, `kv.go`, `kv_view.go`, `metrics_txn.go`, `watchable_store.go`, `watchable_store_txn.go`, `v3_server.go`, `txn/range.go`), read directly rather than inferred, including confirmation of the mutation-sharing hazard (`rr.KVs[i].Value = nil`) and the exact locking sequence around `currentRev`/`revMu`.

## Breaking Change Assessment
1. **Will existing function call with same arguments produce different behavior?** NO — cache misses execute the identical `rangeKeys` codepath unchanged; cache hits return content-identical `RangeResult`s (same KVs, same Count, freshly-stamped `Rev` matching what a live read would report at that instant), only via a faster path.
2. **Will existing file paths change?** NO — new file `server/storage/mvcc/read_cache.go` added; existing files (`kvstore_txn.go`, `kvstore.go`) modified in place, no renames/moves.
3. **Will output format change?** NO — `RangeResult`/`pb.RangeResponse` shapes are unchanged.
4. **Will return value semantics change?** NO — see point 1; point-in-time read semantics documented in CODEMANIFEST are preserved exactly, including for pinned-revision reads (`ro.Rev > 0`), which are forced cache misses (unchanged path) by design.
5. **Will manifest-defined guarantees be altered?** NO — "point-in-time reads ... over the revisioned key space" holds; no exported type signature (`KV`, `WatchableKV`, `WatchStream`, `New`) changes.
6. **Will existing tests break?** NO (to be confirmed empirically in Step 6/Testing) — the change is additive and internal; existing tests exercise `Range`/`Write`/`Read` through the same public interfaces with the same expected outputs. Will run the full `server/storage/mvcc` test suite plus `server/etcdserver` integration tests to confirm empirically before calling this final.

**No breaking change detected.** Proceeding is appropriate.
