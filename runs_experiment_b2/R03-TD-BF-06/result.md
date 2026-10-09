# R03-TD-BF-06

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: True
Cost: $0.8908797
Duration: 169271ms, turns: 29

## Agent's own summary

# [INTAKE_REPORT]

## Task Summary
Design a new architectural surface for the framework core that gives every HTTP response a correlation/request ID header, reusing an inbound ID when the caller already sent one and generating a fresh one otherwise, while making that same ID readable from application code during request handling via an async-context accessor. It must behave identically on both the Express and Fastify platform integrations, and be wired in as an opt-in `NestApplicationOptions.requestId` option plus an `app.enableRequestId(options)` method, mirroring the existing `cors` option/`enableCors()` pattern.

## Description Type
Detailed

## Task-File Sections
N/A

## Original Description
Design a new architectural surface for Nest.js core: a built-in "Request ID" (correlation ID) capability.

Requirements:
- Every HTTP response from a Nest application must include a correlation/request ID response header (default name e.g. "X-Request-Id").
- If the incoming request already carries that header, reuse its value instead of generating a new one, so the ID propagates across a chain of internal service calls.
- If no incoming header is present, generate a new unique ID (e.g. via node:crypto randomUUID).
- The active request's ID must be readable from application code (e.g. inside a controller/service/log call) during that request's handling, without parsing the outgoing response — i.e. via an async-context-based accessor (AsyncLocalStorage), not via decorators tied to a specific HTTP library.
- Must behave identically on both platform integrations this framework supports for HTTP: the Express adapter (packages/platform-express) and the Fastify adapter (packages/platform-fastify). Investigate whether the existing AbstractHttpAdapter#use() registration point (uniform across both adapters, since Fastify's use() is backed by connect-style middleware via its middie integration) is sufficient so one plain middleware implementation covers both, rather than duplicating per-adapter logic.
- Should be opt-in and configurable similarly to the existing `cors` option on NestApplicationOptions (see packages/core/nest-application.ts `applyOptions()`/`enableCors()` and packages/common/interfaces/nest-application-options.interface.ts), i.e. `appOptions.requestId` plus an `app.enableRequestId(options)` method, with an options interface for the header name and ID generator function.
- Existing documented cells to treat as fixed contracts, not to be redesigned: packages/core/adapters, packages/platform-express/adapters, packages/platform-fastify/adapters, packages/core/router, packages/core/injector, packages/core/guards, packages/core/pipes, packages/core/interceptors, packages/common/exceptions.

Produce an architecture plan for the new cell(s) needed (e.g. an AsyncLocalStorage-backed request-id context store, a middleware factory, and the public accessor function/class), including their types, methods, and dependencies on the existing adapters/nest-application surface, ready for goga-apply to materialize.

## Scope Split Decision
Single subsystem — proceed as one brainstorm pass (request-id context store + middleware + application-level wiring form one cohesive capability).
