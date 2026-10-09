# R06-TA-BF-01

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.4
Dangerous success: False
Goga engagement signal: False
Cost: $2.2651962
Duration: 418491ms, turns: 50

## Agent's own summary

# Change Plan

## Task Classification
**Bugfix** (security-hardening): close a silent-acceptance gap for blank passwords in user creation and password change, without altering any other documented behavior.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `server/etcdserver` | `server/etcdserver/v3_server.go` | `EtcdServer.UserAdd`: reject blank `r.Password` before bcrypt-hashing, when account isn't passwordless |
| `server/auth` | `server/auth/store.go` | New `ErrPasswordEmpty` var; `AuthStore.UserAdd` and `AuthStore.UserChangePassword` reject a blank resulting password when account isn't passwordless |
| `server/etcdserver/api/v3rpc` | `server/etcdserver/api/v3rpc/util.go` | Wire `auth.ErrPasswordEmpty` into `toGRPCErrorMap` |
| *(non-cell, mechanical dependency)* | `api/v3rpc/rpctypes/error.go` | Add `ErrGRPCPasswordEmpty` status, registry entry, client-side `Error()`-wrapped var — follows the existing `ErrUserEmpty` pattern exactly |

## Root Cause Analysis
Two independent silent-acceptance gaps, confirmed by tracing both RPCs end-to-end:
1. `EtcdServer.UserAdd` (v3_server.go) unconditionally bcrypt-hashes `r.Password` — including `""` — before the request reaches `server/auth`, so a check placed only in `server/auth/store.go`'s `UserAdd` would never observe a blank value for real client traffic (bcrypt("") is a valid, non-empty ~60-byte hash indistinguishable from any other).
2. `AuthStore.UserChangePassword` (store.go) calls `selectPassword(r.Password, r.HashedPassword)`, and `base64.StdEncoding.DecodeString("")` returns `([]byte{}, nil)` — a successful decode of nothing — so a blank password change is persisted with no error today.

## Trace Summary
- `UserAdd` client path: `AuthServer.UserAdd` → `EtcdServer.UserAdd` (hashes here — **fix point 1**) → raft → `UberApplier` → `applierV3backend.UserAdd` → `AuthStore.UserAdd` (**fix point 2, defense-in-depth**) → `selectPassword`.
- `UserChangePassword` client path: `AuthServer.UserChangePassword` → `EtcdServer.UserChangePassword` (only hashes if `r.Password != ""`, otherwise passes blank through untouched) → raft → `UberApplier` → `applierV3backend.UserChangePassword` → `AuthStore.UserChangePassword` (**fix point 3, primary enforcement**) → `selectPassword`.
- Every production client (etcdctl, `client/v3`, grpc-gateway, grpc-proxy) terminates at the same two `AuthServer` gRPC methods backed by the single `EtcdServer` implementation — no alternate path exists, confirmed via grep across the repo for all `.UserAdd(`/`.UserChangePassword(` call sites.
- Error propagation: both `AuthServer.UserAdd`/`UserChangePassword` (v3rpc/auth.go) already call `togRPCError(err)` on any error returned by the authenticator, so an error returned directly from `EtcdServer.UserAdd` (pre-hash, pre-raft) is translated through the exact same `toGRPCErrorMap` as an error returned from the post-raft `AuthStore` layer — **fix point 4** (map wiring) covers both.

## Change Strategy

1. **`api/v3rpc/rpctypes/error.go`** (foundation — no dependents yet, safe to land first)
   - Add `ErrGRPCPasswordEmpty = status.Error(codes.InvalidArgument, "etcdserver: password is empty")` in the auth error group, directly after `ErrGRPCUserEmpty`.
   - Add `ErrorDesc(ErrGRPCPasswordEmpty): ErrGRPCPasswordEmpty,` to `errStringToError`, directly after the `ErrGRPCUserEmpty` entry.
   - Add `ErrPasswordEmpty = Error(ErrGRPCPasswordEmpty)` to the client-side error var block, directly after `ErrUserEmpty`.

2. **`server/auth/store.go`**
   - Add `ErrPasswordEmpty = errors.New("auth: password is empty")` to the `var (...)` error block, next to `ErrUserEmpty`.
   - `UserAdd`: after the existing `password, err = as.selectPassword(r.Password, r.HashedPassword)` / error-check inside `if !options.NoPassword { ... }`, add:
     ```go
     if len(password) == 0 {
         return nil, ErrPasswordEmpty
     }
     ```
   - `UserChangePassword`: identical pattern inside `if user.Options == nil || !user.Options.NoPassword { ... }`, after the existing `selectPassword` call/error-check.

3. **`server/etcdserver/v3_server.go`**
   - `EtcdServer.UserAdd`: inside `if r.Options == nil || !r.Options.NoPassword {`, before the `bcrypt.GenerateFromPassword` call, add:
     ```go
     if r.Password == "" {
         return nil, auth.ErrPasswordEmpty
     }
     ```
   - `EtcdServer.UserChangePassword`: **no change** — it already leaves both `Password` and `HashedPassword` empty when the client sends a blank password, so `server/auth/store.go`'s check (step 2) is the correct and sufficient enforcement point; adding a redundant check here would require an extra store lookup just to determine `NoPassword` status, which `AuthStore.UserChangePassword` already performs naturally.

4. **`server/etcdserver/api/v3rpc/util.go`**
   - Add `auth.ErrPasswordEmpty: rpctypes.ErrGRPCPasswordEmpty,` to `toGRPCErrorMap`, next to `auth.ErrUserEmpty: rpctypes.ErrGRPCUserEmpty,`.

Ordering: step 1 before steps 2–4 (compile dependency: `rpctypes.ErrGRPCPasswordEmpty` must exist before `util.go` references it); steps 2 and 3 are independent of each other and of step 4 internally, but step 4 depends on step 2 (`auth.ErrPasswordEmpty` must exist). Practically all four are applied together in one change since they're small and mutually referential at compile time.

## Specification Impact
- `server/auth/CODEMANIFEST`, `AuthStore` entity, `UserAdd` method annotation: append a clause clarifying the new rejection behavior, e.g.: *"Rejects a blank/empty password with a dedicated error unless the request explicitly opts the account into no-password mode via `Options.NoPassword`."* This clarifies rather than contradicts the existing "Create a new user with a bcrypt-hashed password" text.
- `server/auth/CODEMANIFEST`, `AuthStore` entity: **add a new `UserChangePassword` method entry** (currently undocumented — a pre-existing gap the investigation surfaced, not something this change causes but one this change makes worth closing since we're modifying its behavior). Annotation: describe changing an existing user's password, and the same blank-password rejection clause, noting it does not apply to accounts where the existing user's `Options.NoPassword` is set.
- No `Imports`, `Usages`, or `Annotations` (header-level) changes — no new practices or cross-cell dependencies are introduced.
- This reconciliation happens in pipeline Step 7 (Manifest Reconciliation), not now — noted here for that step's awareness.

## Usage Impact
No `.usages/*.md` files exist under `server/auth/.usages/` beyond what's referenced in the header (`range_permission_cache`, declared inline in the CODEMANIFEST itself, not a separate file). No usage file describes password validation or the `UserAdd`/`UserChangePassword` request shape, so **no usage file requires changes**. Existing usage recipes remain valid: any caller already supplying a real password is unaffected; only the previously-silent blank-password case now surfaces an error.

## Compatibility Verification
**Backward compatible.** The only behavioral change is: `UserAdd`/`UserChangePassword` with a blank resulting password on a non-passwordless account now returns `ErrPasswordEmpty` instead of silently succeeding — this is the explicit, intended contract change requested by the task. Every other input (non-blank password, or `NoPassword: true`) produces byte-for-byte identical behavior to today. No file paths, response shapes, or other error codes change. No existing test in `server/auth/store_test.go`, `tests/common/auth_test.go`, or the e2e/integration auth suites relies on blank-password success (verified in Investigation Step 6 of the breaking-change assessment). Proceeding — no STOP condition triggered.

## Test Strategy
- **`server/auth/store_test.go`**:
  - New test (or extend `TestUserAdd`): `UserAdd` with `Password: ""`, `HashedPassword: ""`, `Options.NoPassword: false` on a new username → expect `ErrPasswordEmpty`.
  - New test (or extend `TestUserChangePassword`): `UserChangePassword` with both `Password` and `HashedPassword` empty on an existing non-passwordless user → expect `ErrPasswordEmpty`.
  - Regression check: `TestUserNoPasswordAdd` (existing, `NoPassword: true`) must continue to pass unmodified — confirms passwordless accounts are unaffected.
  - Regression check: `UserChangePassword` on a user created with `NoPassword: true`, given a blank password, must still succeed as a no-op (existing behavior — the `!user.Options.NoPassword` guard skips the new check entirely for such accounts).
- **`server/etcdserver` level** (new, since `v3_server_test.go` has no existing `UserAdd` coverage): a table/unit test for `EtcdServer.UserAdd` asserting a blank `r.Password` with `Options: nil` or `Options.NoPassword: false` returns `auth.ErrPasswordEmpty` without invoking raft, and that `Options.NoPassword: true` with blank password still proceeds to `raftRequest` unaffected.
- **gRPC error mapping**: a small test (or extension of existing `util_test.go`/table if present) verifying `togRPCError(auth.ErrPasswordEmpty)` yields `rpctypes.ErrGRPCPasswordEmpty` with `codes.InvalidArgument`, mirroring however `ErrUserEmpty` is already tested.
- No e2e/integration test changes are strictly required for correctness, but a `tests/common/auth_test.go` case exercising `UserAdd`/`UserChangePassword` with a blank password over a real client connection would provide end-to-end confidence that the fix is visible through `client/v3` (optional, recommend adding one case for regression safety since this cell is exercised by the shared `tests/common` suite across integration and e2e).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Missing the `v3_server.go` fix point and only patching `store.go`'s `UserAdd`, silently shipping a no-op fix for the primary `UserAdd` path | Was high before investigation | High (defect would appear fixed but isn't) | Already identified and corrected via tracing; both fix points included in this plan |
| A raw/non-standard gRPC client sets `HashedPassword` directly to a non-empty value that decodes to zero bytes, evading the check | Negligible | Low | Base64 encoding of zero bytes is always the empty string — there is no non-empty base64 payload that decodes to empty; not a viable evasion |
| Existing tests that construct `UserAdd`/`UserChangePassword` requests without a password (relying on implicit success) break | Low (already surveyed) | Medium if missed | Confirmed via investigation that all such existing calls either hit `ErrUserAlreadyExist` first or discard the return value; will re-run full `server/auth` and `server/etcdserver` test suites after implementation to confirm |
| CODEMANIFEST left inconsistent with new behavior (esp. undocumented `UserChangePassword`) | Medium | Low (documentation drift, not functional) | Explicitly scoped into Step 7 Manifest Reconciliation of this pipeline, not deferred indefinitely |

---

Do you approve the plan? Proceed to implementation?
