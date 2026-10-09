# R03-TD-BF-04

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: False
Cost: $1.2334043999999997
Duration: 280562ms, turns: 45

## Agent's own summary

# [PRIMARY_ANALYSIS_REPORT]

## Topic
`http-request-id` (correlation ID propagation across HTTP responses)

## Acceptance Criteria
- Every HTTP response (success, exception-filter error, and unmatched-route 404) carries a response header with a unique correlation ID.
- If the inbound request already carries that header, the same value is echoed back and used — not a freshly generated one.
- Application code (handlers, services, interceptors, filters) can read the current request's ID via one API call, with no branching on which HTTP adapter is active.
- Identical behavior, with zero required per-app configuration, on both `@nestjs/platform-express` and `@nestjs/platform-fastify`.

## Stack & External Dependencies
Node built-ins only: `node:crypto` (`randomUUID`) for ID generation, `node:async_hooks` (`AsyncLocalStorage`) for the platform-agnostic read API. No new npm dependency.

## Existing Cells & Schema
9 documented cells (see `[PROJECT_CONTEXT_REPORT]`). Directly relevant: `packages/core/adapters` (`AbstractHttpAdapter`, including the currently-undocumented `setOnRequestHook`/`setOnResponseHook`), `packages/platform-express/adapters` (`ExpressAdapter`), `packages/platform-fastify/adapters` (`FastifyAdapter`).

## Artifact Resolution

| Name/term | Resolution | Justification |
|---|---|---|
| Request-ID extraction/generation + response-header write | **new artifact** — `RequestIdHook` (routine/factory) | No existing type owns "read inbound header, generate if absent, write outbound header" |
| Request-scoped readable ID store | **new artifact** — `RequestIdStorage` (entity, `AsyncLocalStorage`-backed) | No existing platform-agnostic per-request context store exists in the repo |
| Header name constant | **new artifact** — constant in the new cell | Needs one canonical name shared by hook + storage |
| `AbstractHttpAdapter.setOnRequestHook/setOnResponseHook` | **modify existing cell** `packages/core/adapters` — add these two methods to its CODEMANIFEST | They already exist in source (base class + both platform adapters) but are undocumented and have zero callers today; the new cell becomes their first real consumer, so the contract should describe them accurately |
| `ExpressAdapter` / `FastifyAdapter` | **no change** | Both already implement the hook plumbing correctly; nothing to modify |
| Wiring into app bootstrap | **new, minimal edit** to `nest-application.ts` (undocumented file, not a cell) | Registers the hook during `init()`, same pattern as existing `registerParserMiddleware()` call |

## Key Concepts
- **`RequestIdHook`** — a factory producing the `(req, res, done) => void` function registered via `setOnRequestHook`. Reads the inbound header, falls back to `randomUUID()`, writes the outbound header via `AbstractHttpAdapter.setHeader`, then runs the rest of the request inside an `AsyncLocalStorage.run(id, ...)` context before calling `done()`.
- **`RequestIdStorage`** — thin wrapper around one process-wide `AsyncLocalStorage<string>`, exposing `getId(): string | undefined` for app code to call from anywhere during request handling (guards, pipes, interceptors, controllers, services, exception filters) — same call, regardless of adapter.
- **Header name constant** — one canonical header name (default `x-request-id`) shared by both the hook and any documentation.

## Dark Zones (resolved with recommended defaults — flag if you want different)
1. **Header name**: default to `x-request-id` (the de facto standard; e.g. Heroku/AWS ALB convention) rather than `x-correlation-id`.
2. **ID format**: `crypto.randomUUID()` (UUID v4, Node builtin, no dependency).
3. **Hook point**: register via the existing `setOnRequestHook` extension point — *not* a new `NestModule`-style middleware (that requires user opt-in per route) and *not* `RouterExecutionContext` (misses 404s/transport errors). This is why the fix is "automatic on every response" for free.
4. **Cell placement**: new cell at `packages/core/request-id`, a sibling of `packages/core/guards`/`pipes`/`interceptors`/`adapters` — same "extension mechanism" shape as those.
5. **Public read API name**: `RequestIdStorage.getId()`, exported from `@nestjs/core`.

## Connection to Existing Architecture
```
packages/core/request-id  (NEW)
   depends on
      packages/core/adapters  (AbstractHttpAdapter.setHeader, +setOnRequestHook/setOnResponseHook — CODEMANIFEST updated)

packages/platform-express/adapters ─┐
packages/platform-fastify/adapters ─┴─ already implement setOnRequestHook/setOnResponseHook (no change)

nest-application.ts (undocumented) ─ calls setOnRequestHook(createRequestIdHook(...)) during init(), consuming
                                       packages/core/request-id the same way it already consumes packages/core/router
```
No existing cell's public contract changes in a breaking way; `packages/core/adapters` gains two documented methods it already has in source (no source change, doc-only addition to that CODEMANIFEST).

## Risks and Constraints
- `AsyncLocalStorage.run()` must wrap the call to `done()`/`next()` (not just the header-setting code) so the context propagates through the entire downstream async chain (routing → guards → pipes → controller → interceptors → exception filters) for both adapters.
- Fastify's `onResponse` hook fires *after* the response is already flushed — headers cannot be set there. This is why generation + header-write both happen in `onRequest`, before any body is sent, not in `onResponse`.
- Must not overwrite an existing `x-request-id` response header if application code already set one deliberately... (open call: default behavior will be "always set/overwrite", since app code has no established convention here yet — flag if you want "set only if absent").

## Scope Decision
Single subsystem — proceeding as one cell.

## Notes
This turns an existing, currently-dead extension point (`setOnRequestHook`/`setOnResponseHook`, present in both adapters with no caller anywhere in the repo) into the mechanism that makes the feature both adapter-agnostic and automatic.

**Please approve this analysis** (or flag any of the 5 dark-zone defaults above you want changed) so I can proceed to the type map.
