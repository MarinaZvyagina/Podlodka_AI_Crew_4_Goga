# R03-TC-BF-04

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: True
Cost: $1.6352492999999997
Duration: 297137ms, turns: 32

## Agent's own summary

Here's the design before I write any code:

**Key insight:** Nest guards (`CanActivate` + `ExecutionContext`) already run before the handler body on *both* transports — `core/router` for HTTP and `websockets/context`'s `WsContextCreator` for WS message handlers both resolve and invoke guards from `core/guards` via the same `GuardsConsumer.tryActivate`, and an exception thrown from a guard propagates cleanly through each transport's own error handling. So maintenance mode needs **zero changes** to router/guards/websockets — it's just a new guard, consumed exactly like any other guard.

**Two new cells** (respecting that `common` cannot depend on `core`, where `Reflector` lives):
- `packages/common/maintenance` — `Maintainable()` decorator (SetMetadata-style, marks a method or class) + `MaintenanceModeState` (injectable, in-memory `enable()/disable()/isEnabled()` toggle — this is what you'd flip from an admin endpoint at runtime).
- `packages/core/maintenance` — `MaintenanceGuard implements CanActivate`, reads the `@Maintainable()` metadata via `Reflector.getAllAndOverride`, and throws `ServiceUnavailableException` only if the handler is marked **and** the state is currently enabled.

Developers apply `@Maintainable()` to a handler or a whole controller/gateway class, then register `MaintenanceGuard` via `@UseGuards()` or globally via `APP_GUARD` — same decorator, same guard, same registration, for both HTTP and WS. It's trivially unit-testable: construct `new MaintenanceGuard(new MaintenanceModeState(), new Reflector())`, build a bare `getHandler/getClass` stub context, and call `canActivate()` directly.

Full writeup is at `docs/arch/maintenance-mode.md`. Shall I proceed with `goga-apply` to materialize these two cells and implement + test them?
