# R03-TC-GC-06

Condition: goga_native_architecture
Base tag: condition-c-r03-v1
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: True
Cost: $1.0593072
Duration: 187564ms, turns: 26

## Agent's own summary

Now writing the Scope Resolution Report.

# Scope Resolution Report

## Task Summary
Add a "maintenance mode" capability: a decorator to mark HTTP route handlers/controllers and WebSocket message handlers as "affected by maintenance mode," a runtime-toggleable state (no redeploy), and a guard that rejects marked handlers before their logic runs when maintenance mode is on. Must use one consistent mechanism for both HTTP and WS, and be unit-testable without a real server/socket.

## Candidate Cells
| Cell | Reason | Priority |
|---|---|---|
| packages/core/guards | Owns the `CanActivate` extension mechanism (`GuardsConsumer`, `GuardsContextCreator`) that a maintenance guard would plug into | High (reference only) |
| packages/core/injector | `Reflector`/metadata plumbing lives adjacent (packages/core/services, ungoverned) | Low (reference only) |
| packages/core/router | Composes guards into the HTTP request pipeline | Low (reference only) |

## Included Dependencies
| Cell | Behavioral Relevance |
|---|---|
| packages/core/guards | Confirms `CanActivate.canActivate(context: ExecutionContext)` is invoked uniformly for HTTP and WS (verified: `packages/websockets/context/ws-context-creator.ts` calls the same `GuardsConsumer.tryActivate`) — this is the existing "one consistent mechanism" the task asks for. No behavior in this cell needs to change. |

## Excluded Dependencies
| Cell | Exclusion Reason |
|---|---|
| packages/core/injector | Only supplies DI plumbing; no data flow or contract change needed |
| packages/core/router | Only consumes guards as-is; no signature/contract change needed |
| packages/common/exceptions | A standard `HttpException`/`WsException` subtype is sufficient; no new exception type needs to be added to this governed cell |
| packages/platform-express/adapters, packages/platform-fastify/adapters | Purely infrastructural HTTP adapters; no participation in guard/metadata semantics |

## Usage Relationships
| Usage | Relevance |
|---|---|
| none | No `.usages` practice files exist for `packages/core/guards` or any candidate cell (confirmed via `goga schema`: `usages: []` on every relevant cell) |

## Semantic Participation Summary
The only governed cell semantically touched by this task is `packages/core/guards`, and only as a *consumer* of its existing, unmodified contract: a new `CanActivate` implementation is exactly the extension point that cell documents. Nest already invokes guards identically for HTTP and WS execution contexts (verified directly in `ws-context-creator.ts`), so the "one consistent mechanism" requirement is satisfied by the framework as-is — no core framework behavior needs to change. The decorator/metadata piece relies on `Reflector` (`packages/core/services/reflector.service.ts`), which is **not** a governed cell (absent from `goga schema` output). This task is therefore net-new, additive application code built entirely on top of existing, stable public contracts — it does not modify any CODEMANIFEST-governed cell.

## Final Investigation Scope
- packages/core/guards (read-only reference — confirm contract stability, no modification)
- packages/websockets/context (read-only reference — confirm WS guard invocation parity, ungoverned)
- New code location: outside governed cells (application-level feature), to be placed in a sample app demonstrating both an HTTP controller and a WS gateway (`sample/02-gateways`), since no `sample/*` directory is part of the goga cell schema

## Scope Risks
- **Under-scoping risk**: none identified — no governed cell's exported contract needs modification, so there is no risk of silently breaking a documented API.
- **Over-scoping risk**: initially assumed core framework packages needed a new built-in "maintenance guard" — rejected, since Nest ships no precedent of concrete, business-specific built-in guards in `packages/core`; this would incorrectly conflate a framework mechanism with an application feature.

## Notes
Because the Final Investigation Scope contains zero governed-cell modifications, this change pipeline's manifest/usage reconciliation steps (Steps 7–8) are expected to be no-ops. Implementation will proceed as standard, non-cell-governed application code plus tests, per the existing `packages/core/guards` contract.
