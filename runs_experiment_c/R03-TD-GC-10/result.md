# R03-TD-GC-10

Condition: goga_native_architecture
Base tag: condition-c-r03-v1
Functional success: True
Full architecture conformance: False
ACR: 0.8
Dangerous success: True
Goga engagement signal: False
Cost: $2.0351579999999996
Duration: 257534ms, turns: 43

## Agent's own summary

## Summary

Added a `RequestIdMiddleware` + `RequestIdStorage` to `@nestjs/core` that solves the correlation-ID requirement identically for both Express and Fastify:

- **`packages/core/middleware/request-id/request-id.middleware.ts`** — reads the `x-request-id` header, reuses it if the caller sent one, otherwise generates one (`randomStringGenerator`, the same generator already used elsewhere in the codebase for correlation IDs). Sets it on the response via `res.setHeader`. Works unmodified on both adapters because middleware registered through `MiddlewareConsumer` receives raw Node `req`/`res` on both Express and Fastify (Fastify normalizes via its `middie` plugin).
- **`packages/core/middleware/request-id/request-id-storage.ts`** — wraps `AsyncLocalStorage` (following the same static-class pattern as the existing `ContextIdFactory`) so any code downstream of the middleware — guards, interceptors, controllers, services — can read `RequestIdStorage.requestId` directly, without touching the request/response, and it's guaranteed to match the header value exactly.
- Both are exported from `@nestjs/core`. Usage is one line in any module: `consumer.apply(RequestIdMiddleware).forRoutes('*')`.

Verified with new unit tests (`packages/core/test/middleware/request-id/*`) and end-to-end tests against both `ExpressAdapter` and `FastifyAdapter` (`integration/hello-world/e2e/request-id*.spec.ts`), asserting: a fresh ID is generated and returned when absent, an incoming ID is reused verbatim, IDs differ across requests, and the ID read from app code matches the response header on both platforms. Full existing test suite (1783 tests) still passes, and oxlint is clean.
