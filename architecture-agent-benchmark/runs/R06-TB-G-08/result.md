# R06-TB-G-08

Condition: goga
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Cost: $2.9496142499999998
Duration: 672634ms, turns: 46

## Agent's own summary

# Change Plan

## Task Classification
**Feature** (additive server-side capability; no bugfix, no refactor of existing behavior).

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| server/lease | `server/lease/lessor.go`, `server/lease/lease.go` | New `LessorConfig.MaxLeaseKeys` field + package default; new sentinel error `ErrTooManyLeaseKeys`; new `Lessor.MaxLeaseKeys() int` interface method + `lessor` impl + `FakeLessor` impl; new `Lease.Len() int` method. `Attach` itself is **unchanged**. |
| server/etcdserver/txn (undocumented pkg, reached via server/etcdserver/apply) | `server/etcdserver/txn/put.go`, `server/etcdserver/txn/txn.go` | New pre-mutation capacity check threaded through the existing `checkLease`/`checkPut`/`checkTxn` validation pass (which already runs before any mvcc write, and outside the panic-guarded `executeTxn`/`txn()` write path). New small helper type `leaseKeyBudget` for correct cumulative accounting of multiple new keys targeting the same lease within one Txn. |
| server/etcdserver/api/v3rpc | `server/etcdserver/api/v3rpc/util.go` | New `toGRPCErrorMap` entry: `lease.ErrTooManyLeaseKeys → rpctypes.ErrGRPCTooManyLeaseKeys`. |
| (undocumented) api/v3rpc/rpctypes | `api/v3rpc/rpctypes/error.go` | New `ErrGRPCTooManyLeaseKeys` (codes.ResourceExhausted) + client-matchable `ErrTooManyLeaseKeys` wrapped form, next to the existing `ErrGRPCNoSpace`/`ErrGRPCLeaseTTLTooLarge` entries. |
| (undocumented) server/embed | `server/embed/config.go`, `server/embed/etcd.go` | New `--max-lease-keys` flag, `Config.MaxLeaseKeys` field, `DefaultMaxLeaseKeys` constant, copied into `etcdserver.ServerConfig` at startup — exact mirror of the `MaxTxnOps` plumbing. |
| (undocumented) server/config | `server/config/config.go` | New `ServerConfig.MaxLeaseKeys int` field. |
| server/etcdserver | `server/etcdserver/server.go` | Pass `MaxLeaseKeys: cfg.MaxLeaseKeys` into the existing `lease.LessorConfig{...}` construction at server.go:348-353. |

## Root Cause Analysis
Not a defect — a missing capability. No code path today counts or bounds `Lease.itemSet`. The only call site of `Attach` (`kvstore_txn.go:285`) is reached *after* the key has already been durably written to the backend and index (`kvstore_txn.go:259-260`), and its error path is an unconditional `panic`. Enforcement therefore cannot live inside `Attach`/`storeTxnWrite.put` without either corrupting state (reject-after-mutate) or crashing the server (panic). The correct enforcement point is the existing pre-mutation validation pass that already exists for exactly this class of problem: `checkLease` (`put.go:35`, for standalone `Put`) and `checkPut`→`checkLease` invoked from `checkTxn` (`txn.go:54, 214`), which runs against a **read-only** view before `kv.Write(trace)` is ever opened (`txn.go:67`) and returns a clean error outside the panic-guarded `txn()`/`executeTxn` write path (`txn.go:81-102`).

## Trace Summary
```
Put:  Put() [put.go:30] --checkLease (pre-write)--> kv.Write --> put() --> txnWrite.Put --> storeTxnWrite.put --> Attach
Txn:  Txn() [txn.go:32] --checkTxn->checkPut->checkLease (READ-ONLY, pre-write, txn.go:54)-->
        (only if all checks pass) kv.Write(trace) [txn.go:67] --> txn()/executeTxn (panics on error) --> put() --> Attach
```
Because `checkTxn` iterates every op (including nested `RequestOp_RequestTxn`, recursively) in a single pass *before* `executeTxn` runs any of them, and only walks the branch (`Success`/`Failure`) that `compareToPath` actually selected, this is the one place that can see "all new keys this request is about to add" ahead of any mutation — exactly what's needed for correct cumulative accounting within one Txn.

## Change Strategy

1. **server/lease/lease.go** — add `func (l *Lease) Len() int` (RLock, `return len(l.itemSet)`; mirrors the existing `Keys()` accessor but without the allocation).

2. **server/lease/lessor.go**:
   - Add `MaxLeaseKeys int` to `LessorConfig` (lessor.go:199-206).
   - Add unexported `defaultMaxLeaseKeys = 100_000` near the other `default*` vars (lessor.go:52-58), applied in `newLessor` the same way `checkpointInterval`/`leaseRevokeRate` are defaulted when zero (lessor.go:216-224): `if cfg.MaxLeaseKeys <= 0 { maxLeaseKeys = defaultMaxLeaseKeys } else { maxLeaseKeys = cfg.MaxLeaseKeys }`. This makes the field self-defaulting for any construction path that doesn't go through `embed` (tests, `auth_test.go:86`, `uber_applier_test.go:50` both use `LessorConfig{}`), so no existing test starts failing due to a zero-value cap.
   - Store the effective value on `*lessor` (`maxLeaseKeys int` field) and add `func (le *lessor) MaxLeaseKeys() int { return le.maxLeaseKeys }`.
   - Add `MaxLeaseKeys() int` to the `Lessor` interface (lessor.go:83-141), next to `GetLease`.
   - Add `FakeLessor.MaxLeaseKeys() int { return math.MaxInt32 }` (effectively unlimited for the test double, consistent with `FakeLessor.Attach` always succeeding today).
   - Add sentinel `ErrTooManyLeaseKeys = errors.New("too many keys attached to lease")` next to `ErrLeaseTTLTooLarge` (lessor.go:60-63).
   - **`Attach` itself is not modified** — its behavior, signature, and idempotency for repeat items are unchanged; the cap is enforced strictly upstream.

3. **server/etcdserver/txn/put.go**:
   - New unexported type `leaseKeyBudget` — `map[lease.LeaseID]map[string]struct{}` of new-key names tentatively counted per lease within one Put/Txn validation pass, with `newLeaseKeyBudget()`, and a `reserve(id, key) (alreadyPending bool)` method.
   - New unexported `checkLeaseKeyLimit(lessor lease.Lessor, leaseID lease.LeaseID, key string, budget *leaseKeyBudget) error`:
     - If `lessor.GetLease(lease.LeaseItem{Key: key}) == leaseID`: return `nil` immediately — the key is *already* attached to this exact lease, so this is a re-attach and must never be rejected, regardless of current size or configured cap (satisfies the explicit re-attach requirement).
     - If `budget.reserve(leaseID, key)` reports already-pending: return `nil` (same new key referenced twice in one request, e.g. duplicate Put op — must not double-count).
     - Else: if `max := lessor.MaxLeaseKeys(); max > 0 && lessor.Lookup(leaseID).Len()+budget.pendingCount(leaseID) > max` → return `lease.ErrTooManyLeaseKeys`. (`pendingCount` includes the key just reserved, so this correctly evaluates "current size + all new keys counted so far in this request, including this one.")
   - `checkLease(lessor, p, budget)` gains a `budget *leaseKeyBudget` parameter; after its existing lease-exists check (`put.go:82-85`, unchanged), call `checkLeaseKeyLimit(lessor, leaseID, string(p.Key), budget)` and return its result.
   - `Put()` (put.go:30-46) calls `checkLease(lessor, p, newLeaseKeyBudget())` — a fresh single-use budget, since standalone Put has exactly one key.
   - `checkPut` (put.go:71-78) gains the same `budget *leaseKeyBudget` parameter, passed through to `checkLease`.

4. **server/etcdserver/txn/txn.go**:
   - `Txn()` (txn.go:32-79): construct one `budget := newLeaseKeyBudget()` before calling `checkTxn` (txn.go:54), pass it through.
   - `checkTxn` (txn.go:201-228) gains a `budget *leaseKeyBudget` parameter, passed to `checkPut` (txn.go:214) and threaded unchanged through the recursive `checkTxn` call for nested `RequestOp_RequestTxn` (txn.go:217) — this is what makes cumulative accounting correct across an entire (possibly nested) Txn in one validation pass, since the *same* budget instance accumulates across every op the txn will actually execute.
   - `executeTxn`/`put()`/`txn()` (the actual write-application functions) are **not modified** — the check happens entirely upstream of them, so the existing panic-on-unexpected-write-error invariant (txn.go:91) is untouched and never reached by this new error.

5. **api/v3rpc/rpctypes/error.go**: add `ErrGRPCTooManyLeaseKeys = status.Error(codes.ResourceExhausted, "etcdserver: too many keys attached to lease")` next to `ErrGRPCLeaseTTLTooLarge`/`ErrGRPCNoSpace` (using `ResourceExhausted`, the code already used for the closest existing analog, `ErrGRPCNoSpace` — "database space exceeded" — rather than `OutOfRange`, which this codebase reserves for revision-range errors), and its wrapped client-matchable form `ErrTooManyLeaseKeys = Error(ErrGRPCTooManyLeaseKeys)`.

6. **server/etcdserver/api/v3rpc/util.go**: add `lease.ErrTooManyLeaseKeys: rpctypes.ErrGRPCTooManyLeaseKeys` to `toGRPCErrorMap` (util.go:71-73 area) — reuses the existing, already-exercised `togRPCError` call sites at `key.go:95-98` (Put) and `key.go:130-133` (Txn) with no changes needed there.

7. **server/embed/config.go**: add `DefaultMaxLeaseKeys = 100_000` (next to `DefaultMaxTxnOps`, line 62), `MaxLeaseKeys int \`json:"max-lease-keys"\`` field on `Config` (near line 226), default assignment in `NewConfig()` (near line 505), and the flag `fs.IntVar(&cfg.MaxLeaseKeys, "max-lease-keys", cfg.MaxLeaseKeys, "Maximum number of keys that can be attached to a single lease (0 uses the default).")` (near line 620, alongside `max-txn-ops`).

8. **server/embed/etcd.go**: copy `MaxLeaseKeys: cfg.MaxLeaseKeys,` into the `etcdserver.ServerConfig{...}` construction (near line 209, alongside `MaxTxnOps`).

9. **server/config/config.go**: add `MaxLeaseKeys int` to `ServerConfig` (near line 124, alongside `MaxTxnOps`).

10. **server/etcdserver/server.go**: add `MaxLeaseKeys: cfg.MaxLeaseKeys,` to the existing `lease.LessorConfig{...}` literal (lines 348-353).

**Default value: 100,000.** Rationale: the reported pathology is leases accumulating "hundreds of thousands" of keys; 100,000 sits below that threshold so the feature actually bounds the described failure mode, while remaining roughly 1-2 orders of magnitude above typical legitimate lease-fan-out patterns (session/TTL-per-record use cases typically attach anywhere from single digits to low thousands of keys per lease), so it should not affect the overwhelming majority of existing deployments. Operators with genuinely larger legitimate per-lease fan-out can raise `--max-lease-keys` explicitly.

## Specification Impact
- **server/lease/CODEMANIFEST**: extend the `Lessor` entity's `annotations` and add:
  - New property/behavior note on `Lessor(be Backend, cfg LessorConfig)`'s annotation: `cfg` now also carries the maximum number of distinct keys allowed per lease.
  - `Attach` method annotation gains a `Requirements:`/`Constraints:` note: "Attaching an item already associated with the given lease is always a no-op success, regardless of the lease's current key count." (documents the pre-existing idempotency, now load-bearing for the new limit's re-attach exemption).
  - New method entry: `"MaxLeaseKeys() -> max:int64"` — returns the configured maximum number of distinct keys allowed on a single lease.
  - New sentinel error documented in the `Attach` annotation or a header `Annotations` note: attaching a new key that would exceed the configured maximum is rejected — but this is enforced by the caller (the request-validation layer), not by `Attach` itself, so this should be phrased as a note about the overall contract's capacity, not as new `Attach` behavior (since `Attach`'s own behavior is unchanged).
- **server/lease `.usages/`**: none exist today (`usages: []`); none required — no consumer-facing usage pattern changes hands here beyond what CODEMANIFEST annotations already cover.
- No other candidate cell's CODEMANIFEST requires changes: `server/etcdserver/apply`, `server/storage/mvcc`, `server/etcdserver`, `server/etcdserver/api/v3rpc` CODEMANIFESTs describe applier/KV/server contracts at a level that does not enumerate this internal validation detail, and their documented exported types/methods are unchanged.

## Usage Impact
No `.usages` files exist in any affected cell today (confirmed via `goga schema`, all `usages: []`). None will be created — the change doesn't introduce a new consumer-facing pattern warranting a practice file; it's a straightforward config-driven error like the pre-existing `ErrLeaseTTLTooLarge`.

## Compatibility Verification
**Backward compatible.** Per the Investigation Report's Breaking Change Assessment (all six questions answered NO or "additive-only"): existing calls under the (generous, self-defaulting) limit are unaffected; re-attach is explicitly exempted regardless of lease size; `Attach`'s signature and behavior are untouched; all existing `LessorConfig{}`-zero-value construction sites (`auth_test.go:86`, `uber_applier_test.go:50`) get the same self-defaulted generous cap as production; the new error follows the exact existing mapping mechanism used by `ErrLeaseTTLTooLarge`/`ErrLeaseExists`. One interface-shape change requires updating all implementers: `Lessor.MaxLeaseKeys() int` is added to the `Lessor` interface, so `FakeLessor` (lessor.go:837-880) must gain a matching method — this is a compile-time-enforced, mechanical addition, not a behavioral break, and the only other implementer is the real `*lessor`.

## Test Strategy
- **server/lease** (`lessor_test.go`): new table-driven test(s) for `Attach`/`newLessor` covering: (a) attaching keys up to `MaxLeaseKeys` succeeds; (b) `MaxLeaseKeys` defaults to `defaultMaxLeaseKeys` when `LessorConfig.MaxLeaseKeys` is zero; (c) `Lease.Len()` returns the correct count as items are attached/detached. (Note: `Attach` itself intentionally does **not** enforce the cap — the new tests verify the primitives the txn-layer check depends on, not a behavior change to `Attach`.)
- **server/etcdserver/txn** (`put_test.go`/`txn_test.go`, or new test file): 
  - Put: a new key that would exceed the configured max is rejected with `lease.ErrTooManyLeaseKeys`, and no mvcc mutation occurs (verify via a fake `mvcc.KV`/`lease.Lessor` that the underlying `Write`/`Put` was never invoked, or that store state is unchanged after the rejected call).
  - Put: re-attaching a key already on a lease that is at/over the limit succeeds.
  - Txn: a single Txn with N `RequestOp_Put`s adding N new distinct keys to the same lease, where the lease has room for fewer than N, is rejected as a whole (no partial application) — verifies the `leaseKeyBudget` cumulative accounting.
  - Txn: a Txn that re-attaches the same already-attached key multiple times, or writes the same new key twice, is handled correctly (not double-counted, not rejected purely for repetition).
- **server/etcdserver/api/v3rpc** (`util_test.go` if present, else integration): verify `lease.ErrTooManyLeaseKeys` maps to `rpctypes.ErrGRPCTooManyLeaseKeys` via `toGRPCErrorMap`.
- **tests/integration** (`clientv3/lease/lease_test.go` or `v3_grpc_test.go`): end-to-end test starting a server with a small `--max-lease-keys` (via test cluster config override), attaching keys up to the limit, confirming the next new-key Put/Txn fails with a clean client-visible gRPC error (`codes.ResourceExhausted`), and — critically — issuing a subsequent, unrelated request (e.g. a `Get`/`Put` with no lease) on the same server afterward to confirm the server is still healthy (no crash/hang), satisfying the "server remains healthy" requirement end-to-end.
- **Regression**: run existing `server/lease`, `server/storage/mvcc`, `server/etcdserver/txn`, `server/etcdserver/apply`, and `server/etcdserver/api/v3rpc` unit test suites, plus relevant `tests/integration/clientv3/lease` and `tests/integration/v3_grpc_test.go` suites, unmodified, to confirm no regression.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Default (100,000) too low for some legitimate existing deployment, causing unexpected rejections after upgrade | Low | Medium | Configurable via `--max-lease-keys`; documented in flag help text and CHANGELOG; operators can raise it before/after upgrade. |
| Missed call site still routes an `Attach` failure through the `kvstore_txn.go:285-288` panic (e.g. a future/alternate caller of `Attach` that doesn't go through `checkLease`) | Low | High (server crash) | This plan intentionally leaves `Attach` itself non-capacity-checking — it cannot fail for capacity reasons, so the panic path is structurally unreachable for this new error; verified by not modifying `Attach`'s error surface at all. |
| Txn cumulative accounting bug undercounts/overcounts across deeply nested `RequestOp_RequestTxn` | Low | Medium | Single shared `*leaseKeyBudget` threaded by reference through all recursive `checkTxn` calls within one `Txn()` invocation, exercised by an explicit nested-Txn test case. |
| `FakeLessor` or another future `Lessor` implementer fails to implement `MaxLeaseKeys()` | Low | Low (compile error, caught immediately) | Interface addition is a compile-time check; only one other implementer (`FakeLessor`) exists today and is updated as part of this change. |
| Race between the pre-check (using live `Lessor` state) and the later `Attach` call, within the same apply invocation | Very Low | Low | Both the check and the eventual `Attach` execute synchronously within the single-threaded raft-apply goroutine for one request; no other goroutine ever *adds* items via `Attach` outside this path, and concurrent lease expiry/revocation can only shrink `itemSet` between check and attach, never grow it — so the invariant (`itemSet` size ≤ cap) cannot be violated by this race, only occasionally be more conservative than strictly necessary. |

---

Do you approve the plan? Proceed to implementation?
