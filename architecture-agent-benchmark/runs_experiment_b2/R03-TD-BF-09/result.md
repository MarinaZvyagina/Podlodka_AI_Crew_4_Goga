# R03-TD-BF-09

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: True
Cost: $1.8731568
Duration: 273931ms, turns: 52

## Agent's own summary

# [PRIMARY_ANALYSIS_REPORT]

## Topic
`request-correlation-id`

## Acceptance Criteria
- Every HTTP response, on both the Express adapter and the Fastify adapter, carries a correlation-ID response header.
- If the inbound request already carries that header, its value is reused verbatim; otherwise a new unique value is generated.
- The same ID is readable by application code (e.g. a route handler) during request handling, without re-parsing the outgoing response.
- Behavior and the API application code uses to read the ID are identical regardless of adapter — no adapter-specific branching in application code.

## Stack & External Dependencies
TypeScript / Node.js. No new runtime dependency: ID generation reuses `randomStringGenerator` from `packages/common/utils/random-string-generator.util.ts` (already wraps the existing `uid` dependency, exported via `@nestjs/common/internal`). Correlation storage uses Node's built-in `async_hooks.AsyncLocalStorage` — no new dependency. Middleware is a plain connect-style `(req, res, next)` function, registered via the existing `app.use()` / `AbstractHttpAdapter.use()` path, which both `ExpressAdapter` and `FastifyAdapter` (via its vendored middie compatibility layer) already support identically.

## Existing Cells & Schema
9 documented cells (flat, no nesting): `packages/core/interceptors`, `packages/core/pipes`, `packages/core/adapters`, `packages/core/guards`, `packages/core/injector`, `packages/core/router`, `packages/platform-express/adapters`, `packages/platform-fastify/adapters`, `packages/common/exceptions`.

| Cell | Relevance |
|---|---|
| `packages/core/adapters` | Defines `AbstractHttpAdapter.use()`/`getHeader`/`setHeader` — the contract the new cell relies on but does not modify |
| `packages/platform-express/adapters` | Confirms plain middleware works via inherited `use()` — unmodified |
| `packages/platform-fastify/adapters` | Confirms plain middleware works via documented `use()` (middie) — unmodified |
| `packages/core/router` | Composition root for guards/pipes/interceptors; orthogonal to global `app.use()` middleware — unaffected |

## Artifact Resolution

| Name/term | Resolution | Justification |
|---|---|---|
| `packages/core/request-context` | **new artifact** (new cell) | No existing cell owns correlation-ID/async-context concerns; `goga schema` and a source grep confirm nothing in the repo provides an `AsyncLocalStorage` store or request-ID handling today |
| `AbstractHttpAdapter.use/getHeader/setHeader` | **no change** — consumed only | Already generic across both adapters; the new cell composes with it via `app.use()`, does not extend or mutate it |

## Key Concepts
- **`RequestContextStore`** — the shape of data held in the async-local store for the duration of one request (at minimum, the correlation/request ID).
- **`RequestContext`** — static accessor class wrapping a module-scoped `AsyncLocalStorage<RequestContextStore>`; exposes a way to run a callback within a store and to read the current store from anywhere in the async chain (application code, logging, guards, interceptors, controllers).
- **Request-ID middleware factory** — a routine that produces a connect-style `(req, res, next)` function: reads the inbound header, reuses it if present and non-empty, otherwise generates one via `randomStringGenerator`; sets the same value on the outbound response header; then calls `next()` from inside `RequestContext`'s async-local run so the ID is visible for the rest of the request's async execution, including in the route handler.
- **Header name constant** — the single canonical header name used both for reading the inbound value and writing the outbound one (so a chain of internal calls that forward it stays consistent).

## Dark Zones
1. **Canonical header name.** Proposing `X-Request-Id` (industry-standard, e.g. AWS ALB/Heroku convention) as the single header used for both reading and writing. Not configurable in v1 — keeps the surface minimal per the task's scope; can be revisited if teams need a different convention.
2. **Empty/whitespace-only inbound header value.** Proposing: treated as absent — a new ID is generated (a caller sending `X-Request-Id: ` empty should not propagate a blank correlation ID).
3. **Multiple inbound header values (array, from duplicate headers).** Proposing: use the first value, matching standard header-parsing convention (Node normalizes single-value headers to a string; only a few headers like `set-cookie` arrive as arrays — `x-request-id` will be a string when only one is sent, an array in the pathological duplicate case). Middleware will normalize by taking the first array element if an array is encountered.

## Connection to Existing Architecture
No existing documented cell is modified. The new `packages/core/request-context` cell is a leaf with no dependencies on any other documented cell — it depends only on undocumented `packages/common/utils` (for `randomStringGenerator`) and Node's built-in `async_hooks`, neither of which appears in `goga schema`. It is consumed by application/bootstrap code via the pre-existing `app.use()` mechanism (`packages/core/adapters` `AbstractHttpAdapter.use`), which requires no change since it is already adapter-agnostic and already used for global middleware today.

## Risks and Constraints
- Must not require any per-adapter branching in the public API application code uses to read the current ID (hard constraint from the task).
- Must not add a new runtime dependency (soft constraint, satisfied by reusing `randomStringGenerator`/`uid`).
- AsyncLocalStorage context must survive Nest's internal guard/pipe/interceptor pipeline; codebase precedent (`packages/core/interceptors/interceptors-consumer.ts` `AsyncResource.bind` around RxJS `defer()`) confirms the framework already preserves async-local context across that pipeline, so no further internal-pipeline changes are needed.
- Middleware must run before Nest's own route dispatch on both adapters (ordinary `app.use()` global-middleware registration order, no different from any other Nest global middleware today).

## Scope Decision
Single subsystem — proceeding as one cell.

## Notes
This is intentionally scoped as a small, self-contained addition: one new leaf cell, zero modifications to the 9 already-documented cells, and zero new runtime dependencies.

---

Two small default decisions I'm proposing above (header name `X-Request-Id`, and treating empty/duplicate-array header values as "absent"/"take first") — reasonable industry-standard defaults, or would you like different behavior (e.g. a different header name, or reading multiple possible header names)?
