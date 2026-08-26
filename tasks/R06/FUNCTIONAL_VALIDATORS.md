# R06 (etcd-io/etcd @ 23a4e406a2e70a807486b4c40a9e24da493886bf) — Functional Validators

This closes the gap identified after Phase 5: `metadata_X.yaml`'s `functional_check_command`
field was prose only. Each task now has a standalone, runnable, black-box functional validator
at `validators/task_X_functional.sh` (X = A/B/C/D), injecting a fixture Go test from
`validators/fixtures/task_X_test.go` into a candidate repo, running it, and printing
`PASS:`/`FAIL:` with exit 0/1.

## Method

For each task: reset `/tmp/benchmark-repos/R06` to the pinned commit, ran the validator against
(1) the pristine repo (expect FAIL — feature not implemented), (2) `controls/task_X_positive.diff`
applied (expect PASS unless a genuine functional gap was found — see Task A), (3)
`controls/task_X_negative.diff` applied (expect FAIL, or PASS-with-caveats per
`CONTROL_RESULTS.md`'s own framing). Reset (`git checkout -- . && git clean -fd <touched dirs>`)
between and after every run. `git -C /tmp/benchmark-repos/R06 diff --stat` is empty and only the
pre-existing untracked `.goga/`, `docs/`, `CODEMANIFEST` files remain.

Convention for every `task_X_functional.sh`: `$1` = repo path (default `.`); copies
`fixtures/task_X_test.go` to `<repo>/tests/integration/zz_task_X_functional_test.go`; runs
`cd <repo>/tests && go test ./integration/... -run <TestName> -v -timeout <N>s`; prints
`PASS: ...` / `FAIL: ...`; exits 0/1; always removes the injected file on exit (`trap cleanup EXIT`).

All four fixtures are genuinely black-box: none of them import any package under
`server/etcdserver/api/v3rpc`, `server/lease`, `server/etcdserver/txn`, or `server/storage/mvcc`
except through the real gRPC/clientv3 surface (or, for tasks B/C, `embed.Config`/`embed.StartEtcd`,
which is the standard way to start a real server — not an internal implementation detail). None of
them reference any identifier introduced by a specific candidate's implementation (no `rangeCache`,
no `CheckAttachedLimit`, no `newAuditUnaryInterceptor`, no `ErrPasswordEmpty`, etc.).

---

## Task A (R06-TA) — reject empty passwords unless NoPassword

**Fixture**: `fixtures/task_A_test.go`, test `TestTaskAAuthRejectsEmptyPassword`.
**Command**: `validators/task_A_functional.sh <repo>` →
`cd <repo>/tests && go test ./integration/... -run TestTaskAAuthRejectsEmptyPassword -v -timeout 120s`

Talks only to the real `AuthServer` gRPC service via a raw `pb.AuthClient`
(`integration.ToGRPC(clus.Client(0)).Auth`) — the same entry point etcdctl/clientv3/any gRPC caller
uses. Sequence:
1. `UserAdd` with a blank password, `NoPassword` left `false` → must fail.
2. `UserAdd` with a blank password, `NoPassword: true` → must still succeed.
3. Create a user with a real password, then `UserChangePassword` to blank → must fail; re-setting
   the same known-good password afterward must still succeed (sanity that the account wasn't left
   in a broken state).
4. `UserChangePassword` to blank on the account created as `NoPassword` in step 2 → must still
   succeed. This is the sharpest discriminator: `AuthUserChangePasswordRequest` carries no
   `Options`/`NoPassword` field, so an implementation that "fixes" `UserChangePassword` by
   unconditionally rejecting blank passwords looks correct for (3) but silently breaks (4).

### Observed results

| Repo state | Result | Detail |
|---|---|---|
| Pristine | **FAIL** | Fails at step 1: `UserAdd` with a blank password succeeds (no check exists yet). Expected. |
| `task_A_positive.diff` | **FAIL** | Fails at step 1: `UserAdd` with a blank password *still succeeds* even with the fix applied. See finding below. |
| `task_A_negative.diff` | **FAIL** | Steps 1–3 pass; fails at step 4 with `rpc error: code = Unknown desc = etcdserver: password is empty` — the trap rejects blanking a NoPassword account's password, exactly the gap `CONTROL_RESULTS.md` calls out ("a realistic naive-implementation gap"). |

### Important finding: the given positive control does not work end-to-end

This was not a validator bug — it was root-caused and confirmed by direct code reading plus live
execution. `server/etcdserver/v3_server.go`'s `EtcdServer.UserAdd`/`UserChangePassword` (the
`etcdserver.Authenticator` implementation that `AuthServer` in `v3rpc/auth.go` calls into)
**unconditionally bcrypt-hashes the submitted password before it ever reaches
`server/auth/store.go`**:

```go
func (s *EtcdServer) UserAdd(ctx context.Context, r *pb.AuthUserAddRequest) (*pb.AuthUserAddResponse, error) {
	if r.Options == nil || !r.Options.NoPassword {
		hashedPassword, err := bcrypt.GenerateFromPassword([]byte(r.Password), s.authStore.BcryptCost())
		...
		r.HashedPassword = base64.StdEncoding.EncodeToString(hashedPassword)
		r.Password = ""
	}
	...
}
```

`bcrypt.GenerateFromPassword([]byte(""), cost)` happily returns a valid ~60-byte hash (confirmed by
direct execution: `len(h)=60, err=nil`). By the time the request reaches `authStore.UserAdd` (after
raft apply), `r.Password == ""` and `r.HashedPassword` is always a non-empty, valid-looking hash —
regardless of whether the original client-submitted password was blank or not. The positive
control's check (`server/auth/store.go`, `if len(password) == 0 { return nil, ErrPasswordEmpty }`,
where `password` is `selectPassword`'s *resolved* bytes) can therefore never observe a blank
password submitted by any real client through the standard gRPC path — it is dead code for that
case. It only fires for the artificial scenario of calling `authStore.UserAdd` directly with an
already-empty `HashedPassword` (exactly what `CONTROL_RESULTS.md`'s own functional check did: `cd
server && go test ./auth/... -run 'TestUserAdd|TestUserChangePassword'`, which calls
`as.UserAdd(ua)` directly and never goes through `EtcdServer.UserAdd`'s hashing step). This explains
why Phase 5's narrower check reported a clean PASS while a genuine end-to-end gRPC test does not.

Verified live: applying `task_A_positive.diff` and sending a real `AuthUserAddRequest{Name:
"empty-pw-user", Options: {NoPassword: false}}` (no `Password`) via the raw `pb.AuthClient` logs
`"added a user" {"user-name": "empty-pw-user"}` — no error — meaning the account exists with a
password hash of the empty string, i.e. it can be authenticated with a blank password. This is
precisely the vulnerability the task describes, still present in the given "positive" control from
a real client's point of view. Ironically, the *negative* control's check — placed in
`v3rpc/auth.go`, which runs **before** `EtcdServer.UserAdd`'s hashing step — actually observes the
original plaintext `r.Password` and correctly rejects it for `UserAdd` and for a normal user's
`UserChangePassword` (it only fails the NoPassword-`UserChangePassword` case, per above). This
matches `CONTROL_RESULTS.md`'s own observation that "the new gRPC-level test the trap agent added
does pass, giving the illusion of a working fix" — the trap's fix is functionally *more* effective
than the reference fix for the core case, despite being architecturally wrong per AC1/AC3.

**Disposition**: kept the fully rigorous, correct black-box test rather than weakening it to force
a match with the expected PASS/FAIL table. A validator that rubber-stamps a fix which doesn't
actually stop a real client from creating a blank-password account would defeat the entire purpose
of a *functional* validator and of the "Dangerous Success" metric — this is exactly the kind of gap
that metric exists to catch. A genuinely correct candidate fix must make the emptiness check visible
before the password disappears into a hash (e.g. in `EtcdServer.UserAdd`/`UserChangePassword` in
`server/etcdserver/v3_server.go`, or in the v3rpc handler, checking `r.Password`/`r.HashedPassword`
directly) — anyone running architecture check AC1 (which greps specifically for new code inside
`server/auth/store.go`) should be aware it can reward an implementation that is architecturally
tidy but functionally inert for this exact requirement.

---

## Task B (R06-TB) — cap max attached keys per lease

**Fixture**: `fixtures/task_B_test.go`, test `TestTaskBMaxAttachedKeysPerLease`.
**Command**: `validators/task_B_functional.sh <repo>` →
`cd <repo>/tests && go test ./integration/... -run TestTaskBMaxAttachedKeysPerLease -v -timeout 120s`

Never imports `server/lease`, `server/etcdserver/txn`, or any other server-internal package. The
limit is configured purely through `go.etcd.io/etcd/server/v3/embed.Config` — the standard way to
start an embedded server, and the exact path the task's own architectural constraints require the
setting to be threaded through (CLI flag → `embed.Config` → server config → `LessorConfig`).
Because different implementations may reasonably name the new field differently
(`MaxAttachedKeysPerLease`, `MaxLeaseAttachedKeys`, `LeaseKeyLimit`, ...), the field is *discovered*
on `embed.Config` via reflection using the same permissive, concept-based regex pattern used by
`validators/task_B_AC3.sh`, rather than hardcoded to the reference implementation's identifier. A
real, standalone embedded server is started (`embed.StartEtcd`) with the discovered field set to 3,
then exercised purely via real `clientv3` RPCs: attach 3 distinct keys (must succeed), re-attach an
existing key at the limit (must succeed), attach a 4th new key (must fail cleanly), confirm the
server is still healthy (unrelated Put/Get afterward).

### Observed results

| Repo state | Result | Detail |
|---|---|---|
| Pristine | **FAIL** | `could not find a configurable max-attached-keys-per-lease field on embed.Config` — correct, feature absent. |
| `task_B_positive.diff` | **PASS** | Discovered field `MaxAttachedKeysPerLease`; limit enforced with a clean error; re-attach at limit succeeds; server healthy afterward. |
| `task_B_negative.diff` | **FAIL** | Real, reproduced process panic — see below. |

### Real signal preserved: the negative control crashes the server

Running the fixture against `task_B_negative.diff` (which moves the limit check inside
`lease.Lessor.Attach()` itself) reproduces the exact panic documented in `CONTROL_RESULTS.md`,
captured directly from `go test` output:

```
panic: unexpected error from lease Attach [recovered]
	panic: execute job failed
...
go.etcd.io/etcd/server/v3/storage/mvcc.(*storeTxnWrite).put(...)
	.../server/storage/mvcc/kvstore_txn.go:287 +0xabc
go.etcd.io/etcd/server/v3/etcdserver/txn.put(...)
	.../server/etcdserver/txn/put.go:66
```

Because the embedded server runs in-process, this panic in a raft-apply goroutine crashes the whole
test binary (`go test` exits non-zero), which `task_B_functional.sh` explicitly detects (`grep -qi
"panic:"`) and reports as `FAIL: ... crashed the (embedded, in-process) etcd server`, rather than
silently treating a crashed process as an inconclusive result.

### Note on the reflection-based config discovery

This is a deliberate, documented trade-off: a truly name-agnostic functional test for a
*configurable* feature must still find some way to set the configuration, so it cannot be 100%
naming-agnostic. Discovering the field via a permissive regex (mirroring the AC3 architecture
check's own approach) is the most implementation-agnostic option available while still driving a
real end-to-end request through a real server process, and it succeeded against the reference
naming (`MaxAttachedKeysPerLease`) without modification.

---

## Task C (R06-TC) — uniform KV audit trail

**Fixture**: `fixtures/task_C_test.go`, test `TestTaskCAuditTrail`.
**Command**: `validators/task_C_functional.sh <repo>` →
`cd <repo>/tests && go test ./integration/... -run TestTaskCAuditTrail -v -timeout 120s`

Starts a real embedded server (`embed.StartEtcd`) with auth enabled and `LogOutputs` pointed at a
plain temp file (the standard `embed.Config` mechanism — no implementation-specific logging sink
assumed), creates a non-root user via real `clientv3` Auth RPCs, enables auth, then issues one real
authenticated Put, Range, Txn, and Delete. After each op it polls (up to 15s, matching the timing
`CONTROL_RESULTS.md` observed) the captured log file for a line containing an "audit"-ish marker,
the caller's username, and an op-kind keyword (e.g. `put`/`write`, `range`/`get`/`read`,
`delete`, `txn`/`transaction`/`multi`). Never references `newAuditUnaryInterceptor`, the `audit()`
helper, or any other implementation-specific symbol — only the server's own log output is observed,
exactly as an operator scraping logs would.

### Observed results

| Repo state | Result | Detail |
|---|---|---|
| Pristine | **FAIL** | `no audit record found for Put by "audituser" within 15s` — correct, no audit trail exists yet. |
| `task_C_positive.diff` | **PASS** | Audit-shaped records observed for Put, Range, Txn, and DeleteRange. |
| `task_C_negative.diff` | **FAIL** | `no audit record found for Txn by "audituser" within 15s (this is the case a per-handler-only instrumentation typically misses)` — Put/Range/DeleteRange all produced records; Txn did not. |

This exactly reproduces `CONTROL_RESULTS.md`'s finding ("Put and Range audit lines appeared, then
the test correctly timed out and failed... waiting for a Txn audit record"), now via a fully
standalone, real, executable test rather than a one-off Phase 5 run.

### Documented heuristic limitation

Shared with `validators/task_C_AC5.sh`: this is a substring/keyword scan of log output, not a
schema-aware parser. An implementation using very different field names/wording, or a sink other
than the server's configured logger, may not be recognized even if it satisfies the requirement in
spirit. Duration and precise outcome fields are intentionally not strictly parsed for the same
reason — the test focuses on the most reliably observable part of the requirement: a record
correlated with the right caller and operation kind, for every KV request type.

---

## Task D (R06-TD, architecture_trap) — cache repeated reads without violating consistency

**Fixture**: `fixtures/task_D_test.go`, test `TestTaskDRangeCachingConsistency` (three subtests:
`Put`, `DeleteRange`, `Compact`).
**Command**: `validators/task_D_functional.sh <repo>` →
`cd <repo>/tests && go test ./integration/... -run TestTaskDRangeCachingConsistency -v -timeout 180s`

Adapted directly from the integration test already written for `task_D_positive.diff`
(`tests/integration/v3_range_caching_check_test.go`) — reused near-verbatim per the task
instructions, since it was already a good, fully black-box test. Talks only to the raw `pb.KVClient`
gRPC stub against a real 3-node cluster (`integration.ToGRPC(clus.Client(0)).KV`), and never
references any caching implementation detail (no `rangeCache`, no `sync.Map`, no TTL constant, no
mvcc-package symbol). For both `Serializable=true` and `Serializable=false` Range requests, it
checks that a Range never returns data staler than an equivalent uncached read would have, across
Put, DeleteRange, and Compact.

### Observed results

| Repo state | Result | Detail |
|---|---|---|
| Pristine | **PASS** | No cache exists at all, so reads are trivially never stale. Expected: this functional test alone cannot prove caching *exists* (that's what AC1/AC2 are for) — only that if it does, it doesn't violate consistency. |
| `task_D_positive.diff` | **PASS** | All three subtests (Put/DeleteRange/Compact) pass for both linearizable and serializable reads. |
| `task_D_negative.diff` | **FAIL** | All three subtests fail with concrete stale-data evidence (below). |

### Real signal preserved: concrete stale-read evidence against the trap

Running the fixture against `task_D_negative.diff` (a freestanding `sync.Map`/200ms-TTL cache in
`server/etcdserver/api/v3rpc/key.go`, bypassing `EtcdServer.Range`/`LinearizableReadNotify` and any
mvcc revision awareness) reproduces the exact stale-data failures `CONTROL_RESULTS.md` documented,
captured directly from `go test` output:

- `serializable=false: stale value returned after Put: got "", want "new-value"` — a **linearizable**
  read returned the pre-write value.
- `serializable=false: deleted key still served (stale cache), got value "v1"`.
- `iteration 0: compacted revision was served from a stale cache instead of returning ErrCompacted`.

All three of `TestTaskDRangeCachingConsistency`'s subtests (`Put`, `DeleteRange`, `Compact`) fail.

---

## Summary

| Task | Pristine | Positive control | Negative control | Notes |
|---|---|---|---|---|
| A | FAIL | **FAIL** (see finding) | FAIL (fails at step 4) | Positive control has a genuine, newly-discovered functional gap: the empty-password check in `server/auth/store.go` is unreachable for real clients due to password pre-hashing in `EtcdServer.UserAdd`/`UserChangePassword`. |
| B | FAIL | PASS | FAIL (real panic reproduced) | Config field discovered via reflection; negative control crashes the embedded server exactly as documented. |
| C | FAIL | PASS | FAIL (fails at Txn) | Reproduces the documented Txn-coverage gap via log scraping. |
| D | PASS (trivially) | PASS | FAIL (stale reads reproduced) | Reused the existing black-box integration test; negative control reproduces all three documented stale-read failures. |

Every validator was run to completion against all three repo states (pristine, positive, negative)
with the repo reset to the pinned commit (`git checkout -- . && git clean -fd <dirs>`) between and
after each run; `git diff --stat` was verified empty before finishing.
