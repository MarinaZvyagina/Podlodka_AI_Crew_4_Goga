# R06-TB-BF-02

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: False
Cost: $3.7692820499999997
Duration: 882177ms, turns: 54

## Agent's own summary

# Change Plan

**Task Classification**: Feature (additive server-side configuration + new validation path)

**Affected Cells**

| Cell | Files to Modify | What Changes |
|---|---|---|
| `server/lease` | `lessor.go`, `lease.go` (read-only, no change needed — `Keys()`/`itemSet`/`mu` reused as-is), `CODEMANIFEST` | New `ErrTooManyLeaseKeys` sentinel; `LessorConfig.MaxLeaseKeys int`; `lessor.maxLeaseKeys` field + default in `newLessor`; new `Lessor.CheckAttach(id, items) error` method (real + `FakeLessor` no-op); manifest updated |
| `server/etcdserver` (internal `txn` subpackage + `server.go`) | `txn/put.go`, `txn/txn.go`, `server.go`, `CODEMANIFEST` | `Put()` gains a single-item `CheckAttach` call pre-write; `checkTxn` gains a `leaseItems` accumulator param, `Txn()` does an aggregated per-lease `CheckAttach` pass after `checkTxn` succeeds and before `kv.Write()` opens; `server.go:348` passes `MaxLeaseKeys` into `LessorConfig{}`; manifest annotation note added |
| `server/config` | `config.go` | New `ServerConfig.MaxLeaseKeys` field |
| `server/embed` | `config.go`, `etcd.go` | New `DefaultMaxLeaseKeys` const, `Config.MaxLeaseKeys` field + default assignment + `--max-lease-keys` flag; threaded into `config.ServerConfig{}` |
| `api/v3rpc` | `rpctypes/error.go`, `api/v3rpc/key.go` | New `ErrGRPCTooManyLeaseKeys` + map entry + client alias; new `toGRPCErrorMap` entry translating `lease.ErrTooManyLeaseKeys` |
| `etcdutl` | `etcdutl/etcdutl/common.go` | `SimpleLessor` gains no-op `CheckAttach` to satisfy the widened interface |

**Root Cause Analysis**: Not a defect — new capability. No existing cap on keys-per-lease exists; unbounded growth causes large revoke-time bursts. The only safe enforcement point is the pre-write check phase, because etcd's Txn write path panics on any write-phase error by design (`txn.go:91`), and the mvcc write path (`kvstore_txn.go put()`) has already mutated backend/kvindex state by the time `Attach` would be called.

**Trace Summary**: `EtcdServer.Put/Txn` → `mvcctxn.Put`/`mvcctxn.Txn` → (`checkLease`+new check | `checkTxn`+aggregated new check) → only on success → `kv.Write()` opens → `put()`/`executeTxn()` → `lessor.Attach` (unchanged, still can't fail on this path since it was already vetted). Multi-Put Txns targeting the same lease are handled by aggregating every `RequestPut`'s target lease/key across the whole resolved op tree (including nested `RequestTxn`) before making any accept/reject decision, avoiding the cross-op blind spot identified in investigation.

**Change Strategy**

1. **`server/lease/lessor.go`**:
   - Add `ErrTooManyLeaseKeys = errors.New("too many keys attached to lease")` alongside the other sentinel errors.
   - Add `MaxLeaseKeys int` to `LessorConfig` (0 = unlimited).
   - Add `maxLeaseKeys int` to `lessor` struct; set from `cfg.MaxLeaseKeys` in `newLessor` (no default backfill here — 0 stays 0/unlimited; the *server-level* default lives in `server/embed`, matching how `MinLeaseTTL` has no lessor-level default either).
   - Add to `Lessor` interface: `CheckAttach(id LeaseID, items []LeaseItem) error`.
   - Implement on `*lessor`:
     ```go
     func (le *lessor) CheckAttach(id LeaseID, items []LeaseItem) error {
         le.mu.RLock()
         l := le.leaseMap[id]
         maxKeys := le.maxLeaseKeys
         le.mu.RUnlock()
         if l == nil {
             return ErrLeaseNotFound
         }
         if maxKeys <= 0 || len(items) == 0 {
             return nil
         }
         l.mu.RLock()
         defer l.mu.RUnlock()
         newCount := len(l.itemSet)
         seen := make(map[LeaseItem]struct{}, len(items))
         for _, it := range items {
             if _, ok := seen[it]; ok {
                 continue
             }
             seen[it] = struct{}{}
             if _, ok := l.itemSet[it]; !ok {
                 newCount++
             }
         }
         if newCount > maxKeys {
             return ErrTooManyLeaseKeys
         }
         return nil
     }
     ```
   - Add `func (fl *FakeLessor) CheckAttach(id LeaseID, items []LeaseItem) error { return nil }` next to `FakeLessor.Attach`.

2. **`server/etcdserver/txn/put.go`** — in `Put()`, after `checkAndGetPrevKV` succeeds and before calling `put()`:
   ```go
   if leaseID := lease.LeaseID(p.Lease); leaseID != lease.NoLease {
       if err := lessor.CheckAttach(leaseID, []lease.LeaseItem{{Key: string(p.Key)}}); err != nil {
           return nil, trace, err
       }
   }
   ```
   `checkLease`/`checkPut`/`checkAndGetPrevKV` remain untouched.

3. **`server/etcdserver/txn/txn.go`**:
   - Change `checkTxn` signature to accept `leaseItems map[lease.LeaseID][]lease.LeaseItem`; inside the `RequestPut` case, after `checkPut` returns nil, append `{Key: string(tv.RequestPut.Key)}` to `leaseItems[lease.LeaseID(tv.RequestPut.Lease)]` (skip when `NoLease`); pass `leaseItems` through the recursive `RequestTxn` call unchanged.
   - In `Txn()`, before calling `checkTxn`, create `leaseItems := make(map[lease.LeaseID][]lease.LeaseItem)`; after `checkTxn` returns success, loop `for id, items := range leaseItems { if err := lessor.CheckAttach(id, items); err != nil { txnRead.End(); return nil, nil, err } }` — placed before `txnRead.End()`/`kv.Write()` opens (i.e., still fully within the pre-write phase).

4. **`server/etcdserver/server.go:348`** — add `MaxLeaseKeys: cfg.MaxLeaseKeys,` to the `LessorConfig{}` literal (`cfg` here is `config.ServerConfig`, confirmed at the call site).

5. **`server/config/config.go`** — add `MaxLeaseKeys int` near `MaxTxnOps`.

6. **`server/embed/config.go`** — add `DefaultMaxLeaseKeys = 1000000` (sensible generous default — far above typical usage, so existing deployments are unaffected, while still finite so the feature is active out of the box); add `MaxLeaseKeys int \`json:"max-lease-keys"\`` field; default assignment in `NewConfig()`; `fs.IntVar(&cfg.MaxLeaseKeys, "max-lease-keys", cfg.MaxLeaseKeys, "Maximum number of keys that can be attached to a single lease.")`.

7. **`server/embed/etcd.go`** — thread `MaxLeaseKeys: cfg.MaxLeaseKeys,` into the `config.ServerConfig{}` literal next to `MaxTxnOps`.

8. **`api/v3rpc/rpctypes/error.go`** — add `ErrGRPCTooManyLeaseKeys = status.Error(codes.InvalidArgument, "etcdserver: too many keys attached to lease")` near the other lease errors; add to `errStringToError`; add client alias `ErrTooManyLeaseKeys = Error(ErrGRPCTooManyLeaseKeys)`.

9. **`server/etcdserver/api/v3rpc/key.go`** — add `lease.ErrTooManyLeaseKeys: rpctypes.ErrGRPCTooManyLeaseKeys,` to `toGRPCErrorMap`.

10. **`etcdutl/etcdutl/common.go`** — add `func (sl *SimpleLessor) CheckAttach(id lease.LeaseID, items []lease.LeaseItem) error { return nil }`.

**Specification Impact**

- `server/lease/CODEMANIFEST`: `Lessor(be Backend, cfg LessorConfig)` type annotation gains one sentence noting the configurable per-lease key cap; `cfg` parameter description mentions the new field; new method entry for `CheckAttach` alongside `Attach`; `Attach`'s own annotation unchanged (still always succeeds if the lease exists — cap enforcement lives in `CheckAttach`, called by the consumer beforehand).
- `server/etcdserver/CODEMANIFEST`: `Put`/`Txn` method annotations gain a clause: writes that would exceed the lease's configured key cap fail with a clean error instead of being applied.

**Usage Impact**: No `.usages/` files exist yet for `server/lease` or `server/etcdserver`; none require updates (the `callback_decoupling` inline usage in `server/lease/CODEMANIFEST` remains accurate as-is — no new outbound import introduced).

**Compatibility Verification**: **Backward compatible.** All changes are additive (new config field defaulting to a large finite value that doesn't reject any known real-world usage pattern below one million keys per lease; new interface method implemented everywhere the interface is implemented; internal unexported signature change with a single, already-identified call site). No existing method's behavior changes for callers who don't hit the new cap.

**Test Strategy**

- `server/lease/lessor_test.go`: table test for `CheckAttach` — under cap passes; at-cap + new key rejects with `ErrTooManyLeaseKeys`; at-cap + re-attach of an already-present key passes; nonexistent lease returns `ErrLeaseNotFound`; `MaxLeaseKeys == 0` never rejects regardless of count.
- `server/etcdserver/txn/put_test.go` (or new test in `put.go`'s test file): `Put()` at cap with a new key returns the cap error and does not mutate the store (verify via `mvcc.KV` state / no revision bump).
- `server/etcdserver/txn/txn_test.go`: a `Txn` with two `RequestPut` ops attaching two distinct new keys to the same lease at `cap-1` remaining slots is rejected as a whole (proves the aggregation fix); a `Txn` re-attaching an already-present key at full cap succeeds.
- `server/embed` config test (if one exists for `MaxTxnOps` flag wiring): mirror it for `--max-lease-keys` default + override.
- Integration/e2e (optional, if time permits): one `tests/integration` case exercising `Put` against a real server started with a small `--max-lease-keys` value, asserting the gRPC error surfaces as `rpctypes.ErrTooManyLeaseKeys` on the client.

**Risk Assessment**

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Default value too low, breaking a real deployment with legitimately huge leases | Low | High | Default set to 1,000,000 — an order of magnitude above the "hundreds of thousands" pathological case described; operators tune down via flag if needed |
| Missed a `Lessor` interface implementer, breaking compilation | Low | Medium | Confirmed via repo-wide grep: only `lessor`, `FakeLessor`, `SimpleLessor` implement the full interface; all three updated; `go build ./...` will catch anything missed |
| Multi-op Txn aggregation logic has an off-by-one or path-consumption bug | Medium | Medium | Mirrors `checkTxn`'s already-correct, tested `txnPath` consumption pattern exactly; add dedicated test case with 2 Puts to the same lease in one Txn |
| Existing lease recovery/restore path (`kvstore.go:398`) starts rejecting pre-existing over-cap leases after a config change | Low (by design, avoided) | High if it occurred | `CheckAttach` is never called from the restore path — restore continues calling `Attach` directly, which has no cap enforcement, exactly as today |
| New sentinel error not unwrapped correctly, falling through to `codes.Unknown` at `togRPCError` | Low | Medium | `CheckAttach` returns the sentinel directly (no wrapping), matching the exact pattern of `ErrLeaseNotFound`'s existing successful translation |

---

Do you approve this plan? Proceed to implementation?
