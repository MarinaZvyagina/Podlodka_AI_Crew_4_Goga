# R03-TD-BF-01

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: False
Cost: $1.5067356000000005
Duration: 335059ms, turns: 42

## Agent's own summary

# [PRIMARY_ANALYSIS_REPORT]

## Topic
`request-id-propagation`

## Acceptance Criteria
- Every HTTP response from a Nest application includes a correlation/request-ID response header, on both the Express and Fastify adapters, for every response (success, error, 404, redirect).
- If the inbound request already carries that header, its value is reused verbatim; otherwise a new unique ID is generated.
- Application code (e.g. a route handler or a service) can read the exact same ID that will appear on the response header, without parsing it back out of the response, via one API that behaves identically regardless of which adapter the app is running on.

## Stack & External Dependencies
Node.js built-ins only: `AsyncLocalStorage` (`node:async_hooks`) for cross-async-boundary storage, `randomUUID` (`node:crypto`) for default ID generation. No new npm dependency. Integrates with existing `AbstractHttpAdapter` hook surface (`setOnRequestHook`) already implemented by `ExpressAdapter` and `FastifyAdapter`.

## Existing Cells & Schema
9 documented cells: `packages/core/{interceptors,pipes,adapters,guards,injector,router}`, `packages/platform-express/adapters`, `packages/platform-fastify/adapters`, `packages/common/exceptions`.

| Cell | CODEMANIFEST | Relevance |
|---|---|---|
| `packages/core/adapters` | `packages/core/adapters/CODEMANIFEST` | Owns `AbstractHttpAdapter`; the new cell depends on its `setOnRequestHook`/`setHeader` surface — currently implemented in code but undocumented in this manifest. |
| `packages/platform-express/adapters` | `packages/platform-express/adapters/CODEMANIFEST` | Concrete mutation satisfying the adapter contract; no new types, no manifest change needed. |
| `packages/platform-fastify/adapters` | `packages/platform-fastify/adapters/CODEMANIFEST` | Same, for Fastify. |
| `packages/core/router` | `packages/core/router/CODEMANIFEST` | Not touched — the request-ID hook runs earlier, at the adapter level, before routing. |

`packages/core/nest-application.ts` (bootstrap) and `packages/common/interfaces/nest-application-options.interface.ts` (app options) are real files with **no CODEMANIFEST** — undocumented by the system already; touched as plain wiring, not as cells.

## Artifact Resolution
| Name/term | Resolution | Justification |
|---|---|---|
| `AbstractHttpAdapter.setOnRequestHook` / `.setHeader` | **modify** `packages/core/adapters` | Already implemented by both concrete adapters but absent from the CODEMANIFEST; this feature makes it a real, relied-upon contract, so the gap should be closed. |
| Request-ID storage/propagation mechanism (new class) | **new artifact** in **create new cell** `packages/core/context` | No existing cell owns cross-cutting per-request storage; smallest cohesive new surface. |
| `RequestIdOptions` (header name + generator config) | **new artifact**, placed in `packages/common` (interfaces), not inside the new `packages/core/context` cell | Mirrors the existing `CorsOptions` pattern: adapter-facing option types live in `common/interfaces` so `NestApplicationOptions` (also in common) can reference them without common depending on core. |
| `NestApplication` bootstrap wiring | **modify**, undocumented file (no cell) | Calls the new cell's API once during `init()`; not part of the documented schema today, so no CODEMANIFEST update is applicable — flagged as a known gap, out of this change's scope to fix (would require documenting the whole `nest-application.ts`, which is unrelated to this feature). |

## Key Concepts
- **RequestIdStorage** — `AsyncLocalStorage<string>`-backed static store: `run(id, callback)`, `get(): string | undefined`.
- **RequestIdOptions** — `{ header?: string; generator?: () => string }`, consumed via `NestApplicationOptions.requestId?: boolean | RequestIdOptions`.
- **Bootstrap wiring** — `NestApplication.init()` registers one `setOnRequestHook` callback on the active `httpAdapter` that: reads the inbound header (case-insensitive, via the raw `request.headers` object — identical shape on both Express and Fastify since both sit on Node's `http.IncomingMessage`), falls back to the generator, calls the adapter's existing `setHeader` to stamp the response, then runs the remainder of the request inside `RequestIdStorage.run(id, next)`.

## Dark Zones
Resolved with defaults below (flagging for your one-shot approval rather than a multi-round interview, given the spec is already unambiguous):
1. **Default header name** → `X-Request-Id` (industry-standard default; configurable via `RequestIdOptions.header`).
2. **Default on/off** → enabled by default (`requestId` option defaults to `true`; explicit `requestId: false` opts out), since the stated goal is "every response," not "every response for apps that remember to opt in."
3. **ID format** → `crypto.randomUUID()` default, overridable via `RequestIdOptions.generator`.
4. **Public export surface** → `RequestIdStorage` exported from `@nestjs/core` (co-located with the adapters/bootstrap code that populates it), rather than `@nestjs/common`.

## Connection to Existing Architecture
- New cell `packages/core/context` depends on `packages/core/adapters` (type-only: it doesn't call adapter methods itself, but the bootstrap wiring that uses both lives in `nest-application.ts`).
- `packages/platform-express/adapters` and `packages/platform-fastify/adapters` are exercised as-is (no code changes) — their existing `setOnRequestHook`/`setHeader` implementations are the mechanism this feature activates for the first time.
- No changes to `packages/core/router`, guards, pipes, interceptors, or `packages/common/exceptions`.

## Risks and Constraints
- **AsyncLocalStorage continuity**: the hook must call `next()`/`done()` *inside* `RequestIdStorage.run()` (not after) so the context propagates through the rest of the request's async chain — standard, well-established pattern (same technique used by `@fastify/request-context`).
- **Header casing/collisions**: reading `request.headers[name.toLowerCase()]` is required since Node lowercases inbound header keys; must not assume `req.headers['X-Request-Id']` works.
- **Backward compatibility**: defaulting the option to "on" adds a response header to every existing app that upgrades — acceptable per the stated requirement ("every response"), and a one-line `requestId: false` fully opts out.
- **Adapters without hook support**: any third-party `AbstractHttpAdapter` subclass that doesn't override `setOnRequestHook` silently gets no header — acceptable, out of scope (task only requires parity between Express and Fastify).

## Scope Decision
Single subsystem — proceed.

## Notes
Given the feature is fully specified and small, remaining brainstorm phases (type map, type detail, cell distribution, contracts, cell assembly) will be produced in one consolidated pass and presented together for a single approval, rather than as separate multi-turn gates.
