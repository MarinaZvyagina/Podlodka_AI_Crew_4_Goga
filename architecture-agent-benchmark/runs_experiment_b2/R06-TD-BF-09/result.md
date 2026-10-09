# R06-TD-BF-09

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.8
Dangerous success: True
Goga engagement signal: False
Cost: $4.1552982
Duration: 725523ms, turns: 73

## Agent's own summary

# Change Plan

## Task Classification
**Feature** (additive) — new internal read-cache capability inside `server/storage/mvcc`, no existing contract altered.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `server/storage/mvcc` | New: `read_cache.go`, `read_cache_test.go`. Modified: `watchable_store.go` (override `Read`, add cache field + wiring in `newWatchableStore`), `watchable_store_txn.go` (`End()` invalidates before commit), `kvstore.go` (`Compact` hook for pinned-revision eviction), `CODEMANIFEST` (document new type), `.usages/read-cache.md` (new) | Adds `readCache` type; wires it into the existing `Read`/`Write`/`Compact` paths without touching `store` (the non-watchable path used directly by some tests stays cache-free, matching today's behavior there). |

## Root Cause Analysis
Not a defect — see Investigation Report. The chosen insertion points (`watchableStore.Read`, `watchableStoreTxnWrite.End`, `store.Compact`) are the only places in the codebase where read and write already share synchronization state (`store.currentRev`, `watchableStore.mu`), making them the only points where a cache can be both effective (skip real work on hit) and provably never-stale (evict-before-visible on write).

## Trace Summary
- Hit/miss path: `KV.Read(mode, trace)` → **`watchableStore.Read`** (new override) → cache lookup by `readCacheKey{key, endKind, end, limit, rev, countOnly, fastKeysOnly, withTotalCount}` → on hit, clone and return a `cachedTxnRead` wrapping just a `*RangeResult`; on miss, delegate to `s.store.Read(mode, trace)` unchanged and populate cache in `TxnRead.End()`.
- Invalidation path: `KV.Write(trace)` → `watchableStore.Write` (unchanged) → `Put`/`DeleteRange` accumulate `changes` (unchanged) → **`watchableStoreTxnWrite.End()`** (modified): under `tw.s.mu.Lock()`, call `tw.s.cache.invalidate(changes)` (bump generation, evict overlapping entries) **before** `tw.s.notify(rev, evs)` and `tw.TxnWrite.End()` — i.e. eviction happens no later than today's notify step, still fully inside the lock, still strictly before `store.currentRev` advances.
- Compaction path: `store.Compact` (or wherever `compactMainRev` is advanced) → **new call** `s.cache.invalidateCompacted(rev)` evicting only entries with an explicit pinned `Rev > 0 && Rev <= rev`.
- Lease expiry: unchanged — already routes through `watchableStore.Write`, so it is covered automatically (confirmed in Investigation).

## Change Strategy

1. **`read_cache.go` (new file)**
   - `type endKind uint8` with `endSingleKey`, `endOpenFrom`, `endBounded` — preserves the `nil` vs `[]byte{}` vs `[]byte(range_end)` distinction documented in `kv.go:52-54`, since collapsing to a Go `string` would silently merge `nil` and `[]byte{}` (`string(nil) == ""`) and corrupt cache-key identity between "single key" and "from key to infinity" queries.
   - `type readCacheKey struct { key, end string; endKind endKind; limit, rev int64; countOnly, fastKeysOnly, withTotalCount bool }` — built directly from the exact `RangeOptions` fields plus `key`/`end` passed into `TxnRead.Range`. No `SortOrder`/`SortTarget`/`KeysOnly`(logical)/`Min*Revision` fields exist at this layer (they're applied above, in `txn/range.go`, on the returned `RangeResult`) — caching the raw pre-filter/pre-sort result is correct and gives a strictly higher hit rate, since two requests differing only in sort order share one cache entry.
   - `func rangeOverlapsKey(key string, endKind endKind, end string, changed string) bool` — implements exactly the three documented cases from `kv.go`.
   - `type readCache struct` — `mu sync.Mutex`, `capacity int`, `generation uint64`, `entries map[readCacheKey]*list.Element` (values wrap `{key readCacheKey, result *RangeResult}`), `order *list.List` (LRU via `container/list`, matching the standard Go LRU idiom).
   - **Correctness-critical: defensive cloning.** Callers above this cache (`txn/range.go`'s `filterRangeResults`/`asembleRangeResponse`) mutate the returned `*mvccpb.KeyValue` objects in place (e.g. `rr.KVs[i].Value = nil` for `KeysOnly`). Two different top-level `RangeRequest`s can map to the *same* mvcc-level cache key (e.g. `KeysOnly=true,SortTarget=VALUE` vs `KeysOnly=false,SortTarget=KEY` both produce `RangeOptions.FastKeysOnly=false`). Without cloning, one caller's in-place mutation would corrupt another caller's cached data. Fix: `put()` stores a `proto.Clone`-based deep copy of the computed `*RangeResult`; every `get()` hit returns a fresh deep copy. The miss path continues to hand the caller the original, never-cached object, exactly as today.
   - `func (c *readCache) startRead() (gen uint64)` — snapshot generation under lock.
   - `func (c *readCache) get(k readCacheKey) (*RangeResult, bool)` — lookup + clone + LRU touch.
   - `func (c *readCache) put(k readCacheKey, gen uint64, r *RangeResult)` — under lock, only insert `if gen == c.generation` (closes the read-during-write race); evict LRU tail if over `capacity`.
   - `func (c *readCache) invalidate(changes []*mvccpb.KeyValue)` — under lock: `c.generation++`; linear scan of `c.entries` (bounded by `capacity`, so O(capacity·len(changes)), acceptable for a small hot-key cache) evicting any entry whose `[key,end)` overlaps any changed key via `rangeOverlapsKey`.
   - `func (c *readCache) invalidateCompacted(rev int64)` — under lock, evict entries with `k.rev > 0 && k.rev <= rev` (no generation bump needed — compaction doesn't race the same way since it runs on the same serialized write path and only affects pinned-revision entries, which are never re-populated with an equivalent race window at the same `rev`... actually a concurrent reader pinned to that same `rev` could still be racing; apply the identical generation-gated `put()` used for regular writes so `invalidateCompacted` also bumps `c.generation`, keeping one uniform race-closing mechanism instead of a second one).
   - `defaultReadCacheCapacity = 4096`, override via `StoreConfig.ReadCacheCapacity` (0 = default; **explicit new `-1` sentinel or a `CacheDisabled bool` is not introduced** — out of scope; default capacity always on, matching "must apply automatically" reading of the requirement, keeps `StoreConfig` additive/backward compatible since the new field defaults to zero value that still works).

2. **`watchable_store.go`**
   - Add `cache *readCache` field to `watchableStore`.
   - In `newWatchableStore`, initialize `s.cache = newReadCache(cfg.readCacheCapacity())` before wiring `ReadView`/`WriteView`.
   - Add `func (s *watchableStore) Read(mode ReadTxMode, trace *traceutil.Trace) TxnRead` overriding the promoted `*store.Read`: for cache-eligible option combos (all `Range` calls go through this — no request-shape restriction needed since the key is the full option struct), returns a lightweight `cachingTxnRead` that: on `Range()`, builds the key, calls `c.get`; on hit, returns the clone directly (skips opening any backend/boltdb transaction at all — the actual point of the feature); on miss, opens `s.store.Read(mode, trace)` for real, delegates, and on `End()` calls `c.put(...)` with the generation captured at read-start.
   - `Write` already overridden; no signature change.

3. **`watchable_store_txn.go`**
   - In `watchableStoreTxnWrite.End()`, add `tw.s.cache.invalidate(changes)` inside the existing `tw.s.mu.Lock()` section, before `tw.s.notify(rev, evs)` (ordering relative to `notify` doesn't matter for correctness since both happen before `tw.TxnWrite.End()`'s revision bump, but placing invalidation first keeps the "cache never trails visibility" ordering visually obvious in the diff).
   - Handle the zero-changes early-return branch too — no invalidation needed since nothing changed.

4. **`kvstore.go`**
   - Find the exact `Compact` implementation site (already in cell) and add the new eviction call once `compactMainRev` is updated, guarded the same way other post-compaction bookkeeping is guarded.

5. **`CODEMANIFEST` / `.usages/read-cache.md`**
   - Document the new internal behavior as an annotation on `KV`/`WatchableKV` (or a dedicated `ReadCache` entity, decided during manifest reconciliation) stating the consistency guarantee: synchronous, generation-fenced invalidation, not TTL-based, bounded LRU capacity.

## Specification Impact
`server/storage/mvcc/CODEMANIFEST` currently documents `KV`, `New`, `WatchStream`, `WatchableKV` with no caching annotation. Reconciliation (Step 7) will add either (a) a new annotation on `WatchableKV`/`New` describing the cache guarantee, or (b) a new `Entity` if the cache's surface is judged significant enough to be independently referenced — decided against actual code shape once implemented, per the reconciler's own step. No existing signature changes, so no import graph impact on dependent cells.

## Usage Impact
New cell-level practice `server/storage/mvcc/.usages/read-cache.md` describing, for consumers: "Range results may be served from an internal cache; this is transparent — same inputs always produce a result no staler than an uncached call at the same logical time; do not build your own additional caching layer on top assuming raw request-level TTL semantics." No existing `.usages` files exist in this cell to conflict with.

## Compatibility Verification
**Backward compatible.** Public `KV`/`WatchableKV`/`TxnRead`/`TxnWrite`/`RangeOptions`/`RangeResult` interfaces are unchanged (same methods, same signatures). `store` (non-watchable) is untouched — code paths using `NewStore` directly (some existing tests) see zero behavior change since caching only attaches at the `watchableStore` level. `StoreConfig` gains one optional field with a zero-value-safe default. No STOP condition triggered.

## Test Strategy
All new tests live in `server/storage/mvcc`, following existing conventions (`betesting.NewDefaultTmpBackend`, `zaptest.NewLogger`, `lease.FakeLessor`, table-driven where natural):
1. **Hit avoids real work**: Put a key, Range it twice with identical params via `watchableStore`; assert second call's result equals the first (`protocmp`) and instrument/assert (via a counter on a wrapped backend or by checking `readCache` internal hit counter) that the second call did not touch the backend read tx.
2. **Overlapping write invalidates**: Range a key (populate cache) → Put a new value for that key → Range again with identical params → assert the new value is returned, not the cached one.
3. **Non-overlapping write does not invalidate**: same as above but the write targets a disjoint key → assert the cache entry is still served (via hit counter) and still correct.
4. **Read-during-write race**: goroutine A starts a `Read`, blocks on a synchronization point before finishing (test hook / channel) while goroutine B does a `Put` on the overlapping key and completes fully (including `End()`, which bumps `c.generation`); goroutine A then finishes and calls its `TxnRead.End()` (which attempts `put`). Assert the entry is **not** cached (subsequent Range recomputes / sees fresh data), directly exercising the generation-gate.
5. **Serializable-equivalent freshness**: a Range immediately after a Put (same goroutine, no artificial delay) always observes the Put — exercises the "no reliance on TTL" requirement end-to-end at the `watchableStore` layer (the linearizable-specific composition with `LinearizableReadNotify` is covered indirectly since that mechanism is untouched and lives in a different cell; this test proves the necessary precondition — local writes are visible immediately, before any TTL could possibly expire).
6. **Compaction evicts pinned-revision entries**: Range at an explicit past `Revision`, compact past it, Range again at the same `Revision` → assert `ErrCompacted`, not a stale cached success.
7. **Cache-key discrimination**: single-key (`end=nil`) vs from-key (`end=[]byte{}`) vs bounded range with the same `key` bytes must be distinct cache entries (regression test for the nil/empty-slice pitfall).
8. **Full existing suite regression**: run `go test ./server/storage/mvcc/...` unmodified to confirm no existing test broke.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Shared-mutation corruption via cached `*mvccpb.KeyValue` (KeysOnly stripping, pruning) | High if unmitigated | High (silent data corruption across unrelated requests) | Deep-clone on both `put` and `get`, covered by test 7 (key discrimination) and general correctness tests. |
| Read-during-write staleness race (cache repopulated with stale data after invalidation) | Medium (narrow window, but real under load) | High (violates the linearizability requirement) | Generation-counter gate on `put`, covered by test 4. |
| Linear-scan invalidation cost under high write throughput with a large cache | Low-medium | Performance only, not correctness | Cache capacity is bounded (default 4096) by design — this is explicitly a small hot-key cache, not general-purpose; document the bound in `.usages/read-cache.md`. |
| `nil` vs `[]byte{}` end confusion collapsing distinct queries into one cache key | Medium if not carefully typed | Medium (wrong results for from-key queries) | Explicit `endKind` field in `readCacheKey`, covered by test 7. |
| Compaction racing a concurrent pinned-revision read | Low | Medium (stale post-compaction success) | Reuses the same generation-gated `put` path used for regular writes rather than a bespoke mechanism. |
| Lease-expiry deletes bypassing invalidation | Very low (confirmed non-issue) | High if wrong | Confirmed in Investigation: both construction sites register `s.Write` as the `RangeDeleter`; covered implicitly since invalidation hooks `Write`/`End`, not a request-type-specific path. |

Do you approve this plan? Proceed to implementation?
