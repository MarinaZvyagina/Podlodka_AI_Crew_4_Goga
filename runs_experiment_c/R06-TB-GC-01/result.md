# R06-TB-GC-01

Condition: goga_native_architecture
Base tag: condition-c-r06-v1
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: True
Cost: $4.06437765
Duration: 654711ms, turns: 68

## Agent's own summary

# Investigation Report

## Task Summary
Add a server-configurable cap on the number of distinct keys attachable to one lease. A `Put` or `Txn`-with-`Put`s that would push its target lease's distinct-key count past the cap must fail with a clean, client-facing error, atomically (no partial `Txn` application) and without crashing the server. Re-attaching an already-attached key, and any lease under the limit, must be unaffected — matching today's behavior byte-for-byte.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| server/lease | Adds `Lease.KeyCount() int`, an O(1) accessor the limit check needs | High |
| server/etcdserver/apply | `ApplierOptions` (documented type) gains a config field; `applierV3backend.Put`/`Txn` thread it through | High |
| server/etcdserver | `NewUberApplier` wiring (server.go:1142) and the read-only Txn fast path (v3_server.go:366) both call into the changed `txn` package | High |
| server/etcdserver/api/v3rpc | `toGRPCErrorMap` (util.go:35, unexported) gains one entry | Low |

## Tracing Summary

Confirmed call graph for the write path (`Put` request):
```
gRPC KVServer.Put → EtcdServer (raft propose) → apply.Apply → UberApplier decorator chain
  → applierV3backend.Put (server/etcdserver/apply/backend.go:50)
    → txn.Put (server/etcdserver/txn/put.go:30)
        checkLease(lessor, p)              // pre-mutation, existing
        txnWrite := kv.Write(trace)         // NOT a mutation, just opens the tx
        checkAndGetPrevKV(...)              // pre-mutation, existing (read-only Range)
        [NEW: checkLeaseKeyLimit(...)]      // pre-mutation — must land HERE, before the next line
        put(ctx, txnWrite, p, prevKV)       // FIRST actual mutation: storeTxnWrite.put()
          → backend.UnsafeSeqPut + kvindex.Put (mvcc/kvstore_txn.go:259-260, irreversible)
          → tw.s.le.Attach(...)             // mvcc/kvstore_txn.go:285, panics on any error today
```

For `Txn`:
```
txn.Txn (server/etcdserver/txn/txn.go:32)
  checkTxn(trace, txnRead, rt, lessor, txnPath)   // pre-mutation walk, existing — recurses checkPut per Put op
  [NEW: aggregate-then-check pending lease-key counts here, after checkTxn succeeds, still pre-mutation]
  txnWrite = kv.Write(trace)                      // opens tx, not a mutation
  txn(ctx, lg, txnWrite, rt, isWrite, txnPath, skipRangeExecution)
    → executeTxn → put() per RequestOp_RequestPut  // mutates; any error here → lg.Panic (txn.go:91) for isWrite
```

Both confirm: the only safe insertion point is inside the existing pre-mutation validation pass, before `kv.Write`'s result is used to call `.Put()`.

## Data Flow Analysis
- **Config**: CLI flag `--max-lease-keys` (new) → `embed.Config.MaxLeaseKeys` (new, `uint`, default constant `DefaultMaxLeaseKeys`) → `embed.StartEtcd` → `config.ServerConfig.MaxLeaseKeys` (new) → `EtcdServer.Cfg` → `NewUberApplier` reads `s.Cfg.MaxLeaseKeys` into `apply.ApplierOptions.MaxLeaseKeysCfg` (new, `int`) → `applierV3backend.Put/Txn` pass `a.options.MaxLeaseKeysCfg` into `mvcctxn.Put`/`mvcctxn.Txn` (new parameter) → `checkLeaseKeyLimit` helper (new, in `server/etcdserver/txn`).
- **Read-only Txn fast path**: `v3_server.go:366` calls `txn.Txn` directly (bypassing the apply-layer decorator chain per the cell's own documented "read-only Txn fast path"); confirmed via `IsTxnReadonly`/`IsTxnSerializable` gating that this path can never carry a `Put` (`txn.go:352-364`), so the new parameter is inert there but must still be threaded through to satisfy the new function signature — will pass `int(s.Cfg.MaxLeaseKeys)` for consistency.
- **Limit evaluation**: `checkLeaseKeyLimit(lessor, maxLeaseKeys, pending map[LeaseID]map[string]struct{})`. For each lease ID with pending candidate keys: `lessor.Lookup(id)` (existing, exported) → nil means `checkLease` already rejected it upstream, skip; else for each candidate key not already reported by `lessor.GetLease(LeaseItem{Key: key}) == id` (existing, exported, O(1) map lookup), count as new; reject if `lease.KeyCount() + newCount > maxLeaseKeys` (`maxLeaseKeys <= 0` = unlimited, preserves old behavior exactly).
- **Batch aggregation** closes the confirmed gap: `checkPut` (extended) resolves the *effective* lease ID the same way `put()` already does (`p.IgnoreLease` → pulled from `prevKV.KVs[0].Lease`, else `p.Lease` — verified at put.go:57-58) and records `{leaseID: key}` into a per-`Txn`-call pending map threaded through `checkTxn`'s existing recursion (txn.go:201-228), so two `Put`s to distinct new keys on the same lease within one `Txn` are validated together, not independently against stale state.
- **Restore path is exempt by construction**: `kvstore.go:393-398`'s `Attach` call during backend-replay startup is untouched (we never modify `Attach` or add any check inside it), so leases persisted before this feature existed — potentially already over any newly-configured limit — continue to load without error. Confirmed no other call sites of `.Attach(` exist (`grep` returned exactly these two, both already read).

## Manifest Algorithm Analysis
- `server/lease/CODEMANIFEST` documents `Lease()` with only `ID` (property) and `TTL`/`Remaining`/`Keys` (methods); no algorithm text constrains a new read-only `KeyCount()` accessor — purely additive, no existing annotation to reconcile against beyond adding the new method block.
- `server/etcdserver/apply/CODEMANIFEST`'s `ApplierOptions()` block already documents a **selective** subset of the real Go struct's fields (`KV`, `Lessor`, `AuthStore`, `Cluster`, `Backend`, `QuotaBackendBytesCfg` are documented; `Logger`, `RaftStatus`, `SnapshotServer`, `ConsistentIndex`, `TxnModeWriteWithSharedBuffer`, `WarningApplyDuration` are not). `QuotaBackendBytesCfg -> int64` is the direct structural analog for the new field — same "config value used to reject requests" role — so it should be documented the same way for consistency, though the manifest's own established practice shows this is a judgment call, not a hard requirement.
- `CheckTxnAuth`'s annotation (apply/CODEMANIFEST:175-193) already documents the exact same pattern we need — walking a `Txn`'s nested `Put`s and consulting `lessor` — for a different purpose (authorization). No conflict: our new logic is a parallel, independent pre-check, not a modification of `CheckTxnAuth`.
- No CODEMANIFEST anywhere documents `Lessor.Attach` as capable of failing for a key-count reason, and our design deliberately keeps that true — `Attach`'s documented contract ("If the lease does not exist, an error will be returned") is unchanged.

## Affected Usages
No `.usages` files exist for any candidate cell (`goga schema` reports `"usages": []` for all four). None are being added — this change extends an already-documented decorator-chain/pre-check pattern rather than introducing a new consumption idiom.

| Usage | Cell | Classification | Reason |
|---|---|---|---|
| — | — | — | No usages exist for the affected cells |

## Rejected Hypotheses
1. **Enforce the limit inside `Lessor.Attach`.** Rejected: `storeTxnWrite.put()` (mvcc/kvstore_txn.go:259-288) already mutates the backend and in-memory `kvindex` *before* calling `Attach`, with no rollback path, and currently `panic`s on any `Attach` error. Making `Attach` fallible for this reason would either panic the server on a legitimate rejection (violates "must not crash") or require building a rollback mechanism that doesn't exist today (far outside minimal scope).
2. **Check op-by-op independently against live `Lessor` state inside `checkTxn`, no aggregation.** Rejected: two `Put`s to distinct new keys on the same near-full lease within one `Txn` would each individually appear to fit (since neither has been "committed" to the lessor yet when the other is checked), letting a single atomic request silently exceed the configured limit — directly violating the requirement.
3. **Enforce via the gRPC pre-flight layer, mirroring `MaxTxnOps`.** Rejected: confirmed (`api/v3rpc/key.go:205-226`) that `MaxTxnOps` is enforceable at the gRPC layer only because it's a pure function of the request shape (op count), independent of server state. Lease-key-count is server state that must be evaluated deterministically at apply time (identically on every raft replica); checking it pre-raft-proposal would be a TOCTOU race across concurrent client requests and could diverge between replicas.
4. **Mirror the `quotaApplierV3` decorator pattern (check availability, execute anyway, override error after the fact).** Rejected: confirmed (`quota.go:34-40`) that this pattern always executes the wrapped write and only *labels* the error afterward — i.e. it's soft/eventually-consistent by design. That directly violates "must not silently succeed" / "must not apply only part of the request" for our feature.
5. **Add a new method to the `Lessor` interface for the limit check.** Rejected in favor of reusing already-exported `Lookup`/`GetLease` plus one new method on the concrete `*Lease` type only: avoids touching the `Lessor` interface (zero implementers to update beyond the one `Lease.KeyCount()` addition, which `FakeLessor.Lookup`'s bare `&Lease{ID: id}` already supports safely since `len(nil map)` is `0`).
6. **Use `Lease.Keys()` (existing) for counting instead of a new `KeyCount()`.** Rejected: `Keys()` allocates and copies an `[]string` of every attached key on every call (lease.go:106-114) — calling it on every `Put` to a large, near-limit lease would reintroduce O(n) per-request overhead, working against the feature's own purpose (reducing load bursts tied to large leases).

## Confirmed Root Cause
Not a defect investigation — this is a greenfield capability addition. The "root cause" of the design constraint is: **etcd's write-apply path has no rollback**, and a write-`Txn`'s execution phase is contractually infallible today (`txn.go:81-102`, panics otherwise). Every design decision above is anchored to that one confirmed fact — enforcement must complete, for the *entire* atomic request, strictly before the mutating phase begins. Evidence chain: `kvstore_txn.go:259-288` (mutation precedes `Attach`, no rollback) + `txn.go:85-91` (explicit `lg.Panic` comment: "we always expect it to be successful... trying to silently recover... poses serious risks") + `txn.go:54-58`/`put.go:35-44` (existing `checkLease`/`checkTxn` pre-mutation pattern already proves this is achievable and is etcd's own established idiom for this exact class of problem).

## Confidence Level
**HIGH.** Every touch point was located with fresh reads and exact line numbers; all call sites of the two functions whose signatures change (`txn.Put`, `txn.Txn`) are fully enumerated (2 production, 7 test); both structs gaining new fields (`ApplierOptions`; `Lessor`/`Lease` were deliberately *not* changed) use keyed struct literals everywhere they're constructed, confirmed via direct grep of all non-test and test construction sites — no positional-literal risk. The one non-cell package absorbing the actual logic (`server/etcdserver/txn`) has no CODEMANIFEST, removing ambiguity about contract-governed vs. free-form edits.

## Breaking Change Assessment

1. **Will existing function call with same arguments produce different behavior?** NO for `Lessor.Attach`, `TxnWrite.Put`/`WriteView.Put` (mvcc contract, untouched — confirmed no signature or behavior change). YES-but-mechanical for `txn.Put`/`txn.Txn` (non-cell, signature gains a parameter) — every call site is being updated in the same change, not left to silently miscompile or misbehave; this is an internal refactor, not an external-facing break.
2. **Will existing file paths change?** NO.
3. **Will output format change?** NO — same proto response types; only a new possible error value in an already-`error`-typed return position, exactly analogous to how `ErrLeaseNotFound`/`ErrKeyNotFound` already coexist there.
4. **Will return value semantics change?** NO for existing error cases/success semantics. One net-new error value becomes reachable, gated entirely behind a new, explicitly-opt-in-configurable condition.
5. **Will manifest-defined guarantees be altered?** NO — all CODEMANIFEST changes identified are additive (new method on `Lease`, new documented property on `ApplierOptions`); no existing documented guarantee is removed, weakened, or contradicted.
6. **Will existing tests break?** Compile-time: the 7 enumerated test call sites of `txn.Put`/`txn.Txn` need a mechanical argument added (in scope, to be fixed as part of this change). Behaviorally: NO test assertion changes, since existing/updated test call sites pass `0` (unlimited), reproducing today's unbounded behavior exactly.

**One nuance requiring explicit user acknowledgment, not a pipeline STOP:** shipping a nonzero *default* limit (as the task requires — "sensible built-in default") means that if an already-running deployment has a lease that already exceeds the chosen default, that lease's *future* writes will newly start failing where they previously succeeded — existing keys and the lease itself remain fully intact and served (confirmed: restore/`Attach` path is untouched). This is the task's explicit, requested behavior ("Add a configurable maximum... with a sensible built-in default"), not an accidental regression, and is the reason default-value selection (Step 3, Planning) must lean generous. No CODEMANIFEST-documented guarantee is broken by this — it is new behavior for a new feature, not a change to prior documented behavior. **No BREAKING CHANGE DETECTED** under the goga policy definition (cell-contract guarantees, file paths, output formats, and existing-test behavior are all preserved).
