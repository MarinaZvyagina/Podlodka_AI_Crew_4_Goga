# R03-TD-G-03

Condition: goga
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Cost: $2.1820616999999998
Duration: 386460ms, turns: 51

## Agent's own summary

## Change Plan

### Task Classification
**Feature** (additive extension) — new opt-in capability built entirely on existing, unused, already-symmetric adapter API. No modification to existing adapter behavior.

### Affected Cells
| Cell | Files to Modify | What Changes |
|---|---|---|
| *(new)* `packages/core/request-context` | `request-context.ts` (new), `request-context.util.ts` (new), `index.ts` (new), `CODEMANIFEST` (new), `.usages/request-id.md` (new) | New cell created from scratch |
| `packages/core` (facade) | `index.ts` | Add `export * from './request-context/index.js';` |
| `packages/core/adapters` | `CODEMANIFEST` only | Document the pre-existing, previously-undocumented `setOnRequestHook`/`setOnResponseHook` methods on `AbstractHttpAdapter`. No source code change to `http-adapter.ts`. |
| `packages/platform-express/adapters` | none | Consumed as-is; no modification |
| `packages/platform-fastify/adapters` | none | Consumed as-is; no modification |

### Root Cause Analysis
Not a defect — a capability gap. `AbstractHttpAdapter.setOnRequestHook`/`setOnResponseHook` are fully implemented and symmetric on both `ExpressAdapter` and `FastifyAdapter` (confirmed by direct code read and grep), but nothing in the framework currently calls them. This plan adds the first consumer.

### Trace Summary
The adapter-constructor-registered hook fires first, before routing/404/error handling, for every request on both platforms, with `req`/`res` (or `request`/`reply`) objects that persist unchanged through to the eventual response. `setHeader` called inside the hook therefore reliably lands on the outgoing response regardless of which code path (matched route, 404, thrown error, streamed file) ultimately produces it.

### Change Strategy
1. **`packages/core/request-context/request-context.ts`** — `RequestContext` class: a module-level `const storage = new AsyncLocalStorage<string>();`, `static run<T>(id: string, callback: () => T): T` delegating to `storage.run`, `static getRequestId(): string | undefined` delegating to `storage.getStore()`.
2. **`packages/core/request-context/request-context.util.ts`** — `useRequestContext(httpAdapter: AbstractHttpAdapter, options?: { header?: string })`:
   - `const header = (options?.header ?? 'x-request-id').toLowerCase();`
   - Calls `httpAdapter.setOnRequestHook((req, res, done) => { const incoming = req.headers?.[header]; const id = (Array.isArray(incoming) ? incoming[0] : incoming) || uid(32); httpAdapter.setHeader(res, header, id); RequestContext.run(id, () => done()); });`
   - Uses the `uid` package (already a `@nestjs/core` dependency, already used elsewhere in `packages/core` for id generation — e.g. `middleware/utils.ts`, `discovery/discovery-service.ts`) instead of introducing a new dependency for ID generation.
3. **`packages/core/request-context/index.ts`** — `export * from './request-context.js'; export * from './request-context.util.js';`
4. **`packages/core/index.ts`** — add the new barrel export, alongside the existing `export * from './router/index.js';` / `export * from './services/index.js';` lines, so `RequestContext`/`useRequestContext` are importable as `from '@nestjs/core'` — identical import regardless of `@nestjs/platform-express` or `@nestjs/platform-fastify`.
5. **`packages/core/adapters/CODEMANIFEST`** — add `setOnRequestHook`/`setOnResponseHook` method entries to the `AbstractHttpAdapter` type body (documenting existing, unchanged behavior).
6. **New `packages/core/request-context/CODEMANIFEST`** — `Imports: Types: [AbstractHttpAdapter], From: packages/core/adapters`. Body declares `RequestContext` (Entity: `run`, `getRequestId` methods) and `useRequestContext` (Routine, mutating/consuming `AbstractHttpAdapter`).
7. **New `packages/core/request-context/.usages/request-id.md`** — consumer practice: call `useRequestContext(app.getHttpAdapter())` once after `NestFactory.create(...)`, and read the ID anywhere during request handling via `RequestContext.getRequestId()` — same code on Express or Fastify.

### Specification Impact
- `packages/core/adapters/CODEMANIFEST`: **additive** — two new `methods` entries on the existing `AbstractHttpAdapter` type documenting real, already-implemented, already-symmetric behavior. No existing entry's text changes.
- New `packages/core/request-context/CODEMANIFEST`: net-new cell manifest, following the same Header/Body/Footer structure and `Author: Goga` convention as the other 9 manifested cells.
- `packages/platform-express/adapters/CODEMANIFEST`, `packages/platform-fastify/adapters/CODEMANIFEST`: **unchanged** — no new obligations placed on either adapter; they remain pure providers of the hook/header contract already documented in their existing algorithm steps.

### Usage Impact
- No existing `.usages` files exist in any of the three currently-manifested cells (confirmed in Investigation), so nothing existing is revised.
- One new `.usages/request-id.md` is added to the new cell, documenting the bootstrap call and the read-side API for consumers — this is the only usage-file change.

### Compatibility Verification
**Backward compatible.** No existing public method signature, return value, file path, or documented algorithm changes. The only code that runs differently is code that explicitly opts in by calling the new `useRequestContext(...)` function — applications that don't call it see zero behavioral change. `AbstractHttpAdapter`, `ExpressAdapter`, `FastifyAdapter` source files are untouched.

### Test Strategy
- New unit tests for `RequestContext` (`run`/`getRequestId` correctness, including nested/absent-context return `undefined`).
- New unit tests for `useRequestContext`: (a) generates an ID and calls `setHeader` + `done`/`next` when no inbound header is present; (b) reuses the inbound header value verbatim instead of generating one; (c) the generated/reused ID is readable via `RequestContext.getRequestId()` from inside the `done` callback (proving the AsyncLocalStorage scope is active for downstream code) — run once against a mock `AbstractHttpAdapter`-shaped object exposing `setOnRequestHook`/`setHeader` to prove adapter-agnostic behavior.
- One integration-style test per platform adapter (`platform-express`, `platform-fastify`) is the strongest evidence of "works identically on both": boot a minimal Nest app on each adapter with `useRequestContext` enabled, issue a request with no ID header and assert the response header exists and is non-empty and a route handler observed the same ID via `RequestContext.getRequestId()`; issue a second request with a preset `x-request-id` header and assert the response header echoes that exact value. This directly targets requirements 1, 2, and 4.

### Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Multiple `useRequestContext` calls or conflicting hook consumers overwrite each other (`setOnRequestHook` accepts only a single function) | Low | Medium | Document in `.usages/request-id.md` that `useRequestContext` should be called exactly once, and that it does not compose with a separately user-set `setOnRequestHook` — out of scope for this change since no other consumer exists yet |
| Inbound header value is an array (some Node header edge cases) or empty string | Medium | Low | Explicit handling: `Array.isArray(incoming) ? incoming[0] : incoming`, and falsy (including empty-string) values fall through to generating a fresh ID |
| AsyncLocalStorage scope not preserved across an interceptor's async boundary (per existing `transformDeferred` comment concern) | Low | Medium | `RequestContext.run` wraps `done()`/`next()` synchronously at the top of the hook, which is the same pattern Node's `AsyncLocalStorage` guarantees propagates through the entire async chain spawned from that call — consistent with the codebase's existing async-context assumptions noted in `interceptors-consumer.ts` |
| New cell's `CODEMANIFEST` disagrees with what gets implemented | Low | Low | Manifest reconciliation (Step 7) runs after implementation to verify consistency |

---

Do you approve the plan? Proceed to implementation?
