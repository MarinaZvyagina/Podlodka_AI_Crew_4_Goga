# R03-TD-GC-07

Condition: goga_native_architecture
Base tag: condition-c-r03-v1
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: True
Cost: $2.1045234
Duration: 284499ms, turns: 52

## Agent's own summary

## Investigation Report

### Task Summary
Requested: a cross-adapter correlation/request-ID feature — every HTTP response carries a unique ID header, reusing an inbound header value when the caller already supplies one (so IDs propagate across internal service-to-service call chains) and generating one otherwise; the ID must be readable by application code during request handling via a simple accessor, without parsing the response; behavior must be byte-for-byte identical on `platform-express` and `platform-fastify`; and it must be configurable via `NestApplicationOptions`, mirroring the existing `cors`/`rawBody` option pattern.

### Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `packages/core/adapters` | Owns `AbstractHttpAdapter`, including the `setOnRequestHook`/`setOnResponseHook`/`setHeader`/`getHeader` surface the feature is built on | High |
| `packages/platform-express/adapters` | Concrete Express implementation of that surface | High |
| `packages/platform-fastify/adapters` | Concrete Fastify implementation of that surface | High |
| `packages/core/router/request` (existing sibling cell) | Precedent/pattern for a small, dependency-free "shared primitive" cell under `packages/core/router/` | Medium (pattern reference only, not modified) |

### Tracing Summary

**Express hook wiring** (`packages/platform-express/adapters/express-adapter.ts:69-82`):
```
constructor(instance) → super(instance || express())
  → this.instance!.use((req, res, next) => {
      if (onResponseHook) res.on('finish', () => onResponseHook(req, res))
      if (onRequestHook) onRequestHook(req, res, next)
      else next()
    })
```
This `.use()` call runs **inside the constructor**, i.e. before `registerParserMiddleware` (`nest-application.ts:205-209`), before user middleware (`registerMiddleware` at `nest-application.ts:212`), and before route registration (`registerRouter` at `nest-application.ts:211-230`, called after `registerMiddleware`). Express dispatches middleware in registration order, so this hook is guaranteed to run first on every request, for every route, prefix, and error path.

**Fastify hook wiring** (`packages/platform-fastify/adapters/fastify-adapter.ts:266-283`):
```
constructor(...) → this.instance.addHook('onRequest', (request, reply, done) => {
    if (onRequestHook) onRequestHook(request, reply, done)
    else done()
  })
  this.instance.addHook('onResponse', (request, reply, done) => {
    if (onResponseHook) onResponseHook(request, reply, done)
    else done()
  })
```
Also registered in the constructor, so both hooks are attached before `registerMiddie()` (`init()`, line ~277-286) and before any route or parser registration. Fastify's `onRequest` lifecycle hook fires before routing and before body parsing — mirrors Express's timing.

**Bootstrap order** (`packages/core/nest-application.ts:177-203`, `init()`):
```
init()
 → applyOptions()                     // cors only, today
 → httpAdapter.init()                 // Fastify: registers middie + flushes queued .use()
 → registerParserMiddleware()         // if bodyParser !== false
 → registerModules()                  // → registerMiddleware(httpAdapter) is NOT here; see registerRouter
 → registerRouter()
     → registerMiddleware(httpAdapter)   // user NestModule middleware (app.use/configure())
     → route registration (routesResolver.resolve/registerResolvedRoute)
 → callInitHook()
 → registerRouterHooks()              // registerNotFoundHandler + registerExceptionHandler only
 → callBootstrapHook()
```
Since both adapters attach the request/response hooks in their **constructors** (which run before `init()` is ever called — the adapter instance is constructed by `NestFactory` prior to being handed to `NestApplication`), calling `httpAdapter.setOnRequestHook(...)` / `setOnResponseHook(...)` at any point before the server starts accepting connections (e.g. early in `NestApplication.init()`, alongside `applyOptions()`) is sufficient — the constructor-installed wrapper closures read `this.onRequestHook`/`this.onResponseHook` dynamically on every request, not just once at construction time.

### Data Flow Analysis
1. Inbound request arrives → adapter's constructor-installed wrapper fires the configured `onRequestHook(request, response, done/next)` before any parser, user middleware, or route handler runs.
2. Hook reads `request.headers[configuredHeaderName.toLowerCase()]` — confirmed uniformly available as a plain lowercased-key object on both `express.Request` (Node `http.IncomingMessage` subtype) and Fastify's `FastifyRequest` (same lookup pattern already used at `fastify-adapter.ts:217-235` for version-header extraction, confirming this exact access pattern is an established convention in this codebase).
3. Hook resolves the ID (reuse inbound value or generate), writes it onto the response via `httpAdapter.setHeader(response, headerName, id)` — response object here is `express.Response` (has `.set()`, per `express-adapter.ts:208`) for Express, and Fastify's `reply` (has `.header()`, per `fastify-adapter.ts:607`) for Fastify — both already implement `setHeader` against exactly the object type the hook receives.
4. Hook then invokes `done()`/`next()` from *inside* an `AsyncLocalStorage.run(id, () => done())` call, so the ID remains retrievable via `storage.getStore()` from anywhere in the synchronous-and-asynchronous continuation of that call — i.e., through route matching, guards, interceptors, the controller method (including awaited work), and exception filters — because Node's `AsyncLocalStorage` propagates through the async continuations spawned inside `.run()`, not just the synchronous frame.
5. Because the header is written in step 3, before headers are sent (`response.headersSent` is false at `onRequest` time on both platforms), it survives through to the final response regardless of which code path produces that response (success, 404, or exception filter), since nothing downstream needs to re-set it.

### Manifest Algorithm Analysis
- `packages/platform-express/adapters/CODEMANIFEST` already documents, for the `ExpressAdapter` constructor: *"Register a root-level middleware that runs the configured request/response hooks around every request, ahead of any route-specific middleware."*
- `packages/platform-fastify/adapters/CODEMANIFEST` already documents, for the `FastifyAdapter` constructor: *"Register onRequest/onResponse hooks that delegate to configured request/response hook callbacks."*

Both manifests already describe this exact mechanism as **the intended purpose** of `setOnRequestHook`/`setOnResponseHook` — "configured request/response hooks" — even though nothing in the framework currently configures them. This is strong pre-existing design confirmation, not a repurposing: the contract was authored anticipating a consumer like this feature.

- `packages/core/adapters/CODEMANIFEST`, by contrast, does **not** document `setOnRequestHook`/`setOnResponseHook`/`getHeader`/`setHeader`/`appendHeader` at all, even though `http-adapter.ts` defines them (lines 168-170, 193-195). This is pre-existing manifest drift, unrelated to this change (these methods predate this investigation) — noted for Step 9 (Drift Analysis) as something to reconcile, not something this change caused.

### Affected Usages

| Usage | Cell | Classification | Reason |
|---|---|---|---|
| *(none exist)* | — | — | `goga schema` and `.goga/config.yml` confirm zero declared `.usages` practices on any of the three candidate cells and no project-level `codemanifest.usages`. No existing usage is affected. A new cell-level `.usages` file will be authored for the new cell (consumer-facing: how to read the ID). |

### Rejected Hypotheses

1. **"Wire the ID logic as ordinary `app.use()` middleware instead of the hook mechanism."** Rejected: `app.use()` middleware is registered per-instance timing-dependent on `registerMiddleware()`/user call order (`nest-application.ts:212`) and, for Fastify, depends on `middie` being ready (`init()`), which is *after* the adapter constructor. Using the existing constructor-installed hook is provably earlier and already identical in shape across both adapters — no ordering risk.
2. **"Duplicate the ID logic separately inside `ExpressAdapter` and `FastifyAdapter`."** Rejected per requirement 6 (adapter-agnostic core) and because it would violate the single-cell-per-responsibility rule — the whole point of `AbstractHttpAdapter`'s shared hook surface is to avoid this duplication, and both manifests already frame the hooks that way.
3. **"Store the ID only on the request object (e.g. `request.id`) instead of AsyncLocalStorage."** Rejected: requirement 4 demands accessor-based retrieval "without parsing the response," and a per-adapter request-object property would still require application code to know which adapter's request shape it's holding (`req.id` vs `request.id` conventions differ) — violates requirement 5 (no adapter-specific app code). AsyncLocalStorage gives one uniform accessor regardless of adapter.
4. **"Reuse `REQUEST_CONTEXT_ID`/`REQUEST` DI primitives from `packages/core/router/request` for this."** Rejected: that cell's `REQUEST_CONTEXT_ID` is a DI-container context-id cache key (for provider resolution), an unrelated concept from a correlation ID string; conflating them would overload that cell's single responsibility. Kept as a separate new cell.

### Confirmed Root Cause
Not a bug fix — a net-new capability. Root mechanism confirmed: `AbstractHttpAdapter.setOnRequestHook`/`setOnResponseHook` (defined at `packages/core/adapters/http-adapter.ts:168,170`) are implemented identically in shape by `ExpressAdapter` (`packages/platform-express/adapters/express-adapter.ts:62-98`) and `FastifyAdapter` (`packages/platform-fastify/adapters/fastify-adapter.ts:157-166,266-283,293-305`), are wired before any parsing/routing/user-middleware on both platforms, are currently unused by any framework code or test (verified via repo-wide grep — zero call sites), and are already documented in both platform manifests as existing specifically for "configured request/response hooks." This is the correct, evidence-backed integration point.

### Confidence Level
**HIGH** — every claim above is backed by a specific file:line reference read directly from source, cross-checked against both adapters' CODEMANIFEST files, and confirmed by an exhaustive repo-wide grep showing zero competing usage of the hook slots.

### Breaking Change Assessment
1. Will an existing function call with the same arguments produce different behavior? **NO** — `setOnRequestHook`/`setOnResponseHook` currently no-op by default; nothing currently calls them, so wiring them is purely additive. All other existing methods/signatures are untouched.
2. Will existing file paths change? **NO** — only new files are added (new cell) plus additive edits to `nest-application.ts` and `nest-application-options.interface.ts`.
3. Will output format change? **NO** — responses are unchanged unless the new `requestId` option is explicitly enabled by the application.
4. Will return value semantics change? **NO** — no existing method's return value or type changes.
5. Will manifest-defined guarantees be altered? **NO** — no existing CODEMANIFEST-documented method signature or algorithm changes; the new cell adds a new, separate contract. (Pre-existing drift on `packages/core/adapters/CODEMANIFEST` re: undocumented `setOnRequestHook` etc. is noted for reconciliation but is not *caused* by this change.)
6. Will existing tests break? **NO** — grep confirms no test in `packages/platform-express/test`, `packages/platform-fastify/test`, or `packages/core/test` references these hooks; the feature is opt-in via a new, default-unset `requestId` option, so default application behavior (option absent) is unchanged.

**No breaking change detected.** Proceeding to Step 3: Planning.
