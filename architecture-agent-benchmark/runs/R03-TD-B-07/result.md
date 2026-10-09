# R03-TD-B-07

Condition: baseline
Functional success: True
Full architecture conformance: False
ACR: 0.8
Dangerous success: True
Cost: $2.536850550000001
Duration: 467455ms, turns: 43

## Agent's own summary

## Summary

Implemented a cross-adapter request/correlation ID feature in `@nestjs/common`:

- **`packages/common/context/request-id-storage.ts`** — an `AsyncLocalStorage`-based store with `getRequestId()`. Propagation is by async execution context, not by mutating the request object — which matters because Fastify's middleware compatibility layer hands middleware the raw Node `req`/`res` (a different object identity than the `FastifyRequest`/`FastifyReply` later seen by `@Req()` in controllers), so mutating `req` wouldn't have survived to application code on Fastify.
- **`packages/common/middleware/request-id.middleware.ts`** — `RequestIdMiddleware`: reuses an incoming `x-request-id` header if present and non-empty, otherwise generates one via `randomUUID()`; sets it on the response header; runs `next()` inside `requestIdStorage.run(...)` so `getRequestId()` resolves correctly anywhere during that request (route handlers, injected services, logger calls).
- Wired both into `packages/common/index.ts`'s public exports.

Verified parity across both adapters with new integration specs (`integration/hello-world/e2e/request-id.spec.ts` for Express, `request-id-fastify.spec.ts` for Fastify) using the exact same middleware/controller code for both — no platform branching. Also added unit tests for the storage and middleware in isolation. Ran the full `packages/common` suite (708 tests), the new integration specs, `oxlint`, and `prettier` — all clean.
