# R06-TD-GC-04

Condition: goga_native_architecture
Base tag: condition-c-r06-v1
Functional success: True
Full architecture conformance: False
ACR: 0.6
Dangerous success: True
Goga engagement signal: False
Cost: $3.0622626
Duration: 567489ms, turns: 57

## Agent's own summary

# Investigation Report

## Task Summary
Requested: add a response cache to etcd's read path so that identical repeated `Range` requests (same key/range + options) issued shortly after one another skip the actual MVCC data scan, while guaranteeing no client ever observes data staler than an equivalent uncached read would have returned at request time — for both linearizable and serializable reads — with invalidation triggered by actual writes/deletes to the affected range rather than a fixed timer, and zero behavior change on cache misses. Scope resolution (Step 1) narrowed this to a single cell: `server/storage/mvcc`.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `server/storage/mvcc` | Owns the single convergence point for all reads (`storeTxnCommon.Range`) and all writes (`storeTxnWrite.End`); confirmed by tracing every call path into and out of `Range`/`Put`/`DeleteRange`. | High |

## Tracing Summary

**Read call graph** (all external callers converge on one point):
- `server/etcdserver/v3_server.go:149` `EtcdServer.Range` → `txn.Range(ctx, lg, s.KV(), r, true)` (`server/etcdserver/txn/range.go:53`) → `kv.Read(mvcc.ConcurrentReadTxMode, trace)` → `.Range(ctx, key, end, ro)`
- `mvcc.KV`'s embedded `ReadView` convenience (`server/storage/mvcc/kv_view.go:38-42`, `readView.Range`) also just calls `rv.kv.Read(ConcurrentReadTxMode, ...).Range(...)` — same destination.
- `store.Read(mode, trace)` (`kvstore.go:46-64`) returns a `*storeTxnRead` wrapped by `newMetricsTxnRead` (`metrics_txn.go:31-33`), which does **not** override `Range` — it delegates straight through to the embedded `storeTxnCommon.Range` (`kvstore_txn.go:69-71`).
- **`storeTxnCommon.Range` (`kvstore_txn.go:69-71`) is therefore the single, universal entry point for every read-only `Range` call in the system**, regardless of caller (gRPC Range/RangeStream, internal `txn.Count`, direct `KV.Range()`, etc.).
- Distinct and must **not** be touched: `storeTxnWrite.Range` (`kvstore_txn.go:189-195`) — used only by in-flight write transactions to read their own uncommitted state (e.g. Txn compare-ops, Put's "does this key already exist" lookup at `kvstore_txn.go:230`). It computes revision from `tw.beginRev`/`len(tw.changes)`, not the committed store revision, and caching it would leak uncommitted state.

**Write call graph** (all writers converge on one commit point):
- Raft-applied Put/DeleteRange/Txn → `apply` cell → `mvcc.KV.Write()` → `storeTxnWrite`, mutated via `.put()`/`.delete()` (`kvstore_txn.go:223-346`), each appending the changed `*mvccpb.KeyValue` (with its `Key`) to `tw.changes`.
- Lease-expiry deletion is wired directly to the same `s.Write(...)` (`kvstore.go:117`, `watchable_store.go:107`), confirmed — no separate path.
- Commit happens in `storeTxnWrite.End()` (`kvstore_txn.go:209-221`): if `len(tw.changes) != 0`, it takes `s.revMu.Lock()`, increments `s.currentRev`, then unlocks. This critical section is exactly what `store.Read()` (`kvstore.go:46-62`) synchronizes against via `s.revMu.RLock()` to snapshot `firstRev, rev := s.compactMainRev, s.currentRev` — i.e. **`revMu` is the existing happens-before boundary that already separates "read sees old revision" from "read sees new revision."**
- `watchableStoreTxnWrite.End()` (`watchable_store_txn.go:22-47`) wraps this: it computes watch events from `tw.Changes()`, then calls `tw.TxnWrite.End()` — which is the plain `storeTxnWrite.End()` above — inside `tw.s.mu.Lock()` (the watchable store's own separate mutex, for notify ordering). **Both the plain-store and watchable-store write paths converge on the same single `storeTxnWrite.End()` commit method** — confirmed no second/divergent commit path exists.

## Data Flow Analysis
1. A read request reaches `storeTxnCommon.Range(ctx, key, end, ro)` with a fixed `tr.Rev()` (the store's `currentRev` as snapshotted when `Read()` was called).
2. It calls `rangeKeys`, which does an in-memory B-tree lookup (`kvindex.Revisions`/`.Range`/`.CountRevisions`) plus, for the common non-`FastKeysOnly` path, one `tr.tx.UnsafeRange` + `proto.Unmarshal` **per key** (`kvstore_txn.go:126-148`) — this is the expensive "full read work" the task wants to avoid on repeat.
3. The `*mvcc.RangeResult` returned flows up to `executeRange` in `server/etcdserver/txn/range.go:59-84`, where **the caller directly mutates the returned data**:
   - `filterRangeResults`/`pruneKVs` (`range.go:110-123, 186-195`) reslices `rr.KVs` in place (`rr.KVs = rr.KVs[:j]`), shrinking/reordering the slice.
   - `sortRangeResults` (`range.go:125-154`) sorts `rr.KVs` in place via `Swap`.
   - `asembleRangeResponse` (`range.go:156-172`) does `rr.KVs = rr.KVs[:r.Limit]` **and, critically, `rr.KVs[i].Value = nil` when `r.KeysOnly` is set** — this mutates the pointed-to `*mvccpb.KeyValue` struct itself, not just the slice.
4. Today this is always safe because every uncached call to `rangeKeys` allocates brand-new `*mvccpb.KeyValue` objects via `proto.Unmarshal` (`kvstore_txn.go:141-148`) — nothing is ever shared across calls.

## Manifest Algorithm Analysis
`server/storage/mvcc/CODEMANIFEST`:
- `ReadView.Range` (kv.go): "Read `key`... per `ro`... If the requested revision has been compacted, returns an error." No caching semantics implied or precluded; contract is purely input→output.
- `WriteView.Put`/`DeleteRange`: "The returned rev is the current revision of the KV when the operation is executed... generates one event for each key delete/put in the event history." Confirms every write is individually observable/traceable via `Changes()` — this is exactly the mechanism (`tw.changes`) usable for precise invalidation.
- `HashStorage` (hash.go, per manifest): "Caches consistency-check hashes of the MVCC keyspace so repeated HashByRev calls for the same revision avoid recomputation" — direct architectural precedent within this same cell for a revision-keyed cache with an explicit `Store()` population method, confirming this pattern is idiomatic here.
- `watch_sync_states` usage: describes the synced/unsynced/victim watcher split reacting to write commits via `s.notify(rev, evs)` in `watchable_store_txn.go:44`. The new cache's invalidation hook (also reacting to the same write commit) must run independently of and not interfere with this notify call — confirmed they are structurally separate (notify operates on watch event delivery; cache invalidation would operate on `tw.changes` keys only).

## Affected Usages

| Usage | Cell | Classification | Reason |
|---|---|---|---|
| `watch_sync_states` | `server/storage/mvcc` | INDIRECTLY AFFECTED | New invalidation hook fires from the same write-commit point (`storeTxnWrite.End`) that watch notification uses, but is a separate, independent action — no change to watch delivery semantics, documented here to prevent future confusion between the two mechanisms. |
| `write_path` | `server/etcdserver` | NOT AFFECTED | Confirms Range still bypasses raft-log application and still calls `s.read.LinearizableReadNotify` before reading `KV` — unchanged, since caching is entirely inside `mvcc`, below this boundary. |

## Rejected Hypotheses

1. **"Cache at the `server/etcdserver` layer (in `txn.Range` or `EtcdServer.Range`)."** Rejected: would require re-deriving write-visibility signaling that `mvcc` already provides for free via `revMu`, and risks accidentally caching around/before the linearizability confirmation step. `mvcc` is the only place read-visibility and write-commit are already coordinated under one lock.
2. **"Skip `LinearizableReadNotify` (ReadIndex round-trip) for cache hits to save more load."** Rejected: `LinearizableReadNotify` is what guarantees a linearizable read observes all writes committed-before-request-start, including ones not yet applied to this node's local `mvcc` store. Skipping it for a cache hit would silently downgrade a linearizable request to serializable — a correctness violation of the explicit requirement. The manifest's `write_path` usage explicitly reserves this step as the linearizability boundary; only the "read KV directly" step after it is in scope for caching.
3. **"Key cache entries only on `pb.RangeRequest.KeysOnly`-derived `FastKeysOnly` plus dedupe more finely to avoid any object sharing."** Rejected as unnecessary once the deep-clone requirement (below) is adopted: `FastKeysOnly` is already part of `mvcc.RangeOptions` and thus already part of the natural cache key; the remaining aliasing hazard (`rr.KVs[i].Value = nil` mutating a shared object across a `KeysOnly=true` vs `KeysOnly=false` request that both hash to the same non-`FastKeysOnly` `mvcc.RangeOptions`) is fully resolved by cloning on every hit, not by further key fragmentation.
4. **"Cache before `store.Read()` opens its backend transaction, to also save that cost on a hit."** Deferred, not rejected outright, but out of scope: would require restructuring `Read()`'s transaction lifecycle to be lazy, touching `TxnRead`'s contract (`Rev()`/`FirstRev()` must work without a prior `Range()` call) for a comparatively small additional saving (opening `ConcurrentReadTx()` is a small buffer-copy, not the expensive part — the expensive part is the per-key backend `UnsafeRange`/`proto.Unmarshal` in `rangeKeys`, which the chosen hook point already fully avoids on a hit). Keeping the hook inside `storeTxnCommon.Range` avoids touching `Read()`'s lifecycle and keeps the change minimal and self-contained.

## Confirmed Root Cause
Not applicable in the bug-fix sense (this is a feature addition), but the confirmed **design/root implementation point** is:
- **Cache lookup/populate hook:** `storeTxnCommon.Range` (`kvstore_txn.go:69-71`) — the sole convergence point for all read-only `Range` calls, gated to `ro.Rev <= 0` (current-revision reads only, to avoid taking on compaction-driven invalidation as a second dimension) and keyed on `(key, end, ro)` plus the transaction's snapshot revision `tr.Rev()`.
- **Cache invalidation hook:** inside `storeTxnWrite.End()` (`kvstore_txn.go:209-221`), within the existing `if len(tw.changes) != 0 { s.revMu.Lock(); ... }` critical section — using `tw.changes` (already populated with every changed key by `put`/`delete`) to evict/mark-invalid any cached entry whose `[key, end)` range contains a changed key, **before** `s.revMu.Unlock()`. This placement is what makes invalidation atomic with revision visibility: no reader can observe the bumped `currentRev` without also having the corresponding cache invalidation already visible (both are protected by the same `revMu` critical section), and this holds identically for the plain `store` and `watchableStore` write paths since both converge on this one `End()`.
- **Critical correctness requirement discovered by tracing consumers, not just producers:** `server/etcdserver/txn/range.go`'s `filterRangeResults`, `sortRangeResults`, and `asembleRangeResponse` all mutate the `*mvcc.RangeResult` returned by `Range` **in place** — including `rr.KVs[i].Value = nil` on the pointed-to `*mvccpb.KeyValue` struct itself (`range.go:167`), and reslicing/reordering `rr.KVs`'s backing array. Today this is harmless because every call returns freshly unmarshaled objects. **A cache hit must therefore return a fully independent deep copy** (new `*RangeResult`, new `[]*mvccpb.KeyValue` slice, new `*mvccpb.KeyValue` structs) — never the cached objects themselves — or a `KeysOnly` request would corrupt the cached value for every subsequent non-`KeysOnly` hit on the same entry (a serious, silent data-corruption bug, not merely a staleness one).
- **Reusable existing primitive for range-overlap matching:** `go.etcd.io/etcd/pkg/v3/adt.IntervalTree` (used identically for this exact purpose in `watcher_group.go:153,161,175,190,207,275` to match a changed key against registered watch ranges via `.Stab(adt.NewStringAffinePoint(key))`; also offers `NewBytesAffineInterval`/`NewBytesAffinePoint` for `[]byte` keys directly, avoiding string conversion). Available for the invalidation index if the planner chooses a tree-based structure; a plain guarded map with linear-scan overlap checks is also viable given the cache is expected to hold few entries (hot repeated reads), and the planner should choose based on simplicity given expected small cache size — noted as an open implementation decision, not a blocking ambiguity.

## Confidence Level
**HIGH** — every hook point, lock boundary, and the mutation-aliasing hazard are confirmed with concrete file:line evidence from the actual implementation (not inferred from the CODEMANIFEST alone), and both the read-side and write-side call graphs were traced to their single convergence points with no unresolved branches.

## Breaking Change Assessment
1. **Will existing function call with same arguments produce different behavior?** NO — cache misses call the exact unmodified `rangeKeys` path; cache hits return a deep clone with identical `KVs`/`Rev`/`Count` content to what a fresh call would produce, contingent on the deep-clone and revMu-atomic-invalidation requirements above being implemented (both are prescriptive requirements for the Planner/Implementer, not optional).
2. **Will existing file paths change?** NO — new cache logic lands in new file(s) within `server/storage/mvcc/`; no existing declared `location:` in the CODEMANIFEST changes.
3. **Will output format change?** NO.
4. **Will return value semantics change?** NO, given the deep-clone requirement (`RangeResult.Rev` on a hit reflects the snapshot revision at which it was populated, identical semantics to today's "revision of the store at the time the range was executed" for that same transaction snapshot).
5. **Will manifest-defined guarantees be altered?** NO — `ReadView.Range`, `WriteView.Put`/`DeleteRange` contracts are unchanged; this is an internal, transparent optimization. Recommend (not required) adding a brief `Algorithm:` note to these methods' annotations in Step 7 documenting the new internal caching/invalidation behavior, since it is now part of how the cell achieves its contract even though the contract's input/output shape doesn't change.
6. **Will existing tests break?** Not expected if the above requirements are honored, but this cannot be fully confirmed without running the existing `server/storage/mvcc` test suite (`store_test.go`, `kvstore_txn`-adjacent tests, watch tests) after implementation — flagged for the Testing step (Step 6) rather than assumed.

**No YES answers → not a breaking change. Pipeline may proceed to Planning.**
