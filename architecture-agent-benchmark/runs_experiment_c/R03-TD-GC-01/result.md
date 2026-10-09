# R03-TD-GC-01

Condition: goga_native_architecture
Base tag: condition-c-r03-v1
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: True
Cost: $1.2972017999999996
Duration: 225120ms, turns: 32

## Agent's own summary

## Scope Resolution Report

### Task Summary
Add a framework-level correlation/request-ID feature that (1) puts a unique ID on every HTTP response header, (2) reuses an inbound header value when the caller already sent one so IDs propagate across chained internal calls, (3) exposes that ID to application code during request handling (e.g. for logging) without re-parsing the response, and (4) behaves identically on the Express and Fastify platform adapters with no adapter-specific application code.

### Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `packages/core/router` | `RoutesResolver.resolve()` receives the `applicationRef` (httpAdapter) exactly once per app bootstrap, before any routes are registered — the correct single place to install one adapter-agnostic request hook | High |
| `packages/core/adapters` | `AbstractHttpAdapter` already declares `setOnRequestHook`/`setOnResponseHook`/`setHeader`/`getHeader`/`isHeadersSent` as the adapter-agnostic contract; the feature consumes this existing extension point rather than adding to it | High |
| `packages/platform-express/adapters` | `ExpressAdapter` already implements `onRequestHook` (fired as the very first middleware, before `next()`) and `setHeader` via `response.set` | High |
| `packages/platform-fastify/adapters` | `FastifyAdapter` already implements `onRequestHook` via Fastify's native `onRequest` hook (fires before routing) and `setHeader` via `response.setHeader` | High |
| New cell (not yet created), sibling to `packages/core/router/request` | Needs a small AsyncLocalStorage-backed store + header-name constant + id-generation + a plain accessor function that application code imports — mirrors why `packages/core/router/request` was split out as its own cell (a small, reusable, dependency-free primitive shared by callers on both sides of a would-be cycle) | High |

### Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| `packages/core/adapters` | Defines the `AbstractHttpAdapter` contract (`setOnRequestHook`, `setHeader`, `getHeader`) that both platform adapters implement and that the router will call polymorphically — no adapter-specific code needed in the calling cell |
| `packages/platform-express/adapters` | Concrete Express behavior for the hook timing and header write path must be verified to match Fastify's |
| `packages/platform-fastify/adapters` | Concrete Fastify behavior for the hook timing and header write path must be verified to match Express's; also confirms `onRequest` fires before body parsing/middie, so the ID is available before user middleware/handlers run |

### Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `packages/core/injector` | No DI/provider changes are required — the accessor is a plain function reading an AsyncLocalStorage store, not a request-scoped injectable; DI participation would be speculative scope expansion |
| `packages/core/router/request` | Documents the unrelated `REQUEST` DI-scope token mechanism (new DI context per request). Architecturally analogous (small split-out primitive) but not a behavioral dependency of this feature — informs design only, not touched |
| `packages/core/router/interfaces` | Shared router data/extension-point contracts; nothing in this task changes route resolution shapes or filter/resolver interfaces |
| `packages/core/guards` / `packages/core/pipes` / `packages/core/interceptors` | These compose around a resolved route handler; the ID must be present before them (at the adapter-hook level), so none of these has behavioral participation |
| `packages/common/exceptions` | No new or changed exception types are needed for this feature |
| `packages/platform-express/adapters/utils`, `packages/platform-fastify/adapters/middie` | Sub-cells for body-parser options / middie middleware shape, unrelated to header/hook wiring |

### Usage Relationships

| Usage | Relevance |
|---|---|
| None declared on any candidate cell (`usages: []` for all of them in `goga schema`) | No existing `.usages` practice files apply; none need updating for this task beyond whatever the new cell defines for its own consumers |

### Semantic Participation Summary
- **`packages/core/router`**: owns the one-time bootstrap point where the request-ID hook gets registered on the adapter, ahead of route dispatch — this is where the feature is "switched on" application-wide with no per-app opt-in.
- **`packages/core/adapters`**: supplies the polymorphic contract (`setOnRequestHook`, `setHeader`, etc.) that lets the router cell stay 100% adapter-agnostic — confirms no new abstract methods are needed, this is pure consumption of an existing, currently-unused extension point.
- **`platform-express/adapters`** and **`platform-fastify/adapters`**: each already fires its `onRequestHook` at the earliest point in its respective request lifecycle and already exposes a working `setHeader`; both must be exercised to confirm identical externally observable behavior (header present, correct value, ID readable by app code) since this is the crux of requirement 4.
- **New sibling cell** (working name `packages/core/router/request-id`): owns the actual state — AsyncLocalStorage store, header constant, ID generation/reuse decision, and the public accessor function application code calls. This is genuinely new responsibility with no existing cell home; `packages/core/router` will import its types the same way it already imports `REQUEST_CONTEXT_ID` from `packages/core/router/request`.

### Final Investigation Scope
1. `packages/core/adapters`
2. `packages/platform-express/adapters` (+ confirm no impact on `packages/platform-express/adapters/utils`)
3. `packages/platform-fastify/adapters` (+ confirm no impact on `packages/platform-fastify/adapters/middie`)
4. `packages/core/router` (specifically `RoutesResolver`/`routes-resolver.ts`)
5. New cell to be created: `packages/core/router/request-id`

### Scope Risks
- **Under-scoping risk**: if the public accessor function needs to be exported from `@nestjs/core`'s package facade (`packages/core/index.ts`), that file sits outside any cell (no CODEMANIFEST at `packages/core/` root) — the Implementation step must still update it even though it's not a governed cell; flagging now so it isn't missed as "out of scope."
- **Over-scoping risk**: it would be tempting to also touch `packages/core/injector` to offer a DI-injectable version (e.g. `@Inject(REQUEST_ID)`) for symmetry with the existing `REQUEST` token pattern — excluded here because the task only requires plain accessibility from application code (a route handler calling a function), and DI-scoped injection was not requested and would enlarge the diff considerably.
- **Hook-collision risk**: `setOnRequestHook`/`setOnResponseHook` each hold a single callback (not a chain/array) on both adapters. If any other framework feature ever needs the same hook, they'd collide — out of scope for this task (nothing currently uses these hooks, confirmed via repo-wide grep), but worth the Investigation step confirming no other in-flight cell already claims them.

### Notes
- `goga schema` confirms zero existing consumers of `setOnRequestHook`/`setOnResponseHook` repo-wide — this extension point exists in the contract but is currently dead code, strongly suggesting it was placed there for exactly this kind of adapter-agnostic request-lifecycle feature.
- Fastify's `onRequest` hook fires before routing and before the `middie` (Express-style middleware) shim; Express's hook fires as the very first `app.use()` — both are "earliest possible" points in their respective adapters, which satisfies requirement 3 (ID available throughout handling) and requirement 1 (header can be set before any handler writes the response).
- `AbstractHttpAdapter.setHeader` is already abstracted, so header writing needs no new abstract method — only a call site in the new cell's hook implementation, invoked from wherever the hook is registered.
