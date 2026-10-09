# R06-TD-GC-06

Condition: goga_native_architecture
Base tag: condition-c-r06-v1
Functional success: True
Full architecture conformance: False
ACR: 0.6
Dangerous success: True
Goga engagement signal: False
Cost: $3.6288207000000003
Duration: 639886ms, turns: 49

## Agent's own summary

## Change Plan

### Task Classification
**Feature** (additive, purely internal to one cell — no exported API surface changes).

### Affected Cells
| Cell | Files to Modify | What Changes |
|---|---|---|
| `server/storage/mvcc` | `kvstore.go` (new unexported cache field + default-size var on `store`, init in `newStore`/wherever `store{}` is constructed, clear-on-`Restore`), `kvstore_txn.go` (cache lookup/populate in `storeTxnCommon.Range`; invalidation call in `storeTxnWrite.End`), new file `range_cache.go` (new unexported `rangeCache` type: lookup, insert, invalidate-by-key, invalidate-by-compact-rev, clear; uses `adt.IntervalTree` from `go.etcd.io/etcd/pkg/v3/adt`, already an indirect dependency of this cell via `watcher_group.go`) | Add an in-memory, bounded, unexported read-cache to `store`; wire it into the three existing write/compact/restore choke points. No new files outside this cell. |

No other cell is touched.

### Root Cause Analysis
Every `Range` call — including exact duplicates issued moments apart by different client replicas — unconditionally re-executes `rangeKeys` (`kvstore_txn.go:73`), walking the in-memory `treeIndex` and, unless `CountOnly`/`FastKeysOnly`, re-reading and re-unmarshalling matching values from the boltdb backend. No de-duplication or caching exists anywhere on the read path today (only the unrelated `LinearizableReadLoop` batches the raft *ReadIndex* round-trip, not the data read).

### Trace Summary
`v3rpc.kvServer.Range` → `EtcdServer.Range` (linearizability barrier via `s.read.LinearizableReadNotify` for non-serializable requests, `v3_server.go:138-144`) → `doSerialize` (auth check, unconditional) → `txn.Range` → `kv.Read(...).Range(...)` → **[new cache check here]** `storeTxnCommon.Range` (`kvstore_txn.go:69`) → on miss, unchanged `rangeKeys`. Write commit funnels through the single choke point `storeTxnWrite.End()` (`kvstore_txn.go:209`, shared by both `store` and `watchableStore` since the latter's `End()` delegates via the embedded `TxnWrite`) — **[new invalidation call here]** using `tw.changes` (exact changed keys). Compaction (`store.Compact`, `kvstore.go:272`) and Restore (`store.Restore`, `kvstore.go:292`, reuses the same `*store` instance in place) are the other two invalidation triggers.

### Change Strategy
1. **New unexported type `rangeCache`** (`server/storage/mvcc/range_cache.go`):
   - Internal storage: a `map[rangeCacheKey]*rangeCacheEntry` for the "current-revision" bucket, plus a separate `map[rangeCacheKey]*rangeCacheEntry` for the "explicit historical revision" bucket (key includes the revision) — kept distinct since their invalidation rules differ (overlap-based vs. compaction-based).
   - `rangeCacheKey` = a comparable struct: `{key, end string; limit int64; countOnly, fastKeysOnly, withTotalCount bool; rev int64 /* 0 for current bucket, explicit for historical bucket */}`. `[]byte` fields converted to `string` for map-key comparability (no allocation surprises beyond the existing conversions already done elsewhere in this package).
   - `rangeCacheEntry` = `{kvs []*mvccpb.KeyValue; count int}` (no `Rev` field stored — `Rev` is always reconstructed by the caller from `tr.Rev()`, never cached, per Investigation point 2).
   - An `adt.IntervalTree` (reusing the package's existing dependency, already used identically in `watcher_group.go` for key-range overlap) indexes **current-bucket** entries by their `[key,end)` span, enabling `invalidate(changedKey []byte)` to find and evict all overlapping entries in one `Stab` query instead of a linear scan.
   - `get`/`put` methods return/accept **deep copies**: `put` clones each `*mvccpb.KeyValue` via `proto.Clone` before storing; `get` clones again before returning, so the caller can safely hand the result to `asembleRangeResponse`'s in-place mutation (`Value = nil` for `KeysOnly`) without corrupting the cache, and two concurrent callers of the same entry never share mutable state.
   - A bounded size (new unexported `var defaultRangeCacheSize = 10000` package-level var, following the exact existing pattern of `defaultCompactionBatchLimit`/`defaultCompactionSleepInterval`) with simple FIFO/oldest-eviction once the cap is hit — not exposed via `StoreConfig` (see Specification Impact below).
   - Own `sync.Mutex` guarding all map/tree access — independent of `s.mu`/`s.revMu`.

2. **`store` struct** (`kvstore.go`): add one unexported field `rangeCache *rangeCache`, initialized wherever `&store{...}` is constructed (`NewStore`/`newStore` — single constructor path per Investigation). `Restore` (`kvstore.go:292`, already under `s.mu.Lock()` for its full duration) gets one added line: `s.rangeCache.clear()`, alongside the existing `s.kvindex = newTreeIndex(...)` reset.

3. **`storeTxnCommon.Range`** (`kvstore_txn.go:69`): before calling `tr.rangeKeys(...)`, compute the cache key from `(key, end, ro)` and `tr.Rev()` and check `tr.s.rangeCache`. On hit: return `&RangeResult{KVs: <deep-copied clone>, Count: cached.count, Rev: tr.Rev()}, nil` — skipping `rangeKeys` entirely. On miss (or on `ro.Rev>0` where `ro.Rev>curRev`/`< compactMainRev`, i.e. any error): call `rangeKeys` unchanged; on a **successful, non-error** result, populate the cache before returning. `storeTxnWrite.Range` (`kvstore_txn.go:189`) is untouched — it already bypasses `storeTxnCommon.Range` by overriding the method, so no write-transaction Range call ever touches the cache, avoiding any risk of caching uncommitted data.

4. **`storeTxnWrite.End`** (`kvstore_txn.go:209`): when `len(tw.changes) != 0`, before `tw.tx.Unlock()` makes the write visible, call `tw.s.rangeCache.invalidateKeys(tw.changes)` — for each changed `*mvccpb.KeyValue.Key`, evict every current-bucket entry whose `[key,end)` span contains it (via the `IntervalTree`). Historical-bucket entries are untouched by writes (immutable data, per Investigation point 4).

5. **`store.Compact`** (`kvstore.go:272`): inside the existing `s.mu.Lock()` section (alongside `updateCompactRev`), after `compactMainRev` is updated, call `s.rangeCache.invalidateBelow(newCompactMainRev)` to evict historical-bucket entries whose revision is now compacted away (so a cache hit never returns success for data a fresh read would report `ErrCompacted` for).

### Specification Impact
**None.** No `CODEMANIFEST` in `server/storage/mvcc` (or any other cell) requires a new entry: `rangeCache`, `rangeCacheKey`, `rangeCacheEntry` are unexported implementation details of the `store` type, not new exported types. `StoreConfig`'s documented properties (`CompactionBatchLimit`, `CompactionSleepInterval`) are unchanged — the cache size cap is a package-internal `var` (mirroring the existing `defaultCompactionBatchLimit` pattern), not a new exported config knob, to keep this change's public surface at zero and avoid expanding the `StoreConfig` contract for a first version. `KV`, `RangeOptions`, `RangeResult`, `ReadView`, `WriteView`, `TxnRead`, `TxnWrite`, `WatchableKV`, `New`, `NewStore` — all unchanged.

### Usage Impact
**None.** No `.usages/` file in `server/storage/mvcc` documents cache behavior today, and none of the cell's existing consumer-facing practices (`watch_sync_states`) describe Range read behavior — nothing to update. No new practice file is warranted: this is an internal performance optimization with no new consumer-visible API to document.

### Compatibility Verification
**Backward compatible.** Cache-miss path is byte-identical to the current implementation (same `rangeKeys` call, same error handling). Cache-hit path is designed to be behaviorally indistinguishable from a miss from the caller's perspective: identical `RangeResult{KVs, Count, Rev}` shape, `Rev` always freshly computed (never stale), `KVs` always a fresh deep copy (never a shared/mutable reference), error paths (`ErrFutureRev`, `ErrCompacted`) never cached and always recomputed live. No exported signature, file location, or manifest-defined guarantee changes anywhere in the investigation scope. Confirmed no breaking change per the Investigation Report's six-question assessment (all NO).

### Test Strategy
New/modified tests in `server/storage/mvcc` (existing `*_test.go` files in this package, e.g. `kvstore_test.go`/a new `range_cache_test.go`, following this cell's existing test conventions):
1. **Cache hit correctness**: identical repeated `Range` calls (same key/end/limit/options) return equal `KVs`/`Count` to a fresh (cache-disabled or first-call) result, and the second call does not re-touch the backend (assert via a call-counting/spy backend or by asserting `rangeKeys`'s bolt-read step doesn't re-fire — whatever instrumentation this package's existing tests already use for similar assertions).
2. **Mutation isolation**: after a `KeysOnly` request nulls `Value` on its returned `KeysOnly` result, a subsequent non-`KeysOnly` request for the same range still returns full values — proves deep-copy-on-serve works and guards directly against the `asembleRangeResponse`-mutation hazard found in Investigation.
3. **Write invalidation promptness**: `Get` a range (populates cache) → `Put`/`DeleteRange` a key inside that range → immediately re-`Get` the same range — must reflect the write, never the stale cached value. Also a negative case: write a key **outside** the cached range → cached entry for the unrelated range remains valid (hit, not recomputed) — validates the overlap-precision requirement, not a blanket flush.
4. **Historical revision immutability + compaction**: `Get` at an explicit past revision (cache populated) → unrelated writes happen (current-bucket entries change, historical entry for the old revision remains cached and correct) → `Compact` past that revision → the same historical `Get` now returns `ErrCompacted`, not a stale cached success.
5. **Restore clears everything**: populate cache, call `Restore`, verify cache is empty / next reads recompute (guards against the "same `*store` instance reused in place" hazard from Investigation).
6. **Linearizable/serializable equivalence**: an integration-level test (in `tests/integration` or existing etcdserver-level tests, mirroring however this repo currently tests linearizable-vs-serializable Range behavior) confirming a cache hit is never served to a linearizable read that would violate linearizability — since the cache sits below the existing barrier, this should already hold structurally, but an explicit test guards against regression.
7. **Concurrency/race**: run existing `-race` test suite for this package with concurrent readers/writers hitting overlapping and disjoint ranges, to catch any lock-ordering issue in the new cache mutex relative to `s.mu`/`s.revMu`.

Existing test suites for `server/storage/mvcc`, `server/etcdserver`, and the integration suite must continue to pass unmodified (miss-path behavior is unchanged) — this is the primary regression guard for "cache-miss behaves exactly as before."

### Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Shared-pointer mutation corrupts cache (the `asembleRangeResponse` `Value=nil` hazard found in Investigation) | Medium (easy to get wrong without the finding) | High (silent data corruption, hardest class of bug to catch) | Deep-copy-on-put AND deep-copy-on-get via `proto.Clone`; explicit regression test (Test Strategy #2). |
| Missed invalidation path (some write bypasses `storeTxnWrite.End`) | Low (Investigation confirmed single choke point) | High (stale reads = correctness violation of core requirement) | Investigation traced every write (Put/DeleteRange/Txn/apply-driven) to the one `End()` call; test #3 exercises it directly; `-race`/existing integration write-path tests continue to pass. |
| Cache-map lock contention added to write hot path (`storeTxnWrite.End`) | Medium | Low-Medium (perf regression on writes, not correctness) | Invalidation is a targeted `IntervalTree.Stab` query per changed key (not a full scan), guarded by a dedicated lock held only briefly; can be benchmarked against existing write-path benchmarks in this package if regression is a concern. |
| Unbounded cache memory growth under highly varied query shapes | Medium | Medium | Fixed-size cap with eviction (Change Strategy #1); documented as an internal default, adjustable later via a proper `StoreConfig` knob if real-world usage shows the default is wrong (explicitly out of scope for this change to avoid speculative config surface). |
| Restore/compaction edge cases not fully exercised by existing tests | Low | Medium | Explicit new tests #4 and #5 target exactly these paths. |

---

Do you approve the plan? Proceed to implementation?
