# R03-TD-BF-08

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.8
Dangerous success: True
Goga engagement signal: True
Cost: $5.010022499999999
Duration: 698518ms, turns: 100

## Agent's own summary

Clean lint, everything's in order. Here's a summary of the implementation:

## Summary

Added a new `packages/core/request-id` cell implementing the request/correlation-id feature, grounded in Goga's documented architecture (`goga schema`, `goga-cell` DSL, `goga lint`/`goga contract` all consulted and validated):

- **`RequestIdMiddleware`** — a standard `NestMiddleware`. Reuses the incoming `x-request-id` header when the caller already sent one, otherwise generates a new UUID; writes it onto the response header before any routing/guards/handlers run.
- **`RequestIdStorage`** / **`getRequestId()`** — an `AsyncLocalStorage`-backed store (same pattern as the existing `ContextIdFactory`) binding the id for the rest of the request, so any application code (services, guards, log lines) can call `getRequestId()` and get the exact value that's on the response header, without touching `@Req()` or parsing anything.

**Why this achieves identical behavior on both adapters, not just "mostly":** rather than touching `ExpressAdapter`/`FastifyAdapter` individually, it's registered the same way as any other cross-cutting `NestMiddleware`, via `consumer.apply(RequestIdMiddleware).forRoutes('*')`. That path already runs through the same `AbstractHttpAdapter#use` call and executes in `registerModules()` — before `registerRouter()` sets up controllers, the 404 handler, and the error handler — so the header lands on *every* response (success, 404, or thrown error) identically on Express and Fastify, with zero platform-specific code.

Verified:
- `packages/core` builds clean (`tsc -b`), 1083 existing unit tests still pass.
- New unit tests (`packages/core/test/request-id/`) and new e2e tests against both `NestExpressApplication` and `NestFastifyApplication` (`integration/hello-world/e2e/request-id*.spec.ts`) — 160 total hello-world integration tests pass, including the 10 new ones proving identical header/storage behavior on both platforms.
- `goga lint` passes project-wide (10 cells, 0 errors) with a proper `CODEMANIFEST` + `.usages` doc for the new cell.
