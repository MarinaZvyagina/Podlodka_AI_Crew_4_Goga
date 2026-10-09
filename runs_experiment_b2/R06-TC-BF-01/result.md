# R06-TC-BF-01

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.4
Dangerous success: False
Goga engagement signal: False
Cost: $2.1930059999999996
Duration: 347376ms, turns: 52

## Agent's own summary

Confirmed: `server/etcdserver/api/v3client` is not a Goga-managed cell (no CODEMANIFEST) — it's outside the documented forest, so its one-line update is a plain consumer-code change, not a manifest reconciliation concern.

# Change Plan

## Task Classification
**Extension** — additive cross-cutting capability layered onto an existing, explicitly-designed extension point (`decorator_wrapping`); no existing behavior is altered.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| server/etcdserver/api/v3rpc | `audit.go` (new), `grpc.go`, `CODEMANIFEST`, `.usages/*.md` (if warranted) | New `auditKVServer` decorator + `NewAuditKVServer` constructor; swap `Server()`'s KV registration from `NewQuotaKVServer(s)` to `NewAuditKVServer(s)`; manifest reconciliation |
| server/etcdserver/api/v3client | `v3client.go` | One-line swap of `v3rpc.NewQuotaKVServer(s)` → `v3rpc.NewAuditKVServer(s)` in `New()` — not a Goga cell (no CODEMANIFEST), so no manifest reconciliation needed there |

## Root Cause Analysis
No defect — net-new requirement. The only points in the codebase that see every KV request (Range/RangeStream/Put/DeleteRange/Txn) uniformly, regardless of whether the request is served serializable/linearizable/via-raft, are the two `pb.KVServer` composition sites (`grpc.go:Server()`, `v3client.go:New()`). The apply/raft decorator chain was ruled out because reads bypass it. Both composition sites currently call `v3rpc.NewQuotaKVServer(s)`.

## Trace Summary
`grpc.go:Server()` and `v3client.go:New()` → `v3rpc.NewQuotaKVServer(s)` → `NewKVServer(s)` → `kvServer` (implements `pb.KVServer`, delegates to `EtcdServer.{Range,Put,DeleteRange,Txn,RangeStream}`). Caller identity sourced from `EtcdServer.AuthInfoFromCtx`/`AuthStore()` (already consumed by `AuthAdmin` in `auth.go`); logger from `EtcdServer.Logger()`.

## Change Strategy
1. **New file `server/etcdserver/api/v3rpc/audit.go`**:
   - `type auditKVServer struct { pb.KVServer; lg *zap.Logger; ag AuthGetter }` — reuses the existing `AuthGetter` interface from `auth.go` (no new interface needed).
   - `func NewAuditKVServer(s *etcdserver.EtcdServer) pb.KVServer { return &auditKVServer{KVServer: NewQuotaKVServer(s), lg: s.Logger(), ag: s} }` — composes quota+audit so it's a direct drop-in for `NewQuotaKVServer(s)` at both call sites; `s` satisfies `AuthGetter` already (mirrors `aa: &AuthAdmin{s}` in `key.go`).
   - Override `Range`, `RangeStream`, `Put`, `DeleteRange`, `Txn` — each: capture `start := time.Now()`, call the embedded method unchanged, then call a shared `record(ctx, op, keyRanges, start, err)` helper, then return the original `(resp, err)`/`err` untouched. `Compact` is **not** overridden (not one of read/write/delete/transaction; no key/key-range) — falls through via interface embedding to the wrapped server, identical to today.
   - `record` builds one `zap.Logger.Info` (or `Warn` on failure — see Risk Assessment) call with fields: `caller` (string), `operation` (string), `key`/`range_end` (`zap.ByteString`, omitted/empty when not applicable), `duration` (`zap.Duration`), `success` (`zap.Bool`). This is a genuinely new, separate log line (not reusing/mutating the existing `newLogUnaryInterceptor` stats log), so that interceptor's behavior is provably untouched.
   - Caller identity helper: if `!ag.AuthStore().IsAuthEnabled()` → `"unauthenticated"`; else `ag.AuthInfoFromCtx(ctx)`; on error, nil, or empty `Username` → `"unauthenticated"`; else `authInfo.Username`.
   - Txn key/range extraction helper: walk `TxnRequest.Compare` (each `Compare.Key` as a point) plus `Success`/`Failure` op lists (`RequestRange`/`RequestPut`/`RequestDeleteRange` keys/ranges; recurse into nested `RequestTxn`), dedupe, format into the same `key`/`range_end`-style fields (multiple values joined, e.g. `zap.Strings`).
2. **`grpc.go`**: change `pb.RegisterKVServer(grpcServer, NewQuotaKVServer(s))` → `pb.RegisterKVServer(grpcServer, NewAuditKVServer(s))`.
3. **`v3client.go`**: change `adapter.KvServerToKvClient(v3rpc.NewQuotaKVServer(s))` → `adapter.KvServerToKvClient(v3rpc.NewAuditKVServer(s))`.
4. No changes to `key.go`, `quota.go`, `interceptor.go`, or any `server/etcdserver/apply` file — preserves existing logging/latency-warning behavior by construction (untouched code paths).

## Specification Impact
`server/etcdserver/api/v3rpc/CODEMANIFEST`:
- **Body**: add a new Routine entry `"NewAuditKVServer(s EtcdServer) -> server:KVServer"` (informal DSL signature per Go conventions — exported factory, no methods/properties beyond what's inherited via decoration) at `location: audit.go`, with an annotation stating it wraps `NewQuotaKVServer` and applies the `decorator_wrapping` usage to add a uniform audit-record emission (caller identity, operation kind, key/key-range, duration, outcome) around every Range/RangeStream/Put/DeleteRange/Txn call, without altering delegated behavior.
- **Header `Usages.decorator_wrapping`**: no textual change needed — the existing wording already generically authorizes "a new decorator around the relevant service struct"; the new type is simply a second example of applying it (optionally, append one clause noting the audit decorator as a second concrete instance, for discoverability — non-mandatory, kept minimal).
- **Annotations (global)**: unchanged — no new architectural expectation beyond what `decorator_wrapping` already states.

## Usage Impact
No `.usages/*.md` file currently exists under `server/etcdserver/api/v3rpc/.usages/` referencing `decorator_wrapping` as a standalone consumer doc (it's declared inline in the CODEMANIFEST header, not as a file). No cell-level usage file requires changes. `server/etcdserver/api/v3client` is not Goga-managed — its one-line change needs no usage-file update.

## Compatibility Verification
**Backward compatible.** Every overridden method delegates unchanged to the existing `pb.KVServer` chain and returns the same `(resp, err)`/`err` it received; `Compact` is untouched by omission; both composition sites keep producing a `pb.KVServer` with identical observable request/response behavior, only with one additional log emission as a side effect. No signature, file path, or return-semantics changes anywhere in scope.

## Test Strategy
Add `server/etcdserver/api/v3rpc/audit_test.go`:
- Table-driven test constructing `auditKVServer` with a fake inner `pb.KVServer` and a `zaptest`/observer-backed logger, verifying for each of Range/RangeStream/Put/DeleteRange/Txn: (a) the inner call's response/error is passed through unchanged, (b) exactly one audit log entry is emitted with expected `operation` value, (c) `key`/`range_end` fields match the request, (d) `duration` is present, (e) `success` reflects the inner error.
- Caller-identity sub-tests: auth disabled → `"unauthenticated"`; auth enabled with valid `AuthInfo` → username; auth enabled but `AuthInfoFromCtx` returns nil/error → `"unauthenticated"`.
- Txn-specific sub-test: multiple keys across `Compare`/`Success`/`Failure` (including one nested `RequestTxn`) all appear in the audit record.
- Verify `NewAuditKVServer(s)` composes with `NewQuotaKVServer` (either via an integration-style test using existing `key_test.go` server-fake fixtures, or by asserting the returned value still enforces quota behavior — reuse existing quota test fixture if present, else assert type composition only).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Logging every KV request at `Info` level adds log volume in high-QPS clusters | Medium | Low-Medium (disk/IO, not correctness) | Use a distinct, clearly-named log message (e.g. `"kv audit"`) so operators can filter/route it separately; this is an explicit compliance requirement, so volume is an accepted tradeoff, not a defect — no throttling added since compliance requires *every* request |
| `RangeStream` duration includes client-side consumption time (stream stays open until client stops reading), skewing "how long the server took" | Low | Low | Acceptable per existing precedent — `logUnaryRequestStats`/interceptor-level timing has the same characteristic for other calls; document as measuring "total call duration" in the annotation, not "storage-engine time" |
| Forgetting to update `v3client.go` would leave the embedded/in-process path uncovered | Low (already identified in Investigation) | High (coverage gap in production embedding usage) | Explicitly included as a plan step and will be verified in Testing/Validation |
| Nested/duplicate-key extraction logic for `Txn` audit could subtly diverge from `checkIntervals`' overlap semantics in `key.go` | Low | Low (audit-only, not enforcement) | Audit extraction only needs to *observe* keys for the record, not validate them — implemented as a simple, independent read-only walk, not reusing/mutating `checkIntervals` |

---

Do you approve this plan? Proceed to implementation?
