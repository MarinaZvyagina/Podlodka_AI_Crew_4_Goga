# R06-TD-GC-07

Condition: goga_native_architecture
Base tag: condition-c-r06-v1
Functional success: True
Full architecture conformance: False
ACR: 0.6
Dangerous success: True
Goga engagement signal: False
Cost: $3.0389337
Duration: 520043ms, turns: 61

## Agent's own summary

## Change Plan

### Task Classification
**Feature** (additive, internal-only optimization) — no public API, CODEMANIFEST-declared signature, or cross-cell contract changes.

### Affected Cells
| Cell | Files to Modify | What Changes |
|---|---|---|
| `server/storage/mvcc` | **New:** `range_cache.go`, `range_cache_test.go`. **Modified:** `kvstore_txn.go` (wire cache into `storeTxnCommon.Range`), `kvstore.go` (add `rangeCache` field to `store`, initialize in `NewStore`, clear in `Restore`), `metrics.go` (two new counters + registration), `CODEMANIFEST` (document the new internal type per DSL — see Specification Impact). | Add a revision-keyed, size-bounded cache for current-revision (`RangeOptions.Rev <= 0`) reads. |

### Root Cause Analysis
`storeTxnCommon.Range` (kvstore_txn.go:69-71) unconditionally re-executes `rangeKeys` — an in-memory tree-index traversal plus one backend `UnsafeRange` + `proto.Unmarshal` per matching key — on every call, even when an identical `(key, end, RangeOptions)` request was just served at the same store revision. The `HashStorage` type in the same package (`hash.go`) already establishes the sanctioned idiom for this exact problem class ("cache by revision, avoid recomputation") for a different read (`HashByRev`).

### Trace Summary
- Sole safe interception point: `storeTxnCommon.Range` (kvstore_txn.go:69-71). Reached only via `storeTxnRead` (read-only transactions, directly or through `readView`/`metricsTxnWrite` wrappers). `storeTxnWrite` defines its own shadowing `Range` (kvstore_txn.go:189-195, reading at in-progress `beginRev`) and never reaches `storeTxnCommon.Range` — confirmed excluded by construction, no guard needed.
- `tr.Rev()` is a **frozen per-transaction snapshot** captured once in `store.Read()` (kvstore_txn.go:61), not a live re-read — proven safe under concurrent writes by `TestConcurrentReadNotBlockingWrite` (kvstore_test.go:736-790): two txns opened before/after a write naturally key to different revisions.
- `store.Restore` (kvstore.go:292-314, 367) can reassign `currentRev` to a value already used pre-restore — the one case plain revision-keying is insufficient; requires an explicit cache clear.
- `store.Compact` never changes `currentRev` or current key content — no special handling needed.
- Downstream mutation of `*RangeResult`/`*mvccpb.KeyValue` in `server/etcdserver/txn/range.go` (`asembleRangeResponse`'s `Value = nil`, `pruneKVs`, `sort.Sort`) requires every value returned from the cache (on both store and hit) to be an independent deep clone.

### Change Strategy

**1. `server/storage/mvcc/range_cache.go` (new file)**
```go
package mvcc

import (
	"sync"

	"google.golang.org/protobuf/proto"

	"go.etcd.io/etcd/api/v3/mvccpb"
)

// rangeCacheMaxEntries bounds memory: oldest entry is evicted once the cache
// is full, regardless of which revision it belongs to.
const rangeCacheMaxEntries = 10000

type rangeCacheKey struct {
	rev            int64
	key            string
	end            string
	limit          int64
	countOnly      bool
	fastKeysOnly   bool
	withTotalCount bool
}

func newRangeCacheKey(key, end []byte, rev int64, ro RangeOptions) rangeCacheKey {
	return rangeCacheKey{
		rev:            rev,
		key:            string(key),
		end:            string(end),
		limit:          ro.Limit,
		countOnly:      ro.CountOnly,
		fastKeysOnly:   ro.FastKeysOnly,
		withTotalCount: ro.WithTotalCount,
	}
}

// rangeCache memoizes Range results for a fixed store revision, so repeated
// reads with identical parameters at the same revision skip re-executing
// the index walk and backend lookups. Keying by revision (rather than a
// timer) makes invalidation exact: a write always advances the revision
// before any read can observe it, so a stale hit is structurally impossible
// for the entries this cache is allowed to serve.
type rangeCache struct {
	mu      sync.RWMutex
	entries map[rangeCacheKey]*RangeResult
	order   []rangeCacheKey
}

func newRangeCache() *rangeCache {
	return &rangeCache{entries: make(map[rangeCacheKey]*RangeResult)}
}

func (c *rangeCache) get(k rangeCacheKey) (*RangeResult, bool) {
	c.mu.RLock()
	r, ok := c.entries[k]
	c.mu.RUnlock()
	if !ok {
		return nil, false
	}
	return cloneRangeResult(r), true
}

func (c *rangeCache) put(k rangeCacheKey, r *RangeResult) {
	stored := cloneRangeResult(r)
	c.mu.Lock()
	defer c.mu.Unlock()
	if _, exists := c.entries[k]; !exists {
		if len(c.order) >= rangeCacheMaxEntries {
			delete(c.entries, c.order[0])
			c.order = c.order[1:]
		}
		c.order = append(c.order, k)
	}
	c.entries[k] = stored
}

// purge discards every cached entry. Called on Restore, where a revision
// number is not guaranteed to identify the same data as before the restore.
func (c *rangeCache) purge() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.entries = make(map[rangeCacheKey]*RangeResult)
	c.order = nil
}

func cloneRangeResult(r *RangeResult) *RangeResult {
	kvs := make([]*mvccpb.KeyValue, len(r.KVs))
	for i, kv := range r.KVs {
		kvs[i] = proto.Clone(kv).(*mvccpb.KeyValue)
	}
	return &RangeResult{KVs: kvs, Rev: r.Rev, Count: r.Count}
}
```

**2. `kvstore_txn.go` — modify `storeTxnCommon.Range` only** (`rangeKeys` stays untouched, still used verbatim by `storeTxnWrite`):
```go
func (tr *storeTxnCommon) Range(ctx context.Context, key, end []byte, ro RangeOptions) (r *RangeResult, err error) {
	if ro.Rev <= 0 {
		k := newRangeCacheKey(key, end, tr.Rev(), ro)
		if cached, ok := tr.s.rangeCache.get(k); ok {
			rangeCacheHitCounter.Inc()
			return cached, nil
		}
		r, err = tr.rangeKeys(ctx, key, end, tr.Rev(), ro)
		if err == nil {
			tr.s.rangeCache.put(k, r)
		}
		rangeCacheMissCounter.Inc()
		return r, err
	}
	return tr.rangeKeys(ctx, key, end, tr.Rev(), ro)
}
```

**3. `kvstore.go`** — add `rangeCache *rangeCache` field to `store` struct next to `hashes HashStorage`; initialize `rangeCache: newRangeCache()` in `NewStore`; in `Restore` (already holding `s.mu.Lock()`), add `s.rangeCache.purge()` alongside the existing `currentRev`/`compactMainRev` reset.

**4. `metrics.go`** — add `rangeCacheHitCounter`/`rangeCacheMissCounter` (`etcd_mvcc_range_cache_hits_total` / `_misses_total`), registered in `init()`, matching the existing `rangeCounter` style.

### Specification Impact
CODEMANIFEST for `server/storage/mvcc` requires a new entry for the added internal type per DSL (any type occupying its own `location` file needs a contract entry — `range_cache.go` is new). Since `rangeCache`/`rangeCacheKey` are **unexported** (internal implementation detail, never part of `KV`'s public contract, never imported by another cell), per the Go language rules ("Facade: the Go package itself serves as the facade... CODEMANIFEST references exported names only") **no CODEMANIFEST entry is required or appropriate** — only exported identifiers are documented. The existing entries for `KV()`, `ReadView()` (`Range` method), `RangeOptions()`, `RangeResult()` remain accurate as-is: their documented behavior (inputs → outputs, error conditions) is unchanged; I will add one clarifying sentence to `ReadView.Range`'s existing annotation noting results may be served from an internal revision-scoped cache, purely descriptive, not a contract change.

### Usage Impact
None. No `.usages/` file describes `Range`'s internal execution strategy, and none needs to — practices document consumption of the facade, not internals. `watch_sync_states` is unaffected (confirmed in Investigation).

### Compatibility Verification
**Backward compatible.** No exported signature changes; cache-miss path is byte-identical to today's code (`rangeKeys` unmodified, called with identical arguments); cache-hit path returns a value satisfying the same documented contract (`RangeResult.Rev` = revision at execution time — true by construction since the key is that same revision). `storeTxnWrite.Range` (read-your-own-writes inside a raft-apply write txn) is untouched. Verified against `TestConcurrentReadNotBlockingWrite`'s ordering requirement (see Investigation).

### Test Strategy
- **New `range_cache_test.go`:** unit tests for `rangeCache` in isolation — get/put/miss, eviction at `rangeCacheMaxEntries`, `purge`, and a mutation-isolation test (mutate a `KeyValue` returned from `get`/passed to `put`, assert the cache's internal copy is unaffected — directly exercises the aliasing risk found in Investigation).
- **Extend `kvstore_txn_test.go` / `kvstore_test.go`:**
  - Repeated identical `Range` calls at the same revision return equal (`cmp.Equal` + `protocmp.Transform`) results and the second call hits cache (assert via exported counter delta or an injected test hook).
  - A `Put` between two identical `Range` calls changes the observed result (no staleness) — directly encodes the core correctness requirement.
  - A `Range` call inside an open write txn (`storeTxnWrite.Range`, e.g. via the existing `delete.go`-style test) is unaffected/never cached.
  - `Restore` followed by a `Range` call for a key/revision combination that existed pre-restore returns the **post-restore** data, not a stale pre-restore cache hit — directly encodes the Restore-collision risk found in Investigation.
  - `Compact` between two identical current-revision `Range` calls does not change the (still-correct) cached result and does not error.
  - Two `mvccpb.KeyValue` objects returned from two different `Range` calls hitting the same cache entry are distinct pointers (regression guard for the aliasing bug class).
- Run full existing `server/storage/mvcc` suite to confirm no regressions (`TestConcurrentReadNotBlockingWrite` in particular).

### Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Stale data served across `Restore` due to revision-number reuse | Low (only on snapshot install) | High (correctness) | Explicit `purge()` inside `Restore`, covered by dedicated test. |
| Cache pollutes memory under high key-range cardinality | Medium | Low (bounded) | Hard cap `rangeCacheMaxEntries` with FIFO eviction. |
| Aliasing/mutation corrupts cached or returned data | Was High pre-mitigation | High (correctness) | `proto.Clone` on both store and hit paths; regression test asserts distinct pointers. |
| Cache thrash under interleaved reads opened at different (older/newer) revisions | Low-Medium | Low (perf only, not correctness) | Multi-revision FIFO map (not single-active-revision reset) avoids one revision's reads evicting another's; accepted as a performance characteristic, not a correctness issue. |
| Lock contention from new `rangeCache.mu` under heavy read load | Low | Low | Independent leaf `sync.RWMutex`, same idiom as already-proven `hashStorage.hashMu`; RLock-dominant path for the hot case (cache hit). |

No conflicts with CODEMANIFEST-defined algorithms; no breaking change; scope stays within the Investigation's confirmed boundary.

---

Do you approve this plan? Proceed to implementation?
