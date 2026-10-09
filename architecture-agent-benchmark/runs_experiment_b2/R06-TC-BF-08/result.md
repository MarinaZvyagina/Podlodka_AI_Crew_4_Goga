# R06-TC-BF-08

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.4
Dangerous success: True
Goga engagement signal: True
Cost: $2.8404
Duration: 427655ms, turns: 65

## Agent's own summary

This is complete and verified. Summary of the change:

**What was done:** Added a uniform audit trail for every key-value request by decorating `pb.KVServer` at the gRPC boundary in `server/etcdserver/api/v3rpc/`, following the cell's own documented `decorator_wrapping` extension pattern (goga's CODEMANIFEST for that cell explicitly says: *"Add a new cross-cutting gRPC-level concern as a new decorator around the relevant service struct rather than editing it directly"*).

**Why this location, not the `apply` decorator chain:** I initially considered the `server/etcdserver/apply` decorator chain (its CODEMANIFEST even name-checks "audit logging" as an example use case), but tracing `EtcdServer.Range` in `v3_server.go` showed that reads (serializable *and* linearizable) call `txn.Range` directly and never go through the raft-apply chain — only Put/DeleteRange/Txn do. That would have silently missed all reads. The `pb.KVServer` interface (`Range`, `RangeStream`, `Put`, `DeleteRange`, `Txn`, `Compact`) is the one place all four KV verbs genuinely converge, so wrapping it is the only place coverage is truly uniform.

**Files:**
- `server/etcdserver/api/v3rpc/audit.go` (new) — `auditKVServer` wraps any `pb.KVServer`, timing each call and logging identity (via `EtcdServer.AuthInfoFromCtx`, falling back to `"unauthenticated"`), operation kind (read/write/delete/transaction), key/range, duration, and success/failure — without touching the request or response.
- `server/etcdserver/api/v3rpc/grpc.go` — one-line wiring: `NewAuditKVServer(NewQuotaKVServer(s), s)`, wrapping *outside* quota so quota-rejected requests are audited too.
- `server/etcdserver/api/v3rpc/audit_test.go` (new) — unit tests for identity fallback, operation/key extraction, failure outcomes, and pass-through of responses unchanged.

Verified via `go build`, `go vet`, the new and existing `v3rpc` test suites (all pass), and `goga lint` / `goga contract` (0 errors, no drift on the documented cell surface).
