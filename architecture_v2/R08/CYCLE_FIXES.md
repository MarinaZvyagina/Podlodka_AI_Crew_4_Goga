# CYCLE_FIXES.md — R08 (signalapp/Signal-Android) Condition C

`goga lint .` passes clean across all 94 cells (`cells: 94 errors: 0`) — no formal Goga `Imports:`
cycle exists anywhere in the DSL model. A separate, real Kotlin/Java-import-graph analysis (below)
found substantial genuine cycles, disclosed here rather than hidden — the largest and most
architecturally-varied set of real cycles found in this study so far, spanning 4 distinct root
causes across the 94-cell forest.

## Method: real import-graph analysis, not grep

4,487 real `.kt`/`.java` files across the 6 relevant Gradle-module source trees (`app/src/main/
java`, `core/util/src/main/java`, `lib/billing/src/main/java`, `lib/libsignal-service/src/main/
java`, `feature/registration/src/main/java`, `feature/media-send/src/main/java`) were scanned for
`import` statements. Each file's own package (derived from its path under `src/main/java/`) was
mapped to its owning cell (all 94 resolved cleanly); each import's target package was
longest-prefix-matched against the 94 documented cell packages. 350 real cross-cell edges found;
a standard DFS cycle detector (white/gray/black) was run over the resulting graph.

## Four distinct cycle families, each a genuine architectural pattern — not restructuring debt

### 1. `AppDependencies`-style service-locator hub (`app/.../database`, `.../database/model`,
   `.../dependencies`, `.../recipients`, `.../jobmanager`, `.../jobmanager/impl`,
   `.../database/helpers`, `.../database/helpers/migration`)

The exact same shape found in R02 (`salt/loader`) and disclosed there: `dependencies` (home of
`AppDependencies`, the app-wide static service locator) is *designed* to be imported by nearly
everything — but its own static initializers must reference concrete types from `database`
(`SignalDatabase`) and `jobmanager` (`JobManager`) to construct the singletons it hands out. This
produces `dependencies ↔ jobmanager`, `dependencies ↔ jobmanager/impl`, and (transitively via
`recipients`/`database/model`, which both reach into `dependencies` for cross-cutting access, and
back into each other for shared record/DTO types) a 5-cell SCC: `database`, `database/model`,
`dependencies`, `recipients`, `jobmanager`(+`impl`). `database/helpers ↔ database/helpers/
migration` is a much narrower, expected parent/child pair (the migration ladder's runner lives in
`helpers`, individual migrations live in `helpers/migration` and are invoked by name from there).

### 2. Feature-module navigation hubs (`feature/registration` ↔ ~27 of its own `screens/*`
   cells; `feature/media-send` ↔ 6 of its own `screens/*`/`util`/`preupload` cells)

The single largest cycle family by edge count. Each feature module's top-level cell hosts shared,
genuinely-needed-everywhere types (`RegistrationScaffold`, `RegistrationDependencies`, the
screen-navigation state machine, shared `Screen` composables/enums for `media-send`) that nearly
every individual screen subdirectory imports — the expected direction. But the top-level cell's
own navigation-graph wiring code needs to import each individual screen's entry-point composable
to route to it, producing a formal cycle with (nearly) every leaf screen cell. This is the
standard shape of a Compose/Fragment navigation graph (a central `NavHost`-equivalent that both
provides shared infrastructure to, and dispatches into, every screen) — not an accident of this
restructuring, and not resolvable by moving files around without changing Signal's actual
navigation architecture.

### 3. `libsignal-service/api`'s top-level orchestrator classes (`api` ↔ `messages`,
   `registration`, `account`, `websocket`, `crypto`, `groupsv2`, `svr`, `keys`, `message`;
   `messages` ↔ `util`, `messages/shared`; `util` ↔ `push`; `profiles` ↔ `services` ↔
   `subscriptions`/`donations`)

`api`'s top-level classes (`SignalServiceMessageSender`, `SignalServiceMessageReceiver`,
`SignalServiceAccountManager`) are the library's own public entry points — genuinely depended on
by nearly every subpackage — while those same top-level classes need concrete request/response
types from `messages`, `account`, `crypto`, etc. to do their job, producing the reverse edge.
`profiles ↔ services ↔ subscriptions/donations` is a smaller, separate 3-4 cell cluster: `services`
hosts generic response-processing helpers used by both `profiles` and `donations`/`subscriptions`,
which in turn feed domain types back into `services`.

### 4. `feature/media-send/screens/edit` ↔ its own `video`/`image` children

The same parent/child mutual-helper-borrowing shape already seen and disclosed repeatedly in this
study (R02's `utils` ↔ `utils/decorators`, R09's `AddressToolbar` ↔ `LocationView`): the shared
`edit` screen hosts common editing-toolbar state that `video`/`image` need, while `edit` itself
routes into those two sub-screens for their specific editors.

## Resolution: same disclosure pattern as every prior repo, now at R08's largest scale

Consistent with R01, R02, R05, and R09: the structurally-heavier, type-bearing direction of each
relationship is what a hand-authored Goga `Imports:` block would formalize; the reverse and
lower-traffic real-code edges are disclosed here in prose rather than silently omitted or forced
into an artificial one-directional model. No formal two-cell `Imports:` cycle exists in the DSL
(`goga lint .`: 0 errors across all 94 cells) — the cycles exist only in the real Kotlin/Java
import graph, which is expected for (a) a static-service-locator app architecture, (b) two
Compose/Fragment feature-module navigation graphs, and (c) a network-client library whose public
entry points necessarily touch every concrete message/account/crypto type — none of which a
cell-boundary/documentation restructuring can or should collapse into a clean DAG without
rewriting Signal-Android's actual dependency-injection and navigation architecture (out of scope
for Condition C).

## Two real bugs found and fixed during this cross-check

1. **`database/identity/CODEMANIFEST` used a cell-relative import path** (`From: model` instead of
   the repo-root-relative `From: app/src/main/java/org/thoughtcrime/securesms/database/model`) —
   the same bug class found and fixed in R09. Caught by `import_has_valid_from_path` at
   whole-project lint scope (not a false positive this time — a real path bug), fixed by rewriting
   to the full repo-root-relative path.
2. **4 `return_type_has_link` false triggers** in `feature/registration/.../screens/CODEMANIFEST`:
   signatures ending in a trailing `@Composable (...) -> Unit`-typed *parameter* (not a real
   top-level return type) were misparsed by `goga lint`'s naive last-`->`-split as an unlabeled
   return type. Fixed by labeling the trailing lambda parameter's own return type inline (`->
   Unit` → `-> result:Unit`) — the same fix independently discovered by 3 different batch agents
   working on unrelated sibling cells during this restructuring (`registration/screens/welcome`,
   `.../linkaccount`, `media-send/screens/edit`), now applied consistently to the one cell that
   still had it unresolved.
