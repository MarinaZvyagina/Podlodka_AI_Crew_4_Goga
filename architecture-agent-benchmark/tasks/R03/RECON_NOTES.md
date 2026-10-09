# R03 (nestjs/nest) — Task Design Recon Notes

Repository: `nestjs/nest`
Pinned commit: `f94e9eb15ba2a22f69aef234cb81333764d0b298`
Method: **no local clone** (disk constraint). All evidence gathered via `gh api
repos/nestjs/nest/git/trees/<sha>?recursive=1` (full recursive tree, 3000 paths, `truncated:
false`) and `curl -s https://raw.githubusercontent.com/nestjs/nest/<sha>/<path>` for file
contents. All file paths and code excerpts below were read directly from the pinned commit, not
from memory/training data about NestJS in general — every claim below has a concrete grep/curl
command behind it (transcript available in this session's tool calls).

This repo is the **framework itself**, not an application built with the framework. That shapes
all four tasks: "cross-module" here means crossing framework packages (core / common / websockets
/ platform-*), not "controller → service → repository" business layers, which don't exist in this
codebase. I flagged this early because Research.md's illustrative Task D example (cache behind a
repository abstraction) doesn't literally map onto this repo — I built an equivalent, but
genuinely repo-grounded, "reach into the wrong layer" trap instead of forcing the illustrative
example to fit.

## Key real boundaries confirmed by reading code

1. **Pipe pipeline** — `packages/common/interfaces/features/pipe-transform.interface.ts`
   (`PipeTransform`), `packages/core/pipes/{pipes-consumer,pipes-context-creator}.ts`. Built-in
   pipes live one-per-file in `packages/common/pipes/parse-*.pipe.ts` (int, float, bool, date,
   enum, uuid, array). Confirmed via `packages/common/pipes/index.ts` barrel.

2. **Exception classes** — `packages/common/exceptions/*.exception.ts`, all extending
   `HttpException` (`packages/common/exceptions/http.exception.ts`), one file per status code
   (bad-gateway, bad-request, conflict, forbidden, gateway-timeout, gone,
   http-version-not-supported, im-a-teapot, internal-server-error, method-not-allowed,
   misdirected, not-acceptable, not-found, not-implemented, payload-too-large,
   precondition-failed, request-timeout, service-unavailable, unauthorized,
   unprocessable-entity, unsupported-media-type). Confirmed **429 (Too Many Requests) is
   genuinely missing** — `HttpStatus.TOO_MANY_REQUESTS = 429` exists in
   `packages/common/enums/http-status.enum.ts` but has no dedicated exception class, and is
   absent from `HttpErrorByCode` in `packages/common/utils/http-error-by-code.util.ts`. Read
   `conflict.exception.ts` in full as the template (constructor pattern:
   `(objectOrError?, descriptionOrOptions: string | HttpExceptionOptions = 'Conflict')`, matching
   test file convention under `packages/common/test/exceptions/*.spec.ts`).

3. **Guards** — `CanActivate` interface
   (`packages/common/interfaces/features/can-activate.interface.ts`), executed by
   `GuardsConsumer`/`GuardsContextCreator`
   (`packages/core/guards/guards-consumer.ts`, `guards-context-creator.ts`), driven by metadata
   (`GUARDS_METADATA`), registerable via `@UseGuards`
   (`packages/common/decorators/core/use-guards.decorator.ts`) or globally via `APP_GUARD`
   (`packages/core/constants.ts`). **Critically verified cross-transport reuse**: I grepped
   `packages/websockets/context/ws-context-creator.ts` and confirmed it imports and drives the
   *same* `GuardsConsumer`/`GuardsContextCreator` classes from `packages/core/guards` (not a
   websockets-specific reimplementation) — i.e. guards are not just "documented as reusable",
   they are actually the one mechanism already shared between the HTTP pipeline
   (`packages/core/router/router-execution-context.ts`) and WebSocket gateway message handlers in
   this exact codebase. This is the evidentiary basis for Task C.
   `SetMetadata` (`packages/common/decorators/core/set-metadata.decorator.ts`) +
   `Reflector` (`packages/core/services/reflector.service.ts`) is the standard pairing for
   attaching/reading per-handler metadata that guards consume.

4. **AbstractHttpAdapter** — `packages/core/adapters/http-adapter.ts`, an abstract class with
   concrete instance methods (`use`, `get`, `post`, ...) delegating to `this.instance`, plus a
   long list of `abstract` methods including `setHeader(response, name, value)` and
   `appendHeader(response, name, value)`. Confirmed the two concrete implementations diverge in
   exactly the way the trap requires:
   - `packages/platform-express/adapters/express-adapter.ts`:
     `setHeader(response, name, value) { return response.set(name, value); }`
   - `packages/platform-fastify/adapters/fastify-adapter.ts`:
     `setHeader(response, name, value) { return response.header(name, value); }`
   Also confirmed `HttpAdapterHost` (`packages/core/helpers/http-adapter-host.ts`) as the DI-held
   handle onto the active adapter, and confirmed `BaseExceptionFilter`
   (`packages/core/exceptions/base-exception-filter.ts`) as an existing real example of core code
   correctly going through `applicationRef.reply()/.isHeadersSent()/.end()` instead of touching
   the raw response object directly — i.e. the "correct" pattern for Task D is not hypothetical,
   it's how the framework already treats response manipulation elsewhere. This is the evidentiary
   basis for Task D.

5. **WebSocket adapter abstraction** — `WebSocketAdapter` interface
   (`packages/common/interfaces/websockets/web-socket-adapter.interface.ts`, methods `create`,
   `bindClientConnect`, `bindClientDisconnect?`, `bindMessageHandlers`, `close`), base class
   `AbstractWsAdapter` (`packages/websockets/adapters/ws-adapter.ts`), concrete adapters
   `packages/platform-socket.io/adapters/io-adapter.ts` (`IoAdapter`) and
   `packages/platform-ws/adapters/ws-adapter.ts` (`WsAdapter`). Confirmed `close()` differs
   materially per platform (`io-adapter.ts` calls `super.close(server)` after some socket.io
   bookkeeping; `ws-adapter.ts` wraps `server.close()` in a promise and also closes a registry of
   raw HTTP servers). Confirmed `SocketsContainer`
   (`packages/websockets/sockets-container.ts`) is the existing registry of all active gateway
   server+event-stream hosts (`getAll()`, `addOne()`, keyed by hashed gateway options), populated
   by `packages/websockets/socket-module.ts`.

6. **Graceful shutdown / DI lifecycle hooks** — confirmed in
   `packages/core/nest-application-context.ts`: `enableShutdownHooks(signals, options)`,
   `close(signal?)` which calls `callBeforeShutdownHook`/`callShutdownHook`. The hook contract
   `OnApplicationShutdown` lives at
   `packages/common/interfaces/hooks/on-application-shutdown.interface.ts`, orchestrated by
   `packages/core/hooks/on-app-shutdown.hook.ts`. `packages/core/nest-application.ts`'s `close()`
   already calls `this.socketModule?.close()`, `this.microservicesModule?.close()`,
   `this.httpAdapter?.close()`, and each registered microservice's `.close()` — i.e. graceful
   shutdown already fans out across exactly the packages Task B needs to touch. Real
   integration-test precedent exists at `integration/graceful-shutdown/` and
   `integration/hooks/e2e/{before-app-shutdown,enable-shutdown-hook,on-app-shutdown}.spec.ts`,
   confirming this is a genuinely exercised, non-hypothetical part of the framework.

7. **Dependency direction (verified via `package.json` `dependencies`/`peerDependencies` for
   core, common, websockets, platform-socket.io, platform-ws, platform-express,
   platform-fastify, microservices, testing)**:
   - `packages/core` has **no** dependency on any `platform-*` package in its `dependencies`
     field; `platform-express`/`platform-fastify`/etc. appear only as optional `peerDependencies`
     (for default-adapter convenience), and are loaded, when needed, exclusively through
     `packages/core/helpers/load-adapter.ts`'s `loadAdapter()`, which does a dynamic `import()` —
     I grepped the full tree for any static `from '@nestjs/platform-*'` import inside
     `packages/core` or `packages/websockets` source (excluding tests/integration) and found
     **none**. This dynamic-load pattern is what "allowed dynamic loading, forbidden static
     import" in the B/D metadata is grounded in.
   - `packages/websockets` peer-depends on `@nestjs/platform-socket.io` (as its default adapter)
     but, per the same grep, does not statically import it.
   - `packages/platform-express` and `packages/platform-fastify` depend on `@nestjs/common` +
     `@nestjs/core` only — never on each other. This is the basis for Task D's "no
     platform-express ↔ platform-fastify edge" constraint.

## Task-by-task rationale

- **Task A (Local Change)** — Add `TooManyRequestsException` (429). Fully bounded to
  `packages/common/exceptions/` (+ barrel + tests), following an exact, already-established
  one-class-per-status-code convention with 21 existing siblings. No DI, no adapter, no
  cross-package reasoning required — a clean "simple/bounded" baseline task, deliberately
  *not* using an extension point at all (so it doesn't overlap with Task C).

- **Task B (Cross-module Feature)** — WebSocket graceful-shutdown notification. Genuinely spans
  **3 real boundaries**: (1) `packages/core`'s DI-orchestrated lifecycle-hook/shutdown flow, (2)
  `packages/websockets`'s gateway registry (`SocketsContainer`) and shared adapter abstraction,
  (3) the two platform packages' concrete, materially-different `close()`/wire-protocol
  implementations (`platform-socket.io`, `platform-ws`). A correct solution requires tracing how
  `close()` fans out today and reusing the existing registry rather than inventing a parallel one.

- **Task C (Existing Extension Point)** — "Maintenance mode" per-handler blocking, transport
  gnostic (HTTP + WS gateway). Natural solution = guards + SetMetadata + Reflector, verified
  above to be the one mechanism *actually* shared between HTTP and WS gateways in this codebase
  (not just superficially similar-looking parallel systems). Prompt uses only generic language
  ("mark ... as affected", "rejected before ... logic runs", "one consistent approach") — grep
  confirms zero occurrences of `guard`, `CanActivate`, `interceptor`, `Reflector`,
  `SetMetadata`, `decorator`, or any class name in `task_C.md`.

- **Task D (Architecture Trap)** — Cross-platform request-ID response header. The "easy" path
  (grab the raw response object and call `.setHeader()` on it directly, or hardcode into
  `platform-express` only) compiles and passes an Express-only functional test, since Express's
  response object happens to expose Node's `http.ServerResponse` API — but Fastify's `reply`
  object does not expose `.setHeader` the same way (it uses `.header()`), so the same code either
  throws or silently no-ops under `platform-fastify`. This is a textbook "Functional Success +
  Architecture Violation" (Dangerous Success) setup, and it's grounded in an actual, verified
  divergence between two real adapter implementations rather than an invented scenario — see
  `AbstractHttpAdapter.setHeader` excerpts above.

## Leakage check

Ran `grep -in "guard\|CanActivate\|interceptor\|Reflector\|SetMetadata\|HttpAdapter\|
AbstractWsAdapter\|SocketsContainer\|OnApplicationShutdown\|HttpException\|@publicApi\|
ExpressAdapter\|FastifyAdapter\|IoAdapter\|WsAdapter"` against all four `task_*.md` prompt files:
**zero matches**. All internal class/interface/file names appear only in the `metadata_*.yaml`
ground-truth files, never in the task prompts themselves, consistent with Research.md §22's
"PaymentRepository (bad) vs. natural-language description (good)" rule.

## Honesty notes / limitations

- Guards (Task C) and pipes (Task A's `PipeTransform` family) are both *documented* NestJS
  concepts, so an agent with strong NestJS training-data familiarity may recognize the "right"
  mechanism from the task description alone rather than from reading this repo's code — this is
  a real threat to Task C's validity as a test of "did the agent discover the extension point by
  reading code" vs. "did the agent already know NestJS." I did not find a plausible extension
  point in this repo that is simultaneously (a) real, (b) transport-agnostic enough to make a
  cross-cutting feature natural, and (c) *not* already widely documented in NestJS's public docs
  — NestJS's whole design philosophy is well-documented, discoverable extension points, so this
  tension is close to unavoidable for this particular repository. I flagged rather than hid it.
- Task B and Task D both touch `packages/core`'s adapter/lifecycle machinery, but I made sure
  their required actions are disjoint (B = websocket close/notify + DI shutdown hook; D = HTTP
  response header via `AbstractHttpAdapter`) so a single implementation can't accidentally satisfy
  both.
- I did not clone the repository or run the actual test suite; `functional_check_command` entries
  are precise descriptions of what to run/assert (in the style of the existing
  `integration/graceful-shutdown` and `integration/hooks` e2e specs I located), not verified
  passing output. Positive/negative control implementations described in
  `notes_for_positive_negative_control` have not yet been written or executed — that is Phase 5
  work, out of scope for this task-design pass.
- No local clone was created or left behind; all recon was via `gh api` / `raw.githubusercontent.com`.
  A scratch tree listing was cached at `/tmp/nest_tree.txt` (not part of the repo, not committed).
