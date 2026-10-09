# R06-TB-BF-01

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: True
Cost: $2.7062442
Duration: 561415ms, turns: 77

## Agent's own summary

# Change Plan

## Task Classification
**Feature** (new configurable safety limit) with a small amount of **internal refactor** (threading a new parameter through two internal Go functions and their direct test call sites).

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `server/lease` | `lessor.go`, `lease.go` | New sentinel error `ErrTooManyAttachedKeys`; new `Lease.Len() int` O(1) accessor (paired with existing `Keys()`) |
| `server/etcdserver/apply` | `interface.go`, `backend.go`, `CODEMANIFEST` | New `ApplierOptions.MaxLeaseAttachedKeysCfg int` property; `Put`/`Txn` pass it into `mvcctxn.Put`/`mvcctxn.Txn` |
| `server/etcdserver` | `server.go`, `v3_server.go`, `CODEMANIFEST` | `NewUberApplier()` populates the new option from `s.Cfg`; the read-only `Txn` fast path passes the same config value through |
| (non-cell infra) `server/etcdserver/txn` | `put.go`, `txn.go`, `txn_test.go` | New parameter on `Put`/`Txn`; accumulator-aware `checkLease`/`checkPut`/`checkTxn`; existing tests updated to pass "no limit" |
| (non-cell infra) `server/config` | `config.go` | New `ServerConfig.MaxLeaseAttachedKeys int` field |
| (non-cell infra) `server/embed` | `config.go`, `etcd.go` | New CLI flag `--max-lease-attached-keys`, default constant, struct field, ServerConfig wiring |
| (non-cell infra) `api/v3rpc/rpctypes` | `error.go` | New `ErrGRPCLeaseMaxAttachedKeysExceeded` + client alias `ErrTooManyAttachedKeys` |
| (non-cell infra) `server/etcdserver/api/v3rpc` | `util.go`, `validationfuzz_test.go` | Register the new sentinel→gRPC mapping; update test call site |

## Root Cause Analysis
No capacity limit exists anywhere on `Lessor.Attach`'s backing `itemSet`. The only structurally safe enforcement point is the pre-existing pre-flight validation phase in `server/etcdserver/txn` (`checkLease`/`checkPut`/`checkTxn`), which already runs to completion before any mvcc mutation — because `KV.Put`/`TxnWrite.Put` have no error return, and `Lessor.Attach` is invoked only after the write is already durable (and its error path today is a live `panic`).

## Trace Summary
`ServerConfig.MaxLeaseAttachedKeys` → `EtcdServer.NewUberApplier()` → `ApplierOptions.MaxLeaseAttachedKeysCfg` → `applierV3backend.Put/Txn` → `mvcctxn.Put(..., maxAttachedKeys)` / `mvcctxn.Txn(..., maxAttachedKeys)` → `checkLease`/`checkPut`/`checkTxn` (pre-mutation) using `lessor.Lookup(id)` + new `Lease.Len()` + existing `lessor.GetLease(item)` → on violation, `lease.ErrTooManyAttachedKeys` → `togRPCError` (`toGRPCErrorMap`) → `rpctypes.ErrGRPCLeaseMaxAttachedKeysExceeded` → client. The read-only `Txn` fast path (`v3_server.go:366`) receives the same config value but never exercises the check (no `RequestPut` possible in a read-only txn).

## Change Strategy

1. **`server/lease/lessor.go`** — add near the existing `Err*` vars:
   ```go
   ErrTooManyAttachedKeys = errors.New("too many keys attached to lease")
   ```
2. **`server/lease/lease.go`** — add, next to `Keys()`:
   ```go
   // Len returns the number of keys currently attached to the lease.
   func (l *Lease) Len() int {
       l.mu.RLock()
       defer l.mu.RUnlock()
       return len(l.itemSet)
   }
   ```
3. **`server/etcdserver/txn/put.go`** — thread a `maxAttachedKeys int` and a `pending map[lease.LeaseID]int` (nilable) through `Put` and `checkLease`:
   - `Put(ctx, lg, lessor, kv, maxAttachedKeys, p)` calls `checkLease(lessor, maxAttachedKeys, p, nil)` (single put — no cross-op accumulation needed).
   - `checkLease(lessor, maxAttachedKeys, p, pending)`:
     - existing lease-exists check unchanged;
     - if `maxAttachedKeys <= 0` (disabled) or `p.Lease == 0`, return nil (unchanged behavior);
     - if `lessor.GetLease(LeaseItem{Key: p.Key}) == LeaseID(p.Lease)` → re-attach, return nil (never rejected, per requirement);
     - else compute `already := 0; if pending != nil { already = pending[LeaseID(p.Lease)] }`; if `l.Len()+already >= maxAttachedKeys` → return `lease.ErrTooManyAttachedKeys`; else if `pending != nil { pending[LeaseID(p.Lease)] = already + 1 }`.
   - `checkPut` gains the same two new parameters and forwards them.
4. **`server/etcdserver/txn/txn.go`** — `Txn(ctx, lg, rt, txnModeWriteWithSharedBuffer, kv, lessor, maxAttachedKeys, skipRangeExecution)` allocates `pending := map[lease.LeaseID]int{}` once, passes it into `checkTxn(trace, txnRead, rt, lessor, maxAttachedKeys, txnPath, pending)`, which forwards it (unchanged otherwise) through its existing recursion and into `checkPut`.
5. **`server/etcdserver/apply/interface.go`** — add `MaxLeaseAttachedKeysCfg int` to `ApplierOptions`, positioned next to `QuotaBackendBytesCfg`.
6. **`server/etcdserver/apply/backend.go`** — `Put`/`Txn` pass `a.options.MaxLeaseAttachedKeysCfg` into `mvcctxn.Put`/`mvcctxn.Txn`.
7. **`server/etcdserver/server.go`** — `NewUberApplier()` sets `MaxLeaseAttachedKeysCfg: s.Cfg.MaxLeaseAttachedKeys`.
8. **`server/etcdserver/v3_server.go:366`** — pass `s.Cfg.MaxLeaseAttachedKeys` into the read-only-path `txn.Txn(...)` call for signature consistency (inert at runtime, since read-only txns have no Put ops).
9. **`server/config/config.go`** — add `MaxLeaseAttachedKeys int` next to `MaxTxnOps`.
10. **`server/embed/config.go`** — add `DefaultMaxLeaseAttachedKeys = 1000000` constant; `MaxLeaseAttachedKeys int \`json:"max-lease-attached-keys"\`` struct field; default assignment in `NewConfig()`; `fs.IntVar(&cfg.MaxLeaseAttachedKeys, "max-lease-attached-keys", cfg.MaxLeaseAttachedKeys, "Maximum number of keys that can be attached to a single lease. 0 means no limit.")`.
11. **`server/embed/etcd.go`** — add `MaxLeaseAttachedKeys: cfg.MaxLeaseAttachedKeys,` to the `srvcfg := config.ServerConfig{...}` literal.
12. **`api/v3rpc/rpctypes/error.go`** — add, alongside `ErrGRPCNoSpace`/`ErrGRPCLeaseNotFound`:
    ```go
    ErrGRPCLeaseMaxAttachedKeysExceeded = status.Error(codes.ResourceExhausted, "etcdserver: too many keys attached to lease")
    ```
    plus register in the error-description map and add the client-facing alias `ErrTooManyAttachedKeys = Error(ErrGRPCLeaseMaxAttachedKeysExceeded)` next to `ErrLeaseNotFound`.
13. **`server/etcdserver/api/v3rpc/util.go`** — add `lease.ErrTooManyAttachedKeys: rpctypes.ErrGRPCLeaseMaxAttachedKeysExceeded,` to `toGRPCErrorMap`.
14. **Test call-site fixes** (no behavior change, only compile fixes to pass the new "disabled" value `0`):
    - `server/etcdserver/txn/txn_test.go`: `Txn(ctx, ..., false, s, lessor, 0, false)` and `Put(ctx, ..., lessor, s, 0, tc.op.GetRequestPut())`.
    - `server/etcdserver/api/v3rpc/validationfuzz_test.go`: `txn.Txn(ctx, ..., false, s, &lease.FakeLessor{}, 0, false)`.

**Default value: `1,000,000`.** Rationale: the reported pain point is "hundreds of thousands" of keys on one lease causing a large cleanup burst; a default of one million is comfortably above any known legitimate usage pattern (session/lock-style leases typically carry a handful to low thousands of keys) so it cannot break existing deployments, while still bounding the worst case to a large-but-finite, boundable number instead of unbounded. `0` is reserved as the explicit "disabled" sentinel (consistent with `QuotaBackendBytes`'s "0 = default" idiom, though here `0` means "no cap" since the *default itself* is the safety net, not a separate zero-value special case operators must reach for).

## Specification Impact
- **`server/etcdserver/apply/CODEMANIFEST`**: add `"MaxLeaseAttachedKeysCfg -> int64": |` (matching the existing `int64`-labeled numeric properties like `QuotaBackendBytesCfg`) to `ApplierOptions`'s properties, one line: "The configured maximum number of distinct keys a single lease may have attached; 0 means no limit." Purely additive — no existing property text changes.
- **`server/etcdserver/CODEMANIFEST`**: extend the `Put`/`Txn` method annotations' existing "optionally attaching the key to a lease" / transaction description with one clause noting the write can now fail if it would exceed the target lease's configured key-attachment limit. Additive clarification, not a rewrite of documented algorithm/behavior.
- **`server/lease/CODEMANIFEST`**: add `Len()` under `Lease`'s methods (paired with the already-documented `Keys()`), one line: "Number of keys currently attached to this lease." No changes to `Attach`/`Detach` annotations (their behavior is genuinely unchanged).
- No changes to `server/storage/mvcc/CODEMANIFEST` or `server/storage/backend/CODEMANIFEST` — confirmed out of scope by investigation.

## Usage Impact
- `server/lease`'s `callback_decoupling` usage: no change — the new check does not add an outbound import or a new callback; it stays true.
- `server/etcdserver/apply`'s `decorator_chain` usage: no change — no new decorator introduced, consistent with the usage's own guidance to only add a decorator for *uniform* cross-cutting concerns (this check is request-shaped, not uniform).
- `server/etcdserver`'s `write_path` usage: no change — the new check stays on the apply-time path as the usage requires.
- No `.usages/` consumer-facing files exist yet for these cells (none listed in `goga schema`), so none require updates.

## Compatibility Verification
**Backward compatible.** Every documented CODEMANIFEST type signature (`Lessor.Attach`, `KV.Put`, `EtcdServer.Put`/`Txn`, `ApplierOptions`) is preserved exactly; all manifest changes are additive properties/methods. The only signature changes are to two internal, non-cell, non-client-facing Go functions (`txn.Put`, `txn.Txn` in package `server/etcdserver/txn`), fixed in the same change together with their two test call sites so no test's asserted behavior changes — this mirrors how `TxnModeWriteWithSharedBuffer` was previously added to these same functions. Runtime behavior for any lease under the (generous, 1,000,000-key) default limit is byte-for-byte identical to today; a request that pushes a lease's *distinct* key count over the configured limit changes from "silently succeeds" to "cleanly rejected with `ResourceExhausted`," which is the explicitly required new behavior, not an unintended regression. Re-attaching an already-attached key is explicitly exempted via the `lessor.GetLease(item) == leaseID` check and is unaffected regardless of how far over the limit the lease already is.

## Test Strategy
1. **`server/lease`** (`lease_test.go` or new): `Lease.Len()` returns correct counts after `SetLeaseItem`/zero-value cases.
2. **`server/etcdserver/txn`** (`put_test.go`/`txn_test.go`, extend `putTestCases`/add new cases):
   - Put a new key onto a lease at exactly the limit → `ErrTooManyAttachedKeys`.
   - Put a key already attached to the target lease, lease at/over limit → succeeds (no error) — the critical "re-attach never rejected" case.
   - Put a key moving from lease A to lease B, B at limit → rejected (counts as new for B).
   - Lease under the limit → succeeds unchanged.
   - `maxAttachedKeys == 0` → unlimited, matches today's behavior exactly (regression guard for existing callers/tests).
   - `Txn` with N Put ops all targeting the same lease, N pushing it over the limit cumulatively even though no single op would: rejected, and — critically — none of the ops' side effects observable (validate via a subsequent Range that the key set is unchanged), proving no partial apply.
   - `Txn` with duplicate-key-across-branches or mixed re-attach + new-attach ops in one txn: re-attach ops don't count against the cumulative budget.
3. **`server/etcdserver/api/v3rpc`**: extend `util_test.go`-style error-mapping test (if one exists) to cover the new sentinel→gRPC mapping; confirm `validationfuzz_test.go` still passes with the updated call site.
4. **Integration-level** (if an existing lease integration test file covers attach/detach at scale, e.g. under `tests/integration/clientv3/lease` or `server/lease`): add one test that grants a lease with a low configured `MaxLeaseAttachedKeys` (e.g. via test harness config override), attaches up to the limit successfully, confirms the next new-key Put returns the expected gRPC error, and confirms the server stays healthy and continues serving other requests afterward (directly exercises the "no crash, no hang" requirement end-to-end).
5. **Build/compile gate**: `go build ./...` and `go vet ./...` across the module to catch any missed call site of `txn.Put`/`txn.Txn`.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| A third, unfound caller of `txn.Put`/`txn.Txn` breaks compilation | Low | Build fails immediately, caught by `go build ./...` before merge | Full-repo grep already performed and re-verified in Testing step; compiler will catch any miss |
| Txn accumulator double-counts or under-counts across nested sub-txns | Low | Wrong accept/reject decision on complex nested txns | Dedicated nested-txn test case (item 2 above); `checkTxn`'s existing recursion pattern is reused unmodified, only the accumulator map is threaded through |
| Chosen default (1,000,000) still too low for some legitimate large fan-out deployment | Low-Medium | Existing deployment's writes start failing after upgrade | Fully configurable via flag/config; default documented in Documentation + CHANGELOG so operators can raise it pre-upgrade if they know they exceed it |
| `Lease.Len()` read races with concurrent `Attach`/`Detach` under `l.mu` | Very Low | Stale count momentarily under/over-counts by a few | Matches existing concurrency model exactly (`Keys()` uses the same `RLock`); a momentary race can at most admit/reject one borderline key, never corrupt state or double-count durably, since the real mutation still happens serially inside `Attach` during deterministic apply |
| Pipeline's strict "existing tests break" rule (flagged in Investigation) is treated as a hard STOP | Certain (by design) | Requires explicit user sign-off before Compatibility Guard proceeds | Surfaced explicitly here and in Investigation; recommend user approves treating the 2 mechanical test call-site updates as in-scope, non-breaking maintenance before Step 4 |

---

Do you approve this plan? Proceed to implementation?
