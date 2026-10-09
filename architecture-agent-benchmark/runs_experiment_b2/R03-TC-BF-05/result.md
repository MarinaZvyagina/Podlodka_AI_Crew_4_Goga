# R03-TC-BF-05

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: False
Cost: $1.7926071000000001
Duration: 344793ms, turns: 55

## Agent's own summary

Now I have enough to finalize the plan.

**Change Plan**

```md
# Change Plan

## Task Classification
Feature (net-new, additive)

## Affected Cells
| Cell | Files to Modify | What Changes |
|---|---|---|
| packages/core/maintenance (NEW) | maintenance-mode.service.ts, maintenance-mode.guard.ts, index.ts, CODEMANIFEST, .usages/testing-in-isolation.md | New cell created from scratch |
| packages/common (decorators/core) | + maintenance.decorator.ts (new); decorators/core/index.ts (+1 export line, additive) | New decorator added and exported |
| packages/common (constants.ts) | +1 export line (`MAINTENANCE_MODE_METADATA`) | Additive constant, no existing line touched |
| packages/core (index.ts) | +1 export line (`export * from './maintenance/index.js';`) | Additive facade export |
| packages/core/guards, packages/core/router, packages/websockets/* | none | Untouched — reused as-is via the existing `CanActivate`/`@UseGuards` pipeline |

## Root Cause Analysis
Not a defect. The framework already runs one guard pipeline (`GuardsContextCreator` + `GuardsConsumer`) identically for HTTP (`RouterExecutionContext`) and WS (`WsContextCreator`), confirmed by direct code read. Maintenance mode is implemented as a new `CanActivate` guard plus a `SetMetadata`-based marking decorator, riding that existing pipeline rather than adding new wiring.

## Trace Summary
- Guards run strictly before pipes/interceptors/handler on both transports (`router-execution-context.ts`, `ws-context-creator.ts`) — satisfies "rejected before any of their real logic runs."
- A guard returning `false` already produces a clear, standard rejection on both transports (`ForbiddenException` on HTTP via router; `WsException(FORBIDDEN_MESSAGE)` on WS via `createGuardsFn`) — no new exception plumbing required.
- `common → core` dependency is one-directional (core depends on common, not vice versa) — forces `Reflector`-consuming code (the guard) into `packages/core`, while the dependency-free `SetMetadata` decorator stays in `packages/common`, matching where `Reflector` and `UseGuards`/`SetMetadata` already live respectively.

## Change Strategy
1. Add `MAINTENANCE_MODE_METADATA = '__maintenanceMode__'` to `packages/common/constants.ts`, next to `GUARDS_METADATA`/`PIPES_METADATA`/etc.
2. Add `packages/common/decorators/core/maintenance.decorator.ts` exporting `Maintenance(): MethodDecorator & ClassDecorator`, implemented as `SetMetadata(MAINTENANCE_MODE_METADATA, true)`, JSDoc'd in the same style as `use-guards.decorator.ts`. Export it from `packages/common/decorators/core/index.ts`.
3. Create cell `packages/core/maintenance/`:
   - `maintenance-mode.service.ts` — `@Injectable() class MaintenanceModeService` with private `enabled = false` and `enable()`, `disable()`, `isEnabled(): boolean`.
   - `maintenance-mode.guard.ts` — `@Injectable() class MaintenanceModeGuard implements CanActivate`, constructor `(reflector: Reflector, maintenanceModeService: MaintenanceModeService)`, synchronous `canActivate(context: ExecutionContext): boolean` using `reflector.getAllAndOverride<boolean>(MAINTENANCE_MODE_METADATA, [context.getHandler(), context.getClass()])`, allow when unmarked, else `!maintenanceModeService.isEnabled()`.
   - `index.ts` — re-export both.
   - `CODEMANIFEST` — document both as Entities (JS cell form), footer `Author: Goga`.
   - `.usages/testing-in-isolation.md` — the no-server/no-socket unit-test recipe.
4. Add `export * from './maintenance/index.js';` to `packages/core/index.ts`, mirroring the existing `services/index.js` export line.
5. Add tests (Step 6) under `packages/core/test/maintenance/` and `packages/common/test/decorators/maintenance.decorator.spec.ts`, following the exact structural conventions of `packages/core/test/guards/guards-consumer.spec.ts` and `packages/core/test/services/reflector.service.spec.ts`.

## Specification Impact
- **New** `packages/core/maintenance/CODEMANIFEST` only. No Imports entry for `Reflector`/`CanActivate`/`ExecutionContext` is required: `packages/core/services` and `packages/common` are not documented cells in this schema (`ARCHITECTURE_CONTRACTS.md`: "Directories without a CODEMANIFEST are simply undocumented by this system"), so these are plain intra/cross-package code references noted in Annotations text, not formal `Imports`.
- Body (Entity form, per `goga-cell-javascript`):

```yaml
Annotations: |
  Implements Nest's maintenance-mode extension point: a runtime-toggleable guard that
  denies handlers marked with the `@Maintenance()` decorator (from `@nestjs/common`)
  while maintenance mode is enabled, and allows every other request/message unchanged.
  Reuses `Reflector` from ../services (same package, undocumented cell) to read metadata
  and the `CanActivate` contract from `@nestjs/common` (undocumented cell, peer package).
  Composes with the existing guard pipeline (packages/core/guards) via `@UseGuards` —
  no changes to that pipeline are required.

---

"MaintenanceModeService()":
  location: maintenance-mode.service.ts
  annotations: |
    In-process, mutable runtime toggle for maintenance mode. A single injected instance
    is shared across the application, so calling `enable`/`disable` anywhere takes effect
    everywhere immediately, without a redeploy. Trivially constructible with no arguments
    for isolated unit tests.
  methods:
    "enable()": |
      Turn maintenance mode on. Subsequent `isEnabled` calls return true.
    "disable()": |
      Turn maintenance mode off. Subsequent `isEnabled` calls return false.
    "isEnabled() -> enabled:boolean": |
      Current maintenance-mode state.

"MaintenanceModeGuard(reflector: Reflector, maintenanceModeService: MaintenanceModeService)":
  location: maintenance-mode.guard.ts
  annotations: |
    CanActivate guard, transport-agnostic: works identically wherever the framework's
    guard pipeline runs it (HTTP routes via packages/core/router, WebSocket message
    handlers via packages/websockets), since it inspects only metadata and one service
    flag, never the underlying request/socket.

    `reflector`: reads the `@Maintenance()` marking left by `SetMetadata`, checking the
    handler method first and falling back to its class, so both method-level and
    controller/gateway-level marking are supported
    `maintenanceModeService`: the shared runtime toggle
  methods:
    "canActivate(context: Object<string, any>) -> allowed:boolean": |
      `context`: execution context exposing `getHandler()` and `getClass()`

      Algorithm:
      1. Read maintenance-mode metadata from the handler, falling back to its class
      2. If neither is marked, return true (unaffected handler — always allowed)
      3. If marked, return the negation of `maintenanceModeService.isEnabled()`
```

## Usage Impact
No existing `.usages/*.md` files are modified (none exist for the affected/reference cells). One new practice file is authored: `packages/core/maintenance/.usages/testing-in-isolation.md`, describing:
- Constructing `MaintenanceModeGuard`/`MaintenanceModeService` directly with `new`, no Nest DI container, no HTTP server, no socket.
- A minimal fake `ExecutionContext` (`{ getHandler: () => fn, getClass: () => Cls }`) sufficient for `Reflector.getAllAndOverride` to work, since it only calls `Reflect.getMetadata` on those two values.
- Two example assertions: a `@Maintenance()`-marked handler is blocked once `service.enable()` is called; an unmarked handler stays allowed regardless of toggle state.

## Compatibility Verification
**Backward compatible.** No existing exported symbol changes signature or behavior; no existing file's logic is modified — only three files gain one additive export line each (`constants.ts`, `decorators/core/index.ts`, `core/index.ts`). No existing test can observe a behavior difference since no existing runtime path is altered. Confirmed no breaking change per Investigation Report Step 4 answers (all NO).

## Test Strategy
- `packages/core/test/maintenance/maintenance-mode.service.spec.ts`: default state is disabled; `enable()` → `isEnabled()` true; `disable()` → `isEnabled()` false; independent instances don't share state (proves DI-singleton behavior is a wiring choice, not implicit global state).
- `packages/core/test/maintenance/maintenance-mode.guard.spec.ts`: (a) unmarked handler/class → `canActivate` true regardless of service state; (b) method-marked handler → true when service disabled, false when enabled; (c) class-marked, method unmarked → same on/off behavior via class fallback; (d) method-level marking overrides an unmarked method on a marked class correctly (method metadata is checked first per `getAllAndOverride` order — since method has no own metadata in that case it falls through to class, so this collapses to case (c); no separate "override" case needed — note in test only case (b)/(c) are meaningfully distinct). All constructed via `new MaintenanceModeGuard(new Reflector(), service)` and a plain object execution-context double — no server, no socket, matching `guards-consumer.spec.ts` conventions.
- `packages/common/test/decorators/maintenance.decorator.spec.ts`: applying `@Maintenance()` to a method sets `MAINTENANCE_MODE_METADATA` true on the method; applying it to a class sets it on the class — mirrors `packages/common/test/decorators/injectable.decorator.spec.ts` style (direct `Reflect.getMetadata` assertions, no framework bootstrap).

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Developer marks a handler but forgets to register `MaintenanceModeGuard` (locally or via `APP_GUARD`) | Medium | Marked handler silently stays unprotected | Document explicitly in the new `.usages` file and in the final report that the guard must be bound (mirrors the pre-existing, well-understood `RolesGuard`/`APP_GUARD` pattern every Nest developer already knows) |
| Metadata key collision with a user's own `'__maintenanceMode__'` string key | Low | Extremely unlikely; matches existing constants' double-underscore convention which real-world code doesn't use | Consistent naming with existing internal keys; no mitigation beyond convention needed |
| Guard treats class-level marking as "every method affected" including methods a developer expected to be exempt | Low | Matches explicit task requirement ("mark ... entire controller") | Behavior is the documented, requested semantic — not a defect |

Do you approve this plan? Proceed to implementation?
```
