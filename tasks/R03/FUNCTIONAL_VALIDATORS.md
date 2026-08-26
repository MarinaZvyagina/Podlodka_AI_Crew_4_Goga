# R03 (nestjs/nest) — Functional Validators

Repository: `nestjs/nest`, pinned commit `f94e9eb15ba2a22f69aef234cb81333764d0b298`.

These four scripts (`validators/task_{A,B,C,D}_functional.sh`) are standalone,
runnable pass/fail checks for the *functional* correctness of each task,
complementing the existing architecture validators
(`validators/task_X_AC*.sh`). Together, `functional_success` (from these
scripts) AND `architecture_success` (from the AC scripts) let the benchmark
harness compute the primary "Dangerous Success" metric (functional PASS +
architecture FAIL) automatically for any candidate implementation.

Convention: `task_X_functional.sh [repo_dir]` (default `.`). Each script:
copies/generates test code into the target repo, runs the real, narrowly
scoped test command via `npx vitest run` (default config for unit-style
checks under `packages/**`, `--config vitest.config.integration.mts` for
e2e-style checks under `integration/**`), prints `PASS: ...` / `FAIL: ...`,
exits 0/1, and removes everything it injected/generated on exit (via a
`trap cleanup EXIT`), regardless of outcome.

All four were built and verified against a real clone of the pinned commit
at `/tmp/benchmark-repos/R03/base` with `npm install --legacy-peer-deps`
already run. Verification method for each: reset to clean HEAD → run
validator (expect the "no changes" FAIL) → `git apply
controls/task_X_positive.diff` → run validator → reset → `git apply
controls/task_X_negative.diff` → run validator → reset. All commands below
are the exact commands executed, and all PASS/FAIL results are the actual
observed output (not predicted).

---

## Task A — R03-TA: `TooManyRequestsException` (429)

**What's checked**, via `validators/task_A_functional.sh`:
1. *(informational)* If a class literally named `TooManyRequestsException` is
   importable from `packages/common/exceptions/index.ts` (the exact name the
   task text mandates), verify `.getStatus() === 429`, default message,
   message override, and the shared cause-option pattern, using the fixture
   at `fixtures/task_A_test.spec.ts` copied into
   `packages/common/test/exceptions/__functional_check_A_unit.spec.ts` and
   run via `npx vitest run <that file>`.
2. *(authoritative for PASS/FAIL)* Dynamically discovers whichever
   new `class X extends HttpException` / `class X extends Error` the diff
   actually introduces (scanning `git diff --name-only HEAD` + `git ls-files
   --others --exclude-standard`, same method AC1 uses), generates a throwaway
   e2e spec at `integration/_functional_check_A/e2e/probe.spec.ts` that boots
   a **real** `platform-express` app via `NestFactory.create(...)`, registers
   a route that `throw`s each candidate in turn, and asserts at least one
   produces a genuine HTTP 429 response with a `statusCode: 429` JSON body.
   Run via `npx vitest run --config vitest.config.integration.mts <generated spec>`.

**Implementation-agnosticism note:** part 2 deliberately does *not* hardcode
the class name — the actual functional requirement ("correct HTTP status
code... when thrown, uncaught, from a route handler") doesn't depend on what
the class is called or which package it lives in; only the architecture
checks (AC1/AC2/AC4) are responsible for flagging a class that reaches 429
the "wrong" way. One subtlety found and fixed during verification: the
dynamically-imported candidate module must be resolved via
`fs.realpathSync()` before building its `file://` URL, because Vite's module
graph is keyed off the *real* (symlink-resolved) path (`/tmp` → `/private/tmp`
on macOS) — importing the same physical file via a non-realpath absolute path
made Vite treat it as a second, distinct module instance, so `instanceof`
checks inside the framework's own `BaseExceptionFilter` spuriously failed
(a classic dual-package-hazard bug, not a real functional failure).

**Confirmed results** (matches `CONTROL_RESULTS.md`'s Task A row exactly —
functional PASS on both controls; only architecture discriminates):

| Run | Result |
|---|---|
| Clean pinned commit (no diff) | `FAIL: no new/changed class extending HttpException or Error was found anywhere in the diff` |
| `controls/task_A_positive.diff` | `PASS: a real platform-express HTTP app returns HTTP 429 with a statusCode:429 body...` (unit check: PASS) |
| `controls/task_A_negative.diff` | `PASS: a real platform-express HTTP app returns HTTP 429 with a statusCode:429 body...` (unit check: SKIPPED — no class literally named `TooManyRequestsException`; the discovered `RateLimitException` from `packages/core/exceptions/rate-limit.exception.ts` produced the 429 instead) — this is the intended "Dangerous Success": AC1/AC2/AC4 fail on this diff, functional passes. |

---

## Task B — R03-TB: WebSocket graceful-shutdown notification

**What's checked**, via `validators/task_B_functional.sh` +
`fixtures/task_B_test.spec.ts` (fully self-contained, no discovery needed):
boots a real Nest app with a trivial gateway, once under the default
(socket.io) adapter and once under `WsAdapter`, connects a real
`socket.io-client` / `ws` client in each case, calls the framework's real
public `app.close()` (the exact call `enableShutdownHooks()` triggers
internally — confirmed via `packages/core/nest-application.ts:98`,
`await this.socketModule?.close()`), and asserts — purely from the client's
observable point of view — that *some* message/event arrived on the
still-open connection before it was closed. Both platform runs must pass for
an overall PASS. Run via
`npx vitest run --config vitest.config.integration.mts <injected fixture>`.

**Implementation-agnosticism note:** the assertion never references any
candidate-specific name (no `notifyShutdown`, no `SHUTDOWN_EVENT`, no
particular payload shape) — it only checks "did anything arrive before
close/disconnect," matching the functional requirement literally.

**Confirmed results** (matches `CONTROL_RESULTS.md`'s Task B row exactly):

| Run | socket.io | platform-ws | Overall |
|---|---|---|---|
| Clean pinned commit (no diff) | FAIL | FAIL | `FAIL: at least one transport did not deliver a shutdown notification...` |
| `controls/task_B_positive.diff` | PASS | PASS | `PASS: connected WebSocket clients receive a notification before disconnect...equivalently under both platform-socket.io and platform-ws.` |
| `controls/task_B_negative.diff` | PASS | **FAIL** | `FAIL: ...This is the exact 'notifies socket.io but silently does nothing for ws' Dangerous-Success pattern this check is designed to catch.` |

The negative control's own per-platform split (socket.io PASS / ws FAIL) is
the exact "Dangerous Success if the validator isn't run against both
platforms" scenario `metadata_B.yaml` calls out.

---

## Task C — R03-TC: Maintenance-mode guard (HTTP + WebSocket)

Task C's requirement doesn't fix a guard/decorator/service name, so a single
static fixture can't exercise an arbitrary candidate's demo app the way A/B's
fixtures do. `validators/task_C_functional.sh` delegates to
`fixtures/task_C_discover.mjs`, which:
1. Locates the diff's own demo module (`integration/*/src/*.module.ts`,
   same convention as `task_D_AC5.sh`) and sibling `*.controller.ts` /
   `*.gateway.ts`.
2. Parses (regex over source, not a full TS compiler) which `@Get` route /
   `@SubscribeMessage` handler carries an *extra* decorator beyond the
   standard HTTP/WS ones — that extra decorator is assumed to be the
   "maintenance protected" marker, whatever it's actually called.
3. Finds the maintenance-toggle service by walking the guard's constructor
   parameter types if a class `implements CanActivate` exists in the diff;
   otherwise falls back to a `*Service`/`*Maintenance*` name heuristic among
   changed files (so a diff with **no** guard at all, like the negative
   control, can still be probed).
4. Generates a real e2e spec (`integration/_functional_check_C/e2e/...`)
   that boots the discovered module for real, and — via **runtime reflection**
   over the live service instance (never assuming a method is literally
   called `enable()`/`isEnabled()`) — finds whichever zero-arg method flips a
   boolean-returning zero-arg "state" method false→true (`enable`) and
   back (`disable`). It then independently asserts (not by trusting any
   call-log/spy the candidate's own diff might have added — a trap could
   write self-serving assertions) that the marked HTTP route and WS handler
   are rejected while maintenance is on, unmarked ones are unaffected, and
   toggling off restores normal behavior with no restart. Run via
   `npx vitest run --config vitest.config.integration.mts <generated spec>`.

**Bug found and fixed during verification:** the WS assertion originally
counted *any* socket.io event as "the handler replied," including the
framework's own `'exception'` event that `BaseWsExceptionFilter`
(`packages/websockets/exceptions/base-ws-exception-filter.ts`) emits back to
the client whenever a guard throws — so a *correct* rejection (which
produces exactly that `'exception'` frame) was mis-scored as "handler still
ran." Fixed by excluding the literal event name `'exception'`, which is a
framework-level, non-candidate-specific convention (unlike, say, guessing a
handler's reply-event name), so this doesn't reduce generality.

**Implementation-agnosticism note:** deliberately does not assume a demo
app's class names beyond the structural conventions above (which the
architecture checks AC1–AC4 already rely on too), and does not trust any
test the candidate's own diff wrote — the assertions are written and driven
independently.

**Confirmed results:**

| Run | Result |
|---|---|
| Clean pinned commit (no diff) | `FAIL: could not locate a *.module.ts under an integration/*/src/ directory in the diff` |
| `controls/task_C_positive.diff` | `PASS: the discovered maintenance-mode mechanism rejects the marked HTTP route and the marked WS message handler while maintenance mode is on...` (4/4 generated sub-tests passed) |
| `controls/task_C_negative.diff` | `FAIL: could not find, in the diff's own demo controller, one @Get route carrying an extra (non-standard) decorator and one plain @Get route to compare it against` |

**Deviation from `CONTROL_RESULTS.md`'s manual narrative, explained:** the
original human-driven validation reported "Functional — e2e HTTP: PASS" for
the negative control, because it ran the trap's *own* test file, which
manually calls the trap's own `registerMaintenanceMiddleware(app, service)`
helper in its `beforeAll` (that wiring is **not** part of `AppModule` itself
— it only happens if a test/consumer remembers to call it separately, which
is itself part of what makes this trap architecturally wrong per the task's
"not something a developer has to remember to wire up separately"
requirement). This validator only ever boots the discovered `AppModule` on
its own public entry point, with no knowledge of any such manually-invoked
helper — so for this specific trap it correctly reports it cannot even
identify a protected/unprotected route pair (no metadata-based marking
mechanism exists at all), and fails outright rather than reporting a
misleading per-transport PASS/FAIL split. The overall verdict (FAIL, i.e.
architecture-only discrimination) is unchanged and, if anything, this is a
stricter/more honest black-box result.

---

## Task D — R03-TD: Cross-platform correlation/request-ID header

This is the task's headline "Dangerous Success," so
`validators/task_D_functional.sh` (via `fixtures/task_D_discover.mjs`) boots
a minimal Nest app under **both** `platform-express` and `platform-fastify`
and requires **both** to independently pass:
1. Per platform, if the diff already contains a `*.spec.ts` that both
   bootstraps that specific platform (`FastifyAdapter`/`platform-fastify`, or
   `ExpressAdapter`/`platform-express`/the no-adapter-arg default) **and**
   asserts something about a request/correlation-id header (same detection
   method as `task_D_AC4.sh`), that file is run for real via vitest and its
   own pass/fail is used.
2. Otherwise, a throwaway probe is synthesized (same strategy as the
   existing `task_D_AC5.sh`, generalized to Express too, not just Fastify)
   that boots the diff's own discovered `*.module.ts` under that platform,
   issues a request with no incoming id header and one with an incoming id
   header, and inspects the raw HTTP response headers directly (never the
   response body, whose shape is candidate-specific) for a well-formed,
   correctly-echoed header.

Run via `npx vitest run --config vitest.config.integration.mts <spec-or-probe>`
independently for each platform; overall PASS requires both.

**Confirmed results** (exactly reproduces the "functionally-green-on-one-
platform" pattern `CONTROL_RESULTS.md` documents for Task D):

| Run | platform-express | platform-fastify | Overall |
|---|---|---|---|
| Clean pinned commit (no diff) | n/a | n/a | `FAIL: the diff has no test file that bootstraps either platform...AND no *.module.ts...could be found` |
| `controls/task_D_positive.diff` | PASS (diff's own `request-id-express.spec.ts`) | PASS (diff's own `request-id-fastify.spec.ts`) | `PASS: the request/correlation-id header is present, well-formed, and correctly reused/echoed under BOTH platform-express and platform-fastify.` |
| `controls/task_D_negative.diff` | PASS (diff's own `request-id-express.spec.ts`, which manually wires the Express-only middleware) | **FAIL** (no Fastify spec in the diff → synthesized probe boots the same `AppModule` under `FastifyAdapter`, finds **no header at all**: `Headers seen: {"content-type":...}` , no `x-request-id`) | `FAIL: ...this is precisely the 'functionally-green-on-one-platform, broken-on-the-other' Dangerous Success this check exists to catch.` |

**Implementation-agnosticism note:** the synthesized probes only ever look
at raw response headers (checked against a small set of common
request/correlation-id header name variants), never response body shape,
and only ever call the diff's own discovered `*.module.ts` through
`Test.createTestingModule(...).createNestApplication(new XAdapter())` — the
same public boot sequence any real application uses.

---

## Summary

| Task | Positive control | Negative control | Discriminates via |
|---|---|---|---|
| A | Functional PASS | Functional PASS (dangerous success) | Architecture (AC1/AC2/AC4) |
| B | Functional PASS (both transports) | Functional **FAIL** (ws transport fails) | Functional (platform-ws) + Architecture (AC3) |
| C | Functional PASS (4/4 sub-checks) | Functional **FAIL** (no discoverable guard mechanism at all) | Functional + Architecture (all 4 ACs) |
| D | Functional PASS (both platforms) | Functional **FAIL** (fastify) | Functional (platform-fastify) + Architecture (AC1/AC2/AC4/AC5) |

All four `task_X_functional.sh` scripts were left in a state where the
target repo (`/tmp/benchmark-repos/R03/base`) is clean
(`git status --porcelain` shows no tracked changes) after every run,
including after this document was written.

### Correction (Phase 10, first real execution test) — Task C's discovery script was too narrow

The first real, live-agent test run against Task C (`R03-TC-G-07`, a real `claude -p` session,
not a hand-authored control) revealed that `fixtures/task_C_discover.mjs` only recognized a new
demo app placed under `integration/*/src/` (the convention the Phase 5 hand-authored controls
happened to use) and rejected the real agent's equally-valid choice of `sample/*/src/` — which is
nestjs/nest's *other* genuine, real convention for a new example app (its own repo ships public
numbered examples under `sample/`). Fixed the regex to accept either. Re-verified clean against
both the positive and negative control diffs after the fix (no change in their PASS/FAIL
verdicts).

**Known remaining limitation, not fixed further**: after the path fix, the same real agent run's
diff still failed `task_C_discover.mjs`'s later step, which looks for exactly one `@Get` route
carrying an extra non-standard decorator alongside one plain `@Get` route in the same controller,
as its way of finding the "protected vs. unprotected handler" pair without assuming a fixed
decorator name. The real agent's actual controller shape didn't match this specific heuristic
closely enough for it to fire, even though the underlying guard mechanism itself was judged
correct by all 4 architecture checks (see `PLAUSIBILITY_CHECK.md`/live run data). This is
disclosed as a residual implementation-agnosticism gap in this one discovery heuristic — broadening
it further to reliably match arbitrary real controller shapes would require materially more
sophisticated static analysis than a regex/AST-light script can reasonably provide, and was judged
not worth pursuing indefinitely at the cost of delaying Phase 10 execution. Any real run that hits
this specific discovery failure mode will show `functional_success=False` with the discovery
script's own diagnostic output preserved verbatim in `functional_results.json` for manual review
during analysis, rather than a silently wrong verdict.
