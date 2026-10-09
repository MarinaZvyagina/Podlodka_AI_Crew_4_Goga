# R06-TB-BF-07

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: True
Cost: $3.1445312999999993
Duration: 642348ms, turns: 65

## Agent's own summary

# Change Plan

## Task Classification
**Feature** (net-new capability, additive to the `Lessor` contract; no existing behavior redefined).

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| server/lease | `lessor.go`, `lease.go`, `CODEMANIFEST` | New config field, default const, sentinel error, `MaxLeaseKeys()` interface method + impl, `FakeLessor` update, `Lease.Len()`/`Lease.Contains()`; manifest reconciled |
| server/etcdserver | `server.go` (LessorConfig wiring), `txn/put.go`, `txn/txn.go` (pre-flight capacity check — implementation detail, no manifest change per investigation) | Plumbs new config value; adds pre-flight rejection before any mutating write |
| server/etcdserver/apply | none (no manifest change — `Apply`'s documented algorithm already treats per-request errors opaquely; no new decorator layer needed) | — |
| server/storage/mvcc | none (verified: `Attach`/`Detach` call sites and bootstrap-recovery loop stay byte-for-byte unchanged) | — |
| (non-cell, outside forest) | `api/v3rpc/rpctypes/error.go`, `server/etcdserver/api/v3rpc/util.go`, `server/config/config.go`, `server/embed/config.go`, `server/embed/etcd.go`, `server/etcdmain/help.go`, `etcdutl/etcdutl/common.go` | Error mapping, CLI/config plumbing, second `Lessor` implementer update |

## Root Cause Analysis
Not a defect — `Lessor.Attach` has no capacity notion today, and nothing upstream of it validates lease fan-out before raft-committing a write. This is the intended gap being closed.

## Trace Summary
Client write → gRPC validation (key-uniqueness only) → raft → single-threaded apply (`s.run→applyAll→applyEntries→s.apply`) → `applierV3backend.Put/Txn` → `mvcctxn.Put/Txn` → **pre-flight `checkLease`/`checkTxn` (new capacity gate goes here)** → `kv.Write()` → `storeTxnWrite.put()` → `Lessor.Attach` (stays unconditional, panics upstream guard never triggered by design). Bootstrap recovery (`kvstore.go` restore loop → `Attach`) never passes through the pre-flight gate at all, so it is architecturally untouched.

## Change Strategy
1. **server/lease/lessor.go** — add `DefaultMaxLeaseKeys = 100000` (exported const), `ErrTooManyAttachedKeys` sentinel, `LessorConfig.MaxLeaseKeys int`, `lessor.maxLeaseKeys int` (defaulted in `newLessor` when `<= 0`), `Lessor.MaxLeaseKeys() int` interface method + `*lessor` impl (plain field read, immutable post-construction, no lock) + `FakeLessor.MaxLeaseKeys()`.
2. **server/lease/lease.go** — add `(*Lease).Len() int` and `(*Lease).Contains(item LeaseItem) bool`, both `l.mu.RLock()`-guarded.
3. **etcdutl/etcdutl/common.go** — add `(*SimpleLessor).MaxLeaseKeys() int` returning `lease.DefaultMaxLeaseKeys` (keeps the `var _ lease.Lessor = (*SimpleLessor)(nil)` assertion compiling).
4. **server/etcdserver/txn/put.go** — introduce `checkLeaseCapacity(lessor, p, pendingAttaches map[lease.LeaseID]int) error`; `checkLease` becomes `checkLeaseCapacity(lessor, p, nil)`; `checkPut` gains the `pendingAttaches` param.
5. **server/etcdserver/txn/txn.go** — `Txn()` creates one `pendingAttaches` map and threads it through `checkTxn`'s recursion (nested sub-txns share the same map) so a multi-Put txn attaching several new keys to one lease is checked cumulatively.
6. **api/v3rpc/rpctypes/error.go** — new `ErrGRPCTooManyAttachedKeys` (`codes.ResourceExhausted`), `errStringToError` entry, client-side `ErrTooManyAttachedKeys`.
7. **server/etcdserver/api/v3rpc/util.go** — map `lease.ErrTooManyAttachedKeys` → `rpctypes.ErrGRPCTooManyAttachedKeys`.
8. **server/config/config.go**, **server/embed/config.go**, **server/embed/etcd.go**, **server/etcdserver/server.go** — CLI flag `--max-lease-keys` (default `lease.DefaultMaxLeaseKeys`) plumbed end-to-end into `LessorConfig`.
9. **server/etcdmain/help.go** — cosmetic help-text line.

## Specification Impact
`server/lease/CODEMANIFEST` changes only (this is the cell whose public contract is genuinely growing):
- `Lessor` type annotation / `cfg` param description: extend to mention the new max-keys-per-lease setting alongside "minimum TTL, checkpoint interval, and checkpoint-persistence settings."
- New `Lessor` method: `"MaxLeaseKeys() -> max:int64": |` — "Return the configured maximum number of distinct keys that may be attached to a single lease."
- `Lease` gains two new methods: `"Len() -> count:int64": |` and `"Contains(item LeaseItem) -> attached:bool": |`.
- No change to `Attach`'s documented signature/annotation — its guarantee ("associate items with an existing lease... if the lease does not exist, an error will be returned") is preserved verbatim; the new limit is enforced by the *caller* of `Attach` (an implementation detail outside any documented cell, per investigation), not by `Attach` itself.

`server/etcdserver/apply/CODEMANIFEST` — **no change**. `UberApplier.Apply`'s algorithm already treats per-request-type errors opaquely ("Return the leaf result (or the first short-circuiting decorator's rejection)"); it doesn't enumerate `ErrLeaseNotFound`/`ErrNoSpace` today either, so enumerating this new error would be inconsistent with the manifest's existing abstraction level.

## Usage Impact
None. Neither `server/lease` nor `server/etcdserver/apply` (nor their imports) declare any `.usages` files in `goga schema`. No practice files exist to reconcile.

## Compatibility Verification
**Backward compatible.** Every existing call to `Attach`, `Grant`, `Put`, `Txn` with the same arguments produces the same result for any lease under the (generous, defaulted) cap, and `Attach` itself is behaviorally untouched in all cases including bootstrap recovery. The only new interface method (`MaxLeaseKeys() int`) is additive and both in-repo implementers (`FakeLessor`, `SimpleLessor`) are updated in this same change, so no compile break survives the change. No STOP condition triggered.

## Test Strategy
- `server/lease/lease_test.go` (new or appended to existing lease tests): `Len()`/`Contains()` on empty, single-item, multi-item, and after-Detach lease states.
- `server/lease/lessor_test.go`: `MaxLeaseKeys()` default-when-zero and explicit-config cases; confirm `Attach()` itself is *not* limit-aware (attaching past a small configured cap directly via `Attach` still succeeds — proves the gate lives upstream, not in `Attach`).
- `server/etcdserver/txn` package tests (new `put_test.go`/extend `txn_test.go`): 
  - `checkLeaseCapacity` rejects a genuinely new key once `Len() >= MaxLeaseKeys()`.
  - `checkLeaseCapacity` allows re-attaching a key already in `itemSet` even when at/over cap.
  - `checkLeaseCapacity` is a no-op for `NoLease`.
  - Cumulative Txn case: two Put ops, distinct new keys, same lease, lease at `cap-1` → second op must be rejected even though neither op's *individual* pre-txn state looks over cap.
  - Under-cap lease: existing Put/Txn behavior unchanged (regression guard).
- `server/etcdserver/api/v3rpc` (or `api/v3rpc/rpctypes`) test: `togRPCError(lease.ErrTooManyAttachedKeys)` maps to the right `codes.ResourceExhausted` status.
- Integration-level sanity (if time permits, in `tests/`): a Put that exceeds a small configured `--max-lease-keys` on a running server returns a clean gRPC error and the server keeps serving subsequent requests (crash/hang guard called out explicitly by the requirements).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Missed a third `Lessor` implementer elsewhere in the module (e.g. in `tests/`) | Low | Build failure, easy to spot | `go build ./...` across the whole module during validation; investigation's grep for `func.*Attach(id lease.LeaseID` found exactly two implementers |
| Cumulative Txn accounting double-counts or under-counts across deeply nested sub-txns | Low | Incorrect accept/reject on edge-case nested Txns | Single shared map threaded through all recursive `checkTxn` calls within one top-level `Txn()` invocation; unit test with nested sub-txn covers this |
| Chosen default (100,000) still too low/high for some real deployment | Low | Operator surprise on upgrade | Fully configurable via `--max-lease-keys`; default only gates the explicitly-described pathological case ("hundreds of thousands"), documented in flag help text |
| `checkLeaseCapacity`'s `Lookup`+`Len`+`Contains` sequence assumed race-free by single-threaded raft apply, but some code path bypasses that assumption | Low | Spurious rejection or missed rejection | Confirmed via trace (`s.run`→`applyAll`→`applyEntries`→`s.apply`, entries applied strictly sequentially); `Attach` itself remains unconditional as a structural safeguard against ever panicking even under an unforeseen race |

Do you approve this plan? Proceed to implementation?
