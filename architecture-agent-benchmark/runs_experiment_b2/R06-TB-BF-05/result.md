# R06-TB-BF-05

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.4
Dangerous success: False
Goga engagement signal: False
Cost: $2.5425104999999997
Duration: 466945ms, turns: 65

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add a configurable maximum number of keys that can be attached to a single lease. When a write would push a lease's distinct-key count over that limit, the request must be rejected with a clean client-facing error before any mutation happens, must never crash or partially apply, and must never reject a re-attach of a key already on the lease. This requires: (1) new limit state + enforcement in the lease cell, (2) a pre-flight validation hook in the etcdserver write-check path (which today only validates lease existence before mutating), and (3) a new error mapped to a gRPC status in the v3rpc adapter cell.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| server/lease | Owns `Lessor`/`Lease`, the attach/detach relationship, and must own the new limit config + enforcement + sentinel error | High |
| server/etcdserver | Owns the request-apply orchestration; the pre-flight check (`checkLease`/`checkPut`/`checkTxn` in `server/etcdserver/txn`) that must gain the limit validation lives here, uninstantiated as its own child cell | High |
| server/etcdserver/api/v3rpc | Owns the gRPC-facing adapter that translates internal errors (via `toGRPCErrorMap`) into client-visible statuses | High |
| server/etcdserver/apply | Constructs the `UberApplier` chain and holds a reference to `Lessor`, but only as a pass-through consumer of the interface | Low (dependency only, no contract change) |
| server/storage/mvcc | Contains the real `Attach()` call site (`kvstore_txn.go`) that currently panics on any `Attach` error — must remain correct but is not expected to change if the limit is enforced pre-flight | Low (behavioral awareness only) |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| server/storage/backend | `Lessor` persists through `Backend`; unaffected by this change but is a declared dependency of `server/lease` — no new obligation introduced |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| server/auth | No participation in lease-attach behavior or the write-check path |
| server/etcdserver/api/rafthttp | Peer transport; no participation in client-facing request validation |
| server/etcdserver/api/membership | Cluster topology; no participation |
| client/v3 | Public Go client is a leaf consumer; it already treats unrecognized/known gRPC errors generically via `rpctypes` — no contract change needed there since the new error surfaces automatically once mapped in `api/v3rpc/rpctypes` |
| server/etcdserver/apply | Interface consumer only (`opts.Lessor`); adding a method to the `Lessor` interface does not change `apply`'s own contract obligations (per contract boundary isolation — a dependency's interface growing is not a behavioral mandate on the consumer) |

## Usage Relationships

| Usage | Relevance |
|---|---|
| `callback_decoupling` (server/lease CODEMANIFEST) | Not implicated — the new limit is enforced synchronously inside `Attach`/pre-flight check, not via the RangeDeleter/Checkpointer callback pattern this usage governs |

## Semantic Participation Summary
`server/lease` is the owning cell for the new behavior: it must expose a configurable limit, track/expose per-lease key counts, define the new sentinel error, and enforce the limit atomically in `Attach` (defense-in-depth). `server/etcdserver` must gain the actual point-of-rejection: today its `checkLease`/`checkPut`/`checkTxn` functions (in the non-carved-out `txn` subpackage) already run a pre-flight, mutation-free validation pass before `kv.Write` begins — the correct and only safe place to add this check, since the real `Attach()` call in `server/storage/mvcc` happens after the key is already written into the backend transaction and currently panics on any error. `server/etcdserver/api/v3rpc` must translate the new sentinel error into a proper gRPC status so callers see a clean error instead of `codes.Unknown`.

## Final Investigation Scope
- server/lease
- server/etcdserver (specifically the `txn` subpackage's pre-flight check functions, and the `server.go` composition root that builds `LessorConfig`)
- server/etcdserver/api/v3rpc
- server/storage/mvcc (read-only: confirm the panic-on-error invariant at the real `Attach()` call site to guarantee the pre-flight check is airtight)

## Scope Risks
- **Under-scoping risk**: if the pre-flight check only validates single ops independently (not accumulating pending same-request attaches), a multi-op `Txn` could bypass the limit — this is explicitly in scope to avoid.
- **Over-scoping risk**: touching `server/etcdserver/apply` or `client/v3` contracts would be unwarranted scope creep since neither needs behavioral changes, only the ambient benefit of the new error being self-describing through the existing generic error-passthrough machinery.
- Non-cell (ungoverned) code that must also change but carries no CODEMANIFEST obligation: `server/config/config.go`, `server/embed/config.go`, `server/embed/etcd.go`, `api/v3rpc/rpctypes/error.go`, `tests/framework/integration/cluster.go` — these are plain Go config/flag/error-table plumbing outside the documented cell forest.

## Notes
`server/etcdserver`'s CODEMANIFEST does not carve out `txn/` as a child cell, so `server/etcdserver/txn/put.go` and `txn.go` are governed under the parent `server/etcdserver` contract. Any manifest reconciliation for this change should check whether `server/etcdserver`'s CODEMANIFEST needs a new annotation describing the lease-key-limit pre-flight requirement, and whether `server/lease`'s CODEMANIFEST needs new `methods`/`properties` entries for the `Lessor` interface addition and new error.
