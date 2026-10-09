# R06-TD-GC-08

Condition: goga_native_architecture
Base tag: condition-c-r06-v1
Functional success: True
Full architecture conformance: False
ACR: 0.6
Dangerous success: True
Goga engagement signal: False
Cost: $6.212274450000001
Duration: 1029089ms, turns: 76

## Agent's own summary

## Summary

I added a read cache for repeated identical `Range` requests, scoped entirely inside `server/storage/mvcc` (5 files: `read_cache.go` new, `kvstore.go`, `watchable_store_txn.go`, `CODEMANIFEST`, plus `read_cache_test.go`):

**Where it sits:** `WatchableKV.Read()` now returns a wrapping `TxnRead` that caches current-revision (`Rev==0`) `Range` results, keyed by the exact key/end/options. Because every read path — serializable *and* linearizable, plus `Range` calls made from within read-only `Txn` — funnels through this same `Read()`, one cache correctly serves all of them without needing to special-case consistency levels. Internal write-path range lookups (`Write()`'s embedded reads used by `Put`/`DeleteRange`/`Txn` mutation logic) are untouched since they never go through `Read()`.

**Why it's never stale:** invalidation happens synchronously in `watchableStoreTxnWrite.End()`, in the exact same critical section that already finalizes a write's revision bump (before it becomes visible to any new reader). So by the time a linearizable read is unblocked (after `ReadIndex` confirms the write is applied) or a serializable read runs, any write it must observe has already invalidated the relevant cache entries — a hit is guaranteed at least as fresh as a fresh scan would have been. A snapshot `Restore` clears the whole cache inside the same lock that already serializes it against concurrent reads.

**Precision:** invalidation checks each cached entry's key range against the exact keys a commit touched, so a write to one key only evicts cache entries whose range could have observed it — an unrelated write elsewhere in the keyspace doesn't wipe the cache. Cache is bounded (LRU, capacity 4096) and hits/misses are isolated with cloned data so no caller mutation (e.g. `KeysOnly` stripping) can corrupt cached or concurrently-served copies.

Verified with `go build ./...`, `go vet`, and `go test` (including `-race`) across `server/storage/mvcc`, `server/etcdserver/txn`, and `server/etcdserver/read` — all pass, plus new tests covering cache hits/misses, precise vs. broad invalidation, isolation, LRU eviction, historical-read exclusion, and restore-clears-cache.
