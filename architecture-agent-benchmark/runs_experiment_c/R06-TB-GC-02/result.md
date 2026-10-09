# R06-TB-GC-02

Condition: goga_native_architecture
Base tag: condition-c-r06-v1
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: True
Cost: $3.9664911
Duration: 696551ms, turns: 86

## Agent's own summary

Good, this confirms the exact pattern for the new gRPC error. Now producing the Change Plan.

# Change Plan

## Task Classification
**Feature** (new configurable safety limit) — additive, no removal/modification of existing exported behavior.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| server/lease | `lessor.go`, `lease.go`, `CODEMANIFEST` | New sentinel error; new O(1) count accessor on `Lease` |
| server/etcdserver/apply | new `leasekeylimit.go`, `interface.go`, `uber_applier.go`, `CODEMANIFEST` | New decorator; new `ApplierOptions` field; wiring into the chain |
| server/etcdserver | `server.go`, `CODEMANIFEST` | Wire `s.Cfg.MaxLeaseKeys` into `ApplierOptions` |
| server/config (ungoverned) | `config.go` | New `MaxLeaseKeys int` field |
| server/embed (ungoverned) | `config.go`, `etcd.go` | New default const, struct field, flag, defaults literal, copy to `ServerConfig` |
| server/etcdmain (ungoverned) | `help.go` | New `--max-lease-keys` help line |
| api/v3rpc/rpctypes (ungoverned) | `error.go` | New `ErrGRPCLeaseTooManyKeys` + `ErrLeaseTooManyKeys` |
| server/etcdserver/api/v3rpc (governed, but `util.go` is a leaf helper not part of the CODEMANIFEST type list) | `util.go` | New `toGRPCErrorMap` entry |

## Root Cause Analysis
No component today bounds `Lease.itemSet` size, and no pre-write check exists for lease-key cardinality. `Lessor.Attach()` is called from both the raft-apply write path and the unconditional startup-restore path, so the limit cannot live inside `Attach` itself. The mvcc write (`storeTxnWrite.put()`) mutates the backend/kvindex *before* calling `Attach`, so the limit cannot be enforced there either without risking partial application. The correct enforcement point is a new pre-check decorator in the `server/etcdserver/apply` chain — the same shape `authApplierV3` already uses to reject `Put`/`Txn` before delegating to the inner applier.

## Trace Summary
`v3rpc.kvServer.Put/Txn` → raft → `uberApplier.dispatch` → **`authApplierV3`** → **`quotaApplierV3`** → `applierV3backend` → `mvcctxn.Put/Txn` → `checkLease`(pre-check, no mutation) → `kv.Write`/`storeTxnWrite.put()` (mutates bolt+kvindex, *then* conditionally calls `Lessor.Attach`). The new decorator is inserted between `quotaApplierV3` and `applierV3backend` (order relative to quota doesn't affect correctness since quota always calls its inner applier regardless of its own `ok` check — it will call ours unconditionally, and ours will block before backend runs).

## Change Strategy

**1. server/lease** (`lessor.go`):
```go
ErrLeaseTooManyKeys = errors.New("too many keys attached to lease")
```
placed in the existing `var (...)` block next to `ErrLeaseTTLTooLarge`.

(`lease.go`), new method next to `Keys()`:
```go
// Len returns the number of keys currently attached to the lease.
func (l *Lease) Len() int {
	l.mu.RLock()
	defer l.mu.RUnlock()
	return len(l.itemSet)
}
```
No changes to `Attach`, `LessorConfig`, `NewLessor`, or the `Lessor` interface (both `GetLease` and `Lookup` are already exported and sufficient).

**2. server/etcdserver/apply**, new file `leasekeylimit.go`:
```go
type leaseKeyLimitApplierV3 struct {
	applierV3
	lessor       lease.Lessor
	maxLeaseKeys int
}

func newLeaseKeyLimitApplierV3(lessor lease.Lessor, maxLeaseKeys int, app applierV3) applierV3 {
	return &leaseKeyLimitApplierV3{app, lessor, maxLeaseKeys}
}

func (a *leaseKeyLimitApplierV3) Put(p *pb.PutRequest) (*pb.PutResponse, *traceutil.Trace, error) {
	if err := checkPutLeaseKeyLimit(a.lessor, a.maxLeaseKeys, p, make(map[lease.LeaseID]int)); err != nil {
		return nil, nil, err
	}
	return a.applierV3.Put(p)
}

func (a *leaseKeyLimitApplierV3) Txn(rt *pb.TxnRequest, skipRangeExecution bool) (*pb.TxnResponse, *traceutil.Trace, error) {
	if err := checkTxnLeaseKeyLimit(a.lessor, a.maxLeaseKeys, rt, make(map[lease.LeaseID]int)); err != nil {
		return nil, nil, err
	}
	return a.applierV3.Txn(rt, skipRangeExecution)
}
```
Plus free functions `checkPutLeaseKeyLimit` and `checkTxnLeaseKeyLimit`/`checkTxnReqsLeaseKeyLimit`, structured exactly like `checkPutAuth`/`checkTxnPermission`/`checkTxnReqsPermission` in `auth.go` (recurse into `rt.Success`, `rt.Failure`, and nested `RequestOp_RequestTxn`; call the Put check for each `RequestOp_RequestPut`).

`checkPutLeaseKeyLimit` logic:
```go
func checkPutLeaseKeyLimit(lessor lease.Lessor, maxLeaseKeys int, p *pb.PutRequest, pending map[lease.LeaseID]int) error {
	if maxLeaseKeys <= 0 || p.IgnoreLease {
		return nil
	}
	leaseID := lease.LeaseID(p.Lease)
	if leaseID == lease.NoLease {
		return nil
	}
	item := lease.LeaseItem{Key: string(p.Key)}
	if lessor.GetLease(item) == leaseID {
		return nil // already attached to this lease: re-attach, never rejected
	}
	l := lessor.Lookup(leaseID)
	if l == nil {
		return nil // let the downstream checkLease raise ErrLeaseNotFound
	}
	if l.Len()+pending[leaseID]+1 > maxLeaseKeys {
		return lease.ErrLeaseTooManyKeys
	}
	pending[leaseID]++
	return nil
}
```
- `maxLeaseKeys <= 0` ⇒ unlimited (covers zero-value `ApplierOptions{}` in existing tests/callers that don't set the new field — this is the mechanism that guarantees no breaking change for any caller that doesn't opt in).
- `p.IgnoreLease` short-circuits to allowed without resolving the real lease id — correct because `IgnoreLease` semantics (server/etcdserver/txn/put.go) always reuse the key's *current* lease, and `checkAndGetPrevKV` already guarantees the key exists when `IgnoreLease` is set, so it is structurally always a re-attach.
- The `pending` map is created fresh per top-level `Put`/`Txn` call and threaded through the whole recursive `Txn` walk, so sibling ops against the same lease are tallied cumulatively before any of them execute — closing the under-counting gap identified in investigation.
- Both `rt.Success` and `rt.Failure` are checked unconditionally (matching `checkTxnPermission`'s existing precedent), since which branch executes is only resolved later, deeper in the chain.

`interface.go`: add `MaxLeaseKeys int` to `ApplierOptions`.

`uber_applier.go`, `newApplierV3()`:
```go
func newApplierV3(opts ApplierOptions) applierV3 {
	applierBackend := newApplierV3Backend(opts)
	leaseLimited := newLeaseKeyLimitApplierV3(opts.Lessor, opts.MaxLeaseKeys, applierBackend)
	return newAuthApplierV3(
		opts.AuthStore,
		newQuotaApplierV3(opts.Logger, opts.QuotaBackendBytesCfg, opts.Backend, leaseLimited),
		opts.Lessor,
	)
}
```

**3. server/etcdserver** (`server.go`, `NewUberApplier()`): add `MaxLeaseKeys: s.Cfg.MaxLeaseKeys,` to the `ApplierOptions{}` literal.

**4. Plumbing** (`server/config/config.go`, `server/embed/config.go`, `server/embed/etcd.go`, `server/etcdmain/help.go`): mirror `MaxTxnOps` exactly — new `MaxLeaseKeys int` field in `config.ServerConfig`; new `DefaultMaxLeaseKeys` const, `MaxLeaseKeys int \`json:"max-lease-keys"\`` field, defaults-literal entry, and `fs.IntVar(&cfg.MaxLeaseKeys, "max-lease-keys", cfg.MaxLeaseKeys, "Maximum number of keys that can be attached to a single lease. 0 means no limit.")` in `server/embed/config.go`; copy line in `embed/etcd.go`; one help-text line in `help.go`.

**5. Client-facing error**: `api/v3rpc/rpctypes/error.go` — add `ErrGRPCLeaseTooManyKeys = status.Error(codes.ResourceExhausted, "etcdserver: too many keys attached to lease")` next to `ErrGRPCLeaseTTLTooLarge`, register in the `errStringToError`-style map next to the other lease errors, and add client-side `ErrLeaseTooManyKeys = Error(ErrGRPCLeaseTooManyKeys)`. `server/etcdserver/api/v3rpc/util.go` — add `lease.ErrLeaseTooManyKeys: rpctypes.ErrGRPCLeaseTooManyKeys` to `toGRPCErrorMap`.

**6. Default value — needs your confirmation.** Recommendation: **`DefaultMaxLeaseKeys = 100000` (100k)**, but stored as `int64` field named `MaxLeaseKeys` — Reasoning: the problem statement specifically cites "hundreds of thousands" as the trouble threshold, so the default should sit *below* that band to actually prevent the described incident by default, while still being generous enough that essentially no legitimate single-lease use case (session leases, per-connection leases, etc.) organically reaches 100k distinct keys. This is a judgment call with a real tradeoff (a lower default protects more deployments out-of-the-box but has a small chance of surprising an existing deployment that already legitimately runs a lease near that size); an alternative conservative choice would be `1,000,000` to almost never trigger unintentionally. **I'd like you to pick one of these (or another value) before implementation.**

## Specification Impact
- `server/lease/CODEMANIFEST`: add `Lease.Len() -> count:int` method entry; add `ErrLeaseTooManyKeys`-equivalent note is not required (the DSL doesn't catalog error vars, consistent with how `ErrLeaseNotFound` etc. aren't listed today — confirmed by reading the existing manifest body, which lists only `Lessor`/`Lease` types and methods, no package-level error vars). No change to `Attach`'s annotation (behavior unchanged) or to `LessorConfig`.
- `server/etcdserver/apply/CODEMANIFEST`: add a new type entry for the decorator (mirroring how `UberApplier`/`ApplierOptions` are documented) and note `ApplierOptions.MaxLeaseKeys` in `ApplierOptions`'s properties.
- `server/etcdserver/CODEMANIFEST`: `NewServer`/`EtcdServer` annotations likely don't need changes beyond confirming `NewUberApplier` still matches its documented behavior — to be verified during Manifest Reconciliation (Step 7 of the pipeline) against the actual current text.

## Usage Impact
No `.usages` files exist yet for `server/lease` or `server/etcdserver/apply` (`goga schema` reports `"usages": []` for both), so there is nothing to update; Usage Reconciliation (pipeline Step 8) will only need to confirm this remains true, not edit content.

## Compatibility Verification
**Backward compatible.** Every new identifier is additive. The only caller-visible change in behavior is that a `Put`/`Txn` which attaches a *new* key to a lease already at/over an *explicitly configured* limit now fails — impossible to trigger with the zero-value default unless the operator sets `--max-lease-keys` (and even the shipped non-zero default is chosen to be far above realistic existing single-lease key counts). No existing function signature changes; no changes to `Attach`, `Lookup`, `GetLease`, `LessorConfig`, or any `pb.*` proto type.

## Test Strategy
- **Unit** (`server/lease`): `Lease.Len()` returns correct count as items are added/removed via existing `SetLeaseItem`/internal mutation paths used by current lease tests.
- **Unit** (`server/etcdserver/apply`, new `leasekeylimit_test.go`), using the existing `lease.FakeLessor` test double (already in the cell's exported types per `goga schema`):
  - Put under limit → unaffected (no error, delegates through).
  - Put re-attaching a key already on the lease, with the lease exactly at the limit → allowed.
  - Put attaching a genuinely new key at the limit → rejected with `lease.ErrLeaseTooManyKeys`, and the embedded (mock) inner applier's `Put` is asserted **not called** (proves no partial application).
  - Txn with N new-key Puts against the same lease that individually stay under the limit but cumulatively exceed it → rejected, inner `Txn` not called.
  - `PutRequest.IgnoreLease = true` → never rejected regardless of configured limit.
  - `PutRequest.Lease == 0` → never rejected.
  - `maxLeaseKeys <= 0` → never rejected (unlimited/default-off semantics for zero-value config).
- **Integration** (`tests/integration`, following the existing `v3_lease_test.go` pattern which already starts a real cluster and exercises Lease+Put together): start a member with a low `--max-lease-keys`, attach up to the limit, assert the next distinct-key Put fails with a `ResourceExhausted`/ lease-too-many-keys gRPC status, then assert the server is still healthy — a Range/Put on an unrelated key and a Put re-attaching an already-attached key both still succeed immediately after the rejection.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Chosen default rejects a legitimate existing large-lease deployment after upgrade | Low-Medium | Medium (write failures on that one lease only; no crash, no data loss — existing keys stay attached and lease still functions for reads/revoke) | Default value explicitly chosen high relative to described real-world trouble threshold ("hundreds of thousands"); flagged for your confirmation before implementation |
| Txn sibling-ops under-counting reintroduced by a future edit that forgets to thread `pending` | Medium (over time) | High (silently allows unbounded growth via txn batching) | Dedicated unit test (multi-put-same-lease-in-one-txn) locks this in |
| New decorator ordering relative to quota/auth accidentally lets a mutation slip through | Low | High (defeats the whole feature) | Unit tests assert the inner (mock) applier is never invoked on rejection, not just that an error is returned |
| Restore path regression (limit accidentally enforced during startup replay) | Low (design explicitly avoids touching `Lessor.Attach`/restore path) | High (data consistency leak) | No test currently exists for this since the design deliberately never touches `Attach`/kvstore.go — add one regression test in `server/storage/mvcc` restore tests asserting restore is unaffected by a low `MaxLeaseKeys`... actually mvcc has no knowledge of the limit at all in this design, so no test is needed there; noted as a design invariant instead |

---

Two things need your explicit decision before I start implementing:
1. **Default value** for `MaxLeaseKeys` — I recommend **100,000**, with **1,000,000** as a more conservative alternative. Which do you want?
2. **Flag/identifier naming** — I'm proposing `--max-lease-keys` / `MaxLeaseKeys` / `lease.ErrLeaseTooManyKeys` / `rpctypes.ErrGRPCLeaseTooManyKeys`. Any preference otherwise?

Do you approve this plan? Proceed to implementation?
