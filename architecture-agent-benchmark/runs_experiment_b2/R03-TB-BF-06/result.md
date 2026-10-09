# R03-TB-BF-06

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.2
Dangerous success: False
Goga engagement signal: True
Cost: $3.255539550000001
Duration: 353067ms, turns: 53

## Agent's own summary

# Change Plan

## Task Classification
**Type: Feature (additive extension point).** No existing behavior is modified for callers who don't hit the new code path; a new optional hook is introduced end-to-end through the WS adapter contract.

## Affected Cells
| Cell | Files to Modify | What Changes |
|---|---|---|
| `packages/common` (new cell: `packages/common/interfaces/websockets`) | `web-socket-adapter.interface.ts` | Add `beforeClose?(server: TServer): any;` to the `WebSocketAdapter<TServer, TClient, TOptions>` interface |
| `packages/websockets` (new cell) | `constants.ts` | Add `export const SHUTDOWN_EVENT = 'shutdown';` |
| `packages/websockets` (new cell) | `adapters/ws-adapter.ts` | Add no-op default `public async beforeClose(server: TServer): Promise<void> {}` on `AbstractWsAdapter`, mirroring the existing no-op `dispose()` |
| `packages/websockets` (new cell) | `socket-module.ts` | In `close()`, call `await adapter.beforeClose?.(server)` immediately before `await adapter.close(server)`, per server entry |
| `packages/platform-socket.io` (new cell) | `adapters/io-adapter.ts` | Override `beforeClose(server)`: `server.emit(SHUTDOWN_EVENT)` — broadcasts to every currently-connected socket on that `Server`/`Namespace`; no-op if zero clients |
| `packages/platform-ws` (new cell) | `adapters/ws-adapter.ts` | Override `beforeClose(server)`: iterate `server.clients` (the `ws` library's own `Set`), `ws.send(JSON.stringify({ event: SHUTDOWN_EVENT }))` to each socket whose `readyState === OPEN_STATE`; no-op if `server.clients` is absent/empty |

No files in `packages/core` are modified — `NestApplication.dispose()` already calls `socketModule.close()` unconditionally; that call site needs no change.

## Root Cause Analysis
Summary from Investigation Report: `SocketModule.close()` calls `adapter.close(server)` with no preceding hook, and neither `WebSocketAdapter` nor `AbstractWsAdapter` expose an extension point analogous to the already-implemented (if undocumented) `HttpServer.beforeClose?()` used on the HTTP side. Fix is additive: give WS adapters the same hook shape, then implement the actual per-transport client broadcast in each platform package.

## Trace Summary
`SIGTERM/app.close()` → `NestApplication.dispose()` → `SocketModule.close()` → for each `{server}` in `SocketsContainer.getAll()`: **(new)** `adapter.beforeClose?.(server)` → `adapter.close(server)` → `adapter.dispose()`. Single insertion point, reached identically regardless of which platform adapter is registered (`IoAdapter` or `WsAdapter`), since `applicationConfig.getIoAdapter()` returns whichever was set via `setIoAdapter()`/`useWebSocketAdapter()`.

## Change Strategy
1. **`packages/common`**: widen the `WebSocketAdapter` interface with the optional `beforeClose` method — purely additive to an interface, cannot break implementers.
2. **`packages/websockets`**: add the `SHUTDOWN_EVENT` constant (single source of truth for the event name, shared cross-package via `internal.ts`'s existing `export * from './constants.js'`); add the no-op default on `AbstractWsAdapter` so any adapter that doesn't override it behaves exactly as today; wire the optional-chained call into `SocketModule.close()`.
3. **`packages/platform-socket.io`**: override `beforeClose` using socket.io's native `emit` — broadcast reaches only currently-attached sockets, trivially safe when there are none.
4. **`packages/platform-ws`**: override `beforeClose` using the `ws` library's native `clients` Set — send only to `OPEN_STATE` sockets (mirrors the existing `readyState` guard already used in `bindMessageHandlers`'s `onMessage`), trivially safe when the set is empty.
5. Order guarantee: `beforeClose` always runs and completes (`await`) before `close()` runs for the same server, so the notification is flushed to the socket buffer before socket.io's graceful close / `ws`'s `terminate()` loop runs.

## Specification Impact
No existing CODEMANIFEST is edited (none exists for the 4 touched directories). Four new CODEMANIFEST cells will be created in the Manifest Reconciliation step (via `goga-brainstorm`/`goga-apply`), each documenting only the real, now-implemented surface:
- `packages/common/interfaces/websockets` — `WebSocketAdapter` interface, including the new `beforeClose` method
- `packages/websockets` (adapters + socket-module scope) — `AbstractWsAdapter`, `SocketModule`, `SHUTDOWN_EVENT`
- `packages/platform-socket.io/adapters` — `IoAdapter`
- `packages/platform-ws/adapters` — `WsAdapter`

## Usage Impact
No existing `.usages/*.md` files exist under any touched cell, so none are edited. Per `goga-cookbook` ("create a usage file inside `<cell_path>/.usages/` when creating or updating CODEMANIFEST files"), each new cell gets one consumer-facing practice file describing: (a) that shutdown notification is automatic and requires no gateway code, and (b) how a client-side listener should consume it (`socket.on('shutdown', ...)` for socket.io; parse the `{event: 'shutdown'}` JSON message for `ws`).

## Compatibility Verification
**Backward compatible.** Confirmed in the Investigation Report's Breaking Change Assessment (all 6 questions answered NO). All changes are additive: new optional interface method, new no-op base default, new optional-chained call site, new constant, new adapter overrides. No existing signature, file path, return type, or test is altered.

## Test Strategy
- **`packages/websockets/test/socket-module.spec.ts`** (new): `SocketModule.close()` calls `adapter.beforeClose?.(server)` before `adapter.close(server)` for each registered server (order assertion via call-sequence spy); skips gracefully when the adapter has no `beforeClose`; is a complete no-op when no adapter was ever registered (existing "no WS usage" guard, unchanged branch — regression check).
- **`packages/websockets/test/adapters/ws-adapter.spec.ts`** (new, mirrors absence of prior coverage): `AbstractWsAdapter.beforeClose` default resolves without throwing and performs no observable action.
- **`packages/platform-socket.io/test/io-adapter.spec.ts`** (extend): `beforeClose(server)` calls `server.emit(SHUTDOWN_EVENT)`; no-op-safe when `server.emit` is called with zero listeners/sockets (existing socket.io behavior, no special-casing needed, but assert it doesn't throw).
- **`packages/platform-ws/test/ws-adapter.spec.ts`** (new — no `packages/platform-ws/test` directory exists yet): `beforeClose(server)` sends the JSON shutdown payload to every client with `readyState === OPEN`, skips `CONNECTING`/`CLOSING`/`CLOSED` clients, and is a no-op when `server.clients` is undefined/empty.
- **`integration/graceful-shutdown/e2e/websockets.spec.ts`** (new, modeled on `express.spec.ts`'s real-app/real-client style): two cases — (1) socket.io: connect a real `socket.io-client`, call `app.close()`, assert the client receives a `shutdown` event before the `disconnect` event; (2) `ws`: connect a real `ws` client, call `app.close()`, assert the client receives the JSON shutdown message before its `close` event fires. Both cases also implicitly cover "an app with zero connected clients shuts down without error" via the existing `afterEach(() => app.close())` pattern already exercised elsewhere without any client connected.

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| A custom third-party `WebSocketAdapter` (not `IoAdapter`/`WsAdapter`) has its own `beforeClose` method name collision from unrelated code | Low | Low | Optional-chained call (`adapter.beforeClose?.(server)`) only invokes it if present; any adapter not implementing the new interface member is completely unaffected — behaves exactly as today |
| Sending to a socket mid-close (`readyState` transitioning) throws | Low | Low | Explicit `readyState === OPEN_STATE` guard on the `ws` side (mirrors existing guard pattern in `bindMessageHandlers`); socket.io's `emit` is itself safe against disconnected sockets by design |
| New CODEMANIFEST cells inaccurately describe existing (unrelated) methods on `IoAdapter`/`WsAdapter`/`AbstractWsAdapter` while documenting only the new method | Medium | Low | Document the full existing public surface of each class in the new cells (matching what `packages/core/adapters`' `AbstractHttpAdapter` manifest already does for its own class), not just the new method, so the cell is accurate from creation |
| `forceCloseConnections` short-circuit in `IoAdapter.close()` causes `beforeClose` + immediate httpServer force-close to race, cutting off delivery before the TCP flush completes | Low | Medium | Out of scope to fully solve (pre-existing force-close semantics), but `beforeClose` still runs and flushes to the socket.io send buffer before `close()`'s no-op path returns — same best-effort delivery guarantee `forceCloseConnections` already accepts for other in-flight data |

---

Do you approve this plan? Proceed to implementation?
