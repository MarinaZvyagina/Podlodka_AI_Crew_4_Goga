# R03-TB-BP-05

Condition: goga_full_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.6
Dangerous success: True
Goga engagement signal: False
Cost: $6.026225100000001
Duration: 984088ms, turns: 106

## Agent's own summary

Everything passes clean. Here's a summary of what was implemented.

## Summary

Added an automatic WebSocket shutdown notice to both shipped WS integrations, wired into the existing graceful-shutdown sequence with no per-gateway opt-in required.

**Core change** — `packages/platform-socket.io/adapters/io-adapter.ts` and `packages/platform-ws/adapters/ws-adapter.ts`: `close(server)` (already called by `SocketModule.close()` from `NestApplication.dispose()`, itself invoked by `app.close()`/shutdown-signal handling) now emits a `shutdown` event/message to every currently-connected local client *before* actually closing the connection:
- **socket.io**: `socket.emit('shutdown', { message: 'Server is shutting down' })` per connected socket in the resolved namespace, then yields one event-loop tick (`setImmediate`) before the existing `Server#close()` force-closes transports — needed because engine.io's shutdown path force-closes sockets without waiting for the write buffer to drain, so without the tick the just-emitted packet gets dropped.
- **ws**: `ws.send()` the same payload (in the existing `{event, data}` shape used elsewhere in this adapter), awaiting each send's callback before the existing `ws.terminate()` calls run, so the frame isn't dropped off Node's write buffer.

New constants `SERVER_SHUTTING_DOWN_EVENT`/`SERVER_SHUTTING_DOWN_MESSAGE` in `packages/websockets/constants.ts`, exported publicly from `@nestjs/websockets` so client code can listen for the exact event name.

**Safety by default**: notification is a no-op when a gateway's socket/client map is empty, and `SocketModule.close()` already short-circuits entirely when an app has no gateways/adapter — so idle gateways and non-WS apps see zero behavior change. Verified via new tests (`integration/websockets/e2e/shutdown-notice.spec.ts`) covering both adapters plus the "no clients"/"no gateways" cases.

**Side fix**: adding the notice exposed a latent test-isolation bug in `ws-gateway.spec.ts`/`ws-error-gateway.spec.ts` — stale `ws.on('message', ...)` listeners from prior tests were still attached when a later test's `app.close()` ran, so they caught the new notice and threw. Fixed by switching those single-response listeners to `.once()`, which is correct regardless of this feature.

All existing unit (1186) and integration (28) tests pass, plus typecheck and lint are clean.
