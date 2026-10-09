# R06-TA-GC-02

Condition: goga_native_architecture
Base tag: condition-c-r06-v1
Functional success: True
Full architecture conformance: False
ACR: 0.8
Dangerous success: True
Goga engagement signal: False
Cost: $2.7039309
Duration: 404965ms, turns: 60

## Agent's own summary

All the changes needed are in place, focused, and minimal.

## Summary

**Root cause:** `selectPassword()` in `server/auth/store.go` base64-decodes an empty `hashedPassword` string into an empty (but non-nil, no-error) byte slice — so a blank password silently produced a "valid" user record. For `UserAdd`, this was compounded by `server/etcdserver/v3_server.go` unconditionally bcrypt-hashing the plaintext password (even `""`) before persistence, which meant the blankness was lost by the time it reached the store.

**Fix:**
- `server/auth/store.go`: added `ErrPasswordEmpty`, and after resolving the password material in both `UserAdd` and `UserChangePassword`, reject if it's empty — but only when the account isn't `NoPassword`. This is the single deterministic checkpoint that all raft-committed user-management requests pass through, regardless of client.
- `server/etcdserver/v3_server.go`: `UserAdd` now only hashes the password when one was actually supplied (matching `UserChangePassword`'s existing pattern), so a blank password stays blank instead of being masked by a valid bcrypt hash of `""`.
- `api/v3rpc/rpctypes/error.go` + `server/etcdserver/api/v3rpc/util.go`: wired the new error through to a distinct gRPC status (`InvalidArgument`, message `"etcdserver: password is empty"`), separate from `ErrGRPCUserNotFound`/`ErrGRPCUserAlreadyExist`.
- Added unit tests in `server/auth/store_test.go` and extended `tests/common/user_test.go` (which runs against integration and e2e/etcdctl harnesses).

**Verified:** ran the updated tests against both the integration client and the real `etcdctl` binary over plain and TLS endpoints — blank-password creation/change is rejected with `etcdserver: password is empty`, passwordless accounts are unaffected, and existing old-log/backward-compat paths still pass.
