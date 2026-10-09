# R06-TC-GC-07

Condition: goga_native_architecture
Base tag: condition-c-r06-v1
Functional success: False
Full architecture conformance: False
ACR: 0.4
Dangerous success: False
Goga engagement signal: True
Cost: $1.6653507
Duration: 242690ms, turns: 41

## Agent's own summary

Good — `auth` package already imported in this cell (`auth.go`, `util.go`, `watch.go`). Now I have everything needed to write the plan.

## Change Plan

**Task Classification**: feature (extension) — additive cross-cutting capability, no existing behavior modified.

### Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `server/etcdserver/api/v3rpc` | `interceptor.go` (new interceptor + pure helper functions), `grpc.go` (wire into `chainUnaryInterceptors`), `interceptor_test.go` (new), `CODEMANIFEST` (document new decorator) | Adds audit-record emission as a new interceptor stage; no existing function signature changes |
| `server/etcdserver` | none (read-only dependency on already-public `AuthInfoFromCtx`, `Logger()`) | — |

### Root Cause Analysis
Not a defect — a net-new requirement. Investigation confirmed the only chokepoint that (a) sees every KV RPC including reads and (b) auto-covers future KV methods without per-type wiring is the gRPC unary interceptor chain in `grpc.go`, not the `apply` decorator chain (bypassed by reads) or a `quotaKVServer`-style per-service decorator (only covers explicitly overridden methods).

### Trace Summary
`grpc.ChainUnaryInterceptor(newLogUnaryInterceptor, serverMetrics, newUnaryInterceptor)` in `grpc.go:53-58` → generated `_KV_{Range,Put,DeleteRange,Txn}_Handler` (`api/etcdserverpb/rpc_grpc.pb.go`) builds `grpc.UnaryServerInfo{FullMethod: "/etcdserverpb.KV/<Method>"}` before any interceptor runs → each interceptor calls `handler(ctx, req)` pass-through → `kvServer` (`key.go`) → `EtcdServer.{Range,Put,DeleteRange,Txn}` (`v3_server.go`). `EtcdServer.AuthInfoFromCtx` → `authStore.AuthInfoFromCtx` (`server/auth/store.go:1056`) returns `(nil, nil)` when auth is disabled or no token present, `(nil, ErrInvalidAuthToken)` on bad token, `(&AuthInfo{...}, nil)` on success.

### Change Strategy
1. **`interceptor.go`** — add:
   - `auditOperationForMethod(fullMethod string) (op string, ok bool)`: matches `"/etcdserverpb.KV/Range"` → `"read"`, `.../Put` → `"write"`, `.../DeleteRange` → `"delete"`, `.../Txn` → `"transaction"`; anything else → `ok=false`. Pure function, unit-testable without a server.
   - `auditCallerIdentity(authInfo *auth.AuthInfo, err error) string`: returns `"unauthenticated"` when `err != nil || authInfo == nil || authInfo.Username == ""`, else `authInfo.Username`. Pure function.
   - `auditKeySummary(req any) string`: type-switches on `*pb.RangeRequest`, `*pb.PutRequest`, `*pb.DeleteRangeRequest` (read `Key`/`RangeEnd` directly) and `*pb.TxnRequest` (walk `Compare[].Key`/`RangeEnd`, dedup, join); returns a best-effort printable summary. Pure function, only reads fields — never mutates `req`.
   - `newAuditUnaryInterceptor(s *etcdserver.EtcdServer) grpc.UnaryServerInterceptor`: skips (calls `handler` directly, no logging) when `auditOperationForMethod` returns `ok=false`; otherwise records `start := time.Now()`, calls `resp, err := handler(ctx, req)`, then logs one structured entry via `s.Logger()` with identity/op/key/duration/outcome, and returns `resp, err` unchanged.
2. **`grpc.go`** — insert `newAuditUnaryInterceptor(s)` into the `chainUnaryInterceptors` slice (after `newLogUnaryInterceptor`/metrics/`newUnaryInterceptor`, before the optional caller-supplied `interceptor`, so it doesn't affect leader/capability short-circuit ordering already established).
3. **`interceptor_test.go`** (new) — unit tests for the three pure helpers plus a table-driven test of `newAuditUnaryInterceptor` using a fake `handler` and a captured `zapobserver` core (no real `EtcdServer` needed for the pure-function tests; a minimal `*etcdserver.EtcdServer` is unavoidable for the interceptor-level test since it takes that concrete type — reuse the existing test-construction helpers already used elsewhere in this package's tests, if any exist, else construct the smallest possible `EtcdServer{lgMu, lg, authStore}`).
4. **`CODEMANIFEST`** — extend the `Server(...)` entity annotation (which already says "interceptor: shared unary interceptor (logging/metrics/tracing) applied to every call") to mention audit logging, and extend `decorator_wrapping` usage text to note the interceptor chain as the mechanism for concerns needing coverage of every method including future ones (vs. the per-service-decorator pattern for concerns scoped to specific methods).

### Specification Impact
- `server/etcdserver/api/v3rpc/CODEMANIFEST`: `Usages.decorator_wrapping` text gains one clause distinguishing "per-service decorator" (bounded to explicitly overridden methods) from "shared unary interceptor chain" (uniform over every method, automatically covers new ones) as the two available cross-cutting mechanisms in this cell. `Server(...)` entity annotation gains a line noting the interceptor chain now includes uniform KV audit logging. No signature changes, no new top-level contract types (helpers stay unexported/internal, consistent with "CODEMANIFEST references exported names only" — `Server`'s existing contract already covers this since `interceptor` behavior is internal to `Server`'s composition).

### Usage Impact
No `.usages/` files exist yet for this cell (`goga schema` reports `"usages": []`). None need updating.

### Compatibility Verification
**Backward compatible.** No exported signature changes anywhere; `newAuditUnaryInterceptor` is purely additive and only observes `req`/`resp`/`err` after delegating to `handler`. Existing `newLogUnaryInterceptor` warning/debug logging and `serverMetrics`/`newUnaryInterceptor` behavior are untouched — they remain earlier in the chain, unaffected by a later stage.

### Test Strategy
- `auditOperationForMethod`: table test over all KV FullMethods (Range/Put/DeleteRange/Txn/Compact) and a non-KV method (e.g. `/etcdserverpb.Lease/LeaseGrant`), asserting correct `(op, ok)`.
- `auditCallerIdentity`: table test over (nil,nil) → unauthenticated; (nil, ErrInvalidAuthToken) → unauthenticated; (&AuthInfo{Username:""}, nil) → unauthenticated; (&AuthInfo{Username:"root"}, nil) → "root".
- `auditKeySummary`: one case per request type including a multi-compare Txn.
- `newAuditUnaryInterceptor`: table test with a fake `grpc.UnaryHandler` returning success/error, asserting exactly one audit log entry is emitted for KV methods with correct fields, zero for non-KV methods, and that `resp`/`err` pass through unchanged.
- Existing `TestGRPCError`, `TestCheckRangeRequest`, `TestSendFragment`, `TestWatchResponseProtoFieldCount` must continue passing unmodified (regression guard).

### Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Constructing a minimal `*etcdserver.EtcdServer` for the interceptor-level test is awkward (large struct) | Medium | Low (test-only) | Test the three pure helpers exhaustively (covers all field-extraction/fallback logic); keep the interceptor-level test to a thin wiring check using the smallest viable `EtcdServer{lg: zap.NewNop(), authStore: <real auth.NewAuthStore with disabled auth>}` |
| Txn key extraction incomplete for deeply nested ops (nested Txn inside Success/Failure) | Low | Low (audit is best-effort key summary, not a correctness-critical field) | Document in annotation that Txn key summary covers the top-level `Compare` list, matching existing `CheckTxnAuth` precedent; not a functional regression since nothing consumes this for authorization |
| Adding another interceptor increases per-request latency slightly | Low | Low | Interceptor does O(1) string formatting + one zap log call, same cost class as existing `newLogUnaryInterceptor` |

---

Do you approve this plan? Proceed to implementation?
