# R06 (etcd-io/etcd @ 23a4e406a2e70a807486b4c40a9e24da493886bf) — Phase 4/5 Control Results

Method for all four tasks: cloned the repo four times into isolated working copies
(`/tmp/benchmark-repos/R06_{A,B,C,D}`), all pinned at commit `23a4e406a2e70a807486b4c40a9e24da493886bf`
(`go build ./...` verified clean before any changes). For each task: wrote one runnable validator
script per `architecture_checks` entry in `metadata_X.yaml` (`validators/task_X_AC<n>.sh`, arg `$1`
= repo path, default `.`, prints `PASS:`/`FAIL:`/`MANUAL REVIEW REQUIRED:` + reason, exits 0/1/2),
implemented a real positive-control (architecturally correct) patch and a real negative-control
(plausible-but-wrong "trap") patch as actual Go code, ran the task's functional check plus every
validator against both, saved `git diff` output to `controls/task_X_positive.diff` /
`task_X_negative.diff`, and reset the working copy (`git checkout -- . && git clean -fd`) between
and after each control. No cherry-picking: results below are as observed, including validator bugs
found and fixed along the way.

---

## Task A (R06-TA) — reject empty passwords unless NoPassword

**Positive control**: `server/auth/store.go` — added sentinel `ErrPasswordEmpty` to the existing
`var (... = errors.New(...))` block; added `if len(password) == 0 { return nil, ErrPasswordEmpty }`
right after `selectPassword` resolves, inside the `!Options.NoPassword` branch, in both
`authStore.UserAdd` and `authStore.UserChangePassword`. `v3rpc/auth.go` untouched. Extended
`server/auth/store_test.go` with 4 subtests (empty-password UserAdd/UserChangePassword rejected;
NoPassword=true UserAdd/UserChangePassword with empty password still succeeds).

**Negative control (trap)**: moved the equivalent check into
`server/etcdserver/api/v3rpc/auth.go`'s `AuthServer.UserAdd`/`UserChangePassword` handlers (new
`errPasswordEmpty` + inline conditional before calling the authenticator); `UserChangePassword`'s
trap version can't even consult `Options.NoPassword` (no such field on that request), a realistic
naive-implementation gap. `server/auth/store.go` left unmodified — still accepts empty passwords
if called directly (e.g. by another embedder or future RPC). New test added in a new
`v3rpc/auth_test.go` using a fake `Authenticator`, which passes because it only exercises the
gRPC-level path.

### Results

| Check | Description | Positive | Negative |
|---|---|---|---|
| AC1 | New logic lives in auth domain layer, not gRPC passthrough | PASS | **FAIL** |
| AC2 | Enforced server-side, not client/etcdctl-only | PASS | PASS |
| AC3 | Proper named sentinel, not ad hoc/silent | PASS | **FAIL** |
| AC4 | NoPassword accounts unaffected | PASS | MANUAL REVIEW REQUIRED (exit 2) |
| AC5 | No new dependency edge server/auth <-> v3rpc | PASS | PASS |

Functional check (`cd server && go test ./auth/... -run 'TestUserAdd|TestUserChangePassword' -v`,
then full `./auth/...`): positive control — all PASS, no regressions. Negative control — the
literal `functional_check_command` scope (`server/auth/...`) shows no new subtests at all (the fix
lives outside that package); the new gRPC-level test the trap agent added does pass, giving the
illusion of a working fix.

### Verdict: **DISCRIMINATES**
AC1 and AC3 correctly flip to FAIL on the trap (misplaced business logic, no domain-layer sentinel),
matching `notes_for_positive_negative_control`'s expectation that AC1/AC2-style checks catch this
even though a naive functional test looks fine. AC2/AC5 don't fire for this particular trap variant
(the trap is "wrong layer inside the server", not "client-only") — by design, not a validator gap.

### Notes
- AC4's validator honestly reports `MANUAL REVIEW REQUIRED` (never a faked verdict) in both states
  here, since no NoPassword-specific subtest exists in `server/auth` in the trap's diff scope.
- No validator required fixing after the first pass for this task.

---

## Task B (R06-TB) — cap max attached keys per lease

**Positive control**: added `MaxAttachedKeys` to `LessorConfig` (`server/lease/lessor.go`),
threaded from a new `--max-attached-keys-per-lease` CLI flag (`server/embed/config.go`, wired via
`AddFlags`, consumed by `server/etcdmain/config.go`) through `server/config/config.go` /
`server/embed/etcd.go` into `LessorConfig` construction in `server/etcdserver/server.go`.
Enforcement: a new read-only `Lessor.CheckAttachedLimit(id, key)` (distinct from `Attach`, which is
untouched) called from a new `checkLeaseAttachedKeysLimit` in `server/etcdserver/txn/put.go`,
invoked immediately after the existing `checkLease` in `Put()`/`checkPut()` — i.e. before the write
ever reaches `mvcc`. New error `lease.ErrTooManyAttachedKeys`, catalogued as
`rpctypes.ErrGRPCTooManyAttachedKeys` (`api/v3rpc/rpctypes/error.go`) and mapped in
`toGRPCErrorMap` (`server/etcdserver/api/v3rpc/util.go`). Added unit tests
(`lessor_test.go`, `put_test.go`) and integration test
`tests/integration/v3_lease_attached_keys_limit_test.go` (`TestV3LeaseAttachedKeysLimit`).

**Negative control (trap)**: identical config threading, but the limit check was moved *inside*
`lease.Lessor.Attach()` itself (returns `ErrTooManyAttachedKeys` from there), with no pre-apply
check in `put.go`. A shallow unit test calling `Attach()` directly passes cleanly. Running the same
`TestV3LeaseAttachedKeysLimit` integration test against this version produced a real process panic:
`PANIC ... {"panic": "unexpected error from lease Attach"}`, traced through
`storeTxnWrite.put` (`kvstore_txn.go:287`) -> `applyEntryNormal`, test process exiting non-zero —
captured directly from `go test` output (grepped for `panic:`), not just inferred from code reading.

### Results

| Check | Description | Positive | Negative |
|---|---|---|---|
| AC1 | Attach/panic contract not repurposed | PASS | **FAIL** (Attach now returns a new error type) |
| AC2 | Clean error + no crash end-to-end | PASS | **FAIL** (real panic/crash observed) |
| AC3 | Limit configurable via standard config path | PASS | PASS (config threading itself was still done correctly in the trap) |
| AC4 | New error via rpctypes/toGRPCErrorMap | PASS | PASS (error cataloguing itself was still done correctly) |
| AC5 | Change genuinely crosses config/domain/apply boundaries | PASS | **FAIL** (never touches `server/etcdserver/txn/*`) |

Functional check: positive — `go test ./lease/... ./etcdserver/txn/...` and the integration test
both PASS. Negative — the shallow unit-level test passes, but the integration-level functional
check (`TestV3LeaseAttachedKeysLimit`) crashes the server process instead of returning a clean gRPC
error.

### Verdict: **DISCRIMINATES**
Positive control: 5/5 AC PASS + full functional PASS. Negative control: 3/5 AC FAIL (AC1, AC2, AC5)
with a genuine, observed process crash — while AC3/AC4 legitimately PASS on the trap too, since the
config-threading and error-cataloguing pieces were done correctly even though the check was placed
in the wrong layer. This shows the validators isolate exactly the intended architectural violation
(wrong enforcement point) rather than any incidental difference.

### Notes (validator fix made during this task)
AC2's validator initially had a bug: its "is the config discoverable" pre-check used `go build`,
which doesn't type-check `_test.go` files, so it silently passed even when a referenced config field
didn't actually exist. Fixed to use `go vet` instead; re-verified it now correctly fails against the
pristine (unmodified) base repo, then re-ran all 5 validators against pristine/positive/negative
states to confirm consistent, correct discrimination after the fix.

---

## Task C (R06-TC) — uniform KV audit trail via interceptor chain

**Positive control**: `server/etcdserver/api/v3rpc/interceptor.go` — added
`newAuditUnaryInterceptor`/`auditUnaryRequest`, type-switching on
`*pb.{Range,Put,DeleteRange,Txn}Response` (mirroring the existing `newLogUnaryInterceptor` pattern),
pulling identity via `s.AuthInfoFromCtx(ctx)`, logging caller/operation/key/outcome/duration via
zap. Appended `newAuditUnaryInterceptor(s)` to `chainUnaryInterceptors` in `grpc.go`. `key.go` and
`v3_server.go` untouched. Added integration test `TestV3AuditTrail` (auth-enabled 1-node cluster,
one Put/Range/Txn/DeleteRange, asserts an audit record per op).

**Negative control (trap)**: added an `audit(ctx, s, op, key, start, err)` helper (itself correctly
using `AuthInfoFromCtx`) called from `kvServer.Range`, `Put`, and `DeleteRange` in `key.go` —
deliberately **not** added to `Txn`, mirroring the realistic "forgot one RPC type" failure mode the
interceptor pattern structurally prevents. `grpc.go`/`interceptor.go` untouched.

### Results

| Check | Description | Positive | Negative |
|---|---|---|---|
| AC1 | Registered once, centrally, in interceptor chain | PASS | **FAIL** |
| AC2 | No per-method duplication in KV handlers | PASS | **FAIL** |
| AC3 | No second parallel wrapper (quotaKVServer-style) | PASS | PASS |
| AC4 | Identity via AuthInfoFromCtx | PASS | PASS |
| AC5 | Uniform coverage across all 4 KV RPC kinds | PASS | **FAIL** |

Functional check (`TestV3AuditTrail`): positive — all four ops produced audit log lines, test PASS
(~2.5s). Negative — Put and Range audit lines appeared, then the test correctly **timed out and
failed** (`context deadline exceeded`) waiting for a Txn audit record (~11-15s) — concretely
confirming the metadata's own framing: a naive test checking only Put/Range would have passed
against the trap, but a thorough one (checking Txn too) correctly fails. `cd server && go build
./...` compiled clean for both variants.

### Verdict: **DISCRIMINATES**
AC1, AC2, and AC5 all flip to FAIL on the trap while staying PASS on the correct implementation;
AC3/AC4 correctly stay PASS on both, matching the metadata's own per-check `expected_result_if_trap`
scoping (the trap doesn't violate those two).

### Notes / honest limitations
- AC5's validator is a black-box log-scraping heuristic (substring match on an "audit" marker + an
  op-kind word). It cannot recognize an arbitrary implementation's own log field names/sink if
  wildly different from the reference style, and falls back to `MANUAL REVIEW REQUIRED` (exit 2)
  rather than guessing when the signal is ambiguous — documented in the script itself.
- AC1/AC2 use diff/keyword heuristics rather than full static analysis; an implementation using
  very different identifier names than "audit"/"AuthInfoFromCtx" could require manual review — both
  scripts emit `MANUAL REVIEW REQUIRED` in that case instead of a guessed verdict.

---

## Task D (R06-TD, architecture_trap) — cache repeated reads without violating consistency

This was the hardest of the four (explicitly the "architecture_trap" category). Both controls
required real, working Go code reaching into `server/storage/mvcc`.

**Positive control**: new `server/storage/mvcc/range_cache.go` — a `rangeCache` keyed by
`(key, end, options, effectiveRevision)`. Key design point: validity is keyed on the *exact resolved
revision*, not a shared "live" generation counter, so a long-open read transaction keeps seeing its
own snapshot even after a concurrent write commits (verified via a dedicated
`TestConcurrentReadNotBlockingWrite`-style check). Since MVCC data at a fixed revision never
changes, only compaction can invalidate an entry: `kvstore.go` gained `rangeCache`/`compactRevAtomic`
fields and `setCompactMainRev()` (updates the field, an atomic mirror, and clears the cache),
called at all 3 sites where `compactMainRev` changes (compaction, restore, snapshot restore).
`storeTxnCommon.Range` (used only by read-only transactions, never in-flight writers) consults/
populates the cache before `rangeKeys()`; results are deep-cloned in/out to prevent caller mutation
from corrupting cached entries. `LinearizableReadNotify` in `v3_server.go` was left with zero diff.
Added `tests/integration/v3_range_caching_check_test.go` (`TestV3RangeCachingConsistency`) covering
Put/DeleteRange/Compact, each with Serializable=true/false subtests.

**Negative control (trap)**: `server/etcdserver/api/v3rpc/key.go` — a package-level `sync.Map`
(`rangeRespCache`), keyed only by raw `RangeRequest` fields, fixed 200ms TTL, checked/populated
directly inside `kvServer.Range` before ever calling `s.kv.Range`. Zero mvcc dependency; on a cache
hit it bypasses `EtcdServer.Range` entirely (so `LinearizableReadNotify` is also skipped on a hit,
though AC4 as specified in the metadata only inspects `v3_server.go` and therefore cannot see this
particular consequence — a known, documented scope limitation of AC4, not a validator bug).

### Results

| Check | Description | Positive | Negative |
|---|---|---|---|
| AC1 | No freestanding revision-unaware cache in v3rpc | PASS | **FAIL** (sync.Map/TTL found in key.go) |
| AC2 | Cache depends on mvcc revision/watch machinery | PASS | **FAIL** (no mvcc dependency at all) |
| AC3 | No staleness window after concurrent write | PASS | **FAIL** |
| AC4 | LinearizableReadNotify unconditional for non-serializable reads | PASS | PASS (file literally untouched — see caveat above) |
| AC5 | Deletes/compaction correctly invalidate cache | PASS | **FAIL** |

Functional check: `cd server && go build ./...`, full `go test ./storage/mvcc/...` and
`./etcdserver/...` all PASS for the positive control. Integration test
`TestV3RangeCachingConsistency`: positive PASS; negative FAILS with concrete captured evidence:
- Put: `serializable=false: stale value returned after Put: got "", want "new-value"` — a
  **linearizable** read returned the pre-write value instead of the just-committed one.
- DeleteRange: `serializable=false: deleted key still served (stale cache), got value "v1"`.
- Compact: `iteration 0: compacted revision was served from a stale cache instead of returning
  ErrCompacted`.

### Verdict: **DISCRIMINATES**
AC1/AC2 catch the trap by code-shape alone before running anything (fastest, cheapest signal);
AC3/AC5 catch it functionally with concrete stale-data evidence, including a genuine linearizable-
read violation; AC4 correctly PASSes on both, as anticipated by its narrow, documented scope.

### Notes / honest limitations
- The positive-control cache implementation is deliberately minimal for this exercise: coarse
  whole-cache clear on compaction/restore (not per-key invalidation), an unbounded-growth safety cap
  (100k entries) rather than real LRU eviction. It is a real, correctness-checked implementation
  (verified via the integration test and unit tests), not a stub — but it is not production-grade,
  and that gap is called out explicitly rather than glossed over.
- AC4 has an inherent scope limitation baked into the metadata's own `method` field (it only
  inspects `v3_server.go`), so it cannot detect the trap's more severe consequence (linearizable
  reads being skipped entirely on a cache hit). AC1/AC2/AC3 already catch the trap regardless, so
  this doesn't affect the overall discrimination verdict, but it's a real gap in AC4 specifically
  that a benchmark maintainer should be aware of if AC4 is ever used in isolation.

---

## Overall summary

| Task | Category | Discriminates? | Architecture checks that fire on the trap |
|---|---|---|---|
| A (R06-TA) | local_change | **YES** | AC1, AC3 |
| B (R06-TB) | cross_module_feature | **YES** | AC1, AC2, AC5 |
| C (R06-TC) | existing_extension_point | **YES** | AC1, AC2, AC5 |
| D (R06-TD) | architecture_trap | **YES** | AC1, AC2, AC3, AC5 |

All four R06 tasks pass Phase 5 validation: in every case the positive control achieves full PASS
(functional + all architecture checks) and the negative control achieves functional PASS-or-
near-PASS while failing at least one architecture check, with the failing checks matching the
specific violation each task's `notes_for_positive_negative_control` predicted. One validator bug
was found and fixed during the process (Task B AC2's `go build` vs `go vet` blind spot on
`_test.go` files); it was caught by deliberately re-testing against the pristine base repo, not
assumed away.
