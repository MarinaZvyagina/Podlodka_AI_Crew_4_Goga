# R06-TD-GC-09

Condition: goga_native_architecture
Base tag: condition-c-r06-v1
Functional success: True
Full architecture conformance: False
ACR: 0.6
Dangerous success: True
Goga engagement signal: False
Cost: $5.104395600000002
Duration: 741837ms, turns: 26

## Agent's own summary

# Change Plan

## Task Classification
**Feature** (additive, internal-only optimization to `server/storage/mvcc`; no public API surface changes).

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `server/storage/mvcc` | **New:** `range_cache.go`, `range_cache_test.go`. **Modified:** `kvstore.go` (struct field, init, `updateCompactRev`, `Restore`), `kvstore_txn.go` (`storeTxnCommon.Range`, `storeTxnWrite.End`), `CODEMANIFEST` (annotations only), `kvstore_test.go` or new integration tests. | Adds an internal, event-driven read cache for `Range`, wired into the existing write-commit and compaction hooks. No other cell touched. |

## Root Cause Analysis
(Feature addition — this section captures the confirmed design rationale from the Investigation Report.)
- Both linearizable and serializable reads converge on the same `mvcc.KV.Range` call, after any relevant write has already committed — so one cache, invalidated purely by mvcc's own commit/compaction signals, is safe for both consistency levels.
- The only race is a reader computing a result concurrently with a writer's commit and then inserting a now-stale result into the cache *after* the writer's invalidation already ran. This is closed with a monotonic sequence counter, checked-and-inserted atomically under the cache's own mutex, paired with unconditional overlap-based eviction on every write — so a stale insert either never happens (seq mismatch detected) or is swept up by the very next overlapping write's eviction pass.
- `Range` results are mutated in place downstream (`server/etcdserver/txn/range.go`: slice truncation/reorder, `Value = nil` for `KeysOnly`), so the cache must never let two callers share the same `*mvccpb.KeyValue`/slice header — each `Get` must return a fresh slice of fresh (shallow-copied) `*mvccpb.KeyValue` structs. Byte-slice contents (`Key`/`Value`) are never mutated in place anywhere downstream, so sharing the underlying byte arrays across shallow copies is safe and avoids unnecessary allocation.
- Compaction bypasses the write-commit hook entirely, so historical (`Rev != 0`) cache entries need their own invalidation trigger tied to `compactMainRev`.
- **Deviation from the originally sketched design:** the write-invalidation hook must live in the *base* `storeTxnWrite.End()` (`kvstore_txn.go`), not in the watchable-only wrapper `watchableStoreTxnWrite.End()` (`watchable_store_txn.go`). Evidence: production always uses `watchableStore` (`server/etcdserver/server.go:370`), but plain `*store` (via `mvcc.NewStore`) is exercised directly by a large fraction of this cell's own existing test suite (`kvstore_test.go`, `kv_test.go`, plus `apply`/`txn` package tests), which routinely write then immediately `Range` and expect to see the new data. `watchableStoreTxnWrite.End()` delegates to `storeTxnWrite.End()` via the embedded `TxnWrite` interface, so anchoring the hook in the base method covers both the production (watchable) and test-only (plain) paths with one call site — anchoring only in the watchable wrapper would leave the plain-store path silently serving stale cache hits and would very likely break existing tests.

## Trace Summary
- Read: `EtcdServer.Range` → (linearizable gate, if any) → `txn.Range` → `TxnRead.Range` → **`storeTxnCommon.Range`** (`kvstore_txn.go:69-71`, cache lookup added here) → `rangeKeys` (unchanged) on miss.
- Write: raft-applied Put/DeleteRange/Txn → `store.Write()` → **`storeTxnWrite.End()`** (`kvstore_txn.go:209-221`, invalidation added here) → (watchable wrapper, unchanged) `notify()` for watchers.
- Compaction: `Compact`/`compactLockfree` → **`updateCompactRev`** (`kvstore.go:197-222`, invalidation added right after `s.compactMainRev = rev`, line 211) → async `scheduleCompaction` (unchanged).
- Snapshot restore: **`store.Restore`** (`kvstore.go:292-314`, full cache reset added) — backend is replaced wholesale, so all cached entries (current and historical) must be dropped unconditionally.
- `storeTxnWrite.Range()` (`kvstore_txn.go:189-195`, the write-txn's own in-flight read) is **not** touched — it calls `tw.rangeKeys` directly, bypassing `storeTxnCommon.Range`, so it is structurally excluded from caching already; no change needed there.

## Change Strategy

1. **New file `server/storage/mvcc/range_cache.go`** — unexported types only (no CODEMANIFEST entry needed, per Go cell rules: only exported identifiers are part of the contract):
   ```go
   type rangeCacheKey struct {
       key, end       string
       hasEnd         bool  // disambiguates end==nil (point lookup) from end==[]byte{} (from-key)
       limit, rev     int64
       countOnly      bool
       fastKeysOnly   bool
       withTotalCount bool
   }

   type rangeCacheEntry struct {
       key, end []byte
       hasEnd   bool
       rev      int64 // the request's pinned ro.Rev; 0 means "current"
       result   *RangeResult
   }

   const maxRangeCacheEntries = 4096 // simple growth guard, not a full LRU

   type rangeCache struct {
       mu      sync.Mutex
       seq     uint64
       entries map[rangeCacheKey]*rangeCacheEntry
   }

   func newRangeCache() *rangeCache
   func (c *rangeCache) seqNow() uint64
   func (c *rangeCache) get(k rangeCacheKey) (*RangeResult, bool)
   func (c *rangeCache) tryPut(k rangeCacheKey, seqAtStart uint64, key, end []byte, hasEnd bool, result *RangeResult)
   func (c *rangeCache) invalidateChanges(changes []*mvccpb.KeyValue)
   func (c *rangeCache) invalidateCompacted(compactRev int64)
   func (c *rangeCache) reset()

   func rangeContainsKey(key, end []byte, hasEnd bool, k []byte) bool // mirrors index.go's end==nil/empty/bounded semantics exactly
   func cloneRangeResult(rr *RangeResult) *RangeResult                // fresh slice + fresh *mvccpb.KeyValue structs (shallow field copy)
   ```
   - `tryPut` and `invalidateChanges`/`invalidateCompacted` all run under the same `c.mu`, making eviction+seq-bump and check+insert mutually exclusive — this is what closes the race described in Root Cause Analysis. `c.mu` is always the innermost lock: never held while acquiring `store.mu`/`revMu`/`watchableStore.mu`, only ever acquired from within sections that already hold (or don't need) those locks and released before returning — no new deadlock risk.
   - `maxRangeCacheEntries` is a minimal safeguard against unbounded memory growth (e.g. many distinct historical-`Rev` queries never naturally evicted): `tryPut` simply declines to insert when at capacity, rather than a full LRU — deliberately minimal, tunable later if needed.

2. **`kvstore.go`**:
   - Add field `rangeCache *rangeCache` to `store` struct (near `hashes HashStorage`, line ~81).
   - In `NewStore`'s composite literal (~line 97-112), add `rangeCache: newRangeCache(),`.
   - In `updateCompactRev` (line 197-222), immediately after `s.compactMainRev = rev` (line 211), add `s.rangeCache.invalidateCompacted(rev)`.
   - In `Restore` (line 292-314), after acquiring `s.mu.Lock()` (line 293), add `s.rangeCache.reset()` — the backend is replaced wholesale, so no cached entry (current or historical) can be trusted.

3. **`kvstore_txn.go`**:
   - `storeTxnCommon.Range` (line 69-71) becomes:
     ```go
     func (tr *storeTxnCommon) Range(ctx context.Context, key, end []byte, ro RangeOptions) (r *RangeResult, err error) {
         ck := rangeCacheKey{key: string(key), end: string(end), hasEnd: end != nil, limit: ro.Limit, rev: ro.Rev, countOnly: ro.CountOnly, fastKeysOnly: ro.FastKeysOnly, withTotalCount: ro.WithTotalCount}
         if cached, ok := tr.s.rangeCache.get(ck); ok {
             return cached, nil
         }
         seqAtStart := tr.s.rangeCache.seqNow()
         result, err := tr.rangeKeys(ctx, key, end, tr.Rev(), ro)
         if err == nil {
             tr.s.rangeCache.tryPut(ck, seqAtStart, key, end, end != nil, result)
         }
         return result, err
     }
     ```
     `rangeKeys` itself is **not modified** — this is what makes the cache-miss path byte-for-byte identical to today. Error results (`ErrCompacted`, `ErrFutureRev`) are never cached — they're cheap early-exits in `rangeKeys` already, and caching a future-revision error risks it going stale the moment the store catches up; skipping them avoids that edge case entirely.
   - `storeTxnWrite.End()` (line 209-221) gains one line inside the existing `if len(tw.changes) != 0` block, right after `tw.s.currentRev++`:
     ```go
     tw.s.rangeCache.invalidateChanges(tw.changes)
     ```
     Uses `tw.changes` (`[]*mvccpb.KeyValue`, already built by `put`/`delete`) directly — no dependency on the watch-layer's `evs`, so this fires uniformly for both `watchableStore`- and plain-`store`-backed writes.

4. **No changes to `watchable_store.go` / `watchable_store_txn.go`** — `notify()` and its call site are untouched; invalidation is anchored one layer down where it covers both callers of `storeTxnWrite.End()`.

5. **`CODEMANIFEST` (annotation-only, additive)**:
   - Global `Annotations:` — append: *"Repeated `Range` reads for identical key/end/`RangeOptions` may be served from an internally-maintained result cache rather than recomputed; the cache is invalidated synchronously by the same write-commit path that produces watch events, and by compaction, so no caller ever observes a value staler than an equivalent uncached read at the time of its request, regardless of read consistency mode."*
   - `ReadView()`'s `Range` method annotation — append a `Requirements:` block: *"Results may be served from an internal cache when a prior call used identical `key`, `end`, and `ro`; that cache is invalidated on any write/delete affecting the requested range and on compaction reaching a cached historical revision — never solely by a time-based expiration."*
   - `KV()`'s `Compact` method annotation — append: *"Also evicts any internally cached range-read results pinned at or below `revision`, since a live read for those would now return `ErrCompacted`."*
   - `KV()`'s `Restore` method annotation — append: *"Also discards all internally cached range-read results, since the replacing backend is not guaranteed to be consistent with previously cached data."*
   - No new `Usages` entry and no new body type — this stays purely descriptive of behavior already owned by existing types, per DSL ("the document does not prescribe how to implement the code") and cookbook guidance against over-engineering the manifest for an internal-only detail.

## Specification Impact
Four existing annotation blocks in `server/storage/mvcc/CODEMANIFEST` gain additive text (global header, `Range`, `Compact`, `Restore`). No signature, type, or location entry changes. No `Imports`/`Usages` changes.

## Usage Impact
No `.usages/*.md` files exist for this cell (confirmed — only the inline `watch_sync_states` header usage). No usage file changes required; the new annotation text stands on its own and doesn't need a dedicated practice document since it describes a single, self-contained behavioral guarantee already scoped to existing methods.

## Compatibility Verification
**Backward compatible.** `KV`/`ReadView`/`WriteView` interfaces, `RangeOptions`, `RangeResult` — all unchanged. Cache-miss path executes the pre-existing `rangeKeys` unmodified. Cache-hit path returns a structurally identical, freshly-copied `RangeResult`. No exported identifier added, renamed, or removed. Existing error semantics (`ErrCompacted`, `ErrFutureRev`) are preserved verbatim since error results are never cached.

## Test Strategy
1. **`range_cache_test.go` (new, white-box, same package)**: `get`/`tryPut` basic hit/miss; `invalidateChanges` evicts only overlapping entries (point key, bounded range, from-key/`hasEnd` cases) and leaves disjoint entries intact; `invalidateCompacted` evicts only `rev != 0 && rev < compactRev` entries; `reset` clears everything and bumps `seq`; the CAS guard — call `seqNow()`, then `invalidateChanges` (simulating a race), then `tryPut` with the stale `seqAtStart` and assert nothing was inserted; `maxRangeCacheEntries` cap is respected.
2. **`kvstore_test.go` additions (white-box, asserting on `s.rangeCache.entries` directly)**:
   - Repeated identical `Range` after a `Put` results in exactly one cache entry and a second call returns data equal to the first.
   - `Put`/`DeleteRange` on an unrelated key does **not** evict a cached entry for a different, non-overlapping key.
   - `Put`/`DeleteRange` overlapping a cached range **does** evict it, and the next `Range` reflects the new data.
   - `Compact` past a cached historical-`Rev` entry evicts it; a subsequent read at that revision returns `ErrCompacted` from both the (now absent) cache and `rangeKeys` directly.
   - Deep-copy correctness: mutate `result.KVs[0].Value = nil` on a caller's received result (simulating `KeysOnly` handling in `txn/range.go`), then issue the same `Range` again and assert the newly returned `Value` is intact — proves no shared-pointer aliasing.
   - `Restore` clears all cache entries.
3. **Regression**: run the full existing `server/storage/mvcc` suite unmodified — in particular `TestConcurrentReadNotBlockingWrite`, `TestConcurrentReadTxAndWrite`, `TestWatchResponseEventsNotSharedAcrossWatchers`, and all `TestStore*`/`TestKV*`/`TestWatch*`/`TestScheduleCompaction`/`TestCompactAllAndRestore` — to confirm no behavioral drift; these exercise the plain-`store` write-then-read pattern that motivated anchoring invalidation in `storeTxnWrite.End()`.
4. Race detector run (`go test -race ./server/storage/mvcc/...`) given the new shared mutable state (`rangeCache`) accessed from both read and write paths.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Anchoring invalidation only in the watchable wrapper, missing plain-`store` test usage | Was High (identified during planning) | High (stale reads, broken tests) | Anchored in base `storeTxnWrite.End()` instead — covers both paths by construction (see Root Cause Analysis deviation). |
| `string(nil) == string([]byte{})` collapsing point-lookup and from-key cache keys | Medium if overlooked | High (wrong entries served for a different request shape) | `hasEnd bool` added explicitly to both the cache key and cache entry. |
| Shared `*mvccpb.KeyValue` pointers between cache and caller, corrupted by downstream in-place mutation (`KeysOnly`, `pruneKVs`) | Medium | High (data corruption across unrelated requests) | `cloneRangeResult` always returns a fresh slice of fresh (shallow-copied) `*mvccpb.KeyValue` structs on every `get`/`tryPut`; verified by a dedicated test. |
| Lost-update race between a reader's populate and a concurrent writer's invalidation | Medium (any concurrent write+read on same range) | High (silent stale data — the exact failure mode the task forbids) | Sequence-counter CAS guard, both eviction and check-and-insert under the same cache mutex; verified by a dedicated deterministic (non-timing-based) test. |
| Compaction invalidation missed (compaction doesn't go through `notify()`) | Was High if unaddressed | High (serving data a live read would reject with `ErrCompacted`) | Explicit `invalidateCompacted` hook in `updateCompactRev`, the single call site reached by both `Compact()` and resumed/lock-free compaction paths. |
| Snapshot `Restore` swaps the backend wholesale; stale entries survive | Medium (only on snapshot install, relatively rare) | High (arbitrary stale/wrong data after a snapshot) | Unconditional `reset()` at the top of `Restore`. |
| Unbounded cache growth (many distinct historical-`Rev` or large-range queries) | Low-Medium over long uptime | Medium (memory pressure) | `maxRangeCacheEntries` cap; declines new inserts past the limit rather than implementing a full LRU (kept intentionally minimal). |
| New lock (`rangeCache.mu`) introduces a deadlock with `store.mu`/`revMu`/`watchableStore.mu` | Low | High if it occurred | `rangeCache.mu` is always the innermost/last lock acquired and is released before returning in every call site; no code path acquires an outer lock while holding it. Verified with `-race` and by code review of every call site. |

---

Do you approve the plan? Proceed to implementation?
