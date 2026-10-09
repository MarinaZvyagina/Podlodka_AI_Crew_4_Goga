# R06-TC-BF-04

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.4
Dangerous success: False
Goga engagement signal: False
Cost: $1.9335932999999998
Duration: 362657ms, turns: 47

## Agent's own summary

# Change Plan

## Task Classification
**Extension** — additive cross-cutting capability via the existing decorator-chain extension point; no existing behavior is modified, only observed.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| server/etcdserver/apply | `audit.go` (new), `uber_applier.go` (edit), `CODEMANIFEST` (edit) | New `auditApplierV3` decorator; one-line wiring in `restoreAlarms()`; `decorator_chain` narrative updated |

## Root Cause Analysis
Not a defect — a net-new requirement. The cell's own manifest names this exact gap ("audit logging" as an example new decorator) and provides the mechanism (Chain-of-Responsibility) to close it uniformly. Investigation confirmed: identity only exists on `InternalRaftRequestWrapper.Header`, visible only inside `Apply()`; corrupt/capped decorators short-circuit without delegating, so the new decorator must sit outside them to see 100% of requests, including alarm-rejected ones.

## Trace Summary
`uberApplier.Apply` → chain's `Apply()` (only `authApplierV3` overrides it) → `applierV3backend.Apply` → `applyFunc` = `uberApplier.dispatch` → `a.applyV3.{Put,Range,DeleteRange,Txn}` (re-enters the same chain from the top, `a.applyV3` = whatever `restoreAlarms()` last set). Placing `auditApplierV3` as the final wrap in `restoreAlarms()` makes it the new head of `a.applyV3`, so both traversals (the `Apply()` pass and the `dispatch()` re-entry pass) go through it first — the `Apply()` pass captures identity, the re-entry pass on `Put`/`Range`/`DeleteRange`/`Txn` produces the audit record using that captured identity, timing the call it wraps.

## Change Strategy
1. **Add `server/etcdserver/apply/audit.go`** implementing `auditApplierV3` exactly as specified in the arguments: identity capture in `Apply()` (mutex-guarded field, mirroring `authApplierV3`'s pattern), per-call timing + outcome recording in `Put`/`Range`/`DeleteRange`/`Txn`, recursive `Txn` key/range collection mirroring `auth.go`'s `checkTxnReqsPermission` traversal shape, single `record()` helper emitting one structured `zap.Info` log line per request via `ApplierOptions.Logger` (already threaded through, no new dependency).
2. **Edit `restoreAlarms()`** in `uber_applier.go`: append `a.applyV3 = newAuditApplierV3(a.lg, a.applyV3)` after the existing conditional corrupt/capped wraps, so audit is always the outermost layer, rebuilt (cheaply — stateless besides the per-call-scoped identity field) every time alarms change, guaranteeing it never gets bypassed regardless of alarm state.
3. **Edit `CODEMANIFEST`**: extend the `decorator_chain` usage entry to state the chain is now `audit (always outermost) → [corruption lockout] → [space-cap] → RBAC authorization → quota → base`, and that audit records identity/operation/key-range/duration/outcome for Put/Range/DeleteRange/Txn only, uniformly, regardless of what the inner layers decide. No changes to `Imports`, `ApplierOptions`, or the `UberApplier`/`NewUberApplier` body entries — `auditApplierV3` is unexported/internal exactly like `authApplierV3`/`quotaApplierV3`/`applierV3Capped`/`applierV3Corrupt`, none of which appear as CODEMANIFEST body types today, so no new body entry is added (consistent with `goga-cell-go`: CODEMANIFEST tracks the exported facade, not internal decorators).

## Specification Impact
Only the `Usages.decorator_chain` free-text narrative in `server/etcdserver/apply/CODEMANIFEST` changes (documentation of the now-5-layer chain and the new outermost position). No `Imports`, no type/method/property contract entries change. `ApplierOptions`, `UberApplier`, `NewUberApplier` signatures and documented algorithm steps are untouched — the manifest's `Apply()` algorithm description ("Run the chain's apply hook top-to-bottom... Dispatch... invoked again through the same chain outermost-first") remains accurate; audit simply becomes part of "the chain."

## Usage Impact
None. `server/etcdserver/apply` has no `.usages/` directory (checked: `ls server/etcdserver/apply/` shows no `.usages` subdir), and no other cell imports a `decorator_chain`-related usage from this cell. No `.usages/*.md` files require updates.

## Compatibility Verification
**Backward compatible.** Every existing call to `Put`/`Range`/`DeleteRange`/`Txn`/`Apply` with the same arguments returns the same `(resp, trace, err)` / `*Result` — the new decorator only observes and logs, never mutates inputs, outputs, or control flow. Existing `WarnOfExpensiveRequest`/`WarnOfFailedRequest`/`ApplySecObserve` calls in `dispatch()`'s defer are untouched. Existing tests (`uber_applier_test.go`, `auth_test.go`) assert only on `result.Err`/black-box behavior, never on `a.applyV3`'s concrete type, and already exercise nil-`Header` requests, which `callerIdentity()` handles explicitly.

## Test Strategy
Add `server/etcdserver/apply/audit_test.go` (or extend `uber_applier_test.go`) covering, via `defaultUberApplier(t)` + a `zaptest`/observer logger core to capture emitted log fields:
- Identity extraction: `Header.Username` set → that value logged; `Header` nil → `"unauthenticated"`; `Header` present but `Username` empty → `"unauthenticated"`.
- Operation kind: one case each for Put→`"write"`, Range→`"read"`, DeleteRange→`"delete"`, Txn→`"transaction"`.
- Key/range: Put logs the plain key; Range/DeleteRange log `[key,rangeEnd)`; Txn (including a nested Txn inside `Success`) logs the union of all touched keys/ranges.
- Outcome: a successful call logs `success=true`; an error (e.g. from a nonexistent-lease Put or explicit test-injected error) logs `success=false`; `mvcc.ErrCompacted` still logs `success=true`.
- Alarm short-circuit coverage: activate CORRUPT (or NOSPACE) alarm, issue a Put/Range/DeleteRange/Txn, and confirm an audit record with `success=false` is still emitted — proving audit sits outside those decorators.
- Regression: confirm `WarnOfExpensiveRequest`/`WarnOfFailedRequest` behavior (already covered by existing tests) is unaffected — run existing `TestUberApplier_Alarm_*` tests unchanged and confirm they still pass.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Rebuilding the audit wrap on every `restoreAlarms()` call adds allocation overhead on alarm toggle | Low | Low | Wrapper is a cheap single-struct allocation; alarms toggle rarely (not per-request) |
| Logging every KV request at Info level could be noisy/costly under high QPS | Medium | Medium | Task requires uniform coverage per compliance ask; noted as an accepted tradeoff — no sampling/level change requested by task, so not implemented speculatively |
| Txn key aggregation string could be large for huge transactions | Low | Low | Bounded by request size itself (already bounded by etcd's txn limits); acceptable for an audit log line |
| Mutex contention on `auditApplierV3.mu` since apply is otherwise serialized per raft-apply loop | Low | Low | Raft entries are applied serially by a single goroutine already (same assumption `authApplierV3` relies on) |

---

Plan is ready. Do you approve the plan? Proceed to implementation?
