# R06-TC-BF-03

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.4
Dangerous success: False
Goga engagement signal: False
Cost: $2.0312167500000005
Duration: 213483ms, turns: 39

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add a uniform, compliance-grade audit-logging mechanism covering every key-value request (Range, RangeStream, Put, DeleteRange, Txn) handled by the etcd server: caller identity, operation kind, key/range, duration, and outcome — implemented as a structural decorator so new request types can't be silently missed, without altering functional behavior or existing logging.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `server/etcdserver/api/v3rpc` | Hosts `pb.KVServer` and the existing `quotaKVServer` decorator idiom; `grpc.go:80` is the single registration point where all four KV request kinds converge before the raft/serializable fork. This is where the new audit decorator is implemented and wired. | Primary |
| `server/etcdserver` | Exposes `EtcdServer.AuthInfoFromCtx(ctx)` (identity resolution, "unauthenticated" fallback via `(nil, nil)`) and the `RaftKV` interface that `v3rpc` depends on. No code changes here, but the audit decorator calls into it. | High (dependency, read-only) |
| `server/auth` | Defines `AuthInfo{Username, Revision}`, the type returned by `AuthInfoFromCtx`. Referenced, not modified. | Medium (type dependency) |
| `server/etcdserver/apply` | Its CODEMANIFEST explicitly names "audit logging" as an example for its decorator chain — but tracing confirmed Range and serializable/read-only Txn never enter this chain (they call `s.KV()` directly, bypassing raft/`uberApplier`). Flagged for a manifest-doc correction, not a code change. | Medium (doc-discrepancy only) |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| `server/etcdserver` | Supplies `AuthInfoFromCtx` (identity) and is the concrete type passed into `NewAuditKVServer(s, ...)`; the audit decorator's behavior is directly parameterized by this cell's API. |
| `server/auth` | `AuthInfo.Username` is the exact field surfaced in every audit record's caller-identity field. |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `server/storage/mvcc` | No direct participation — the audit decorator observes at the RPC boundary, never touches `KV`/`WatchableKV` directly. |
| `server/storage/backend` | Infrastructural-only; irrelevant to identity/operation/outcome capture at the RPC boundary. |
| `server/lease` | Out of task scope — task is scoped to key-value requests (Range/Put/DeleteRange/Txn), not lease operations. |
| `server/etcdserver/api/rafthttp` | Peer transport, no relevance to client-facing KV request auditing. |
| `server/etcdserver/api/membership` | No behavioral participation in KV request handling or auditing. |
| `client/v3` | Client-side cell; audit trail is a server-side concern only. |

## Usage Relationships

| Usage | Relevance |
|---|---|
| `server/etcdserver/apply`'s `decorator_chain` Usages entry | Directly relevant as a *documentation discrepancy*: it names audit logging as belonging to this chain, but the chain structurally cannot observe Range/serializable-Txn. Must be corrected during manifest reconciliation to avoid misleading future changes into the wrong extension point. |
| No cell-level `.usages/` practices exist yet in `server/etcdserver/api/v3rpc` for the decorator idiom (`quotaKVServer`) | Implicit precedent only — not a formal Usages practice today; nothing to import. |

## Semantic Participation Summary
`server/etcdserver/api/v3rpc` is the sole cell whose implementation changes: it gains a new decorator type wired into the existing `pb.KVServer` registration chain. `server/etcdserver` and `server/auth` participate only as read-only dependencies supplying the identity-resolution API and type already used elsewhere in `v3rpc` (e.g., `AuthAdmin`, `quotaKVServer`). `server/etcdserver/apply` participates only insofar as its manifest text is factually incorrect about being the uniform extension point for this concern — that text should be corrected so the documented architecture matches reality, even though no code in that cell changes.

## Final Investigation Scope
- `server/etcdserver/api/v3rpc` (implementation target)
- `server/etcdserver` (dependency verification: `AuthInfoFromCtx`, `RaftKV`, `EtcdServer.Logger()`)
- `server/auth` (dependency verification: `AuthInfo` shape)
- `server/etcdserver/apply` (manifest-text correction only, no code)

## Scope Risks
- **Under-scoping risk**: if `server/etcdserver/apply`'s manifest text is left uncorrected, a future engineer reading "add audit logging as a decorator here" will re-introduce a decorator that misses Range/serializable-Txn — the exact bug being fixed now. Mitigate by updating that cell's Usages text during reconciliation even though no Go code there changes.
- **Over-scoping risk**: none identified — `mvcc`/`backend`/`lease`/`rafthttp`/`membership` have no behavioral touchpoint with RPC-level request auditing and are correctly excluded.

## Notes
- `Compact` is intentionally out of scope (confirmed with the user's task framing: read/write/delete/transaction only, not maintenance operations).
- `RangeStream` is in scope as a "read" operation kind since it is a real, wire-exposed `pb.KVServer` method used by `etcdctl get` and `client/v3`.
