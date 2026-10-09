# R03-TD-BF-03

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: False
Cost: $1.60382565
Duration: 123889ms, turns: 8

## Agent's own summary

# [PROJECT_CONTEXT_REPORT]

## Cell Hierarchy
```
packages/core/interceptors        (InterceptorsConsumer, InterceptorsContextCreator)
packages/core/pipes               (ParamsTokenFactory, PipesConsumer, PipesContextCreator)
packages/core/adapters             (AbstractHttpAdapter)
packages/core/guards               (GuardsConsumer, GuardsContextCreator)
packages/core/injector              (Injector, InstanceLoader, InstanceWrapper, Module, NestContainer)
packages/core/router                (RouterExecutionContext, RouterExplorer, RoutesResolver)
packages/platform-express/adapters  (ExpressAdapter)
packages/platform-fastify/adapters  (FastifyAdapter)
packages/common/exceptions          (BadRequestException, ForbiddenException, HttpException, InternalServerErrorException, IntrinsicException, NotFoundException, UnauthorizedException)
```
No `children` nesting; all 9 cells are top-level and flat. This is a partial/curated documentation surface over a much larger monorepo (e.g. `packages/core/nest-application.ts`, `packages/common/utils/`, `packages/core/injector/router` bootstrap wiring, etc. exist in the working tree but have no CODEMANIFEST).

## Base Usages & Annotations
From `.goga/config.yml`: `language: javascript` only. No `.goga/usages/` directory exists in the project (confirmed via `find .goga -type f`), so there are no base/cookbook usage files to inherit and no `.goga/usages/cooks/` entries for external libraries (e.g. no existing house-style guidance for `node:async_hooks`/AsyncLocalStorage usage to follow — this will be a first for the documented surface).

## Relevant Existing Cells

| Cell | CODEMANIFEST location | Relevance to the task |
|---|---|---|
| `packages/core/adapters` | `packages/core/adapters/CODEMANIFEST` | Declares `AbstractHttpAdapter.setOnRequestHook`/`setOnResponseHook` — the exact extension point the new cell will drive. No signature change needed, but the new cell becomes a documented consumer of this contract. |
| `packages/platform-express/adapters` | `packages/platform-express/adapters/CODEMANIFEST` | `ExpressAdapter` is one of the two concrete implementations whose hook wiring the new cell relies on for symmetric behavior. No change to this CODEMANIFEST expected — its existing `setOnRequestHook`/`setOnResponseHook` mutation already covers what's needed. |
| `packages/platform-fastify/adapters` | `packages/platform-fastify/adapters/CODEMANIFEST` | Same role as above for `FastifyAdapter`. No change expected. |
| `packages/core/router` | `packages/core/router/CODEMANIFEST` | `RouterExecutionContext.create` is described as the place that "sets the configured response status and headers" per route — establishes that per-request header-setting already happens in the framework's request-handling spine, which is precedent for where correlation-ID propagation conceptually belongs, but the actual response-header write for this feature happens earlier (in the adapter-level onRequest hook, before routing), not inside this cell. No change expected here. |
| `packages/common/exceptions` | `packages/common/exceptions/CODEMANIFEST` | Not relevant to this feature. |

## Relevant Usages
None. No `.usages/` files exist under any of the 9 documented cells (schema shows `"usages": []` for every cell), and `.goga/usages/` does not exist at all — there is no established usages catalog to consult for this task.

## Description-to-Schema Matches

| Name/term from description | Schema match? | Hypothesis |
|---|---|---|
| `AbstractHttpAdapter` | Yes — `packages/core/adapters` | Existing artifact; new cell will import it (its `setOnRequestHook`/`setOnResponseHook` contract), no modification to this cell needed. |
| `ExpressAdapter` | Yes — `packages/platform-express/adapters` | Existing artifact; consumed transitively via the adapter contract, no direct modification expected. |
| `FastifyAdapter` | Yes — `packages/platform-fastify/adapters` | Existing artifact; same as above. |
| `randomStringGenerator` (`packages/common/utils/random-string-generator.util.ts`) | No — not part of any documented cell (`packages/common/exceptions` is the only documented `common` cell) | Existing artifact, but undocumented by goga; new cell will import it directly from source, not via a CODEMANIFEST-tracked dependency. |
| Request-ID store / AsyncLocalStorage mechanism | No | New artifact — new cell to create. |
| `NestApplication.init()` (`packages/core/nest-application.ts`) | No — `packages/core` root is undocumented at this granularity (only sub-cells `interceptors`, `pipes`, `adapters`, `guards`, `injector`, `router` are documented) | Existing artifact needing a small wiring edit (to call the new cell's setup), but it sits outside any currently documented cell boundary — treat as an undocumented integration point we touch minimally, not a cell to redocument in full. |
