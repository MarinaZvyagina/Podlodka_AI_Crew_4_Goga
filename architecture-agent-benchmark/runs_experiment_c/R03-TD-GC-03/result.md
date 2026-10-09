# R03-TD-GC-03

Condition: goga_native_architecture
Base tag: condition-c-r03-v1
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: False
Cost: $3.628381800000001
Duration: 613704ms, turns: 60

## Agent's own summary

# Change Plan

## Task Classification
**Feature** (net-new, additive capability) — no bugfix, no refactor of existing behavior.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `packages/core/adapters` (existing) | `CODEMANIFEST` only (no code change — methods already exist) | Add `methods:` entries documenting `setOnRequestHook`, `setOnResponseHook`, `setHeader`, `getHeader`, `isHeadersSent`, `appendHeader` on `AbstractHttpAdapter`, since this change makes `setOnRequestHook`/`setHeader` contractually load-bearing for the first time |
| `packages/platform-express/adapters` (existing) | `CODEMANIFEST` only (no code change) | Add/confirm `methods:` entries for `setHeader`/`getHeader`/`isHeadersSent`/`appendHeader` overrides (`response.set`/`.get`/`.headersSent`/`.append`) — the constructor's existing `Algorithm:` text already references "configured request/response hooks," no change needed there |
| `packages/platform-fastify/adapters` (existing) | `CODEMANIFEST` only (no code change) | Same, for `response.header`/`.getHeader`/`.sent` |
| **New cell** `packages/core/request-id` | `CODEMANIFEST`, `index.ts`, `request-id.constants.ts`, `request-id-storage.ts`, `request-id-middleware.ts`, `.usages/reading-the-request-id.md` | New leaf cell: AsyncLocalStorage-backed storage + accessor, platform-agnostic middleware factory, default header constant |
| `packages/core/nest-application.ts` (uncellified) | `applyOptions()`, new `enableRequestId()` method, import of new cell | Wires the new cell's middleware factory into `httpAdapter.setOnRequestHook` via the existing `getHttpAdapter()` cast, triggered either by the new `NestApplicationOptions.requestId` flag or by calling `enableRequestId()` directly — mirrors the existing `cors` pattern exactly |
| `packages/core/index.ts` (uncellified) | add `export * from './request-id/index.js';` | Public export of `getRequestId` etc. from `@nestjs/core`, alongside the existing `Reflector`/`adapters` exports |
| `packages/common/interfaces/nest-application-options.interface.ts` (uncellified) | add `requestId?: boolean \| RequestIdOptions;` field | Public option surface, mirrors `cors?: boolean \| CorsOptions \| CorsOptionsDelegate<any>;` |
| `packages/common/interfaces/nest-application.interface.ts` (uncellified) | add `enableRequestId(options?: RequestIdOptions): void;` to `INestApplication` | Mirrors existing `enableCors(options?: any): void;` |
| `packages/core/test/request-id/*.spec.ts` (new) | unit tests | Storage/middleware behavior |
| `packages/core/test/nest-application.spec.ts` (existing) | add cases | `applyOptions()`/`enableRequestId()` wiring |
| `integration/request-id/` (new, mirrors `integration/cors` layout) | `src/app.controller.ts`, `src/app.module.ts`, `e2e/express.spec.ts`, `e2e/fastify.spec.ts`, `tsconfig.json` | End-to-end proof: header present on 200, on inbound-ID reuse, on 404, identically on both adapters; `getRequestId()` read from inside a controller equals the response header |

## Root Cause Analysis
Not applicable in the bugfix sense — this is new capability. The enabling gap (from Investigation): no existing mechanism makes a per-request value both (a) set as a response header before every possible response path and (b) readable from application code without touching `req`/`res`. The existing `setOnRequestHook`/`setHeader` adapter surface satisfies (a) today, unused; nothing in the codebase satisfies (b) for HTTP.

## Trace Summary
`NestApplication.init()` → `applyOptions()` (L187, before `httpAdapter.init()` L188 and before `registerParserMiddleware()`/`registerModules()`/`registerRouter()`) is the seam. `enableRequestId()` will call `this.getHttpAdapter().setOnRequestHook(middleware)`, reusing the existing `getHttpAdapter(): AbstractHttpAdapter` cast helper (nest-application.ts:110-112) rather than widening the `HttpServer` interface in `packages/common` — keeps the diff minimal and avoids touching a third, unrelated uncellified interface file. Both adapters' constructors already wire `onRequestHook` as the unconditionally-first `use()`/`onRequest` step, so registering it any time before the first real request (order-independent relative to `httpAdapter.init()`) is safe — confirmed in Investigation.

## Change Strategy
1. **New cell `packages/core/request-id`** (leaf, zero cross-cell dependencies):
   - `request-id.constants.ts` — `export const DEFAULT_REQUEST_ID_HEADER = 'X-Request-Id';`
   - `request-id-storage.ts` — `AsyncLocalStorage<{ requestId: string }>` instance (module-private) + exported `runWithRequestId<T>(requestId: string, callback: () => T): T` (uses `.run`, not `.enterWith`, per hard constraint) + exported `getRequestId(): string | undefined`.
   - `request-id-middleware.ts` — exported `RequestIdOptions` interface (`{ header?: string; generator?: () => string }`) and `createRequestIdMiddleware(setHeader: (response: any, name: string, value: string) => any, options?: RequestIdOptions)`, returning a `(req, res, done: (err?: Error) => void) => void` function that: reads `req.headers[header.toLowerCase()]` (first array element if the client sent it twice), falls back to `options.generator?.() ?? randomUUID()`, calls `setHeader(res, header, id)`, then calls `runWithRequestId(id, () => done())`.
   - `index.ts` — barrel re-exporting all three files' public members, mirroring `packages/core/adapters/index.ts`'s single-line barrel style.
2. **`nest-application.ts`**: add `import { createRequestIdMiddleware, type RequestIdOptions } from './request-id/index.js';`. In `applyOptions()`, before (or after — order doesn't matter, they're independent) the existing `cors` block, add a `requestId` block following the identical `isObject`/boolean branching already used for `cors`. Add `public enableRequestId(options?: RequestIdOptions): void` that builds the middleware via `createRequestIdMiddleware((response, name, value) => this.httpAdapter.setHeader(response, name, value), options)` and calls `this.getHttpAdapter().setOnRequestHook(middleware)`.
3. **Public surface**: add `requestId?: boolean | RequestIdOptions;` to `NestApplicationOptions`; add `enableRequestId(options?: RequestIdOptions): void;` to `INestApplication`; re-export the new cell from `packages/core/index.ts` so app code does `import { getRequestId } from '@nestjs/core';` — identical import regardless of which adapter the app uses, satisfying "no per-platform application code."
4. **Manifest reconciliation** (Step 7 of the outer pipeline): update the three existing cells' CODEMANIFESTs to document the six previously-undocumented methods now load-bearing for this feature. No algorithm text changes needed for the "existing" methods' *behavior* (unchanged) — this is pure documentation catch-up.

## Specification Impact
- `packages/core/adapters/CODEMANIFEST`: add `methods:` entries for `setOnRequestHook`, `setOnResponseHook`, `setHeader`, `getHeader`, `isHeadersSent`, `appendHeader` under the existing `AbstractHttpAdapter` type. No signature/behavior change to describe — purely filling a documentation gap identified in Investigation.
- `packages/platform-express/adapters/CODEMANIFEST` / `packages/platform-fastify/adapters/CODEMANIFEST`: add corresponding `methods:` entries only where the override has adapter-specific behavior worth a line (`setHeader`→`response.set`/`response.header`, etc.), matching the existing convention in these files of documenting overrides, not every inherited method.
- New `packages/core/request-id/CODEMANIFEST`: full new document — Header (no Imports needed, since the cell is a leaf; no Usages needed initially), Body declaring `RequestIdStorage`-style routines (`runWithRequestId`, `getRequestId`) and the `createRequestIdMiddleware` routine/entity, Footer with `Author: Goga`.

## Usage Impact
- No existing `.usages/*.md` files are affected (confirmed: all four candidate cells report `usages: []`).
- New cell-level practice `packages/core/request-id/.usages/reading-the-request-id.md`: documents, for consumers (controllers, guards, interceptors, services, exception filters), how to call `getRequestId()` and that it returns `undefined` outside of a request handled with `enableRequestId()`/`requestId` enabled — written after the CODEMANIFEST, per cookbook design order.

## Compatibility Verification
**Backward compatible.** New option (`requestId`), new method (`enableRequestId`), new package export, new cell — all additive. Default is `undefined`/falsy, so `applyOptions()`'s new branch is a no-op for every existing app that doesn't set it, identical to today. No existing method's behavior, return value, or file path changes. No existing test can regress (confirmed no existing test references `setOnRequestHook`/`setOnResponseHook`). Proceeding — no STOP condition triggered.

## Test Strategy
- **Unit** (`packages/core/test/request-id/`): `request-id-storage.spec.ts` — `getRequestId()` returns `undefined` outside `runWithRequestId`, returns the correct value inside (including through a nested `async`/`await` chain, to prove ALS survives microtask boundaries), and returns `undefined` again after the callback resolves. `request-id-middleware.spec.ts` — generates an ID when no inbound header present, reuses the inbound header value verbatim when present (including mixed-case header key lookup), calls `setHeader` with the configured/default header name, calls `done()` with no arguments.
- **Unit** (`packages/core/test/nest-application.spec.ts` additions): `applyOptions()` calls `enableRequestId()` when `appOptions.requestId` is truthy and does not when falsy/absent (spy-based, mirrors existing `cors` spec pattern in the same file); `enableRequestId()` calls `httpAdapter.setOnRequestHook` exactly once with a function.
- **E2E** (`integration/request-id/e2e/{express,fastify}.spec.ts`, both against the same `src/app.module.ts`): (a) response includes the header with a valid value on a normal 200 route; (b) sending an inbound header value on the request causes the exact same value to come back on the response; (c) a request to an undefined route still returns the header on its 404 response; (d) a controller handler that calls `getRequestId()` internally returns a value matching the response header — proves requirement 3 end-to-end, not just via unit mocks; (e) two concurrent in-flight requests never observe each other's ID (proves ALS isolation, not a shared mutable field).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Fastify's `onRequest` hook might not actually fire before its 404 handler in practice (Investigation flagged this as framework-documented but not locally re-verified) | Low | High (would silently violate requirement 4 on one platform only) | E2E test (c) above asserts this directly against a real Fastify instance; if it fails, `enableRequestId()` implementation must be revisited (e.g. also hooking `setNotFoundHandler`) before this plan is considered complete |
| `als.run` overhead on every request (perf) | Low | Low | Feature is opt-in; no cost for apps that don't enable it; AsyncLocalStorage overhead is well-understood and small relative to full request handling |
| Duplicate/array-valued inbound header (client sends the header twice) | Low | Low | Middleware takes the first array element deterministically; documented in the new `.usages` file so consumers aren't surprised |
| Manifest reconciliation scope creep (tempted to also fix the unrelated pre-existing `appendHeader`-doesn't-append bug noticed in Fastify) | Medium | Low | Explicitly out of scope per Investigation's rejected-hypothesis list; will not be touched in this change |
| Header name collision if an app already sets its own `X-Request-Id` manually elsewhere | Low | Low | `options.header` is configurable; default documented clearly; last-write-wins is standard and acceptable, no special handling needed |

Change Plan complete. Do you approve the plan? Proceed to implementation?
