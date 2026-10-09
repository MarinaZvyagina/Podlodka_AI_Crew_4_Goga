# R06-TC-GC-10

Condition: goga_native_architecture
Base tag: condition-c-r06-v1
Functional success: False
Full architecture conformance: False
ACR: 0.4
Dangerous success: False
Goga engagement signal: False
Cost: $1.6788743999999998
Duration: 241113ms, turns: 46

## Agent's own summary

# Change Plan

## Task Classification
**Feature** (additive cross-cutting concern — audit logging for KV requests)

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| server/etcdserver/api/v3rpc | `audit.go` (new), `audit_test.go` (new), `grpc.go` (edit), `CODEMANIFEST` (edit) | New interceptor + helpers; wire into composition root; document new type/routine and revise `decorator_wrapping`/`Server()` annotations |

No other cell requires modification. `server/etcdserver` and `server/auth` are consumed read-only (`EtcdServer.AuthInfoFromCtx`, `EtcdServer.Logger`, `auth.AuthInfo.Username`), all already-exported members per their CODEMANIFESTs.

## Root Cause Analysis
Uniform, automatic per-request-type coverage cannot be achieved with this cell's existing `decorator_wrapping` pattern (struct decorators override individual methods by hand — `quotaKVServer` only overrides `Put`/`Txn`, proving the pattern is inherently selective). The cell's `Server()` composition root already documents a second, distinct mechanism for concerns that must apply to *every* call: the shared `interceptor` chain. Gating a new interceptor on the KV service's gRPC method-path prefix (`/etcdserverpb.KV/`) gives coverage keyed to gRPC's own dispatch mechanism, so any current or future method registered under `pb.KVServer` is audited with no per-handler code.

## Trace Summary
`grpc.NewServer` → `ChainUnaryInterceptor(...)` → for any `/etcdserverpb.KV/*` call: new `newAuditUnaryInterceptor(s)` wraps `handler(ctx, req)` → (`quotaKVServer` →) `kvServer.{Range,Put,DeleteRange,Txn,Compact}` → `s.kv` (mvcc). The new interceptor sits alongside `newLogUnaryInterceptor`/`serverMetrics`/`newUnaryInterceptor` in the same chain slice, executing independently — it does not read or mutate their state, and they do not read or mutate its output.

## Change Strategy
1. **`audit.go`** (new file):
   - `kvAuditOperation(fullMethod string, req any) (kind string, key, rangeEnd []byte, audited bool)` — pure function, no I/O.
   - `auditIdentity(authInfo *auth.AuthInfo) string` — pure function, no I/O.
   - `newAuditUnaryInterceptor(s *etcdserver.EtcdServer) grpc.UnaryServerInterceptor` — thin wiring: resolves `kind/key/rangeEnd/audited` up front (before calling `handler`, since `req` is available immediately and doesn't require the response); if `!audited`, calls `handler` and returns immediately with no extra work; otherwise times the call, invokes `handler(ctx, req)` unmodified, resolves identity via `s.AuthInfoFromCtx(ctx)` (ignoring its error — audit must not fail the request), and logs one record at `Info` level unconditionally (not gated by debug level or latency threshold, since this is a compliance trail, not a diagnostic aid) via `s.Logger()` using message `"kv audit"` with fields `identity`, `operation`, `key`, `range_end`, `duration`, `success`.
2. **`grpc.go`**: insert `newAuditUnaryInterceptor(s)` into `chainUnaryInterceptors` after `newUnaryInterceptor(s)` and before the caller-supplied `interceptor` (keeps existing three untouched in position/order; new entry only adds behavior for KV paths).
3. **`audit_test.go`** (new file): table-driven unit tests for the two pure helpers, following `key_test.go`/`util_test.go` conventions — no `EtcdServer` construction needed, matching this package's existing practice of unit-testing extracted pure logic rather than the interceptor closures themselves (consistent with `newLogUnaryInterceptor`/`newUnaryInterceptor` having no direct unit tests today, covered instead by integration/e2e).
4. **`CODEMANIFEST`**: add a new Routine entry for `newAuditUnaryInterceptor`, add a new Usage (e.g. `interceptor_wrapping`) documenting when to use the full-coverage interceptor pattern vs. the selective `decorator_wrapping` pattern, and touch up `Server()`'s annotation to mention the audit interceptor is part of the chain.

## Specification Impact
- **New Usage** `interceptor_wrapping` (or similar key) in the header: documents that concerns needing guaranteed, automatic coverage of every current and future method on a service must be added as a `chainUnaryInterceptors` entry gated by gRPC method path, not as a struct-decorator override — contrasted explicitly against `decorator_wrapping`.
- **New Body entry**: `"newAuditUnaryInterceptor(s EtcdServer) -> interceptor:UnaryServerInterceptor"` at `location: audit.go`, annotated with its algorithm (classify → skip if non-KV → time → delegate → resolve identity → log) and referencing the new Usage.
- **`Server(...)` annotation**: extend the `interceptor` parameter description or the composition-root annotation to note the KV audit interceptor is unconditionally part of the built-in chain (not the caller-supplied one).
- No signature of any existing declared type changes (`Server`, `NewQuotaKVServer`, etc. all keep their current contracts).

## Usage Impact
No `.usages/*.md` consumer-facing practice files exist yet for this cell (none found under `server/etcdserver/api/v3rpc/.usages/`), and this change doesn't alter how any consumer calls `Server()` or any KV RPC, so no consumer-facing usage file needs to change. This will be re-verified in the usage-reconciliation step.

## Compatibility Verification
**Backward compatible.** The new interceptor is purely additive: it never mutates `ctx`, `req`, or the value/error returned by `handler`, and non-KV calls take a zero-added-work fast path. Existing interceptors, decorators, and handlers are untouched in content; `grpc.go` only gains one more slice entry. No signature, file path, output format, or return-semantics changes to any existing declared contract.

## Test Strategy
- **Unit tests** (`audit_test.go`): `kvAuditOperation` — one case per KV method (Range/RangeStream/Put/DeleteRange/Txn/Compact) verifying `kind`/`key`/`rangeEnd`/`audited`, plus a non-KV method path (e.g. `/etcdserverpb.Lease/LeaseGrant`) verifying `audited == false`; `auditIdentity` — nil `AuthInfo`, empty-username `AuthInfo`, populated-username `AuthInfo`.
- **Build/vet**: `go build ./...` and `go vet ./...` across the workspace (matches this repo's existing verification bar per the last commit).
- **No integration/e2e test added** — the existing e2e assertion on `"request stats"` log content is unaffected since the audit log uses a distinct message; adding a new e2e assertion for `"kv audit"` is out of scope unless requested, since unit coverage of the classification/identity logic plus the additive-only interceptor design already satisfies the stated requirements.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Audit logging adds latency to every KV request | Low | Low | Logging is a single structured `Info` call using the existing `zap.Logger`; classification is a cheap type switch; no I/O beyond the logger's own sink |
| New log volume floods output in high-QPS clusters | Medium | Low-Medium | Documented as an explicit, intentional compliance trail (matches the task's "every read/write" requirement); acceptable given it's an explicit ask, not a default-on debug feature |
| Interceptor ordering interacts badly with existing chain | Low | Medium | Placed after the existing built-in interceptors and before the caller-supplied one; does not read/mutate their state; verified via Compatibility Verification above |
| Txn requests have no single key, audit record looks incomplete | Low | Low | Documented behavior: `key`/`rangeEnd` stay nil for Txn, `kind = "transaction"` still recorded — matches requirement wording ("key or key range... transaction") |

---

Do you approve the plan? Proceed to implementation?
