# R03-TC-BF-03

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.75
Dangerous success: False
Goga engagement signal: True
Cost: $4.881363149999998
Duration: 733680ms, turns: 88

## Agent's own summary

Clean, minimal diff. Here's a summary of the implementation:

## What was built

**Planning** — used `goga schema`/`goga lint` to read the existing 9-cell documented architecture, wrote `docs/arch/maintenance-mode.md` as an architecture plan, then materialized it via `goga-apply` into two new CODEMANIFEST-documented cells (`goga lint`/`goga schema` clean throughout).

**`packages/common/maintenance`** (no framework dependencies):
- `Maintenance()` — a `SetMetadata`-based decorator, usable on a class (controller or `@WebSocketGateway()`) or a method (HTTP handler or `@SubscribeMessage()` handler) — same shape as `@UseGuards()`.
- `MaintenanceModeService` — an `@Injectable()` singleton holding the in-memory on/off flag (`enable()`/`disable()`/`isEnabled()`), toggleable from anywhere in the running app (e.g. an admin controller), no redeploy needed.

**`packages/core/maintenance`**:
- `MaintenanceModeGuard` — an ordinary `CanActivate` guard. It reads the `Maintenance()` metadata via `Reflector.getAllAndOverride` (handler first, falling back to class), and if the target is marked and maintenance mode is on, throws `ServiceUnavailableException` (503) before any handler logic runs.

Because Nest's guard pipeline is already transport-agnostic (the same `GuardsConsumer`/`GuardsContextCreator` machinery is invoked identically by `core/router` for HTTP and by `websockets` for `@SubscribeMessage()`), registering this **one** guard — globally via `APP_GUARD` or locally via `@UseGuards(MaintenanceModeGuard)` — protects both HTTP and WebSocket handlers with no transport-specific branching.

**Tests** (15 new, all passing, no server/socket involved): decorator metadata attachment, service state transitions, and guard behavior across every (marked/unmarked) × (on/off) combination, including an explicit case showing the identical guard rejects both an HTTP-shaped and a WS-`@SubscribeMessage()`-shaped handler.

Verified: `goga lint` (0 errors), full `tsc -b packages` build, and the full existing suite (178 files / 1788 tests) all pass.
