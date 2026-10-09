# R03-TC-BF-02

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: False
Cost: $1.0688382
Duration: 259751ms, turns: 31

## Agent's own summary

# [PRIMARY_ANALYSIS_REPORT]

## Topic
maintenance-mode

## Acceptance Criteria
N/A (not a task-file input). Derived acceptance bar from the request itself:
1. A handler/controller (HTTP) or a message handler/gateway (WS) can be marked "affected by maintenance mode" with one decorator, usable at method or class level.
2. Toggling a runtime service on/off changes behavior immediately, no redeploy.
3. Marked handlers are rejected before their body executes, only while the flag is on; unmarked handlers are always unaffected, on both transports.
4. The guard is unit-testable with plain mocks — no HTTP server, no socket.

## Stack & External Dependencies
TypeScript, `@nestjs/common`/`@nestjs/core` conventions already in this repo: `SetMetadata`, `Reflector`, `CanActivate`/`ExecutionContext`, `@Injectable()`. No new external dependencies.

## Existing Cells & Schema
9 documented cells (see `[PROJECT_CONTEXT_REPORT]`). Relevant ones:
| Cell | CODEMANIFEST location | Relevance |
|---|---|---|
| `packages/core/guards` | `packages/core/guards/CODEMANIFEST` | Contract our guard implements (`CanActivate`) and is resolved/run by (`GuardsContextCreator`/`GuardsConsumer`) |
| `packages/core/router` | `packages/core/router/CODEMANIFEST` | Confirms HTTP-side guard placement ("before the handler") |
| `packages/common/exceptions` | `packages/common/exceptions/CODEMANIFEST` | Optional: `ServiceUnavailableException` available for a clearer HTTP denial |

## Artifact Resolution
| Name/term | Resolution | Justification |
|---|---|---|
| Maintenance-mode marker decorator | new artifact | No existing decorator serves this; pure `SetMetadata`-style, no schema match |
| Maintenance-mode state holder (service) | new artifact | No existing runtime toggle exists anywhere in the 9 cells |
| Maintenance-mode guard | new artifact | Composes `CanActivate` (from `packages/core/guards`) but is itself new; `core/guards` cell documents the extension point, not concrete guard implementations, which are expected to live outside it (same pattern real Nest apps use) |
| `packages/core/guards` (CanActivate contract) | depend on existing cell, unmodified | Confirmed via CODEMANIFEST read; we only implement its interface |
| `Reflector` | depend on existing (undocumented) source, unmodified | Exists at `packages/core/services/reflector.service.ts`, outside the 9 tracked cells; used as an ordinary import like any consumer would |

## Key Concepts
- `MAINTENANCE_MODE_METADATA` — metadata key constant
- `AffectedByMaintenance()` — `SetMetadata`-based decorator, dual-mode (`ClassDecorator & MethodDecorator`)
- `MaintenanceModeService` — `@Injectable()`, holds an in-memory boolean flag; `isEnabled(): boolean`, `enable(): void`, `disable(): void`
- `MaintenanceModeGuard implements CanActivate` — constructor-injects `Reflector` and `MaintenanceModeService`; `canActivate(context: ExecutionContext): boolean`

## Dark Zones
1. **New cell's package/path.** Proposal: `packages/common/maintenance` — decorators/metadata are conventionally in `common` (mirrors `common/decorators`, `common/exceptions`), and this cell has no dependency on DI internals, only on `common`'s own `ExecutionContext`/`SetMetadata` plus `core`'s `Reflector` (a cross-package dependency that already exists in the reverse direction elsewhere, e.g. router → common/exceptions). Alternative would be `packages/core/guards` itself, but that would mean modifying a cell explicitly marked "no changes" in the request.
2. **Denial signaling.** Proposal: `canActivate` returns a plain `boolean` (`false` when blocked). This lets the existing per-transport plumbing produce the correct error type automatically (HTTP → `ForbiddenException` via `core/router`; WS → `WsException('Forbidden resource')` via `ws-context-creator`), which is exactly the "one mechanism, no parallel plumbing" requirement — zero transport-awareness needed inside our guard.

## Connection to Existing Architecture
- Depends on `packages/core/guards` (implements its `CanActivate` contract) — read-only, not modified.
- Depends on `packages/core/router` only insofically as confirmation that HTTP already calls guards before handlers — not modified, no direct import.
- No changes to `packages/websockets` (undocumented cell) — it already calls guards generically; our guard needs zero special-casing for WS.

## Risks and Constraints
- Must not introduce a second, WS-specific guard mechanism — single `MaintenanceModeGuard` class must serve both transports unchanged.
- State holder must be a normal DI singleton (`@Injectable()` provider), not a module-level mutable global, so it's constructor-injectable into the guard and swappable with a fake in unit tests.
- Guard must not assume `context.switchToHttp()`/`switchToWs()` are safe to call for both transports — must only use the transport-agnostic `ExecutionContext` surface (`getHandler()`, `getClass()`).

## Scope Decision
Single subsystem — proceed as one cell, no split.

## Notes
Naming: proposing `packages/common/maintenance` as the cell path, with decorator `AffectedByMaintenance()`.

**One question before I lock this in:** does `packages/common/maintenance` as the new cell path work for you, or would you rather it live under `packages/core` (e.g. `packages/core/maintenance`) alongside the other guard-adjacent extension-point cells?
1. `packages/common/maintenance` (recommended — mirrors `common/decorators`/`common/exceptions`, no DI-internals dependency)
2. `packages/core/maintenance` (keeps it next to `core/guards`, but pulls in a `common`→`core` naming asymmetry since decorators are usually in `common`)
