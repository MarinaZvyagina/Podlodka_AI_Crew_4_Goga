# R06-TD-GC-05

Condition: goga_native_architecture
Base tag: condition-c-r06-v1
Functional success: True
Full architecture conformance: False
ACR: 0.6
Dangerous success: True
Goga engagement signal: True
Cost: $2.2118807999999994
Duration: 461842ms, turns: 51

## Agent's own summary

# Change Plan

## Task Classification
**Feature (extension)** — adds a new performance optimization (read caching) to an existing method without altering its contract, signature, or observable behavior on cache-miss.

## Affected Cells
| Cell | Files to Modify | What Changes |
|---|---|---|
| `server/etcdserver` | `server/etcdserver/range_cache.go` (new), `server/etcdserver/v3_server.go` (edit `Range`), `server/etcdserver/server.go` (add field + init), `server/etcdserver/CODEMANIFEST` (annotate), `server/etcdserver/range_cache_test.go` (new) | Add an unexported, revision-fenced cache type; wire it into `EtcdServer.Range`'s `get()` closure; initialize it in `NewServer`; document it in the manifest. |
| `server/storage/mvcc` | none | Consumed read-only via already-imported `KV.Rev()`; no contract change. |

## Root Cause Analysis
`EtcdServer.Range` (`server/etcdserver/v3_server.go:106`) unconditionally executes a full MVCC scan (`txn.Range`) on every call, even when an identical request was just answered and nothing has changed. There is currently no mechanism to short-circuit repeated identical reads.

## Trace Summary
`EtcdServer.Range` → `doSerialize(chk, get)` → `get()` → `txn.Range(ctx, s.Logger(), s.KV(), r, true)` → `mvcc.KV.Read(...)` snapshot, with `resp.Header.Revision` set to the store's revision at snapshot time (`rr.Rev`). Auth check (`chk`) runs unconditionally before `get()`, unaffected by caching. `v3rpc.kvServer.Range` mutates `resp.Header` in place after return (`hdr.fill`), which is why cache hits must return a cloned response, never a shared pointer.

## Change Strategy

1. **New file `server/etcdserver/range_cache.go`** — define:
   - `rangeCacheKey` — a comparable struct built from the cacheable subset of `*pb.RangeRequest` fields (`Key`/`RangeEnd` as `string`, `Limit`, `SortOrder`, `SortTarget`, `KeysOnly`, `CountOnly`, `MinModRevision`, `MaxModRevision`, `MinCreateRevision`, `MaxCreateRevision`).
   - `rangeReadCache` — holds a mutex, the last-known revision ("generation"), and `map[rangeCacheKey]*pb.RangeResponse`.
   - `newRangeReadCache() *rangeReadCache`.
   - `(c *rangeReadCache) get(r *pb.RangeRequest, currentRev int64) (*pb.RangeResponse, bool)`:
     - returns `false` immediately if `r.Revision != 0` (only current-revision reads are cacheable).
     - locks, checks `c.generation == currentRev`; if so, looks up the key; on hit returns `proto.Clone(resp).(*pb.RangeResponse), true`.
   - `(c *rangeReadCache) put(r *pb.RangeRequest, resp *pb.RangeResponse)`:
     - returns immediately (no-op) if `r.Revision != 0`.
     - locks; if `resp.Header.Revision != c.generation`, a newer revision has appeared — reset the map and bump `c.generation` to `resp.Header.Revision` (this is the "invalidate everything cached under an older, now-superseded revision" step — correct because any write anywhere bumps the store revision, and we can't cheaply tell if any *particular* stale entry's range was affected, so we conservatively drop all of them).
     - stores `proto.Clone(resp).(*pb.RangeResponse)` under the derived key (clone taken at store time so the cache's copy is independent of the object handed back to the RPC layer, which `hdr.fill` will mutate).
   - a private constructor for `rangeCacheKey` from `*pb.RangeRequest`.

2. **Edit `server/etcdserver/v3_server.go`, `EtcdServer.Range`** (lines ~145-154): replace
   ```go
   get := func() { resp, _, err = txn.Range(ctx, s.Logger(), s.KV(), r, true) }
   ```
   with a closure that first calls `s.rangeCache.get(r, s.KV().Rev())`; on hit, sets `resp` from the cached clone and returns; on miss, performs the exact same `txn.Range` call as today, and on success calls `s.rangeCache.put(r, resp)` before returning. `doSerialize`, `chk`, error handling, tracing, and the surrounding function body are untouched.

3. **Edit `server/etcdserver/server.go`**: add field `rangeCache *rangeReadCache` next to the `kv mvcc.WatchableKV` field, and initialize it with `newRangeReadCache()` at the same point `kv` is constructed in `NewServer` (and, if `kv` is ever replaced wholesale — e.g. on snapshot restore alongside `NewUberApplier` — reset `rangeCache` there too, since a replaced store means old cached entries and revisions are no longer meaningful).

4. **Manifest**: add a `Usages` entry (or extend `write_path`) describing the caching behavior and the revision-fencing invariant, and reference it from the `EtcdServer().Range` / `RaftKV().Range` method annotations.

## Specification Impact
`server/etcdserver/CODEMANIFEST`:
- Extend the header `Usages.write_path` (or add a new `read_cache` usage key) explaining: reads may be served from an in-memory cache keyed by request parameters, valid only while `KV`'s current revision matches the revision the cached response was captured at; any committed write invalidates all entries from an older revision; only current-revision (`Revision == 0`) requests participate.
- Update `EtcdServer().Range` and `RaftKV().Range` method annotations to reference the new usage, noting the cache never changes what is returned, only whether the underlying scan is repeated.
No signature changes; no new/removed types in the contract surface (the cache is an internal implementation detail, not part of the exported API — it will not appear in `goga schema`'s type list for the cell).

## Usage Impact
No `.usages/*.md` files exist for `server/etcdserver` today (`goga schema` shows `usages: []`). None require updates since there are no consumer-facing practice files describing `Range` consumption patterns to keep in sync. (No new `.usages` file will be created either — the caching detail is an internal implementation note, not a consumption pattern change; consumers of `EtcdServer`/`RaftKV` see no API difference.)

## Compatibility Verification
**Backward compatible.** Cache-miss path is byte-identical to current code (same function calls, same arguments, same object returned). Cache-hit path returns a value proven equal to what a fresh call would produce at that instant (same revision ⇒ same MVCC snapshot ⇒ same result), returned as an independent clone to avoid the `hdr.fill` mutation race. No signature, type, file path, or manifest-guarantee changes. No existing test should observe any difference.

## Test Strategy
1. **New unit tests in `server/etcdserver/range_cache_test.go`** (no full `EtcdServer`/raft/mvcc setup needed — pure logic tests against `rangeReadCache`):
   - Hit: `put` then `get` with identical request params and unchanged revision returns a cloned-but-equal response.
   - Miss on different params: different key/limit/sort/etc. under the same revision misses.
   - Miss on explicit revision: `r.Revision != 0` never hits or populates the cache.
   - Invalidation on revision bump: after `put` at revision N, a `get` call passing `currentRev = N+1` misses, and a subsequent `put` at revision N+1 clears the entry previously stored at N (verify old-key lookup also misses post-bump, proving the generation reset, not just per-key staleness).
   - Returned object independence: mutate the response returned by `get` (simulating `hdr.fill`) and verify a second `get` call is unaffected (proves clone-on-read).
   - Concurrency: concurrent `get`/`put` calls (via `go test -race`) don't race.
2. **Existing integration tests** (`tests/integration/clientv3/kv_test.go` `TestKVRange`, etc.) must continue to pass unmodified — they validate the cache-miss path is unchanged and, incidentally, that repeated identical `Get`s still return correct data (exercising the cache-hit path transparently).
3. Consider adding one integration-level test asserting a `Put` between two identical `Get`s is observed by the second `Get` (directly exercises the "no staler than an uncached read" requirement end-to-end), if the existing integration test harness supports revision inspection conveniently — to be confirmed during implementation/test-engineer step.

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Shared mutable response object races across concurrent cache hits | Medium (without mitigation) | High (data race, corrupted headers) | Clone on both `put` (store-side) and `get` (read-side); verified with `-race` in new tests. |
| Cache grows unbounded under high key-space cardinality | Low | Low-Medium (memory) | Whole-map reset on every revision bump naturally bounds retention to "distinct requests since the last write" — in a write-idle window count is bounded by distinct client request shapes, not by keyspace size; no TTL needed. |
| Added `s.KV().Rev()` call on every `Range` (hit and miss) increases per-request overhead | Low | Low | `Rev()` is an existing, already-used idiom in this file (`v3_server.go:429,730`) and opens only a short-lived `SharedBufReadTxMode` read tx — cheap relative to a full range scan; net effect is still a large win for repeated-read bursts. |
| Compaction interacting with cached historical reads | Low (mitigated by design) | Medium if unmitigated | Only `Revision == 0` requests are cached; explicit historical-revision reads always bypass the cache, sidestepping the `ErrCompacted`-after-cache scenario entirely. |
| `NewUberApplier`/snapshot-restore replaces `kv` wholesale, potentially leaving cache referencing a stale generation number from before the restore | Low | Medium (could very rarely serve one stale response after restore before revision naturally diverges) | Reset `s.rangeCache` alongside `kv` replacement in the restore path, matching how other per-store state is already reset there. |

---

**Do you approve the plan? Proceed to implementation?**
