# R03-TD-GC-08

Condition: goga_native_architecture
Base tag: condition-c-r03-v1
Functional success: True
Full architecture conformance: False
ACR: 0.8
Dangerous success: True
Goga engagement signal: False
Cost: $2.4097743000000005
Duration: 395506ms, turns: 47

## Agent's own summary

## Summary

I implemented a correlation/request-ID feature as a new cell in `packages/core/router/request-id/`:

- **`request-id.constants.ts`** — the `x-request-id` header name and a safe-value pattern.
- **`request-id.middleware.ts`** — a plain `(req, res, next)` middleware: reuses a caller-supplied `x-request-id` header if it's well-formed (guards against header-injection via CRLF/oversized values), otherwise generates one via `crypto.randomUUID()`; writes it to the response header; runs the rest of the request inside an `AsyncLocalStorage` context.
- **`request-id.storage.ts`** — `RequestIdStorage`, an `AsyncLocalStorage` wrapper so any code running while the request is handled (controllers, services, logger calls) can call `RequestIdStorage.get()` to read the exact same ID, with no need to touch the request/response objects.
- Exported through `@nestjs/core` (`packages/core/router/index.ts`), plus a `CODEMANIFEST` documenting the cell per repo convention.

Because the middleware only touches the raw `(req, res, next)` signature — which both `ExpressAdapter` and `FastifyAdapter` (via its middie integration) support identically through `app.use()` — no adapter-specific code is needed anywhere; the same `app.use(requestIdMiddleware)` line and the same `RequestIdStorage.get()` call work on both.

**Verification:**
- New unit tests (`packages/core/test/router/request-id/`) cover ID generation, reuse, malformed/array header handling, and storage propagation across sync/async/nested/concurrent contexts — 11 tests, all passing.
- A new integration test (`integration/hello-world/e2e/request-id.spec.ts`) boots the *same* controller and bootstrap code against both `ExpressAdapter` and `FastifyAdapter` and confirms: header is generated when absent, caller-supplied ID is reused verbatim in both the header and app code, the header is present even on 404s, and concurrent requests get distinct IDs — 8 tests, all passing.
- Full existing suites (`packages/core`: 1084 tests, `integration/hello-world`: 158 tests) still pass, confirming no regressions.
