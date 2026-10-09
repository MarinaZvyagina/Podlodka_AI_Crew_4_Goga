# R03-TD-GC-05

Condition: goga_native_architecture
Base tag: condition-c-r03-v1
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: True
Cost: $3.1065653999999996
Duration: 669073ms, turns: 66

## Agent's own summary

# Change Plan

## Task Classification
**Feature** (net-new, additive, opt-in capability) with a secondary **drift-fix** component (documenting existing undocumented `AbstractHttpAdapter` methods that this feature newly depends on).

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| packages/core/router/request-id *(new cell)* | `CODEMANIFEST` (new), `index.ts` (new), `request-id.ts` (new) | New cell: header-name constant, ID resolution routine, adapter-hook-building routine |
| packages/core/adapters | `CODEMANIFEST` (edit only, no code change) | Document pre-existing but previously-undocumented `setHeader`/`getHeader`/`appendHeader`/`isHeadersSent`/`setOnRequestHook`/`setOnResponseHook` methods on `AbstractHttpAdapter`, since the new cell now depends on `setHeader`/`setOnRequestHook` as load-bearing contract |
| packages/platform-express/adapters, packages/platform-fastify/adapters | none | No code changes — investigation confirmed both already implement the needed hook/header methods identically |

**Outside governance (no CODEMANIFEST, edited under normal engineering practice, not reconciled in Steps 7-8):**
- `packages/common/interfaces/nest-application-options.interface.ts` — add `requestId` option
- `packages/core/nest-application.ts` — wire the opt-in
- New integration test suite `integration/request-id/`

## Root Cause Analysis
No capability gap in the adapters exists — `AbstractHttpAdapter.setOnRequestHook`/`setHeader` are already implemented identically, pre-routing, by both `ExpressAdapter` and `FastifyAdapter`, with zero current consumers. The missing piece is a cell that implements the header-or-generate rule and a bootstrap wire-up that installs it opt-in (mirroring `enableCors`), avoiding any default behavior change for existing apps. A genuine adapter-divergence risk was found and neutralized: Fastify's `request.headers` is a getter/setter pair (`Object.assign({}, raw.headers, additionalHeaders)`), so the shared logic must reassign `req.headers = { ...req.headers, [headerName]: id }` rather than mutate the returned object in place, or Fastify could silently drop the write under some plugin orderings.

## Trace Summary
Adapter constructor (Express: first `app.use()`; Fastify: `addHook('onRequest', ...)`) → dispatches to `onRequestHook` if set → our hook resolves/generates ID → reassigns `req.headers` → `httpAdapter.setHeader(res, headerName, id)` → `done()`/`next()` → normal request flow (guards → pipes → interceptors → handler) → `@Headers('x-request-id')` / `@Req().headers['x-request-id']` in the handler resolves via the unchanged, already-adapter-uniform `route-params-factory.ts:34` lookup → response sent with the header already set (survives 404/error paths since it runs before routing, on the one shared `req`/`res` object per request).

## Change Strategy

1. **Create `packages/core/router/request-id/`** with:
   - `request-id.ts`:
     - `DEFAULT_REQUEST_ID_HEADER = 'x-request-id'` constant.
     - `resolveRequestId(headers, headerName)`: reads `headers[headerName]`; if it's a non-empty string, take it as-is; if array-valued (duplicate header), take the first entry; otherwise generate via `crypto.randomUUID()` (Node built-in, no new dependency).
     - `createRequestIdHook(httpAdapter, options)`: returns `(req, res, done) => { const id = resolveRequestId(req.headers, headerName); req.headers = { ...req.headers, [headerName]: id }; httpAdapter.setHeader(res, headerName, id); done(); }`. `options` carries `{ header?: string, generator?: () => string }`.
   - `index.ts`: re-exports both from `request-id.ts` (cell facade, per JS cell rules).
   - `CODEMANIFEST`: Imports `AbstractHttpAdapter` from `packages/core/adapters`; declares `resolveRequestId` and `createRequestIdHook` as Routines (input→output signatures per DSL), `DEFAULT_REQUEST_ID_HEADER` as a minimal-declaration constant (same pattern as `REQUEST`/`REQUEST_CONTEXT_ID` in the sibling `request` cell). Annotations state the header-or-generate algorithm and the Fastify-safe reassignment requirement explicitly, so future maintainers don't regress it back to in-place mutation.
   - `.usages/reading-the-request-id.md`: documents `@Headers('x-request-id')` / `@Req().headers['x-request-id']` as the consumer-facing access pattern — explicitly stating this works identically on both adapters and requires no new decorator.

2. **`packages/common/interfaces/nest-application-options.interface.ts`**: add
   ```ts
   /**
    * Attaches a correlation/request ID to every request and response.
    * Reuses the inbound header value when present, otherwise generates one.
    * Available to application code via `@Headers('x-request-id')` or `@Req()`.
    * @default false
    */
   requestId?: boolean | { header?: string; generator?: () => string };
   ```
   (mirrors the existing `cors?: boolean | CorsOptions | CorsOptionsDelegate<any>` shape immediately above it).

3. **`packages/core/nest-application.ts`**:
   - Import `createRequestIdHook`, `DEFAULT_REQUEST_ID_HEADER` from `./router/request-id/index.js`.
   - Add `public enableRequestId(options?: { header?: string; generator?: () => string }): void { this.httpAdapter.setOnRequestHook(createRequestIdHook(this.httpAdapter, options)); }`.
   - In `applyOptions()`, alongside the existing `cors` branch, add: if `this.appOptions?.requestId` is truthy, call `this.enableRequestId(isObject(this.appOptions.requestId) ? this.appOptions.requestId : undefined)`. Default (option absent/false): nothing is wired, `onRequestHook` stays `undefined`, zero behavior change.

4. **No changes** to `AbstractHttpAdapter`, `ExpressAdapter`, `FastifyAdapter` implementation — only manifest documentation catch-up on the adapters cell.

## Specification Impact
- **New**: `packages/core/router/request-id/CODEMANIFEST` — full new document (Imports/Usages/Annotations header, `DEFAULT_REQUEST_ID_HEADER`/`resolveRequestId`/`createRequestIdHook` body, footer with `Author: Goga`).
- **Edited**: `packages/core/adapters/CODEMANIFEST` — append `methods` entries for `setHeader`, `getHeader`, `appendHeader`, `isHeadersSent`, `setOnRequestHook`, `setOnResponseHook` under `AbstractHttpAdapter`, matching what's already implemented in `http-adapter.ts`. This is documentation-only; no algorithm or signature in the manifest is being changed, only completed — verified non-conflicting with existing manifest text (nothing currently asserts these methods don't exist).
- `packages/core/router/CODEMANIFEST` — **unchanged**. The new cell is not consumed by the router; router's own contract (guards/pipes/interceptors composition) is untouched.

## Usage Impact
- New `.usages/reading-the-request-id.md` in the new cell — the only usage file this change creates. No existing `.usages` file in any candidate cell references header handling or adapter hooks (confirmed empty `usages: []` for all candidates in `goga schema`), so no existing practice needs revision.

## Compatibility Verification
**Backward compatible.** For any application that does not set `appOptions.requestId` (or call `enableRequestId()`), `NestApplication.init()`'s new branch is not taken, `httpAdapter.onRequestHook` remains `undefined`, and the pre-existing dispatch wrapper in both adapters takes its unchanged `else` path. No existing file's return values, output formats, or manifest-defined guarantees change. No existing test asserts an exact/closed header set on responses (verified via grep in Investigation). Proceeding — no STOP condition met.

## Test Strategy
1. **Unit tests** (`packages/core/test/router/request-id/request-id.spec.ts`, colocated with other cell tests under `packages/core/test`):
   - `resolveRequestId` reuses an existing header value verbatim (including a case-sensitivity check: lookup key must be lowercase since Node normalizes incoming header names).
   - `resolveRequestId` generates a new value (mock `crypto.randomUUID`) when the header is absent or empty.
   - `resolveRequestId` takes the first entry when the header arrives as an array (duplicate header).
   - `createRequestIdHook` calls `httpAdapter.setHeader` with the resolved ID and calls `done()`.
   - **Regression guard for the Fastify finding**: a test that passes a mock `req` whose `headers` is a getter/setter pair (simulating Fastify's `additionalHeaders` behavior) and asserts the hook reassigns `req.headers` (triggering the setter) rather than mutating the object in place — this is the test that would have caught the divergence if the naive implementation had been used.

2. **Adapter parity e2e** — new integration app `integration/request-id/src/app.module.ts` with one controller route that both returns a body and independently captures `@Headers('x-request-id')` in a way the response body can assert against (e.g. echoes it back), so the test can compare "what the handler saw" against "what the response header says" for equality:
   - `integration/request-id/e2e/express.spec.ts` (using `NestExpressApplication` + `supertest`, mirroring `integration/cors/e2e/express.spec.ts`) and `integration/request-id/e2e/fastify.spec.ts` (using `NestFastifyApplication` + `.inject()`, mirroring `integration/hello-world/e2e/fastify-adapter.spec.ts`) — **run the identical assertion set on both**:
     a. No inbound header → response carries a header matching a UUID pattern, and it equals what the handler read via `@Headers()`.
     b. Inbound header supplied by the caller → response header equals the inbound value verbatim (not regenerated), and the handler sees the same value.
     c. A request to an unmatched route (404) still carries the response header — proving the hook runs pre-routing on both platforms.
     d. Two sequential requests get two different generated IDs (no accidental caching across requests).
   - This directly satisfies "verified not assumed" and "not a mostly-works situation" — the two spec files assert the exact same behavior contract, so any adapter-specific divergence fails CI on one of them.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Naive in-place `req.headers[name] = id` mutation silently fails on Fastify under some plugin ordering | Medium (subtle, version/plugin-order-dependent) | High (violates the core "identical on both adapters" requirement) | Use full-object reassignment (`req.headers = {...}`) as specified; regression unit test simulates the getter/setter case directly |
| Treating this as always-on breaks existing apps' assumptions about their response headers | Low if opt-in is followed | High (breaking change) | Strictly opt-in via `appOptions.requestId`/`enableRequestId()`; default path untouched |
| Header name casing confusion (`X-Request-Id` vs `x-request-id`) causes a consumer's `@Headers('X-Request-Id')` to appear to "not match" | Low | Low (HTTP headers are case-insensitive; `route-params-factory.ts` already lowercases lookups) | Document in the new `.usages` file that header names are case-insensitive by HTTP spec and by this framework's own `@Headers()` lookup |
| Manifest drift-fix (documenting existing adapter methods) is misread by drift-analyzer as a manifest change requiring implementation changes | Low | Low | Explicitly scope Step 9 (Drift Analysis) to confirm this is documentation catching up to already-existing code, zero implementation delta |

---

Do you approve the plan? Proceed to implementation?
