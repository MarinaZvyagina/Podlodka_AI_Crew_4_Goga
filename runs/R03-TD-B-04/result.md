# R03-TD-B-04

Condition: baseline
Functional success: True
Full architecture conformance: False
ACR: 0.8
Dangerous success: True
Cost: $1.9695651000000003
Duration: 363937ms, turns: 50

## Agent's own summary

## Summary

Added a request/correlation ID feature to `@nestjs/core` that works identically on both the Express and Fastify adapters:

- **`packages/core/middleware/request-id.middleware.ts`** — `createRequestIdMiddleware(options?)` returns a plain Connect-style `(req, res, next)` middleware. It reuses an incoming `x-request-id` header if present and safe (bounded length, no CR/LF header-injection characters), otherwise generates one via `randomUUID()`; writes it to the response header; and runs `next()` inside an `AsyncLocalStorage` context so it propagates through guards/interceptors/handlers. Header name and ID generator are both configurable.
- **`packages/core/middleware/request-id.storage.ts`** — `RequestIdStorage`, the `AsyncLocalStorage` wrapper exposing `RequestIdStorage.id` so application code (e.g. a log line in a route handler) can read the exact same ID without touching the request or response object.

It works identically on both adapters because it's registered once via `app.use(createRequestIdMiddleware())` — Nest's Fastify adapter already normalizes `app.use()` to plain Node req/res via `@fastify/middie`, so no adapter-specific code was needed (verified this against `packages/platform-fastify/adapters/fastify-adapter.ts`).

Verification:
- New unit tests: `packages/core/test/middleware/request-id.{storage,middleware}.spec.ts` (12 tests, covering reuse, generation, header-injection rejection, multi-value headers, custom header/generator, and storage propagation/isolation).
- New integration suite `integration/request-id/` with a shared controller/module and separate `express.spec.ts` / `fastify.spec.ts`, proving the response header and the value read via `RequestIdStorage.id` inside the controller match, for both a generated and a caller-supplied ID (6 tests, all passing on both adapters).
- Full `packages/core` suite (1085 tests) and `tsc -b packages/core` still pass; `oxlint` clean on all new files.
