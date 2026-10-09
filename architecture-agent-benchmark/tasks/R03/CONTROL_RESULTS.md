# R03 (nestjs/nest) — Phase 4/5 Control Results

Repository: `nestjs/nest`, pinned commit `f94e9eb15ba2a22f69aef234cb81333764d0b298`.

Method: cloned the pinned commit into `/tmp/benchmark-repos/R03/base`, then made four
independent working copies (`repo_A`..`repo_D`) via local `git clone`, each with
`npm install --legacy-peer-deps` run once. Each task's positive and negative control was
implemented as real code in its own working copy, exercised via `npx vitest run` (unit specs
run directly against TypeScript source; end-to-end specs run via
`npx vitest run --config vitest.config.integration.mts <path under integration/>`, which
resolves `.js` relative imports back to sibling `.ts` source so no build step is required), and
against every validator script for that task. Working copies were reset with
`git checkout -- . && git clean -fd` between controls. `package-lock.json` churn produced by
`npm install` was excluded from all diffs as installer noise, not part of any control's diff.

---

## Task A — R03-TA: `TooManyRequestsException` (429)

**Category:** local_change. Add a new built-in HTTP exception class for status 429, following
the one-file-per-status-code convention already used by the 21 sibling exception classes in
`packages/common/exceptions/`.

### Validators
- `validators/task_A_AC1.sh` — scope check: all changed files rooted at
  `packages/common/exceptions/`, `packages/common/test/exceptions/`, or the optional
  `packages/common/utils/http-error-by-code.util.ts`.
- `validators/task_A_AC2.sh` — greps the new exception file for `extends HttpException`.
- `validators/task_A_AC3.sh` — diffs `packages/common/package.json`; greps changed files for
  `from '@nestjs/core'` / `from '@nestjs/platform-`.
- `validators/task_A_AC4.sh` — confirms a new `export * from './too-many-requests.exception.js'`
  line was added to the barrel, and that `packages/common/index.ts` still re-exports the barrel.

All four scripts implement their check fully automatically (no MANUAL REVIEW REQUIRED needed for
this task — every check is a grep/diff over paths and file content).

### Positive control (`controls/task_A_positive.diff`)
Adds `packages/common/exceptions/too-many-requests.exception.ts` — a thin `TooManyRequestsException
extends HttpException` constructor mirroring `ConflictException`/`ForbiddenException` exactly
(same `objectOrError`/`descriptionOrOptions` signature, default message `"Too Many Requests"`,
`HttpStatus.TOO_MANY_REQUESTS` baked in, `@publicApi` doc comment). Exports it from
`packages/common/exceptions/index.ts` in alphabetical position. Adds
`packages/common/test/exceptions/too-many-requests.exception.spec.ts`, mirroring
`conflict.exception.spec.ts` (status code, default message, custom message, custom object, cause
option, `instanceof HttpException`/`Error`). Verified end-to-end with a scratch
`integration/_scratch-429` app (platform-express, a route handler throwing
`new TooManyRequestsException()`, asserted HTTP 429 + `statusCode: 429` body via supertest); the
scratch harness was deleted before taking the diff since it is not part of the deliverable change.

### Negative/trap control (`controls/task_A_negative.diff`)
Adds `packages/core/exceptions/rate-limit.exception.ts` — a bespoke `RateLimitException extends
Error` (not `HttpException`) — and special-cases it inside
`packages/core/exceptions/base-exception-filter.ts`'s `catch()` method with an
`instanceof RateLimitException` branch that manually builds a 429 response body and calls
`applicationRef.reply(...)`, bypassing the generic `HttpException` handling path entirely.
Exported from `packages/core/exceptions/index.ts`. Verified end-to-end the same way as the
positive control (scratch app, `throw new RateLimitException()` from a route handler) — the HTTP
response is still 429 with `statusCode: 429`, i.e. functionally indistinguishable from the
correct solution to a request-level test.

### Results

| Check | Positive control | Negative (trap) control |
|---|---|---|
| Functional (unit specs, `packages/common/test/exceptions`) | PASS (170/170 tests, incl. 6 new) | N/A — trap class lives outside `packages/common`, so it is not exercised by this exact vitest target; verified instead via the scratch e2e app (see below) |
| Functional (e2e: throw from route handler, assert HTTP 429) | PASS | PASS (this is the "dangerous success" — a naive HTTP-level test cannot tell the two apart) |
| AC1 (scope) | PASS | **FAIL** — touches `packages/core/exceptions/*`, not `packages/common/exceptions/*` |
| AC2 (extends HttpException) | PASS | **FAIL** — no candidate file under `packages/common/exceptions` contains `extends HttpException`; `RateLimitException` extends `Error` |
| AC3 (no new cross-package dependency) | PASS | PASS (trivially — the trap doesn't touch `packages/common/package.json` or add a `@nestjs/core`/`@nestjs/platform-*` import; it *is* the forbidden code living in `packages/core`, which AC1/AC2 catch instead) |
| AC4 (exported via standard barrel) | PASS | **FAIL** — no new export line added to `packages/common/exceptions/index.ts` |

### Verdict: **DISCRIMINATES**

The positive control passes the functional check and all four architecture checks. The negative
control passes the functional check (429 returned correctly to an HTTP client — a textbook
"Dangerous Success") but fails 3 of 4 architecture checks (AC1, AC2, AC4). No validator needed
adjustment; all four discriminated correctly on first implementation. AC3 does not itself catch
this particular trap (the trap doesn't create a *dependency* edge, it just puts code in the wrong
*package*), which is expected — AC1/AC2/AC4 are the checks doing the discriminating work here,
and that is fine since only ≥1 architecture check needs to fail for a valid negative control.

---

## Task B — R03-TB: WebSocket graceful-shutdown notification

**Category:** cross_module_feature. Every connected WebSocket client must receive a shutdown
notification before its connection is closed, as part of the app's existing graceful-shutdown
flow, equivalently for `packages/platform-socket.io` and `packages/platform-ws`.

### Validators
- `validators/task_B_AC1.sh` — checks the new logic is reachable purely from the standard
  `close()`/DI shutdown-hook chain, not a new manually-invoked entrypoint.
- `validators/task_B_AC2.sh` — greps the diff for `SocketsContainer` usage vs. any new
  independently-maintained registry of connected sockets/gateways.
- `validators/task_B_AC3.sh` — checks that both `packages/platform-socket.io/adapters/io-adapter.ts`
  and `packages/platform-ws/adapters/ws-adapter.ts` (or the shared base class) received comparable
  changes, and that `packages/core`/`packages/websockets` contain no socket.io-/ws-specific wire
  calls outside the adapter files.
- `validators/task_B_AC4.sh` — diffs `packages/core/package.json`/`packages/websockets/package.json`
  and greps changed non-test `.ts` files for static `from '@nestjs/platform-socket.io'` /
  `from '@nestjs/platform-ws'` imports.
- `validators/task_B_AC5.sh` — a genuine runnable regression check: shells out to
  `npx vitest run packages/websockets packages/platform-socket.io packages/platform-ws` and gates
  PASS/FAIL on the real exit code.

**Design note surfaced during validation:** the implementing agent found, by reading
`nest-application-context.ts`, that `callShutdownHook()` (the literal `onApplicationShutdown` DI
hook) fires *after* `dispose()` already tears down sockets — so a provider hung purely off
`onApplicationShutdown` cannot structurally notify clients before disconnect. The positive control
instead hooks into `packages/websockets/socket-module.ts`'s existing `close()`, which is itself
invoked from the same `app.close()`/`enableShutdownHooks()` dispose chain the task's architectural
constraint is protecting (no separate, manually-invoked entrypoint is introduced). AC1 was written
to accept this reachability model as satisfying the constraint's intent (reachable automatically
from `close()`, no extra call required in application code) rather than requiring the literal
`OnApplicationShutdown` interface to be implemented by name.

### Positive control (`controls/task_B_positive.diff`, 6 files)
Adds an optional `notifyShutdown?(server, reason?)` method to the `WebSocketAdapter` interface
(`packages/common/interfaces/websockets/web-socket-adapter.interface.ts`) with a no-op default in
`AbstractWsAdapter` (`packages/websockets/adapters/ws-adapter.ts`) — additive/optional, consistent
with the existing `bindClientDisconnect?` pattern. `socket-module.ts`'s `close()` iterates the
existing `SocketsContainer` and calls `adapter.notifyShutdown?.(server)` for every registered
gateway server before the pre-existing `adapter.close(server)` call. Concrete behavior:
`IoAdapter.notifyShutdown` does `server.emit('shutdown', {message})` plus a short flush wait (needed
because socket.io's `close()` otherwise races the emit off the wire); `WsAdapter.notifyShutdown`
sends a JSON `{event:'shutdown', data}` message to every open client in `server.clients`. New
shared constants (`SHUTDOWN_EVENT`, `DEFAULT_SHUTDOWN_MESSAGE`) added to
`packages/websockets/constants.ts`.

### Negative/trap control (`controls/task_B_negative.diff`, 1 file)
Same trigger point (`socket-module.ts`'s `close()`, same `SocketsContainer` iteration), but
instead of going through the adapter abstraction, does
`(server as any).sockets && (server as any).emit('shutdown', ...)` inline — hardcoded socket.io
duck-typing with no `ws`-library support at all (raw `ws` servers have no `.sockets` property, so
platform-ws clients receive nothing).

### Results

| Check | Positive control | Negative (trap) control |
|---|---|---|
| Functional — socket.io e2e (client gets notified before disconnect) | PASS | PASS |
| Functional — platform-ws e2e (client gets notified before disconnect) | PASS | **FAIL** (no message ever sent) |
| AC1 (wired through standard close/shutdown chain) | PASS | PASS |
| AC2 (SocketsContainer, no new bookkeeping) | PASS | PASS |
| AC3 (adapter abstraction, symmetric across platforms) | PASS | **FAIL** (neither platform adapter touched; inline `.emit()` sits directly in `packages/websockets`) |
| AC4 (no new static platform dependency) | PASS | PASS |
| AC5 (existing websockets/platform-socket.io/platform-ws suites regression-free, 113 tests) | PASS | PASS |

### Verdict: **DISCRIMINATES**

AC3 — and the trap's own platform-ws functional test — correctly catch the trap: it passes the
socket.io-only naive check but silently does nothing for `ws`-based apps, which is exactly the
"Dangerous Success if the validator isn't run against both platforms" scenario the task's
ground-truth notes predicted. All 5 checks pass cleanly for the honest implementation; no
validator required tuning after the first implementation pass (unlike Tasks C/D, no bugs were
found in the validators themselves during this task).

Honesty notes from the implementing agent, preserved here rather than smoothed over:
- `integration/hooks/e2e/enable-shutdown-hook.spec.ts` (a spawned-child-process signal test) is
  flaky/fails intermittently in this sandbox even on the unmodified pinned commit (verified via
  `git stash`) — a pre-existing environment issue unrelated to this change, outside AC5's defined
  scope (`packages/*` suites only), and left unfixed.
- Running the new feature against the pre-existing `integration/websockets` e2e suite (not part of
  the official AC5 command) surfaces stray-listener failures in `ws-gateway.spec.ts`/
  `ws-error-gateway.spec.ts`: those tests leave WS clients open across test boundaries (using `.on`
  instead of `.once`), so the new shutdown broadcast reaches lingering listeners from earlier
  tests. This is a real interaction worth a human reviewer's attention on a genuine PR, but it is
  outside AC5's method as specified in the ground-truth metadata, so it does not affect the
  validator's verdict.
- socket.io needs a short flush delay between `emit()` and `close()` for the notification to
  reliably reach the client before disconnect; without it the functional e2e test is flaky. This
  delay is included in the positive control's `IoAdapter.notifyShutdown`.

`repo_B` confirmed clean (`git status --porcelain` empty) at the end.

---

## Task C — R03-TC: Maintenance-mode guard (HTTP + WebSocket)

**Category:** existing_extension_point. A developer must be able to mark a handler/controller as
"affected by maintenance mode" such that marked HTTP routes and WS message handlers are rejected
before their body runs, using one consistent mechanism for both transports.

### Validators
- `validators/task_C_AC1.sh` — greps the diff for `implements CanActivate`.
- `validators/task_C_AC2.sh` — greps the diff for `SetMetadata`/`Reflector` usage vs. suspicious
  hardcoded path-string registries (`Set<string>`/array of literal URL paths checked against
  `request.url`/`request.path`).
- `validators/task_C_AC3.sh` — cross-references whether the diff's test/example files exercise
  the same guard class against both an HTTP controller and a `@SubscribeMessage` WS handler, and
  confirms zero new code in `packages/platform-express`/`packages/platform-fastify`. Falls back to
  "MANUAL REVIEW REQUIRED" only in the genuinely ambiguous case where a `CanActivate` class exists
  but cross-referencing it to both transport test files is unclear — if no `CanActivate` class
  exists at all (AC1 already establishes that), it reports a clean FAIL rather than punting.
- `validators/task_C_AC4.sh` — greps the diff for `.use(` raw middleware registration or edits
  inside `express-adapter.ts`/`fastify-adapter.ts`.

### Positive control (`controls/task_C_positive.diff`, under `integration/maintenance-mode/`)
`MaintenanceModeGuard implements CanActivate` (injects `Reflector` + a `MaintenanceModeService`),
reads a `@MaintenanceProtected()` decorator (built on `SetMetadata`) via
`reflector.getAllAndOverride(MAINTENANCE_PROTECTED_KEY, [handler, class])`, and throws
`ServiceUnavailableException` when the handler is marked and maintenance mode is on. Registered
globally via `{ provide: APP_GUARD, useClass: MaintenanceModeGuard }`. Demonstrated and tested
against a real `AppController` HTTP route (`/protected`) AND a real `AppGateway`
`@SubscribeMessage('protectedMessage')` handler, both booted via `Test.createTestingModule()` +
`app.listen()` + a real `socket.io-client` connection — not mocked. 9/9 tests pass: 4 pure unit
tests instantiating the guard directly against mock `ExecutionContext`s (no server), plus 5 e2e
tests over real HTTP/WS.

### Negative/trap control (`controls/task_C_negative.diff`)
Same demo app, but protection is implemented as raw `app.use((req, res, next) => {...})` Express
middleware registered directly on the Nest app, checking `req.path` against a hardcoded
`new Set<string>(['/protected'])` inside `MaintenanceModeService`. No `CanActivate` class exists
anywhere in the diff. The WS gateway is left completely unprotected — proven by an e2e test
explicitly titled to flag the bug, showing the protected WS handler still executes during
maintenance mode.

### Results

| Check | Positive control | Negative (trap) control |
|---|---|---|
| Functional — unit (guard in isolation, no server) | PASS (4 tests) | N/A — no guard class exists to unit-test in the trap |
| Functional — e2e HTTP | PASS | PASS (a naive HTTP-only functional test would be fooled) |
| Functional — e2e WS | PASS | **FAILS as intended** (protected WS handler still executes) |
| AC1 (CanActivate) | PASS | **FAIL** |
| AC2 (reflective metadata, not path registry) | PASS | **FAIL** |
| AC3 (same mechanism for HTTP+WS, no platform-* code) | PASS | **FAIL** |
| AC4 (no raw middleware/adapter bypass) | PASS | **FAIL** |

### Verdict: **DISCRIMINATES**

All 4 architecture validators pass unanimously on the positive control and fail unanimously on
the negative control. The trap's HTTP-facing behavior looks correct to a naive, HTTP-only
functional test (its whole reason for being a plausible trap), but its WS gateway is silently
unprotected and every architecture check flags the underlying mechanism (raw middleware +
string-keyed registry instead of guard + metadata).

One real implementation bug was found and fixed while building the positive control's own test
harness (not the validators): `vi.spyOn(ControllerPrototype, 'method')` strips the
`Reflect`-metadata that Nest decorators (`@Get`, `@MaintenanceProtected`) attach to the original
function object, silently breaking route registration (404s) — switched to a plain `callLog`
array pushed to from inside handler bodies, which still satisfies "assert the handler didn't
execute" without corrupting decorator metadata. One validator calibration fix: AC3 initially
returned "MANUAL REVIEW REQUIRED" even in the unambiguous case where no `CanActivate` class
exists at all (already conclusively established by AC1); changed to report a clean FAIL in that
case and reserved "MANUAL REVIEW REQUIRED" for genuine ambiguity only. Both controls were re-run
after the fix and still discriminate correctly. `repo_C` confirmed clean
(`git status --porcelain` empty) at the end.

---

## Task D — R03-TD: Cross-platform correlation/request-ID header

**Category:** architecture_trap. Every HTTP response must carry a request/correlation ID header,
reused from an incoming header if present, readable from application code, and working
identically under `packages/platform-express` and `packages/platform-fastify`.

### Validators
- `validators/task_D_AC1.sh` — greps `packages/core/**/*.ts` (excluding `http-adapter.ts` itself)
  and diff-touched `packages/common/**/*.ts` for raw `.setHeader(`/`.appendHeader(` calls not
  dispatched through `httpAdapter`/`applicationRef`; skips JSDoc comment lines to avoid a
  false-positive on doc-comment mentions of `response.setHeader`.
- `validators/task_D_AC2.sh` — `git diff --stat` symmetry check: both platform adapters changed
  equivalently, or neither changed because the feature lives entirely above the adapter layer.
- `validators/task_D_AC3.sh` — greps for `getType() ===`, `instanceof ExpressAdapter`,
  `instanceof FastifyAdapter` in `packages/core`/`packages/common`.
- `validators/task_D_AC4.sh` — checks new/changed test files reference both
  `ExpressAdapter`/platform-express and `FastifyAdapter`/platform-fastify bootstrapping.
- `validators/task_D_AC5.sh` — a genuine runnable check, not review-only: boots the diff's actual
  changed module/controller under `FastifyAdapter` (running the diff's own Fastify e2e spec if
  one exists, else auto-synthesizing and executing a minimal one against the discovered
  module), issues a real request, and asserts the header is present and well-formed.

File enumeration in these scripts uses `git diff --name-only HEAD` unioned with
`git ls-files --others --exclude-standard` (plain `git status --porcelain` was found during
development to collapse untracked directories into a single line and miss individual new files
inside them — fixed and re-verified).

### Positive control (`controls/task_D_positive.diff`, under `integration/_scratch-D/`)
A global `APP_INTERCEPTOR` (`request-id.interceptor.ts`) reads `request.headers['x-request-id']`
(plain-object header access — valid on both platforms' underlying request objects) or generates
one via `randomUUID()`, sets the response header through
`this.adapterHost.httpAdapter.setHeader(response, 'X-Request-Id', id)` (dispatched through
`HttpAdapterHost`/`AbstractHttpAdapter`, never a raw platform call), and exposes the value to
application code via a Node `AsyncLocalStorage` holder (`request-id.storage.ts`) read inside the
controller as `getRequestId()` — no assumption about either platform's request/response object
shape anywhere in the implementation.

### Negative/trap control (`controls/task_D_negative.diff`)
`request-id.middleware.ts` obtains the raw Express instance via
`app.getHttpAdapter().getInstance()` and registers `expressApp.use((req, res, next) => {
res.setHeader('X-Request-Id', id); next(); })` directly — bypassing `AbstractHttpAdapter`
entirely and assuming an Express/Node response shape. This is a textbook "Dangerous Success": its
Express-only e2e spec (`request-id-express.spec.ts`) is fully green, but booting the identical
`AppModule` + middleware setup under `FastifyAdapter` throws `expressApp.use is not a function`
and returns no `X-Request-Id` header at all — confirmed via a throwaway probe before cleanup.

### Results

| Check | Positive control | Negative (trap) control |
|---|---|---|
| Functional — under platform-express | PASS | PASS (naive Express-only suite is fully green) |
| Functional — under platform-fastify | PASS | **FAIL** (middleware throws; no header; body empty) |
| AC1 (header set via abstract adapter, not raw call) | PASS | **FAIL** |
| AC2 (symmetric / adapter-neutral implementation) | PASS | **FAIL** (Express-only escape hatch) |
| AC3 (no platform-type branching in shared code) | PASS | PASS — see note below |
| AC4 (test coverage includes both platforms) | PASS | **FAIL** (no Fastify spec in the diff) |
| AC5 (real, runnable Fastify boot verification) | PASS | **FAIL** (auto-synthesized Fastify run finds no header) |

### Verdict: **DISCRIMINATES**

4 of 5 validators (AC1, AC2, AC4, AC5) correctly flip from PASS on the positive control to FAIL on
the negative control, and the negative control's functional check is green under Express while
failing under Fastify — precisely the "functionally-green, architecturally-broken" pattern this
task is designed to probe for. AC3 passes on *both* controls by design/correctly: it targets
platform-*branching* (`getType() === 'express'`-style conditionals), which is a different
architectural smell than the trap's actual mistake (hardcoding to one platform without any
branch at all) — this is expected behavior, not a miscalibration, and is called out explicitly
rather than treated as a false negative.

Two bugs were found and fixed in the validators during development (before finalizing): AC1 had
a false positive matching `response.setHeader` mentioned inside a JSDoc comment (fixed by
skipping comment lines before receiver extraction), and file enumeration under-counted new files
inside newly-created untracked directories (fixed by switching to
`git diff --name-only HEAD` + `git ls-files --others --exclude-standard`). Both controls were
re-run after each fix to confirm calibration. `repo_D` was confirmed clean
(`git status --porcelain` empty) at the end.
