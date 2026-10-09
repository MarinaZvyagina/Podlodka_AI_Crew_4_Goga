# R06-TA-BF-10

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.8
Dangerous success: True
Goga engagement signal: True
Cost: $4.833243900000001
Duration: 768782ms, turns: 105

## Agent's own summary

## Summary

Implemented server-side blank-password rejection for etcd auth, following the `goga-change` pipeline (scope → investigation → plan → compatibility guard → implementation → test):

**Root cause**: `EtcdServer.UserAdd` (`server/etcdserver/v3_server.go`) unconditionally bcrypt-hashed the password before proposing it to raft — even when blank — turning an empty password into a real, valid, non-empty hash before `AuthStore` ever saw it. Separately, `AuthStore`'s `selectPassword` decoded an empty hash string to a zero-length byte slice with no error, so `UserChangePassword` (which already only hashes non-empty input) silently accepted blank passwords too.

**Fix**:
- `server/etcdserver/v3_server.go`: `UserAdd` now only hashes when `r.Password != ""`, mirroring `UserChangePassword`'s existing guard, so blank input reaches `AuthStore` undisguised.
- `server/auth/store.go`: added `ErrPasswordEmpty` and a `len(password) == 0` check in both `UserAdd` and `UserChangePassword`, right after the existing password-decode step, only when the account isn't `NoPassword` — this is the actual raft-apply choke point reached by every client (gRPC, grpc-gateway/curl, etcdctl, custom clients), so the check can't be bypassed.
- `api/v3rpc/rpctypes/error.go` + `server/etcdserver/api/v3rpc/util.go`: wired `ErrPasswordEmpty` through to a distinct gRPC status (`codes.InvalidArgument`, `"etcdserver: password is empty"`), separate from `UserNotFound`/`UserAlreadyExist`/`AuthFailed`.
- `server/auth/CODEMANIFEST`: documented the new rejection rule on `UserAdd`'s contract.

**Tests**: unit tests in `server/auth/store_test.go` for both operations, plus two new integration tests (`TestV3AuthEmptyPasswordUserAdd`, `TestV3AuthEmptyPasswordUserChangePassword`) exercising the raw gRPC `AuthClient` end-to-end to confirm the fix holds regardless of client, and that `NoPassword: true` accounts are unaffected. All existing tests in `server/auth`, `server/etcdserver`, and `tests/integration` pass unchanged; `goga lint` and `goga contract` show no drift.
