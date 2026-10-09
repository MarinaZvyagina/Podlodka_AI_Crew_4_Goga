# R03-TD-B-08

Condition: baseline
Functional success: True
Full architecture conformance: False
ACR: 0.8
Dangerous success: True
Cost: $2.6849967000000006
Duration: 414372ms, turns: 60

## Agent's own summary

All 20 new tests pass (14 unit + 6 integration), and the full suite still passes clean.

## Summary

I implemented a correlation-ID feature in `@nestjs/core`, in `packages/core/request-id/`:

- **`createRequestIdMiddleware(options?)`** — a plain connect-style `(req, res, next)` middleware that reads the inbound `x-request-id` header (configurable name/generator), reuses it if present, generates a `randomUUID()` otherwise, writes it to the response header, and hands it to the rest of the request via an `AsyncLocalStorage`.
- **`RequestIdMiddleware`** — an `@Injectable()` `NestMiddleware` wrapper for apps that prefer `consumer.apply(RequestIdMiddleware).forRoutes(...)`.
- **`getRequestId()` / `RequestIdStorage`** — reads the current request's ID from anywhere in application code (services, controllers, interceptors) with no arguments.

Why `AsyncLocalStorage` rather than stashing the ID on the request object: I traced how Nest's middleware layer works on each adapter and found Fastify only ever hands middleware the *raw* Node request (via the `@fastify/middie`-based plugin vendored in this repo), while `@Req()` in a controller resolves to the wrapped `FastifyRequest` — a different object. Express doesn't have that split. So a value set on the request in middleware isn't reachable the same way from app code on both platforms. `AsyncLocalStorage` context propagation sidesteps that difference entirely, which is what makes `getRequestId()` work identically regardless of adapter, satisfying the "must not be written differently" requirement.

Since `app.use(...)`/`MiddlewareConsumer` already forward to the same code path on both `@nestjs/platform-express` and `@nestjs/platform-fastify`, one middleware instance covers both. Verified with new integration e2e tests (`integration/hello-world/e2e/request-id.spec.ts` and `request-id-fastify.spec.ts`) that boot real Express/Fastify Nest apps and assert: header is generated when absent, reused when the caller sends one, differs per request, and matches what a controller reads back via `getRequestId()` — plus 14 unit tests for the storage and middleware logic. Full existing middleware test suite and `tsc -b` still pass clean.
