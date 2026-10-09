# R06-TD-GC-01

Condition: goga_native_architecture
Base tag: condition-c-r06-v1
Functional success: True
Full architecture conformance: False
ACR: 0.6
Dangerous success: True
Goga engagement signal: True
Cost: $2.1742269000000003
Duration: 527685ms, turns: 49

## Agent's own summary

# Change Plan

## Task Classification
**Feature** (additive performance optimization) — introduce a read-through cache for MVCC Range reads with event-driven, write-triggered invalidation. No existing behavior is altered on the miss path; no public API changes.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `server/storage/mvcc` | `kvstore.go` | Add `rangeCache` field to `store` struct; initialize in `NewStore`. |
| `server/storage/mvcc` | `kvstore_txn.go` | Add `(tr *storeTxnRead) Range(...)` override (cache check/populate); add invalidation call inside `storeTxnWrite.End()`'s existing `revMu.Lock()` section. |
| `server/storage/mvcc` | new file `range_cache.go` | New unexported `rangeCache` type: cache map, interval tree for scoped invalidation, bounded-size eviction, get/put/invalidate methods, deep-copy helpers. |
| `server/storage/mvcc` | `range_cache_test.go` (new) + additions to `kvstore_test.go`/`watchable_store_test.go` | Unit tests for cache hit/miss/invalidation/race-safety; regression tests confirming miss-path behavior is unchanged. |

No other cell (`server/etcdserver`, `server/lease`, `server/storage/backend`, `server/auth`, `client/v3`) requires modification — confirmed in Investigation as pure pass-through consumers of the unchanged `mvcc.KV`/`TxnRead`/`ReadView` interfaces.

## Root Cause Analysis
Not a defect — a capability gap. All Range/Count/Compare reads (linearizable and serializable alike) converge on `(*store).Read().Range()`; all writes commit through `storeTxnWrite.End()`, sharing `store.revMu` with `Read()`'s revision snapshot. This shared lock is the only mechanism in the codebase that provides a provable happens-before relationship between "a write commits and bumps `currentRev`" and "a read observes that bump" — making it the correct (and only correct) synchronization point for both cache invalidation and race-free cache insertion.

## Trace Summary
- Read entry points → `mvcc.KV.Read(...).Range(...)`: `txn.Range` (txn/range.go:47), `txn.Count` (txn/range.go:34, wraps Range), `applyCompare` (txn/txn.go:274). All three ultimately call `storeTxnRead.Range` (post-change) or today's `storeTxnCommon.Range` (kvstore_txn.go:69).
- Write commit path: `storeTxnWrite.End()` (kvstore_txn.go:209) — `s.revMu.Lock(); s.currentRev++ (if changes); ...; s.revMu.Unlock()`. `tw.changes` (`[]*mvccpb.KeyValue`, already populated by `put()`/`delete()`) is the exact changed-key set to feed invalidation.
- Downstream mutation hazard: `server/etcdserver/txn/range.go` (`pruneKVs`, `sortRangeResults`, `asembleRangeResponse`'s `rr.KVs[i].Value = nil`) mutates `RangeResult`/`*mvccpb.KeyValue` in place — mandates deep copy on every cache hit and on insert.
- Reusable primitive: `pkg/adt.IntervalTree` (`adt.NewStringAffineInterval`, `.Stab`), already used identically in `server/storage/mvcc/watcher_group.go` for range-vs-key matching.

## Change Strategy

1. **`kvstore.go`**: add `rangeCache *rangeCache` field to `store` struct (near `kvindex`); in `NewStore`, set `s.rangeCache = newRangeCache(defaultRangeCacheCapacity)`. No change to `NewStore`'s signature or any exported behavior.

2. **New file `range_cache.go`**:
   - `type rangeCacheKey struct { key, end string; limit int64; countOnly, fastKeysOnly, withTotalCount bool }` — built from `RangeOptions` minus `Rev` (caching restricted to `Rev <= 0`).
   - `type rangeCache struct { mu sync.Mutex; entries map[rangeCacheKey]*list.Element; order *list.List /* FIFO for bounded eviction */; ranges adt.IntervalTree /* [key,end) -> map[rangeCacheKey]struct{} */; capacity int }`.
   - `newRangeCache(capacity int) *rangeCache`.
   - `(c *rangeCache) get(k rangeCacheKey) (*RangeResult, bool)` — map lookup + deep copy of the stored result before returning (never returns a shared pointer).
   - `(c *rangeCache) put(k rangeCacheKey, result *RangeResult)` — stores a deep copy; registers the `[key,end)` interval (adding `k` to that interval's key-set, inserting the interval if new); evicts oldest entry via FIFO list if `capacity` exceeded (removing it from both `entries` and its interval's key-set, pruning the interval from the tree if its key-set becomes empty).
   - `(c *rangeCache) invalidate(changedKeys [][]byte)` — for each changed key, `Stab` the interval tree, collect every `rangeCacheKey` in the matched intervals' key-sets, delete them from `entries`/`order`, then remove the now-empty intervals.
   - `cloneRangeResult(*RangeResult) *RangeResult` — allocates a new `KVs` slice and shallow-copies each `*mvccpb.KeyValue` (new struct, same immutable `Key`/`Value` byte-slice headers) plus copies `Rev`/`Count`. Used identically for both "snapshot on insert" and "copy on hit" to guarantee no two call sites ever observe the same mutable `*mvccpb.KeyValue`.

3. **`kvstore_txn.go`**:
   - Add `func (tr *storeTxnRead) Range(ctx context.Context, key, end []byte, ro RangeOptions) (*RangeResult, error)`, shadowing the embedded `storeTxnCommon.Range`:
     - `if ro.Rev > 0 { return tr.rangeKeys(ctx, key, end, tr.Rev(), ro) }` — historical reads: **unchanged path, byte-for-byte**.
     - Build `k := rangeCacheKey{...}` from `key, end, ro`.
     - `if res, ok := tr.s.rangeCache.get(k); ok { return res, nil }` — cache hit, no kvindex/backend touch.
     - Else: `res, err := tr.rangeKeys(ctx, key, end, tr.Rev(), ro)` (today's exact call); on `err == nil`, attempt insert guarded by the race check: `tr.s.revMu.RLock(); if tr.s.currentRev == tr.rev { tr.s.rangeCache.put(k, res) }; tr.s.revMu.RUnlock()`; return `res, err` unchanged.
   - `storeTxnWrite.Range` is **not modified** — it already overrides `Range` independently, so write-txn-internal reads (e.g. `applyCompare` during a txn's own apply, `put()`'s previous-value lookup) never consult or populate the cache.
   - Inside `storeTxnWrite.End()`, within the existing `if len(tw.changes) != 0 { tw.s.revMu.Lock(); tw.s.currentRev++ ... }` block, add a call `tw.s.rangeCache.invalidate(changedKeysOf(tw.changes))` **before** `tw.s.revMu.Unlock()` (so invalidation happens-before any reader can observe the bumped revision). `changedKeysOf` extracts `.Key` from each `*mvccpb.KeyValue` in `tw.changes`.

4. **No changes** to `mvcc.KV`, `WatchableKV`, `TxnRead`, `ReadView`, `WriteView`, `RangeOptions`, `RangeResult`, `watchableStore`, `watchableStoreTxnWrite`, or any file outside `server/storage/mvcc`.

## Specification Impact
`server/storage/mvcc/CODEMANIFEST` — the `KV`/`TxnRead` contract (input→output behavior) is unchanged, so no signature/annotation edit is required for correctness. During Manifest Reconciliation (pipeline Step 7), add a short implementation-note annotation at the `store`/`TxnRead.Range` (or nearest relevant type) documenting that repeated identical "latest" range reads may be served from an internal, write-invalidated cache — informational only, not a new contractual obligation, since the observable contract is identical either way.

## Usage Impact
None. Both affected cells have empty `.usages/` directories (`goga schema` reports `usages: []`); the change is purely internal to `server/storage/mvcc`'s implementation and does not alter how consumers use the cell's facade (`KV`/`TxnRead`/`ReadView` — unchanged).

## Compatibility Verification
**Backward compatible.** Every existing exported type/method signature in `server/storage/mvcc` is unchanged. Cache-miss path executes the identical sequence of calls (`tr.rangeKeys(ctx, key, end, tr.Rev(), ro)`) that runs today. Cache-hit path returns data that is definitionally identical to what an uncached read at the same snapshotted revision would produce (MVCC data at a fixed revision is immutable), returned as an independent deep copy so downstream in-place mutation (`pruneKVs`, sort, `KeysOnly` nil-out) cannot leak between callers. `storeTxnWrite.Range` (write-txn-internal reads) and `Rev > 0` (historical reads) are both explicitly excluded from caching, so no existing test relying on read-your-writes-within-a-txn or historical-revision semantics is affected.

## Test Strategy
- **`range_cache_test.go`** (new, table-driven per repo convention):
  - get/put round-trip correctness (deep copy — mutate the returned result, confirm cache's internal copy is unaffected).
  - invalidation: put entries for several `[key,end)` ranges, invalidate a key that overlaps one, confirm only overlapping entries are evicted, non-overlapping entries survive (hit-rate preservation).
  - capacity bound: insert beyond capacity, confirm FIFO eviction keeps size bounded and evicted entries are also removed from the interval tree (no leak / no stale-interval false invalidation-noop).
- **`kvstore_test.go` / `kvstore_bench_test.go` additions**:
  - Repeated identical `Range` calls between writes return identical results without re-touching the backend (assert via a counter/hook, or via benchmark showing reduced backend `UnsafeRange` calls).
  - Concurrent-write-during-read regression test simulating the insertion race: start a slow read (inject a delay), commit a concurrent overlapping write mid-read, assert the read's result is never cached (i.e., a subsequent read observes the new data, not the stale one) — directly exercises the `currentRev` re-check-before-insert guard.
  - `Rev > 0` historical reads bypass the cache entirely (assert no interaction with `rangeCache`).
  - `KeysOnly` and non-`KeysOnly` concurrent requests against the same range never corrupt each other's `Value` field (regression test for the mutation hazard found in investigation).
- **Existing full `server/storage/mvcc` suite** (`kvstore_test.go`, `watchable_store_test.go`, `store_test.go`, etc.) run unmodified to confirm zero regression on the miss/historical/write paths.
- **Existing `server/etcdserver` test suite** (`v3_server_test.go` if present, integration tests under `tests/`) run unmodified — no code there changes, but running them confirms the transparent benefit doesn't alter observable server behavior (linearizable/serializable Range responses, Txn Compare results).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Stale data served to a linearizable/serializable read | Low | High (violates core requirement) | Cache hit requires the read's own snapshotted `tr.Rev()` and presence in the cache; presence is guaranteed fresh by revMu-ordered invalidation-before-visibility and by the insert-time `currentRev` re-check closing the concurrent-write race. Covered by dedicated regression test above. |
| Shared-object mutation corrupts concurrent responses (`KeysOnly` nil-out, sort/prune in place) | Medium (real hazard found in investigation) | High (silent data corruption) | Mandatory deep copy via `cloneRangeResult` on both insert and every hit; dedicated regression test. |
| Unbounded memory growth from wide/varied query patterns (many distinct limits/options per key) | Medium | Medium (resource exhaustion) | FIFO capacity bound with eviction wired into both the map and interval tree. |
| Interval tree / map desync after eviction or invalidation (stale keys left in tree, or vice versa) | Low | Medium (missed invalidation or memory leak) | Eviction and invalidation both remove from map, key-set, and (when key-set empties) the tree interval atomically under `rangeCache.mu`; covered by unit tests. |
| Lock ordering deadlock (`revMu` vs `rangeCache.mu`) | Low | High (deadlock) | Strict ordering enforced: `revMu` always acquired before `rangeCache.mu` in both the insert path (`Range`) and invalidate path (`End`); plain cache-hit lookups never acquire `revMu` at all, so no cycle is possible. |
| Reduced hit rate under heavy unrelated write traffic | Low (by design tradeoff) | Low (performance only, not correctness) | Accepted: the insert-time global `currentRev` check is intentionally conservative (skips caching if *any* write raced ahead, not just an overlapping one) to guarantee correctness simply; scoped interval-tree invalidation still preserves hits for genuinely unrelated keys across unrelated writes on already-cached entries. |

---

Do you approve the plan? Proceed to implementation?
