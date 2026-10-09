# R06-TD-BF-03

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.8
Dangerous success: True
Goga engagement signal: False
Cost: $2.5745093999999997
Duration: 760623ms, turns: 57

## Agent's own summary

Good, this confirms the exact hook point. Now writing the Change Plan.

## Change Plan

### Task Classification
**Feature** (performance optimization with a hard correctness invariant) — additive, internal to `server/etcdserver`.

### Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `server/etcdserver` | `range_cache.go` (new), `v3_server.go`, `server.go`, `metrics.go` | New bounded, revision-validated LRU cache type; `Range()`'s `get` closure checks/populates it; `applySnapshot`'s restore path purges it; new hit/miss counters |

No other cell's files, CODEMANIFEST, or exported signatures change.

### Root Cause Analysis
Every `Range` RPC redoes the full `txn.Range` → `executeRange` scan (tree-index walk, backend value fetch, filter/sort/assemble) even when issued moments after an identical request against unchanged data — there is no memoization keyed to MVCC's own revision, which is the only quantity that actually determines a `Range` result.

### Trace Summary
`kvServer.Range` → `EtcdServer.Range` → (`!Serializable`) `s.read.LinearizableReadNotify` → `s.doSerialize(chk, get)` → `chk` (RBAC) → `get` → **[new: cache check]** → `txn.Range` (on miss only) → `executeRange` → `asembleRangeResponse`. Cache insertion point is inside `get`, after both the linearizability barrier and the RBAC check, so it inherits both guarantees unconditionally.

### Change Strategy
1. **`server/etcdserver/range_cache.go` (new)**: define `rangeCacheKey` (comparable struct: `key, rangeEnd string; revision, limit int64; sortOrder, sortTarget int32; keysOnly, countOnly bool; minMod, maxMod, minCreate, maxCreate int64`) and a `rangeCache` type wrapping a `container/list`-based LRU bounded at a fixed capacity constant (e.g. `rangeCacheCapacity = 512`), guarded by a `sync.Mutex`.
   - `get(kv mvcc.KV, r *pb.RangeRequest) (*pb.RangeResponse, bool)`: opens one `kv.Read(mvcc.SharedBufReadTxMode, traceutil.TODO())`, reads `rev, firstRev := tr.Rev(), tr.FirstRev()`, calls `tr.End()`; computes `effRev := r.Revision; if effRev == 0 { effRev = rev }`; if `effRev < firstRev`, returns `(nil, false)` (would be `ErrCompacted` — never served from or written to cache); builds the key; on hit, returns a **fresh** `*pb.RangeResponse{Header: &pb.ResponseHeader{...cloned...}, Kvs: cached.Kvs, Count, More}`.
   - `put(r *pb.RangeRequest, effRev, firstRev int64, resp *pb.RangeResponse)`: no-op if `effRev < firstRev`; otherwise clones `resp` into a private entry (fresh `Header`, shared `Kvs`) and inserts/evicts LRU-oldest at capacity.
   - `purge()`: clears all entries (used on restore).
2. **`v3_server.go`**: in `Range()`'s `get` closure, call `s.rangeCache.get(s.KV(), r)` first; on hit, set `resp` and return; on miss, call `txn.Range` exactly as today, and if `err == nil` call `s.rangeCache.put(...)` with the same `resp` object the caller will receive (the `put`/clone logic guarantees no aliasing back to the caller's copy). Add a hit/miss counter increment.
3. **`server.go`** (`applySnapshot`, right after `s.kv.Restore(newbe)` succeeds at line 1064): call `s.rangeCache.purge()` — eliminates any theoretical staleness window across a wholesale backend replacement, at negligible cost since restores are rare.
4. **`metrics.go`**: add `rangeCacheHits`/`rangeCacheMisses` counters (or a single `rangeCacheEvents` CounterVec with a `result` label), registered the same way as existing `requestDurationSec`.
5. `s.rangeCache` is constructed once in the `EtcdServer` constructor alongside other fields (zero-value-unsafe `container/list`-backed type needs explicit `New()`).

### Specification Impact
No `CODEMANIFEST` body signature changes (no new/changed type, method, or property visible to consumers). The `server/etcdserver` `CODEMANIFEST`'s `Range` method annotation ("Serve a linearizable or serializable key/range read, per `write_path`") remains accurate — this is a pure internal-implementation refinement of that same behavior. Per DSL, `location:` fields already list only files with declared types; `range_cache.go` introduces no new declared type/method that needs a CODEMANIFEST entry, since `rangeCache`/`rangeCacheKey` are unexported implementation details, not part of the cell's public API contract. **Manifest reconciliation step will double check whether a short annotation addendum (not a new type) is warranted to document the caching behavior for future maintainers** — this is a documentation nicety, not a contract change.

### Usage Impact
No `.usages/*.md` files reference `Range`'s internals in a way that becomes stale — the public consumption pattern (call `Range`, get a `RangeResponse`) is unchanged. No usage file updates required.

### Compatibility Verification
**Backward compatible.** Cache-miss path is byte-identical to current code (same call, same object returned, unmodified). Cache-hit path returns a response equivalent in every client-observable field to what a fresh call would produce for the same effective revision, per MVCC immutability. No exported signature changes anywhere. Confirmed against Investigation Report's Breaking Change Assessment (all six checks: NO).

### Test Strategy
1. **Unit tests for `rangeCache`** (`range_cache_test.go`): hit-after-put returns equivalent data; distinct keys (varying each field) don't collide; entry below `firstRev` is neither served nor stored; LRU eviction at capacity; returned response on hit has a distinct `Header` pointer from the stored entry (regression guard for the aliasing hazard) while sharing `Kvs`.
2. **`EtcdServer.Range` integration-level test** (extend existing `v3_server_test.go` if present, else add): repeated identical `Range` calls with no intervening write return equal data and the second call doesn't invoke the underlying `KV.Read`'s full range scan (assert via a counting fake `mvcc.KV`, or assert cache hit counter increments); a `Put` between two identical `Range` calls forces a fresh read (cache miss, updated data visible); a `Range` at an explicit historical revision that later gets compacted returns `ErrCompacted` on every call, cached or not.
3. **Concurrency test**: many goroutines issuing the identical `Range` concurrently under `-race` — verifies no shared mutable `Header` aliasing.
4. Existing `TestV3RangeRequest`-style e2e/integration tests (etcdctl/tests/integration) must continue passing unmodified — confirms no observable behavior drift for both serializable and linearizable reads.

### Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Shared mutable `Header` aliasing causes data race under concurrent hits | Medium (without care) | High (race, corruption) | Always clone `Header` per returned response, both on hit and when storing; covered by dedicated unit test + `-race` concurrency test |
| Cache grows unbounded under high key-space cardinality | Low | Medium (memory) | Fixed-capacity LRU eviction |
| Stale historical-revision entry survives past a compaction | Low (only affects explicit `Revision` reads) | Low (would only mis-serve a should-be-`ErrCompacted` response) | Every `get`/`put` re-checks live `FirstRev()`; never serves/stores below it |
| Restore/snapshot-install leaves stale entries referencing pre-restore data | Very low (revisions are monotonic across a correctly functioning cluster) | Low–Medium | Explicit `purge()` call right after `s.kv.Restore(newbe)` |
| Extra `kv.Read()/End()` cycle per request adds latency even on miss | Low | Low | `SharedBufReadTxMode` avoids the buffer-copy cost; this is the same lock/txn-open cost already paid inside `txn.Range` itself, not new order-of-magnitude work |

---

Do you approve this plan? Proceed to implementation?
