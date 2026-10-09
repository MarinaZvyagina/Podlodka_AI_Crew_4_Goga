# R06-TB-BP-10

Condition: goga_full_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: True
Cost: $2.7300918000000007
Duration: 546155ms, turns: 56

## Agent's own summary

# Change Plan

## Task Classification
Feature (additive, configurable safety limit) — no bugfix, no refactor of existing behavior.

## Affected Cells
| Cell | Files to Modify | What Changes |
|---|---|---|
| server/lease | `lessor.go` | New error, new `LessorConfig` field, new `Lessor.CheckAttach` method + impl, `FakeLessor.CheckAttach` |
| server/etcdserver/txn (plain Go, not a modeled cell) | `put.go` | `checkLease` calls `CheckAttach` instead of `Lookup` |
| server/etcdserver/api/v3rpc (modeled cell) + api/v3rpc/rpctypes (plain Go) | `util.go`, `../../api/v3rpc/rpctypes/error.go` | New gRPC error + map entry |
| server/config, server/embed (plain Go) | `config.go` (both), `etcd.go` | New config field, flag, default, wiring |
| server/etcdserver (modeled cell) | `server.go` | Wire new field into `LessorConfig` |
| etcdutl/etcdutl (outside forest) | `common.go` | `SimpleLessor.CheckAttach` (mechanical, keeps build green) |

## Root Cause Analysis
There is no read-only, pre-mutation way to ask "would attaching this key to this lease exceed a policy limit." The only place safe to answer that question is `checkLease`, which both `Put()` and `Txn()`/`checkPut()` already call before any KV mutation begins. Enforcing inside `Attach()` itself is unsafe: `kvstore_txn.go`'s live-write path panics on any error from `Attach`, since `TxnWrite.Put` has no error return.

## Trace Summary
`Put()`/`checkPut()` → `checkLease(lessor, p)` → (new) `lessor.CheckAttach(leaseID, [{Key: p.Key}])` → returns `ErrLeaseNotFound` (unchanged) or new `ErrTooManyLeaseKeys` → propagates as `error` through `mvcctxn.Put`/`Txn` → apply decorator chain (already `error`-returning) → `EtcdServer` apply result → `v3rpc` → `togRPCError` (map lookup, exact-match) → gRPC status → client. No mutation (`kv.Write`) has started when this returns, in either the Put or Txn path.

## Change Strategy
1. **server/lease/lessor.go**
   - Add `ErrTooManyLeaseKeys = errors.New("too many keys attached to lease")` next to the existing `Err*` vars.
   - Add `MaxLeaseAttachedKeys int` to `LessorConfig` (zero value = unlimited; no "replace zero with a default" logic needed, since zero *is* the desired unlimited behavior — unlike `MinLeaseTTL`/`CheckpointInterval` which replace zero with a nonzero default).
   - Add `maxLeaseAttachedKeys int` to the `lessor` struct; set directly from `cfg.MaxLeaseAttachedKeys` in `newLessor` (no defaulting branch).
   - Add to the `Lessor` interface:
     ```go
     // CheckAttach reports whether Attach would succeed for the given items,
     // without mutating lease state. Items already attached to the lease do
     // not count against the configured limit.
     CheckAttach(id LeaseID, items []LeaseItem) error
     ```
   - Implement on `*lessor`: `le.mu.RLock()`, look up lease (miss → `ErrLeaseNotFound`), then `l.mu.RLock()`, count items in `items` not already in `l.itemSet`; if that count > 0 and `len(l.itemSet) + newCount > le.maxLeaseAttachedKeys` (only when `le.maxLeaseAttachedKeys > 0`) → `ErrTooManyLeaseKeys`; else `nil`.
   - `Attach()` body is untouched — confirmed no enforcement added there.
   - `FakeLessor.CheckAttach(id LeaseID, items []LeaseItem) error { return nil }`.

2. **etcdutl/etcdutl/common.go**: `SimpleLessor.CheckAttach(id lease.LeaseID, items []lease.LeaseItem) error { return nil }`, placed next to its existing `Attach`.

3. **server/etcdserver/txn/put.go**: rewrite `checkLease` to:
   ```go
   func checkLease(lessor lease.Lessor, p *pb.PutRequest) error {
       leaseID := lease.LeaseID(p.Lease)
       if leaseID != lease.NoLease {
           return lessor.CheckAttach(leaseID, []lease.LeaseItem{{Key: string(p.Key)}})
       }
       return nil
   }
   ```
   This is a strict superset of today's check (was: `if l := lessor.Lookup(leaseID); l == nil { return ErrLeaseNotFound }`), same error for the same failure, new error only for the new condition.

4. **api/v3rpc/rpctypes/error.go**: add `ErrGRPCLeaseTooManyKeys = status.Error(codes.ResourceExhausted, "etcdserver: too many keys attached to lease")` beside the other lease errors; add to `errStringToError`; add client-side `ErrLeaseTooManyKeys = Error(ErrGRPCLeaseTooManyKeys)` beside `ErrLeaseTTLTooLarge`.

5. **server/etcdserver/api/v3rpc/util.go**: add `lease.ErrTooManyLeaseKeys: rpctypes.ErrGRPCLeaseTooManyKeys,` to `toGRPCErrorMap`.

6. **Config plumbing**, exactly mirroring the `MaxTxnOps`/`MaxRequestBytes` pattern at each of the four sites:
   - `server/config/config.go`: `MaxLeaseAttachedKeys int` field with doc comment "0 disables the limit (default)."
   - `server/embed/config.go`: `DefaultMaxLeaseAttachedKeys = 0` constant; `MaxLeaseAttachedKeys int \`json:"max-lease-attached-keys"\`` field; set in `NewConfig()`'s literal; flag `fs.IntVar(&cfg.MaxLeaseAttachedKeys, "max-lease-attached-keys", cfg.MaxLeaseAttachedKeys, "Maximum number of distinct keys that can be attached to a single lease (0 is unlimited).")`.
   - `server/embed/etcd.go`: `MaxLeaseAttachedKeys: cfg.MaxLeaseAttachedKeys,` in the `config.ServerConfig{...}` literal.
   - `server/etcdserver/server.go`: `MaxLeaseAttachedKeys: cfg.MaxLeaseAttachedKeys,` in the `lease.LessorConfig{...}` literal (matching the existing local variable name used at that call site, `cfg`, confirmed from the read file).

## Specification Impact
`server/lease/CODEMANIFEST` (only manifest touched):
- `Lessor(be Backend, cfg LessorConfig)` entity annotation / `cfg` line: extend to mention "...minimum TTL, checkpoint interval, checkpoint-persistence, and the maximum number of distinct keys a lease may have attached (0 = unlimited) settings."
- `Attach(id int64, items []LeaseItem) -> err:error` method annotation: extend with a `Constraints:`-style note — attaching an item already associated with the lease never counts against the limit; attaching a distinct new item that would push the lease over its configured maximum key count is rejected as a whole (no partial attach), returning the new error.
- Add a line noting `ErrTooManyLeaseKeys` as a named error the cell can return, alongside the existing `ErrLeaseNotFound` reference style already used in the method's annotation.
No other cell's CODEMANIFEST changes — `server/etcdserver/txn`, `server/embed`, `server/config`, `api/v3rpc/rpctypes`, and `etcdutl` are all plain Go packages outside the modeled forest (confirmed via `goga schema`).

## Usage Impact
No `.usages` files exist today for any touched cell (confirmed in Investigation Report). None need creation to satisfy the task — the DSL treats usages as consumer-facing practice docs, not a requirement generator, and this change doesn't introduce a new consumption pattern that needs its own worked example beyond what CODEMANIFEST annotations already state.

## Compatibility Verification
**Backward compatible.** `Attach()` behavior is byte-for-byte unchanged. `LessorConfig{}` zero-value (used throughout existing tests) yields `maxLeaseAttachedKeys == 0` → unlimited, identical to today's real (unlimited) behavior. `checkLease`'s existing `ErrLeaseNotFound` case is preserved exactly. The only new interface method (`CheckAttach`) is additive; its two additional in-repo implementers (`FakeLessor`, `SimpleLessor`) are updated in the same change so nothing fails to compile. New config field defaults to `0`/unlimited at every layer, so no existing deployment's behavior changes on upgrade unless it explicitly sets the new flag.

## Test Strategy
- **server/lease** (unit, `lessor_test.go`): 
  - `CheckAttach` returns `ErrLeaseNotFound` for unknown lease (existing-equivalent case).
  - With `MaxLeaseAttachedKeys` set low (e.g. 2): attaching up to the limit succeeds via `Attach`+`CheckAttach` sequence; attaching one more distinct key is rejected by `CheckAttach` with `ErrTooManyLeaseKeys`.
  - Re-`CheckAttach`/`Attach` of an already-attached key succeeds even when the lease is already at/over the limit (construct a lease already over the limit — e.g. limit lowered conceptually by attaching items when `MaxLeaseAttachedKeys` was higher/zero, or directly seed `itemSet` — then confirm re-attach of an existing key is never rejected).
  - `MaxLeaseAttachedKeys == 0` (or default `LessorConfig{}`): unlimited, unaffected — attach many keys, always succeeds (regression guard mirroring existing large-attach tests if present).
- **server/etcdserver/txn** (unit, `put_test.go`/new table cases): `checkLease` propagates `ErrTooManyLeaseKeys` from a `FakeLessor`-like stub; a `Txn` containing a put that would exceed the limit is rejected by `checkTxn` before any write executes (assert via a KV/lessor test double that no mutation occurred).
- **server/etcdserver/api/v3rpc** (unit): `togRPCError(lease.ErrTooManyLeaseKeys)` yields `rpctypes.ErrGRPCLeaseTooManyKeys` with `codes.ResourceExhausted`.
- **Integration** (`tests/integration` lease/kv suite): start a real server with `--max-lease-attached-keys` set low; Put keys up to the limit (succeed); Put one more new key on that lease (fails with the new gRPC error, correct code); re-Put an existing key on the same lease (succeeds); **follow with an unrelated Put/Range on a different key/lease to prove the server is still healthy and serving** after the rejection.

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Missing an implementer of `lease.Lessor`, leaving a compile break | Low | High (build fails) | Already enumerated exactly 3 implementers via repo-wide grep (`lessor`, `FakeLessor`, `SimpleLessor`); all three updated in this change |
| Race between check-time count and execute-time mutation under concurrent apply | Very Low | High if it existed | Etcd applies raft-committed entries serially (single apply goroutine); confirmed no other Attach/Detach can interleave between `checkLease` and the subsequent mutation within the same request |
| Wrong default breaks existing deployments | Very Low | High | Default is `0` = unlimited at every layer — identical to current behavior; enforcement is strictly opt-in |
| gRPC error code choice (`ResourceExhausted`) debatable vs. `FailedPrecondition`/`OutOfRange` | Low | Low (cosmetic/API-surface) | Chose `ResourceExhausted` to mirror `ErrGRPCNoSpace` (same family: hit a capacity ceiling); flagged below for explicit approval |
| Flag/field naming (`max-lease-attached-keys` / `MaxLeaseAttachedKeys`) collides with future upstream naming | Low | Low | Follows existing `max-txn-ops`/`max-request-bytes` naming convention; flagged below for explicit approval |

### Items flagged for explicit approval before implementation
1. **Flag name & field naming**: `--max-lease-attached-keys` / `MaxLeaseAttachedKeys` (config), `ErrTooManyLeaseKeys` (internal error), `ErrGRPCLeaseTooManyKeys`/`ErrLeaseTooManyKeys` (gRPC/client error).
2. **Default value**: `0` (unlimited) at every layer — feature is opt-in only.
3. **gRPC status code**: `codes.ResourceExhausted` with message `"etcdserver: too many keys attached to lease"`.
4. **Enforcement point**: only in `checkLease` (pre-mutation validation), not inside `Attach()` itself — meaning direct callers of `Lessor.Attach()` outside the Put/Txn path (if any exist beyond what was traced) would not be capacity-limited by `Attach()` alone, only by `CheckAttach()` where callers choose to call it.

Do you approve this plan? Proceed to implementation?
