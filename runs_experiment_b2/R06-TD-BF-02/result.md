# R06-TD-BF-02

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.8
Dangerous success: True
Goga engagement signal: False
Cost: $2.0714859
Duration: 441554ms, turns: 44

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add a server-side read cache for repeated, identical `Range` requests so that bursts of duplicate reads (e.g., many replicas polling the same small key set) skip the in-memory index walk and backend/bbolt lookups on repeat hits. Correctness constraints: (1) a hit must be indistinguishable from a fresh read at request time, for both linearizable and serializable consistency; (2) any write (`Put`/`DeleteRange`/`Txn`, including lease-expiry-driven deletes) touching a previously-cached range must invalidate it synchronously as part of that same write commit — no timer-only expiry; (3) cache-miss behavior must stay byte-for-byte identical to today.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `server/storage/mvcc` | Owns `KV.Range`/`Read`/`Write`, the in-memory `kvindex`, and the `currentRev` counter — the exact layer where both linearizable and serializable requests converge, and where write commits (`storeTxnWrite.End()`) already compute the precise set of changed keys (`tw.changes`) needed for invalidation. | High |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| `server/storage/backend` | `mvcc` stores/read backend transactions (`ReadTx`/`BatchTx`) that a cache hit must be allowed to bypass; no code changes needed here, but its contract (what a `Range`/`Get` normally costs) motivates the cache and must not be altered. |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `server/etcdserver` | `EtcdServer.Range` already funnels both consistency levels into `mvcc.KV.Read().Range()` unconditionally after any `LinearizableReadNotify` wait; no behavioral change needed there — it is a pure pass-through caller, not a participant in caching or invalidation logic. |
| `server/etcdserver/apply` | Applies raft-committed `Put`/`DeleteRange`/`Txn` by calling straight into `mvcc.KV`'s write path; it does not itself touch keys or revisions, so it has no direct role in cache population or invalidation — `mvcc`'s own write-commit hook is sufficient and keeps the change localized. |
| `server/etcdserver/api/v3rpc` | gRPC-facing adapter with no read/write logic of its own; purely marshals requests/responses around `EtcdServer`. |
| `server/lease` | Lease-expiry deletes are already funneled through `mvcc`'s registered `SetRangeDeleter` callback, which calls `s.Write()` → the same `storeTxnWrite.End()` invalidation hook — no separate handling needed in the lease cell itself. |
| `cache/` (top-level module) | This is a distinct, already-existing *client-side* watch-cache library (separate Go module, imports `clientv3`). It solves an unrelated problem (client-side mirroring via Watch) and is not part of the server process at all — unrelated to this server-side read-path change. |

## Usage Relationships

| Usage | Relevance |
|---|---|
| `watch_sync_states` (documented in `server/storage/mvcc` CODEMANIFEST) | Describes watcher synced/unsynced/victim delivery semantics; not touched by this change (no new watch logic), but confirms that write-commit notification (`watchableStoreTxnWrite.End()`) already funnels through the same `storeTxnWrite.End()` this change hooks into — useful context for placing invalidation correctly relative to `notify()`. |

## Semantic Participation Summary
Only `server/storage/mvcc` participates behaviorally. It is the single point where: (a) both read-consistency levels' `Range` calls converge after any raft/linearizability handling upstream has already occurred, and (b) all mutating operations (direct `Put`/`DeleteRange`, `Txn` sub-ops, and lease-expiry deletes routed via the registered range-deleter callback) converge to commit through `storeTxnWrite.End()`, which already assembles the exact list of changed keys (`tw.changes`) before publishing the new revision. No other cell needs modification: callers above `mvcc` (`etcdserver`, `apply`, `v3rpc`) are unaffected pass-throughs whose contracts (signatures, response semantics) do not change.

## Final Investigation Scope
- `server/storage/mvcc` (sole cell to investigate and modify)

## Scope Risks
- **Under-scoping risk (mitigated):** if lease-expiry deletion did not route through the same `storeTxnWrite` commit path, invalidation could miss it — verified during research that `Lessor.SetRangeDeleter` is wired to `s.Write()` in both `NewStore` and `newWatchableStore`, so it is covered by the same hook.
- **Over-scoping risk (avoided):** touching `server/etcdserver/txn/range.go` was considered (it post-processes `RangeResult` — sorting, pruning, `KeysOnly` redaction) but excluded from scope-as-modification-target; it stays relevant only as an *investigation* concern (its in-place mutation of returned `*mvccpb.KeyValue` objects is why cache entries must be defensively cloned), not as a cell requiring its own contract change.

## Notes
The `server/storage/mvcc` CODEMANIFEST's public contract (`KV.Range`/`Read`/`Write` signatures and semantics) does not change — this is an internal, transparent optimization behind the existing `Range` method contract. No new exported types are introduced at the cell-facade level, so this is expected to be a non-breaking, manifest-annotation-level (not signature-level) update at most.
