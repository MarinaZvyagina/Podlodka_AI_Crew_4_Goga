# CYCLE_FIXES.md — R03 (nestjs/nest)

Unlike R06 (etcd), a real circular dependency was found among the documented cells, via
relative-import analysis (`grep -hoE "from '\.\./[a-zA-Z-]+" packages/core/<cell>/*.ts`,
cross-referenced against all other documented cells):

- `packages/core/router` imports heavily from `packages/core/injector` (`NestContainer`,
  `InstanceWrapper`, `Module`, `Injector`, `ModulesContainer`, `STATIC_CONTEXT`) — a real, deep,
  legitimate dependency (the router needs the DI container to resolve controller/provider
  instances per request).
- `packages/core/injector/container.ts` imports `REQUEST` from
  `packages/core/router/request/request-constants.ts` — a single, thin dependency: a
  request-scope DI token string constant, unrelated to routing logic itself.

This is a real cell-to-cell cycle (`router` → `injector` → `router`), which Goga's AST analyzer
forbids as a declared `Imports` cycle (`docs/cell/ast/analyzer.md`'s `ImportsHasNotCyclicalDeps`
rule) — and, per this study's design, genuine cell-native restructuring requires the *real*
package dependency graph to also be acyclic, not just the declared one.

## Fix (declarative only, zero real code motion)

`packages/core/router/request/` (containing `request-constants.ts`: `REQUEST`,
`REQUEST_CONTEXT_ID`; and `request-providers.ts`: `requestProvider`) already physically lives in
its own subdirectory with zero dependencies on either `router` or `injector` (confirmed by reading
its actual imports — only external `@nestjs/common` types). This subdirectory already needed its
own CODEMANIFEST regardless of the cycle (it's real subdirectory-with-code under the `router`
cell, which Goga's `location` rule forbids leaving undocumented under the parent cell) — so
splitting it into its own cell serves double duty:

1. `packages/core/router/request/CODEMANIFEST` created as a new, independent leaf cell.
2. `packages/core/injector/CODEMANIFEST`'s `Imports` now references `REQUEST` `From:
   packages/core/router/request` — **not** `From: packages/core/router`.
3. `packages/core/router/CODEMANIFEST` (the main router cell) is untouched by this fix — it never
   needed to import from `router/request` itself, only `injector` did.

Topological order after the fix (leaves first): `packages/core/router/request`,
`packages/core/router/interfaces`, `packages/common/exceptions`, `packages/core/adapters`,
`packages/platform-express/adapters/utils`, `packages/platform-fastify/adapters/middie` → 
`packages/core/interceptors`, `packages/core/pipes`, `packages/core/guards`,
`packages/platform-express/adapters`, `packages/platform-fastify/adapters` → `packages/core/injector`
→ `packages/core/router`.

No behavior changed, no files moved — only which cell's CODEMANIFEST declares the `REQUEST`
import was corrected to point at the more precise, already-real subdirectory boundary.
