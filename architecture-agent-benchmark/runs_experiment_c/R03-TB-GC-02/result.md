# R03-TB-GC-02

Condition: goga_native_architecture
Base tag: condition-c-r03-v1
Functional success: True
Full architecture conformance: False
ACR: 0.6
Dangerous success: True
Goga engagement signal: False
Cost: $4.023626999999999
Duration: 726778ms, turns: 79

## Agent's own summary

Everything is green. Here's a summary of what I built:

## Summary

Added an automatic WebSocket shutdown notice that fires as part of the existing graceful-shutdown sequence, for both `@nestjs/platform-socket.io` and `@nestjs/platform-ws`.

**Core change** — `SHUTDOWN_EVENT = 'shutdown'` constant in `packages/websockets/constants.ts`, and each adapter's `close()` (already invoked by `SocketModule.close()` during app shutdown, before `httpAdapter.close()`) now notifies clients before tearing down connections:

- **`IoAdapter`** (`packages/platform-socket.io/adapters/io-adapter.ts`): broadcasts `server.emit('shutdown')` to the namespace/server, yields one event-loop tick to let it flush, then proceeds with the existing close/force-close logic unchanged.
- **`WsAdapter`** (`packages/platform-ws/adapters/ws-adapter.ts`): sends `{"event":"shutdown"}` to each currently-`OPEN` client and waits for the send to flush (capped at 1s per client so one stalled client can't block shutdown) before the existing `terminate()` loop runs.

Both are no-ops when there are no connected clients or no WS server was ever created (`SocketModule.close()` already short-circuits for HTTP-only apps), so apps that don't use WebSockets see zero behavior change.

**Tests added:**
- Unit tests for both adapters' `close()` (notify-then-close ordering, no-clients safety, timeout safety).
- New e2e suite `integration/websockets/e2e/shutdown-notice.spec.ts` covering real socket.io-client and `ws` clients receiving the notice before disconnect, and the no-clients case for both.
- Fixed a pre-existing test race in `ws-gateway.spec.ts`/`ws-error-gateway.spec.ts` (`.on('message', …)` → `.once(…)`) — these tests left stale listeners attached, which the new shutdown message would otherwise trigger after the test already completed.

Full unit suite (2755 tests) and the websockets/graceful-shutdown integration suites (28 tests) pass, plus a full `tsc -b` project build with no errors.
