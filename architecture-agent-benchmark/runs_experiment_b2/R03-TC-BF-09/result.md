# R03-TC-BF-09

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: False
Cost: $1.2075558000000002
Duration: 293232ms, turns: 29

## Agent's own summary

# [PRIMARY_ANALYSIS_REPORT]

## Topic
`maintenance-mode`

## Acceptance Criteria
(No task file — condensed from the detailed description)
1. A decorator marks an individual handler method or an entire controller/gateway class as "affected."
2. An in-process, DI-injectable toggle (enable/disable/isEnabled) controls maintenance state at runtime — no redeploy, no env var.
3. While ON: calls to marked handlers are rejected before their body runs, with a clear error; unmarked handlers unaffected. While OFF: marked handlers behave normally.
4. One mechanism serves both HTTP route handlers and WS message handlers.
5. Unit-testable in isolation — no real server/socket needed.

## Stack & External Dependencies
TypeScript/JavaScript, `@nestjs/common` conventions only (decorators via `Reflect.getMetadata`/`SetMetadata`, `CanActivate`/`ExecutionContext` interfaces already shipped in this package). No new external dependency.

## Existing Cells & Schema
9 documented cells (see prior `[PROJECT_CONTEXT_REPORT]`). Directly relevant: `packages/common/exceptions` (documented). `packages/common/interfaces`, `packages/common/decorators`, `packages/core/services` (Reflector) exist in source but are **not** documented cells.

## Artifact Resolution

| Name/term | Resolution | Justification |
|---|---|---|
| Marking decorator | new artifact — `AffectedByMaintenance()` in new cell `packages/common/maintenance` | No existing decorator does this; follows the `SetMetadata`-based pattern already used in `packages/common/decorators` |
| Toggle service | new artifact — `MaintenanceModeService` in same new cell | Plain injectable singleton; no existing state holder for this |
| Guard | new artifact — `MaintenanceModeGuard` in same new cell | Implements the existing `CanActivate` interface; does not modify `packages/core/guards`, only satisfies its contract |
| Error thrown | modify: reuse existing `ServiceUnavailableException` from `packages/common/exceptions` | Already exists (503) in that documented cell; semantically correct ("temporarily unavailable"), no need to invent a new exception type |
| Guard integration with HTTP/WS pipelines | no change — existing `packages/core/guards` + `packages/websockets` guard-consumption paths, unmodified | Both already run any `CanActivate` guard registered via `@UseGuards()`/global guard before the handler; verified by reading `router-execution-context.ts` and `ws-context-creator.ts` |

## Key Concepts
- `AffectedByMaintenance()` — class-or-method decorator, sets boolean metadata.
- `MAINTENANCE_MODE_METADATA` — metadata key constant.
- `MaintenanceModeService` — `enable()`, `disable()`, `isEnabled(): boolean`.
- `MaintenanceModeGuard` — `canActivate(context: ExecutionContext): boolean`, reads metadata off handler and class, throws `ServiceUnavailableException` when both flagged-and-enabled.

## Dark Zones (resolved)

1. **Where does the new cell live — `common` or `core`?**
   Resolved: **`packages/common/maintenance`**. Checked `package.json`: `@nestjs/common` has zero dependency on `@nestjs/core`, while `@nestjs/core` depends on `@nestjs/common` — never the reverse. `Reflector` (the class normally used to merge class+method metadata) lives in `packages/core/services`, an undocumented cell in `@nestjs/core`. If the guard lived in `common` and imported `Reflector`, that would invert the real package dependency direction. Fix: the guard reads metadata itself via plain `Reflect.getMetadata(KEY, context.getHandler())` / `context.getClass()`, exactly what `Reflector.getAllAndOverride` does internally — no dependency on `core` at all. This also matches precedent: `CanActivate`/`ExecutionContext` (the contract this guard satisfies) and `SetMetadata` (the mechanism the decorator uses) already live in `common`, undocumented but present.

2. **Class-level vs method-level precedence when both/either is set.**
   Resolved: boolean-flag semantics, no override complexity needed — "affected" if the metadata is truthy on the handler OR its class (`Reflect.getMetadata` on handler first, falling back to class). This mirrors the everyday "guard the whole controller, or just one route" usage pattern already established by `@UseGuards()` itself.

3. **Exception type for the rejection.**
   Resolved: `ServiceUnavailableException` (503) — already exists in `packages/common/exceptions`, semantically distinct from guard-deny's usual `ForbiddenException` (403, an authorization concept), and matches "service-state, not identity" framing of maintenance mode.

## Connection to Existing Architecture
- **Consumes, does not modify:** `packages/core/guards` (the guard is just another `CanActivate` it resolves/runs — same as any user-defined guard), `packages/websockets` (WS gateways register the same guard the same way), `packages/common/exceptions` (reuses `ServiceUnavailableException`).
- **New cell:** `packages/common/maintenance`, with a documented dependency edge to `packages/common/exceptions` only.
- No existing CODEMANIFEST needs modification.

## Risks and Constraints
- Must not introduce a `common → core` dependency (see Dark Zone 1) — hard constraint from the real package graph.
- Must stay guard-based rather than middleware-based, since middleware doesn't run in the WS message-handler pipeline (Nest middleware is HTTP-only) — guards are the only mechanism that already runs identically pre-handler for both transports.
- Toggle service must be a normal DI singleton (not a module-level mutable export) so tests can instantiate `new MaintenanceModeService()` / `new MaintenanceModeGuard(service)` directly and drive `canActivate` with a hand-built fake `ExecutionContext` — no Nest testing module, no server, no socket.

## Scope Decision
Single subsystem — proceed as one cell.

## Notes
This is intentionally a small, self-contained cell (4 files): metadata constant, decorator, service, guard. No changes anywhere else in the framework are required — the entire feature is additive.

---

Given the scope is narrow and the open design questions (cell placement, precedence, exception type) are now resolved on concrete technical grounds, do you approve this analysis so I can proceed to the type map (Phase 4)?
