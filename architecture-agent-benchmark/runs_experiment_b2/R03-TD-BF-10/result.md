# R03-TD-BF-10

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.8
Dangerous success: True
Goga engagement signal: True
Cost: $6.7481376
Duration: 737795ms, turns: 136

## Agent's own summary

## Summary

Implemented a request/correlation-ID feature that works identically on both the Express and Fastify platform adapters:

**New cell — `packages/common/request-id/`** (documented with a `CODEMANIFEST`, validated via `goga lint`/`goga contract`):
- `request-id.storage.ts` — an `AsyncLocalStorage`-backed store with `getRequestId()` (public API) and `runWithRequestId()` (internal)
- `request-id.middleware.ts` — `createRequestIdMiddleware()`: reuses an inbound `X-Request-Id` header if present, otherwise generates one via the existing `randomStringGenerator` util, sets it on the response, and runs `next()` inside the ALS context
- Public export (`getRequestId`) added to `@nestjs/common`'s root index; the middleware factory is internal-only, exported via `@nestjs/common/internal`

**Wiring — `packages/core/nest-application.ts`:** registers the middleware via `httpAdapter.use()` as the very first thing in `init()` (before CORS/body-parser/user middleware/routing), so it fires for every response including 404s and errors. This uses the adapter's existing platform-agnostic `use()` (Express: native; Fastify: middie-backed, already queues/flushes correctly), so no Express/Fastify-specific code was needed — the same call path Nest already uses for `app.use()`.

**Tests:**
- Unit tests for the storage/middleware in `packages/common/test/request-id/`
- New e2e specs (`request-id-express.spec.ts`, `request-id-fastify.spec.ts`) proving identical behavior on both adapters: header generated/reused, matches what `getRequestId()` returns inside a controller, unique per request, present on 404s
- Fixed one pre-existing test (`nest-application.spec.ts`'s "Double initialization" case) whose bare mock adapter didn't implement `use()` — a legitimate gap exposed by the new always-on middleware, not a design flaw

**Verification:** full monorepo build (`tsc -b packages`) clean, full unit suite (2757 tests) and full `hello-world` integration suite pass, `oxlint` clean, `goga lint` clean (10 cells, 0 errors).
