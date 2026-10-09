# R03-TB-BF-05

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: True
Cost: $1.4633082000000002
Duration: 267759ms, turns: 46

## Agent's own summary

# Change Plan

**Task Classification**: Feature (new cross-cutting capability), additive only — no bugfix, no refactor of existing behavior.

**Affected Cells**

| Cell | Files to Modify | What Changes |
|---|---|---|
| packages/common (interfaces/websockets) | `interfaces/websockets/web-socket-adapter.interface.ts` | Add optional `notifyShutdown?(server: TServer): any;` to `WebSocketAdapter` |
| packages/websockets | `constants.ts`, `adapters/ws-adapter.ts` (AbstractWsAdapter), `socket-module.ts` | New `SHUTDOWN_EVENT` constant; default no-op `notifyShutdown` on the base adapter; `SocketModule.close()` calls it per-server before `adapter.close(server)` |
| packages/platform-socket.io | `adapters/io-adapter.ts` | Override `notifyShutdown` — `server.emit(SHUTDOWN_EVENT, payload)` |
| packages/platform-ws | `adapters/ws-adapter.ts` | Override `notifyShutdown` — iterate `server.clients`, `ws.send(...)` to OPEN sockets |

**Root Cause Analysis**: `SocketModule.close()` tears down every registered WS server via `adapter.close(server)` with no notification step anywhere in the chain; platform-ws's `close()` additionally hard-kills via `ws.terminate()`. No existing hook (per-gateway lifecycle interfaces) satisfies "no developer wiring," so the fix must live in the adapter/module layer that already runs unconditionally during shutdown.

**Trace Summary**: `NestApplicationContext.close(signal)` → `dispose()` (NestApplication override) → `socketModule.close()` → per server in `SocketsContainer`: **[NEW] `adapter.notifyShutdown?.(server)`** → `adapter.close(server)` → `adapter.dispose()` → `socketsContainer.clear()`. This sits entirely inside the existing shutdown sequence (after `onModuleDestroy`/`beforeApplicationShutdown` hooks, before `onApplicationShutdown` hooks) — no new call sites into `packages/core`.

**Change Strategy**
1. `packages/websockets/constants.ts` — add `export const SHUTDOWN_EVENT = 'shutdown';`.
2. `packages/common/interfaces/websockets/web-socket-adapter.interface.ts` — add `notifyShutdown?(server: TServer): any;` to the `WebSocketAdapter` interface (optional, matching existing `bindClientDisconnect?` precedent).
3. `packages/websockets/adapters/ws-adapter.ts` (`AbstractWsAdapter`) — add `public async notifyShutdown(_server: TServer): Promise<void> {}`.
4. `packages/websockets/socket-module.ts` — in `close()`, inside the existing `.map(async ({ server }) => ...)`, add `await (adapter as AbstractWsAdapter).notifyShutdown?.(server);` immediately before `await adapter.close(server);`.
5. `packages/platform-socket.io/adapters/io-adapter.ts` — add `public async notifyShutdown(server: Server | Namespace): Promise<void> { server.emit(SHUTDOWN_EVENT, { event: SHUTDOWN_EVENT, data: { message: 'Server is shutting down' } }); }`.
6. `packages/platform-ws/adapters/ws-adapter.ts` — add `public async notifyShutdown(server: any): Promise<void>` guarding `server.clients`, sending `JSON.stringify({ event: SHUTDOWN_EVENT, data: { message: 'Server is shutting down' } })` to each client with `readyState === READY_STATE.OPEN_STATE`.

**Specification Impact**: `packages/websockets`, `packages/platform-socket.io/adapters`, `packages/platform-ws/adapters` have no CODEMANIFEST today (confirmed via `goga schema`). New CODEMANIFEST files will be authored for these three cells (plus registering them into the documented architecture graph) as part of Step 7 (Manifest Reconciliation), documenting the mutated `AbstractWsAdapter::IoAdapter` / `AbstractWsAdapter::WsAdapter` types and the new `notifyShutdown` method/behavior contract. `packages/common`'s existing exceptions-only manifest scope doesn't cover `interfaces/websockets`, so that interface file is documented as part of the `packages/websockets` cell's Imports contract, not a new standalone cell (too fine-grained per cookbook granularity rule).

**Usage Impact**: New `.usages` file(s) for `packages/websockets` (e.g. `graceful-shutdown-notification.md`) describing, for consumers, that gateways automatically get this behavior with no wiring — consumer-facing documentation only, no contractual obligation.

**Compatibility Verification**: Backward compatible. All changes are additive (new optional interface member, new default no-op method, one new awaited call in an existing async map). No existing signature, return type, file path, or control-flow branch is altered. Confirmed no existing test exercises `SocketModule.close()` or `WsAdapter.close()`/`IoAdapter.close()` in a way this touches.

**Test Strategy**
- `packages/websockets/test/socket-module.spec.ts` (new): verify `close()` calls `adapter.notifyShutdown` before `adapter.close` per server; verify no-op when `getIoAdapter()` is undefined (no gateways) and when `socketsContainer` is empty (no clients/servers) — the two "safe by default" cases.
- `packages/websockets/test/adapters/ws-adapter.spec.ts` (new): `AbstractWsAdapter.notifyShutdown` default resolves without touching the server.
- `packages/platform-socket.io/test/io-adapter.spec.ts` (extend): `notifyShutdown` calls `server.emit(SHUTDOWN_EVENT, ...)`.
- `platform-ws/test/ws-adapter.spec.ts` (new — package currently has no test dir): `notifyShutdown` sends to OPEN clients only, skips CLOSED/CONNECTING, no-op when `server.clients` is undefined.

**Risk Assessment**

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `ws.send()` message not flushed before `ws.terminate()` | Medium | Low (best-effort notice, not a delivery guarantee; explicitly framed as "heads-up") | `notifyShutdown` is fully awaited (async boundary) before `close()`/`terminate()` runs, maximizing the chance the write is flushed; changing `terminate()`→`close()` is out of scope (would alter existing force-close semantics) |
| Emitting/sending to a server with 0 clients | None | None | `server.emit` on socket.io and iterating an empty `server.clients` Set are both true no-ops |
| Third-party custom `WebSocketAdapter` implementations | None | None | Method is optional (`?.`) on both the interface and the call site |

Do you approve this plan? Proceed to implementation?
