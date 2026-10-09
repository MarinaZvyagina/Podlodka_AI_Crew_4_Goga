# R03-TC-BF-06

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: False
Cost: $0.8910081000000001
Duration: 151477ms, turns: 27

## Agent's own summary

# [PRIMARY_ANALYSIS_REPORT]

## Topic
maintenance-mode

## Acceptance Criteria
- A developer can mark an individual HTTP route handler, an entire HTTP controller, or a WebSocket message handler as "affected by maintenance mode" using one consistent decorator-based approach (not two separate mechanisms for HTTP vs WS).
- Toggling maintenance mode on/off is controllable at runtime from inside the running app (no redeploy).
- While maintenance mode is on, calls to marked handlers are rejected before their handler logic executes.
- Unmarked handlers work normally regardless of maintenance mode state.
- When maintenance mode is off, marked handlers work normally again.
- The mechanism is unit-testable in isolation: construct the guard, call `canActivate()` with a mock `ExecutionContext`, no real server or socket needed.
- Reuses the existing transport-agnostic `CanActivate`/`ExecutionContext` guard pipeline — no parallel HTTP-only/WS-only mechanism.

## Stack & External Dependencies
TypeScript / Node.js, `@nestjs/common` (decorators, `Injectable`, `CanActivate`, `Reflector`), `@nestjs/core` (guard execution — unmodified), `@nestjs/websockets` (WS guard execution — unmodified), Vitest (repo's existing test runner, confirmed by `vitest.config.mts` at repo root).

## Existing Cells & Schema
9 documented cells: `core/interceptors`, `core/pipes`, `core/adapters`, `core/guards`, `core/injector`, `core/router`, `platform-express/adapters`, `platform-fastify/adapters`, `common/exceptions`.

Relevant:
| Cell | Relevance |
|---|---|
| `packages/core/guards` | The `CanActivate` mechanism (`GuardsConsumer`, `GuardsContextCreator`) the new guard plugs into — untouched. |
| `packages/core/router` | Confirms guards run before pipes/interceptors/handler on the HTTP path — untouched. |
| `packages/websockets` (undocumented) | Confirms `WsContextCreator` runs the *same* `GuardsConsumer.tryActivate` before WS handlers — untouched. |
| `packages/common/decorators` (undocumented) | Home of `SetMetadata`, `UseGuards`, etc. — the new marking decorator belongs here, following the same pattern. |

## Artifact Resolution
| Name/term | Resolution | Justification |
|---|---|---|
| `CanActivate`/`ExecutionContext` guard mechanism | Reuse `packages/core/guards` as-is | Already transport-agnostic (verified by reading both `core/router` and `websockets/context/ws-context-creator.ts`); no modification needed. |
| Decorator to mark handlers/controllers | New artifact | No existing decorator serves this purpose; follows the `SetMetadata`-based pattern already used by `UseGuards`/`UseInterceptors`. |
| Runtime toggle service | New artifact | No existing service holds cross-cutting runtime-flippable state. |
| Guard that enforces the mark | New artifact | A new `CanActivate` implementation, not a change to `GuardsConsumer`/`GuardsContextCreator`. |
| "maintenance mode" feature as a whole | New cell | Cohesive, self-contained cross-cutting concern; not a natural extension of any of the 9 documented cells (none owns "marking + runtime toggle + enforcement" as a responsibility). |

## Key Concepts
- **Metadata key + decorator** — a single decorator (class- or method-level) that stamps a marker onto reflection metadata, read later by the guard.
- **`MaintenanceModeService`** — injectable, holds current on/off state in memory; exposes methods to enable/disable/query, callable from anywhere in the running app (e.g. an admin endpoint).
- **`MaintenanceModeGuard`** — `CanActivate` implementation: reads the decorator's metadata off the current handler+class via `Reflector`, checks `MaintenanceModeService`, denies if both "marked" and "mode is on."

## Dark Zones
1. **Decorator name** — public API surface, needs a definitive name (e.g. `@MaintenanceAffected()` vs `@Maintenance()`).
2. **Cell placement** — `packages/common/maintenance` (framework-wide, consumable by any HTTP or WS app code — my hypothesis) vs. somewhere under `core`.
3. **Denial semantics** — should the guard itself throw a specific exception (e.g. `ServiceUnavailableException`, HTTP 503) for clearer error messages, or just return `false` and let the existing per-transport default apply (`ForbiddenException` for HTTP, generic `WsException` for WS)? Task says "rejected... with a clear error," which favors throwing an explicit exception.
4. **Global registration** — does the guard need to be applied globally (`APP_GUARD`) by the framework automatically, or does the developer explicitly add `@UseGuards(MaintenanceModeGuard)` alongside the marker decorator? (A marker with no guard attached does nothing.)

## Connection to Existing Architecture
No modification to any of the 9 documented cells. New cell composes with `packages/core/guards` (implements `CanActivate`, consumed by the existing `GuardsConsumer`/`GuardsContextCreator`) and is applied via `packages/core/router` (HTTP) and `packages/websockets` (WS) purely through the pre-existing `@UseGuards()` wiring — zero code changes in either.

## Risks and Constraints
- Must not introduce a second, WS-specific marking mechanism — single decorator, single metadata key, single guard class.
- State must be an injectable singleton (not a module-level mutable global) so it's DI-friendly and mockable in tests.
- Guard must be cheap (no I/O) since it runs on every marked request/message.

## Scope Decision
Single subsystem — proceed as one cell.

## Notes
None.

---

**One approval needed before I proceed to the type map.** Proposed resolutions to the 4 dark zones above:
1. Decorator name: **`@MaintenanceAffected()`**
2. Cell placement: **`packages/common/maintenance`**
3. Denial semantics: guard throws **`ServiceUnavailableException`** (HTTP 503) for HTTP; for WS, letting the existing `WsContextCreator` wrap the guard's `false`/thrown result into its standard `WsException` is consistent with how every other WS guard failure is surfaced — the guard itself stays exception-type-agnostic by just returning `false`, and I'll throw `ServiceUnavailableException` only when invoked in an HTTP context (the guard doesn't know it's not always HTTP).

   Actually — simpler and more consistent with "one mechanism": always throw `ServiceUnavailableException`. On HTTP it's a clean 503 with a `"Service temporarily unavailable"` (or maintenance-specific) message. On WS, Nest's `WsExceptionsHandler` catches any thrown error and turns it into an emitted error event with `{status: 'error', message}`, so an `HttpException` subclass thrown from a guard is still a reasonable, informative error there — no special-casing needed in the guard itself.
4. Global registration: **not automatic** — developer explicitly wires `@UseGuards(MaintenanceModeGuard)` (globally via `APP_GUARD`, per-controller, or per-gateway) same as any other guard; the marker decorator only has effect where the guard is active. This matches Nest's existing opt-in guard model rather than silently forcing new global behavior.

Reply "approved" to continue, or tell me which of the 4 to change.
