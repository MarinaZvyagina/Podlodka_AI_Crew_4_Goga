# R06 recon notes — etcd-io/etcd @ 23a4e406a2e70a807486b4c40a9e24da493886bf

Method: no full clone (disk-constrained machine; `df -h /` showed 30Gi free, still avoided a
full clone per instructions). All recon done via `gh api repos/etcd-io/etcd/git/trees/<sha>?recursive=1`
for the file tree, `curl raw.githubusercontent.com/.../<sha>/<path>` for file contents, and
`gh api search/code -f q='<term> repo:etcd-io/etcd'` for cross-file symbol location. No local
clone was created; nothing to clean up.

## Module layout (confirmed via go.work / go.mod files)

```
go.work use (
  .                          -> go.etcd.io/etcd/v3 (root)
  ./api                      -> go.etcd.io/etcd/api/v3
  ./cache                    -> client-side "etcd cache" library (experimental, separate module)
  ./client/pkg
  ./client/v3
  ./etcdctl
  ./etcdutl
  ./pkg
  ./server                   -> go.etcd.io/etcd/server/v3
  ./tests
  ...
)
```

`server/embed` and `server/etcdmain` (CLI/config layer) live *inside* the `server` module in this
commit, not as top-level dirs — noted because the task prompt for the original brief assumed a
possibly different layout; verified the actual paths before writing metadata.

`cache/` is a real, separate go.mod module: a client-side watch-driven mirror/cache library
(`cache/README.md`: "Experimental etcd client cache library... relies on RequestProgress RPCs").
It is unrelated to server-side read caching and was deliberately *not* used as the Task D
extension point — it's client-side, a different concern (mirrors keys for a client app), and
naming/hinting at it would have been a leak anyway.

## Task A evidence — `server/auth/store.go`

- `authStore.UserAdd` (line ~423) and `authStore.UserChangePassword` (line ~497) both call
  `as.selectPassword(r.Password, r.HashedPassword)`.
- `selectPassword` (line ~414): if `password != "" && hashedPassword == ""` it bcrypt-hashes the
  password; **otherwise** it does `base64.StdEncoding.DecodeString(hashedPassword)`. If both
  `password` and `hashedPassword` are empty strings, this branch returns `[]byte{}, nil` — no
  error. Confirmed: **etcd currently allows creating/updating a password-required user with a
  blank password**, with no existing validation catching it.
- `server/etcdserver/api/v3rpc/auth.go`: `AuthServer.UserAdd` / `UserChangePassword` (lines
  115-169) are pure passthroughs — `resp, err := as.authenticator.UserAdd(ctx, r); if err != nil
  { return nil, togRPCError(err) }; return resp, nil` — confirming server/auth is the sole
  business-logic owner and v3rpc is a translation-only layer.
- Existing sentinel-error style confirmed (`ErrUserEmpty`, `ErrUserAlreadyExist`,
  `ErrNoPasswordUser`, etc., declared in a single `var (...)` block near the top of store.go).

This is a genuinely bounded, single-component (auth domain) local change.

## Task B evidence — lease attach-limit / panic contract

- `server/storage/mvcc/kvstore_txn.go`, `storeTxnWrite.put()` (~line 280-289):
  ```go
  if leaseID != lease.NoLease {
      if tw.s.le == nil {
          panic("no lessor to attach lease")
      }
      err = tw.s.le.Attach(leaseID, []lease.LeaseItem{{Key: string(key)}})
      if err != nil {
          panic("unexpected error from lease Attach")
      }
  }
  ```
  This runs during raft apply, i.e. **after consensus** — any error here is fatal by design.
- `server/lease/lessor.go` `Attach()` (line 555) currently only ever returns `ErrLeaseNotFound`
  (line 561). Confirmed via `gh api search/code -f q='Attach lessor repo:etcd-io/etcd'`.
- `server/etcdserver/txn/put.go` (new-ish file, header says "Copyright 2025") has `checkLease()`
  (~line 78) which validates lease existence via `lessor.Lookup(leaseID)` *before* `Put()` calls
  `txnWrite.Put()` (which internally calls Attach). This is the existing precedent for "validate
  before the storage layer touches it" — the exact pattern a correct limit-check implementation
  should follow.
- `server/lease/lessor.go` `LessorConfig` struct (~line 198): `MinLeaseTTL`, `CheckpointInterval`,
  `ExpiredLeasesRetryInterval`, `CheckpointPersist` — confirms the established config-threading
  pattern a new `MaxAttachedKeys`-style field would follow.
- `server/etcdmain/config.go` + `server/embed/config.go` confirmed to exist as the CLI-flag /
  embed-config layer (tree listing), consistent with how MinLeaseTTL and similar settings reach
  `LessorConfig`.
- `api/v3rpc/rpctypes/error.go`: confirmed catalogue pattern — `ErrGRPCLeaseNotFound`,
  `ErrGRPCLeaseExist`, `ErrGRPCLeaseTTLTooLarge` (lines 36-38), each also present in
  `server/etcdserver/api/v3rpc/util.go`'s `toGRPCErrorMap` (lines ~34-60, e.g. `mvcc.ErrCompacted:
  rpctypes.ErrGRPCCompacted`). This is the real, single translation point between internal
  domain errors and client-visible gRPC errors — a new error must follow it.

This task genuinely crosses ≥3 boundaries: config/CLI (server/etcdmain, server/embed) → lease
domain (server/lease) → request-validation/apply layer (server/etcdserver/txn) → error catalogue
(api/v3rpc/rpctypes + server/etcdserver/api/v3rpc). The panic contract gives a sharp, checkable
"wrong layer" failure mode if an agent naively puts the check inside `Attach()`.

## Task C evidence — gRPC interceptor chain (verified extension point)

- `server/etcdserver/api/v3rpc/grpc.go`, `Server()` function:
  ```go
  chainUnaryInterceptors := []grpc.UnaryServerInterceptor{
      newLogUnaryInterceptor(s),
      serverMetrics.UnaryServerInterceptor(),
      newUnaryInterceptor(s),
  }
  ...
  opts = append(opts, grpc.ChainUnaryInterceptor(chainUnaryInterceptors...))
  ```
  registered once for the whole `grpc.Server` covering KV/Watch/Lease/Cluster/Auth/Maintenance.
- `server/etcdserver/api/v3rpc/interceptor.go`, `newLogUnaryInterceptor` /
  `logUnaryRequestStats` (lines ~78-180): already type-switches on
  `*pb.RangeResponse / *pb.PutResponse / *pb.DeleteRangeResponse / *pb.TxnResponse` to log
  request/response size, count, and content uniformly, in one function, without any per-handler
  code in key.go. This is a real, already-exercised precedent for "cross-cutting concern over all
  KV RPCs, implemented once."
- `server/etcdserver/api/v3rpc/quota.go`: `quotaKVServer` — the *other* real pattern in this repo
  (decorator embedding `pb.KVServer`), used deliberately in the metadata as the "plausible parallel
  mechanism a naive agent might reach for instead" (negative-control sketch), since it's visible in
  the same package and does something superficially similar (wraps Put/Txn to add a cross-cutting
  check). Registered via `pb.RegisterKVServer(grpcServer, NewQuotaKVServer(s))` in grpc.go.
- `server/etcdserver/api/v3rpc/auth.go`: `AuthGetter.AuthInfoFromCtx` / `AuthAdmin.isPermitted`
  confirm an existing, reusable way to obtain the caller's identity from a request context,
  implemented by `EtcdServer` (`server/etcdserver/server.go`) and already used elsewhere in v3rpc.

Verified via `gh api search/code -f q='AuthInfoFromCtx repo:etcd-io/etcd'` that this accessor is
used in `server/auth/store.go`, `server/etcdserver/api/v3rpc/auth.go`, `server/etcdserver/api/v3rpc/watch.go`,
`server/etcdserver/server.go`, `server/etcdserver/v3_server.go` — a well-established cross-cutting
accessor, not a one-off.

**Confirmed: task_C.md does not mention "interceptor," "middleware," "chain," "decorator,"
"grpc.go," "interceptor.go," or any Go identifier.** It only describes the desired externally
observable behavior (uniform audit trail for every KV RPC, without per-handler hand-added logging).

## Task D evidence — read path / MVCC revision (architecture trap)

- `server/etcdserver/api/v3rpc/key.go`: `kvServer.Range` calls `s.kv.Range(ctx, r)` where `kv` is
  `etcdserver.RaftKV` (implemented by `*etcdserver.EtcdServer`).
- `server/etcdserver/v3_server.go`, `EtcdServer.Range` (~line 122 onward): for `!r.Serializable`,
  calls `s.read.LinearizableReadNotify(ctx)` before reading — this is etcd's actual linearizable-read
  mechanism, confirmed present in the code (not assumed).
- `server/storage/mvcc/kv.go`: `ReadView.Range(...) (r *RangeResult, err error)` and `RangeResult{
  KVs, Rev, Count }` — every read already carries back the exact revision it was served at.
  `KV` interface also exposes `Rev()`. This is the natural correctness signal a revision-aware
  cache would use.
- `server/storage/mvcc/kvstore_txn.go`: writes (`Put`, `DeleteRange`) bump revision as part of the
  same write path that also does lease Attach/Detach (see Task B evidence) — confirms writes and
  reads are on genuinely separate code paths with no default coupling to anything in
  `server/etcdserver/api/v3rpc`.
- `server/storage/mvcc/watchable_store.go` exists and implements the `Watchable`/`WatchStream`
  interfaces declared in `kv.go` — the existing change-notification mechanism a correct
  cache-invalidation strategy could hook into, instead of a blind TTL.
- Ruled out `server/auth/range_perm_cache.go` as a distractor: it's a permission interval-tree
  cache for authorization checks (`getMergedPerms`, invalidated via `refreshRangePermCache` on
  auth-store mutations) — a different concern (authz, not KV read caching) and not referenced in
  any task prompt.

This matches Research.md section 19's own canonical example ("add caching for repeated reads";
trap = cache at the controller/API layer, bypassing storage's consistency guarantees) and is
grounded in real etcd code rather than invented.

## Leak check (Research.md section 22)

Re-read all four `task_*.md` prompts against the "PaymentRepository vs. cache must invalidate
after data changes" good/bad example:

- No file paths, package names, Go type/function/interface names, or etcd-internal terms
  (`Backend`, `Lessor`, `AuthStore`, `TokenProvider`, `interceptor`, `quotaKVServer`, `MVCC`,
  `revision`, `watchable_store`, `mvcc`, `checkLease`, `LessorConfig`, `AuthInfoFromCtx`) appear in
  any of task_A.md / task_B.md / task_C.md / task_D.md.
- All four prompts are phrased as external behavioral/business requirements ("reject blank
  passwords," "cap keys per lease," "audit trail for every KV request," "cache repeated reads
  without staleness"), matching the "good" style example in Research.md.
- Task C in particular was re-checked line by line to ensure it describes only the *externally
  observable requirement* (uniform coverage, no per-handler hand-added logging) and never says
  "interceptor," "middleware," or names any file — the closest it gets is "without relying on
  someone remembering to add logging by hand every time a new request type is added," which
  describes a property, not a mechanism name.

## Why each task is realistic / plausible as a real etcd engineering ticket

- Task A mirrors real password-policy tickets seen in auth systems generally; etcd already has a
  `NoPassword` account option (used by e.g. `etcdctl user add --no-password`), so "don't allow an
  empty password on a password account" is a natural, small follow-up.
- Task B mirrors a real, previously-discussed etcd operational pain point (very large numbers of
  keys under one lease causing slow/expensive revocation) — etcd already caps lease TTL
  (`MaxLeaseTTL`) and enforces a `maxTxnOps` per-transaction cap (`server/etcdserver/api/v3rpc/key.go`
  `checkTxnRequest`), so a max-keys-per-lease cap is a very natural sibling feature, not an
  invented one.
- Task C (audit logging) is a standard compliance ask for any multi-tenant key-value store with
  auth, and etcd already partially does per-request stats logging (interceptor.go), making "make
  this a full audit trail" a natural extension.
- Task D (caching repeated reads) is Research.md's own canonical trap pattern, verified concretely
  against etcd's actual linearizable-read and MVCC-revision mechanisms rather than assumed.
