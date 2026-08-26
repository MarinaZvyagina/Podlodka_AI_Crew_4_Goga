# PLAUSIBILITY_CHECK.md — R03 (nestjs/nest)

## Disclosure: a partial, accidental pre-read of task_A.md

Before `tasks/R03/task_A.md`–`task_D.md` were deliberately read (after finishing the
architecture forest, per the assignment's ordering requirement), a single Bash tool call in this
session combined an unrelated `goga init` invocation with a `head -5` preview of the concatenated
`task_A.md`–`task_D.md` files, intended only to confirm the task files existed. This
inadvertently printed the first 5 lines of `task_A.md`:

> "Our HTTP exception classes cover most of the common client and server error codes people need
> day to day — bad request, unauthorized, forbidden, not found, conflict, and so on..."

This is disclosed here rather than silently absorbed. Assessment: these 5 lines describe NestJS's
built-in HTTP exception classes in terms already public knowledge (NestJS's own docs have a
long-standing "Exception filters" / "Built-in HTTP exceptions" page) and already present in the
assignment's own candidate list for this repository (`packages/common` — "decorators, interfaces,
pipes/guards/interceptors contracts"). `packages/common/exceptions` was independently going to be
in scope regardless — the mutation chain from a base `HttpException` to ~20 concrete
status-code subclasses is one of the most substantial, well-documented parts of `packages/common`,
and no architecture description of this repository's "spine" that also covers the router's
exception-handling path (which it must, to explain how the platform adapters' `mapException`
methods interact with it) could plausibly omit it. Nothing in the 5 lines seen (which never
mentions the specific status code the task turns on) informed the cell's authorship, and the cell
as written never mentions rate limiting, "too many requests," or any specific missing status
code — it describes the existing 5 documented subclasses generically, using the codebase's own
class names and constructor-shape pattern.

## When the remaining check was performed

`tasks/R03/task_A.md` through `task_D.md` were read in full only after `SCOPE.md` was written and
frozen, and after all 9 CODEMANIFEST files were authored, materialized, linted, and (to the
extent the tooling allowed — see `SETUP_COST.md`) drift-checked. No content in the architecture
forest was revised in response to reading the tasks.

## The four task prompts (quoted)

- **Task A**: add a new built-in HTTP exception class for the 429 ("too many requests" / rate
  limiting) status code, "matching the behavior, constructor options, and documentation style of
  the existing ones as closely as possible."
- **Task B**: on graceful shutdown (Kubernetes termination signal), send connected WebSocket
  clients (both the socket.io-based and the `ws`-based gateway integrations) a small heads-up
  message before their connection is closed, as part of the same shutdown sequence already used
  for HTTP.
- **Task C**: let a developer mark individual route handlers, whole controllers, or WebSocket
  message handlers as "affected by maintenance mode," toggle a maintenance-mode flag at runtime,
  and have marked handlers rejected before their logic runs while everything else keeps working —
  "using one consistent approach rather than building two separate mechanisms" for HTTP and
  WebSocket handlers, and unit-testable without a real server or socket.
- **Task D**: add a request/correlation ID response header, reusing a caller-supplied ID when
  present, made available to application code while handling the request, working identically on
  both HTTP platform integrations this framework ships.

## Term-level check: no task-specific vocabulary appears in the forest

Grepped all 9 CODEMANIFEST files for the task-specific terms each prompt turns on: none of "429",
"too many requests", "rate limit", "maintenance mode", "correlation", "request id", "socket.io",
"kubernetes", "migration", "heads-up", "termination signal" appear anywhere in the forest. One
incidental, generic term-level hit: `packages/core/adapters/CODEMANIFEST` mentions "graceful
shutdown" once, in `AbstractHttpAdapter`'s own annotation ("`setHttpServer`/`getHttpServer`
expose the raw listening server so the rest of the framework (e.g. graceful shutdown) can reach
it directly") — a true, generic statement about why the HTTP server reference is exposed at all
(NestJS's own `enableShutdownHooks()` feature), written before any task was read, and it says
nothing about WebSockets, gateways, or sending clients a message — Task B's actual mechanism.
Judged not to be leakage: it is the kind of one-line rationale any real architecture doc would
give for why a property getter exists, and it does not touch the part of the codebase (websockets)
that Task B is actually about — which this forest does not document at all (see `SCOPE.md`,
"Deliberately excluded").

## Where genuine overlap exists, and why it's expected rather than leakage

Two of the four tasks (C, D) touch functionality that lives inside cells this forest documents;
one (A) touches a cell only at the "this component exists" level; one (B) has no overlap at all
because its relevant subsystem (websockets) was deliberately excluded from scope (`SCOPE.md`).
This is disclosed in full rather than papered over, per `TREATMENT_DESIGN.md` §4:

- **Task C ↔ `packages/core/guards`**: this is the closest overlap, and it is a direct
  consequence of the assignment's own explicit instruction to prioritize "the guard/interceptor/
  pipe extension mechanisms" — an instruction given before any task was read, presumably because
  guards genuinely are one of NestJS's three canonical request-pipeline extension points (this is
  also how NestJS's own documentation categorizes them), not because the assignment was reverse
  engineered from the task list. Task C is explicitly framed as an "Existing Extension Point" task
  per `PROTOCOL.md` §8 ("prompt does not name it — agent must discover it or fail to"), and a
  maintenance-mode gate is a textbook `CanActivate` guard. The forest describes the *mechanism*
  (`GuardsConsumer.tryActivate`'s allow/deny reduction, `GuardsContextCreator`'s method → class →
  global precedence order) using only real, pre-existing names; it never mentions maintenance
  mode, migrations, or admin toggles. It also does not solve Task C's actual hard part — the
  requirement to use "one consistent approach" across HTTP *and* WebSocket message handlers, the
  latter requiring the (unscoped) `websockets` cell this forest does not cover at all. Judgment
  call: kept as-is; documenting a real, load-bearing extension point generically, at the level of
  detail a maintainer's own docs would use, is exactly what the Goga condition is meant to test.
- **Task D ↔ `packages/core/adapters` / `packages/platform-express/adapters` /
  `packages/platform-fastify/adapters`**: also a direct consequence of the assignment's explicit
  instruction to prioritize "the platform-adapter boundary." Task D is explicitly framed as an
  "Architecture Trap" per `PROTOCOL.md` §8 (an easy solution that passes functional tests but
  violates architecture, vs. a correct solution requiring understanding of existing boundaries) —
  and the trap here plausibly hinges on implementing the response header once, correctly, through
  `AbstractHttpAdapter`'s shared surface rather than duplicating platform-specific logic in each
  adapter (or bypassing the adapter abstraction entirely). The forest documents the abstract
  contract and both concrete mutations' real methods (`reply`, `setHeader`-equivalent behavior is
  not itself documented — neither adapter's `CODEMANIFEST` entry mentions headers, response IDs,
  or correlation at all); it says nothing about request/correlation IDs. An agent still has to
  recognize that "identical behavior across both platforms" maps onto this specific
  already-documented abstraction boundary.
- **Task A ↔ `packages/common/exceptions`**: weakest overlap, and the one where a partial
  accidental pre-read occurred (disclosed above). The forest documents the existing 5 concrete
  exception subclasses and the shared constructor-shape pattern generically; it never names or
  hints at the missing 429 status code, "rate limiting," or "too many requests." This tells an
  agent *that* a uniform, extensible exception hierarchy exists (a true, load-bearing
  architectural fact independently worth documenting), not *which* status code is missing from
  it.
- **Task B ↔ nothing in this forest**: no overlap. `packages/websockets`, `packages/platform-ws`,
  and `packages/platform-socket.io` — the only cells that could plausibly relate to Task B — were
  deliberately excluded from scope (see `SCOPE.md`, "Deliberately excluded"), a decision made
  before any task was read.

## Outcome

No revision was made to the architecture forest as a result of this check. The two closest
overlaps (Task C / `core/guards`, Task D / the platform-adapter boundary) are judged to be the
expected, in-scope consequence of the assignment's own explicit prioritization of exactly those
architectural areas — decided before task content was known — rather than task-specific hint
content, and are disclosed here explicitly per `TREATMENT_DESIGN.md` §4's "independent
plausibility check" requirement. The one accidental partial pre-read (5 lines of `task_A.md`) is
also disclosed above in full, with the assessment that it did not change scoping or content.
