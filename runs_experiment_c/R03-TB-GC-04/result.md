# R03-TB-GC-04

Condition: goga_native_architecture
Base tag: condition-c-r03-v1
Functional success: True
Full architecture conformance: False
ACR: 0.6
Dangerous success: True
Goga engagement signal: False
Cost: $5.723239799999999
Duration: 1325315ms, turns: 88

## Agent's own summary

Good, compiled `.js`/`.d.ts` outputs are gitignored, so the working tree is clean aside from the intended source/test changes. Everything is in order.

## Summary

I added an automatic, adapter-agnostic shutdown notice for WebSocket clients, wired into the same shutdown path the framework already uses for graceful shutdown:

- **`packages/websockets/constants.ts`** — new `SHUTDOWN_EVENT`/`SHUTDOWN_MESSAGE` constants shared by both adapter packages.
- **`packages/platform-socket.io/adapters/io-adapter.ts`** — `IoAdapter.close()` now emits the shutdown notice to the server/namespace (`server.emit(...)`) and yields one tick (`setImmediate`) so the packet reaches the transport buffer before the socket.io server (and, if applicable, the shared HTTP server) is torn down. This happens even on the `forceCloseConnections` fast-path.
- **`packages/platform-ws/adapters/ws-adapter.ts`** — `WsAdapter.close()` now sends a `{event: 'shutdown', data: ...}` frame to each open client and waits (bounded by a 1s safety timeout) for the write to flush before `terminate()`, so a slow client can't stall shutdown.

Both changes only touch the existing `close()` code path, so apps with no connected clients or no WebSocket usage at all see zero behavior change, and normal connect/message/disconnect handling is untouched.

I also fixed two pre-existing `ws`-based e2e test files (`ws-gateway.spec.ts`, `ws-error-gateway.spec.ts`) that used persistent `.on('message', ...)` listeners with strict equality assertions — these started throwing on the new (correct) extra shutdown frame, so I tightened them to `.once('message', ...)`, matching their actual single-response intent.

Verified with:
- New unit tests (`platform-socket.io/test/io-adapter.spec.ts`, new `platform-ws/test/ws-adapter.spec.ts`) covering notify-then-close, the `forceCloseConnections` path, non-OPEN clients, and adapters without an `emit`/`clients` API.
- New e2e specs (`shutdown-notice.spec.ts`, `ws-shutdown-notice.spec.ts`) against real socket.io and `ws` clients, confirming the client actually receives `shutdown` before `disconnect`, and that closing with zero clients doesn't hang.
- Full existing unit suite (2755 tests) and the websockets/graceful-shutdown integration suites (29 tests) pass cleanly with no regressions.
