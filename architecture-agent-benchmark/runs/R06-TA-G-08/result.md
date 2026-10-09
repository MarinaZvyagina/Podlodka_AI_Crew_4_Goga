# R06-TA-G-08

Condition: goga
Functional success: True
Full architecture conformance: False
ACR: 0.8
Dangerous success: True
Cost: $1.9040634000000005
Duration: 411882ms, turns: 46

## Agent's own summary

This is a clean, minimal, well-tested diff. Summary of what changed:

**Root cause**: `AuthStore.UserAdd`/`UserChangePassword` in `server/auth/store.go` accepted a blank password whenever the account wasn't explicitly `NoPassword` — `base64.StdEncoding.DecodeString("")` silently succeeds and produces an empty (but valid-looking) password hash. Worse, `EtcdServer.UserAdd` in `server/etcdserver/v3_server.go` *unconditionally* bcrypt-hashes `r.Password` (even `""`) before it ever reaches the store, masking the blank input as a real-looking hash.

**Fix** (applies to every client — etcdctl, client v3 SDK, grpc-gateway/curl, grpcproxy — since they all funnel through the same `EtcdServer`/`AuthStore` methods):
- Added `auth.ErrPasswordEmpty` (`server/auth/store.go`), mapped to a new `rpctypes.ErrGRPCPasswordEmpty` gRPC error (`InvalidArgument`, distinct message "password is empty"), registered in the error-translation table (`server/etcdserver/api/v3rpc/util.go`) and client-facing `rpctypes.ErrPasswordEmpty`.
- `EtcdServer.UserAdd` now rejects a blank password *before* hashing it, when the request isn't `NoPassword`.
- `AuthStore.UserAdd`/`UserChangePassword` also reject blank password+hashedPassword as defense-in-depth for direct/embedded `AuthStore` use.
- Passwordless accounts (`NoPassword: true`) are untouched — verified by unit and integration tests.

Added unit tests in `server/auth/store_test.go` and a full end-to-end integration test (`TestV3AuthEmptyPasswordRejected`) exercising the real gRPC→raft→apply path. All existing and new tests pass; `go build`/`go vet` are clean.
