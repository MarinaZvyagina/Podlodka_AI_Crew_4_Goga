# R06-TB-BF-04

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: False
Cost: $2.5123161
Duration: 419945ms, turns: 58

## Agent's own summary

## Scope Resolution Report

# Scope Resolution Report

## Task Summary
Add a configurable maximum number of distinct keys attachable to a single lease. A write (Put or Txn) that would newly attach a key past that limit for its target lease must be rejected atomically with a clear client-facing error, without partial application, crash, or hang. Re-attaching an already-attached key must never be rejected, and leases under the limit must be unaffected. Existing over-limit leases must still recover/restart successfully.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `server/lease` | Owns the Lease/Lessor attach-detach relationship and the item set per lease; owns any new sentinel error for this policy | High |
| `server/etcdserver/apply` | The documented decorator-chain extension point for new cross-cutting request behavior on Put/Txn; owns `ApplierOptions` wiring | High |
| `server/storage/mvcc` | `KV`/`TxnWrite.Put` is the mutation point that currently panics on unexpected `Attach` errors; must stay a no-op change if enforcement moves earlier | Medium |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| `server/lease` | Provides `Lease`, `Lessor.Lookup`, `Lessor.Attach`; new read accessors needed to answer "is key K already on lease L" and "how many keys does L have" without mutating |
| `server/etcdserver/apply` | `applierV3backend.Put/Txn` is where `Lessor`, `KV`, and per-request config (`ApplierOptions`) already converge for every committed Put/Txn; the natural injection point for a new configured limit |
| `server/storage/mvcc` | `storeTxnWrite.put()` calls `Lessor.Attach` today and panics on any error — must remain a no-op path (Attach must stay unconditional) so recovery/replay is never affected |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `server/auth` | No behavioral participation — RBAC is orthogonal to the lease key-count policy; existing `checkLeasePutsKeys` already iterates `Lease.Keys()` for permissions, unrelated to counting |
| `server/storage/backend` | Pure bbolt persistence primitive; the cap is an in-memory/admission-control concern, not a persistence-format change |
| `server/etcdserver/api/v3rpc` | Only a pass-through gRPC adapter; error surfaces via the existing `togRPCError` map (in `server/etcdserver/api/v3rpc/util.go`, not a documented cell) with no new behavioral logic of its own |
| `server/etcdserver/api/rafthttp`, `server/etcdserver/api/membership` | No participation — transport/topology only |
| `client/v3` | External consumer; receives the new gRPC error like any other status error, no contract change needed on the client cell itself |

## Usage Relationships

| Usage | Relevance |
|---|---|
| `decorator_chain` (in `server/etcdserver/apply` CODEMANIFEST) | Directly relevant: documents the intended extension point for new cross-cutting Put/Txn behavior ("add a new cross-cutting concern... as a new decorator in this chain rather than modifying the base applier"). Must be reconciled against the fact that Txn's atomicity requirement (no partial application) forces the actual precondition check to run against the already-resolved Compare winning-path, a detail currently owned by the *base* applier's `server/etcdserver/txn` package, not the decorator layer |
| `callback_decoupling` (in `server/lease` CODEMANIFEST) | Relevant as a boundary constraint: confirms `server/lease` must not gain a new outbound import toward `mvcc`/`etcdserver` to implement this — the cap enforcement must be driven from the caller side using data `Lessor`/`Lease` already exposes, not by `lease` reaching into txn machinery |

## Semantic Participation Summary
`server/lease` participates because it owns the exact state (`Lease.itemSet`) the cap decision depends on; it needs new read-only, thread-safe query surface (membership + count) plus a client-facing sentinel error, but its `Attach` mutation semantics and the `Lessor` interface itself stay untouched — recovery/replay must remain infallible. `server/etcdserver/apply` participates because it is the documented seam between raft-committed requests and the `Lessor`/`KV` cells, and owns `ApplierOptions`, the natural home for a new configured limit; however, its own CODEMANIFEST-documented decorator pattern assumes checks that don't need to know which Compare-branch of a Txn actually executes (auth and quota decorators both either check unconditionally-of-branch or check-then-allow-apply). This concern is different in kind — it requires the exact winning-path Put set before any mutation, which today is resolved inside `server/etcdserver/txn` (an undocumented, non-cell package invoked by `applierV3backend`, the innermost/base link of the decorator chain) via its existing `checkTxn`/`checkPut`/`checkLease` precondition phase — the same phase that already halts on `lease.ErrLeaseNotFound` before any write starts. `server/storage/mvcc` participates passively: it must NOT change behavior, confirming enforcement belongs strictly before `TxnWrite.Put`/`Lessor.Attach` are ever invoked.

## Final Investigation Scope
- `server/lease` (primary: new read accessors + new error)
- `server/etcdserver/apply` (primary: config wiring/threading through `ApplierOptions`, decorator-vs-base-execution placement decision)
- `server/storage/mvcc` (secondary: verify no behavior change required/occurs)
- `server/etcdserver/txn` (non-cell, but load-bearing: existing precondition-check phase is the only correctness-safe place for the atomic, branch-aware check — must be investigated even though it has no CODEMANIFEST)
- `api/v3rpc/rpctypes` and `server/etcdserver/api/v3rpc/util.go` (non-cell; existing `togRPCError` mapping table, needed for the client-facing error, no new logic)
- `server/embed`, `server/config` (non-cell; existing flag-threading pattern for `MaxTxnOps`, needed for "configurable at server startup")

## Scope Risks
- **Under-scoping risk**: if the decorator-chain guidance in `server/etcdserver/apply`'s CODEMANIFEST is treated as an absolute rule, an implementer could be pushed toward a decorator design that either (a) cannot guarantee non-partial Txn application, or (b) duplicates Compare-branch resolution outside `server/etcdserver/txn`, risking drift/inconsistency between two independent evaluations of the same Txn.
- **Over-scoping risk**: touching `server/lease`'s `Lessor` interface (e.g., adding a getter method) would force updates to `FakeLessor` and `etcdutl`'s `SimpleLessor` — unnecessary if the limit is threaded as a plain parameter instead of an interface method.
- **Non-cell blast radius**: `server/embed/config.go`, `server/config/config.go`, `server/etcdserver/txn/*.go`, and `api/v3rpc/rpctypes/error.go` are outside the documented cell forest (no CODEMANIFEST governs them), so manifest reconciliation (Step 7) will only cover `server/lease` and `server/etcdserver/apply`; the rest is validated by code review/tests only.

## Notes
This will be flagged explicitly at Planning (Step 3): the recommended design keeps the atomic, branch-aware precondition check inside `server/etcdserver/txn`'s existing `checkTxn`/`checkPut`/`checkLease` phase (extending the same mechanism that already halts on `lease.ErrLeaseNotFound`), with `server/etcdserver/apply`'s `ApplierOptions` carrying the new configured limit down to it — rather than adding a new standalone decorator. The `server/etcdserver/apply` CODEMANIFEST's `Annotations` will be updated to record this as a documented, deliberate exception to `decorator_chain`, with the reasoning captured inline.
