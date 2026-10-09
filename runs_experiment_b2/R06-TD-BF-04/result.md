# R06-TD-BF-04

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.8
Dangerous success: True
Goga engagement signal: False
Cost: $4.40896485
Duration: 663051ms, turns: 47

## Agent's own summary

# Change Plan

## Task Classification
**Feature (extension)** — additive caching behavior inside an existing cell's implementation, no contract-breaking changes.

## Affected Cells
| Cell | Files to Modify | What Changes |
|---|---|---|
| `server/storage/mvcc` | `kvstore.go` (new), `kvstore_txn.go` (edit), `read_cache.go` (new), `read_cache_test.go` (new), `kv_test.go`/`watchable_store_test.go` (edit, add coverage), `CODEMANIFEST` (edit) | Add `ReadCacheSize` to `StoreConfig`; add `readCache` field to `store`; hook lookup/populate into `storeTxnCommon.Range`; hook invalidation into `storeTxnWrite.End()`; hook purge into `updateCompactRev` and `Restore` |

## Root Cause Analysis
`server/storage/mvcc` is the single choke point for all reads (`storeTxnCommon.Range`, reached only via `store.Read()`/`storeTxnRead`) and all writes (`storeTxnWrite.End()`, reached from the applier and from lease-expiry alike). Its existing `revMu`/`s.mu` locking already provides the happens-before ordering a correct, non-TTL cache needs: any read that observes a given `currentRev` has, by construction, also observed every cache invalidation from every write committed at or before that revision. See Investigation Report for full evidence chain, including the downstream mutation hazard in `server/etcdserver/txn/range.go` that mandates defensive copying.

## Trace Summary
- Read: `EtcdServer.Range` → (linearizable: `LinearizableReadNotify` first) → `txn.Range` → `kv.Read()` → `storeTxnCommon.Range` → **[cache lookup here]** → `rangeKeys` on miss.
- Write: applier / lease-expiry → `kv.Write()` → `watchableStoreTxnWrite.End()` → `notify()` → **[cache invalidate here, per changed key]** → `storeTxnWrite.End()` (revMu bump).
- Compact: `store.Compact` → `updateCompactRev` → **[cache purge here]**, same `revMu.Lock()` section as `compactMainRev` bump.
- Restore: `store.Restore` → **[cache purge here]**, already fully serialized against readers by `s.mu.Lock()` for the whole call.

## Change Strategy
1. **`kvstore.go`**: add `ReadCacheSize int` to `StoreConfig`. In `NewStore`, apply default (`0` → `defaultReadCacheSize`; `<0` → disabled) and construct `s.readCache` accordingly. Add `readCache *readCache` field to `store`. In `updateCompactRev`, after `s.compactMainRev = rev` is committed, call `s.readCache.purge()`. In `Restore`, call `s.readCache.purge()` inside the existing `revMu.Lock()` block that resets `currentRev`/`compactMainRev` (or re-create `s.readCache` fresh there, which is equivalent and slightly simpler).
2. **`kvstore_txn.go`**: in `storeTxnCommon.Range`, consult `tr.s.readCache.get(key, end, ro)` before calling `rangeKeys`; on hit, return a defensively-copied `RangeResult` with `Rev: tr.Rev()`. On miss, call `rangeKeys` as today, and on success (`err == nil`) populate the cache with a defensive copy. In `storeTxnWrite.End()`, when `len(tw.changes) != 0`, call `tw.s.readCache.invalidate(kv.Key)` for every changed key, **before** the `revMu.Lock()`/`currentRev++` that follows, so the happens-before proof holds.
3. **`read_cache.go`** (new file): `readCache` type wrapping `k8s.io/utils/lru.Cache` (bounded LRU of `(key,end,RangeOptions) → *RangeResult`) plus `go.etcd.io/etcd/pkg/v3/adt.IntervalTree` as a reverse index from byte-key to the set of cache keys whose queried range could contain it — mirroring the existing, already-shipped `server/proxy/grpcproxy/cache` implementation exactly in structure (same libraries, same `Add`/`Get`/`Invalidate`/reverse-index-via-`Stab` pattern), adapted from `pb.RangeRequest`/`pb.RangeResponse` to `mvcc.RangeOptions`/`mvcc.RangeResult`. Includes the defensive-copy helper for `[]*mvccpb.KeyValue`.
4. Only `storeTxnCommon.Range` (used by read-only `storeTxnRead`) is touched — `storeTxnWrite.Range` (used for reads inside a write txn, e.g. `Txn` compare/then/else) defines its own `Range` method that shadows the embedded one and is deliberately left untouched, keeping that path byte-for-byte identical to today.

## Specification Impact
`server/storage/mvcc/CODEMANIFEST`:
- Add a new `Usages` entry, e.g. `read_cache_invalidation`, documenting: "`Range` results are cached in-memory and invalidated synchronously by every committed write (never by a timer); a cache entry is only ever absent or exactly as fresh as a live read." Reference it from the global `Annotations` and from `KV().methods."Range(...)"`'s annotation.
- Update `KV().methods."Range(...)"` annotation to state the caching behavior as a documented characteristic (not a contract signature change — `Range`'s input/output shape is untouched).
- Update `New(...)` annotation to mention `cfg` now also carries the read-cache size.
No signature in the Body section changes; this is annotation-only + one new documented `Usages` entry.

## Usage Impact
No pre-existing `.usages/` files exist for this cell (confirmed — cell has no `.usages` directory yet). This change will not create a consumer-facing `.usages` practice file, because the cache is purely an internal implementation characteristic of `Range` — it does not change how a consumer calls the cell's API, which is what `.usages` files document. No usage files to update.

## Compatibility Verification
**Backward compatible.** Confirmed in the Investigation Report's Breaking Change Assessment: all six questions answered NO, given identical `KVs`/`Count` on hit and miss, live-recomputed `Rev`, unchanged signatures, and unchanged miss-path code. The one open item — whether any existing test bypasses `Write()` in a way the cache can't see — is resolved empirically in the Test Strategy below, not assumed away.

## Test Strategy
1. **New `read_cache_test.go`**: unit tests for `readCache` in isolation — get/put round-trip, distinct `RangeOptions` combinations produce distinct entries, `invalidate` evicts only overlapping ranges (point and range), `purge` clears everything, LRU eviction at capacity.
2. **`kvstore_test.go` / `kv_test.go` additions**: end-to-end tests against `*store`/`*watchableStore` via the public `KV` interface only (no white-box access) proving the four requirements:
   - Repeated identical `Range` calls between writes return identical results (functional — cache is an implementation detail, so this mainly guards against regressions rather than proving "no work was redone"; add one white-box test in-package asserting a cache hit occurred, e.g. via a counter/spy, since that's the actual behavior under test).
   - A `Put`/`DeleteRange`/`Txn` affecting a previously-queried range is visible on the very next `Range` call for that range (no sleep/TTL wait).
   - A write to an unrelated key does **not** evict a cached entry for a different key (proves the cache stays useful under unrelated write traffic — the property that ruled out the pure-revision-keyed design).
   - `Range` calls with different `KeysOnly`/sort-affecting request shapes but identical `mvcc.RangeOptions` don't corrupt each other's data (regression test for the `range.go` mutation hazard) — best exercised at the `server/etcdserver/txn` level or by simulating the same mutation pattern directly against `mvcc.KV.Read().Range()` results in-package.
   - `Compact` followed by a `Range` at a now-compacted revision still returns `ErrCompacted` (not a stale cached success).
   - `Restore` drops all cached entries.
3. **Regression run**: full `go test ./server/storage/mvcc/...` (and `./server/etcdserver/txn/...`) with default `StoreConfig{}` (cache enabled by default) to catch any existing test that assumed no caching — fix forward if found, per Investigation's open risk item.

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Existing test bypasses `Write()`/mutates backend directly, cache serves stale data in that test | Low (no such pattern found in preliminary grep) | Medium (test failure, not prod correctness) | Run full test suite post-implementation; fix any such test to go through the normal write path, or explicitly disable caching (`ReadCacheSize: -1`) in that specific test if bypassing is intentional test scaffolding |
| Interval tree (`adt.IntervalTree`) grows unbounded over long uptime as distinct never-repeating ranges are queried (LRU evicts the value side but not the reverse-index node) | Low-medium, same accepted trade-off as the already-shipped `grpcproxy/cache` | Low (slow memory growth, not correctness) | Mirror the exact same accepted behavior as `server/proxy/grpcproxy/cache/store.go`, which has this same characteristic in production; do not over-engineer beyond existing precedent |
| Forgetting the defensive-copy step, reintroducing the `KeysOnly`/sort mutation-corruption hazard found during tracing | Was Medium before this plan; now Low | High if missed (data corruption across unrelated requests) | Explicit copy-in/copy-out implementation step + dedicated regression test in Test Strategy item 2d |
| `RangeResult.Rev` served stale from cache instead of live current revision | Low (explicitly designed against) | Medium (clients could see revision go backward) | `get()` always returns `Rev: tr.Rev()` from the calling txn, never the cached value — covered by design, verify with a dedicated assertion in tests |

## Compatibility Verification
Backward compatible — no STOP condition triggered.

Do you approve the plan? Proceed to implementation?
