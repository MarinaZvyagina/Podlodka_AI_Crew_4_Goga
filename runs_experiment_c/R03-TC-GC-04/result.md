# R03-TC-GC-04

Condition: goga_native_architecture
Base tag: condition-c-r03-v1
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: False
Cost: $0.2870067
Duration: 29056ms, turns: 2

## Agent's own summary

This repo is the NestJS framework source (packages/common, packages/core, packages/websockets, etc.) plus ~36 independent sample apps — there's no single "our API" application here, so before I write anything I need to know where this should live.

My recommended approach either way: a single `@MaintenanceMode()` decorator (via `SetMetadata`, usable on both methods and whole classes) paired with one `MaintenanceModeGuard` that reads that metadata with `Reflector.getAllAndOverride` and consults a small toggleable `MaintenanceModeService` (in-memory flag, `enable()`/`disable()`/`isEnabled()`). Since Nest's `CanActivate` guards receive a platform-agnostic `ExecutionContext` and run identically for HTTP controllers and WS gateway message handlers (via `@UseGuards`), this one mechanism naturally covers both without separate code paths — and it's trivial to unit test by hand-constructing a mock `ExecutionContext` (`getHandler`/`getClass`/`getType`) and calling `canActivate()` directly, no server or socket needed.

Where would you like this implemented — a specific sample app (e.g. `sample/02-gateways` or `sample/16-gateways-ws`, which already mix HTTP + WS), or as a new demo app under `sample/`? Or did you mean this as a reusable addition to the framework packages themselves (`packages/common`/`packages/core`)?
