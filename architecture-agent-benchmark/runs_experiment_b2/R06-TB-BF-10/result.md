# R06-TB-BF-10

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.6
Dangerous success: False
Goga engagement signal: True
Cost: $7.2901115999999995
Duration: 1360694ms, turns: 128

## Agent's own summary

I've hit the budget limit for this session, so I'll stop here and summarize.

## Summary

Implemented a configurable per-lease key limit in etcd, using the goga toolchain (schema/lint/cell/cookbook/lang-disp skills + `goga-change` scope-resolver) to ground the design in the documented architecture before coding.

**Design:** Enforcement happens as a pre-mutation check in `server/etcdserver/txn/{put,txn}.go` (`checkLease`/`checkPut`/`checkTxn`) — the same place that already validates a lease exists before any write touches storage. This runs before `Lessor.Attach` is ever reached, so the existing `panic("unexpected error from lease Attach")` in `mvcc/kvstore_txn.go` is never triggered, and `Lessor.Attach` itself is untouched (so lease recovery/restore on restart, which also calls `Attach`, is unaffected — pre-existing leases over the new limit keep working). A `Txn` with multiple new puts to the same lease is tracked via a per-request "pending new keys" map threaded through `checkTxn`, so the cumulative effect is checked correctly and the whole txn is rejected before any mutation if it would exceed the limit.

**Changes:**
- `server/lease`: new `Lessor.MaxLeaseKeys()`, `Lease.TotalItemCnt()`, `lease.ErrTooManyLeaseKeys`, `LessorConfig.MaxLeaseKeys` (default 10,000 via `defaultMaxLeaseKeys`)
- `server/etcdserver/txn/put.go`, `txn.go`: the actual limit check (re-attach of an existing key always allowed; leases under the limit unaffected)
- `api/v3rpc/rpctypes`: new `ErrGRPCTooManyLeaseKeys` (ResourceExhausted) / `ErrTooManyLeaseKeys`, wired into `server/etcdserver/api/v3rpc/util.go`'s error map
- `server/config`, `server/embed/{config,etcd}.go`: new `--max-lease-keys` flag → `ServerConfig.MaxLeaseKeys` → `lease.LessorConfig` (wired in `server/etcdserver/server.go`)
- `etcdutl/etcdutl/common.go`: `SimpleLessor.MaxLeaseKeys()` stub for the test double
- CODEMANIFEST for `server/lease` updated with the new contract surface and the "never enforced in Attach" invariant
- New test file `server/etcdserver/txn/lease_key_limit_test.go` covering: new-key-under-limit, new-key-at-limit rejected, re-attach-at-limit allowed, server stays healthy after rejection, and Txn cumulative/atomicity cases

**Verified:** `go build ./...` clean across the `server`, `api`, and `etcdutl` modules; `go vet`/`gofmt` clean; the full pre-existing suite (`lease`, `etcdserver/txn`, `etcdserver/apply`, `etcdserver/api/v3rpc`) passed before I added the new tests. I ran out of budget before getting a final confirmed run of the new test file itself back from the test runner (the sandbox kept auto-backgrounding `go test` and the output never populated) — that's the one thing I'd re-verify first if you pick this back up: `cd server && go test ./etcdserver/txn/... -run 'LeaseKeyLimit' -v`.
