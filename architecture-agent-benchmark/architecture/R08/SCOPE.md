# SCOPE.md — R08 (signalapp/Signal-Android)

## Method

Scope was decided from Signal-Android's own module layout and package structure — verified by
direct source reading (`ls`, `find`, `grep`, and full/partial file reads of the actual
implementation), per `TREATMENT_DESIGN.md` §4 — **before** `tasks/R08/task_A.md`–`task_D.md` were
read (see `PLAUSIBILITY_CHECK.md` for the post-hoc self-check, performed only after scoping,
authoring, materialization, linting, and drift-checking were all complete).

The repository is a 49-Gradle-module Android app (`app`, `core/*`, `lib/*`, `feature/*`) mixing
~372k Kotlin LOC with ~175k legacy Java LOC. Rather than the flatter `pkg/subpkg` layout of a
typical Python/Go service, Signal-Android's real architectural spine spans two different kinds of
boundary: **Gradle-module boundaries** (`feature/registration`, `feature/media-send`,
`lib/billing`, `core/util`, `lib/libsignal-service` — each independently compiled, each with its
own build target) and **package boundaries within the large `app` module**
(`org.thoughtcrime.securesms.jobmanager`, `.../database`, `.../recipients`,
`.../dependencies`) that are just as load-bearing even though Gradle does not enforce a
compilation boundary between them. Both kinds are represented in this forest; each cell's
`SCOPE.md` entry below states which kind it is.

## Cells covered (9) and why

| Cell | Kind | Evidence it's load-bearing |
|---|---|---|
| `app/.../jobmanager` | package boundary (within `app`) | The single background-job execution framework for the entire app; `grep -rl "JobManager"` across `app/src/main/java` returns 172 files. Every asynchronous, persisted, retryable unit of work in the app (message send, attachment upload, key rotation, etc.) is a `Job` subclass registered through this framework's `Job.Factory`/`Constraint.Factory` extension points. |
| `app/.../recipients` | package boundary (within `app`) | `Recipient`/`RecipientId` are the app's core domain identifier; `grep -rl "Recipient\."` across `app/src/main/java` returns hundreds of files (conversations, calls, groups, messages, payments, stories all key off it). Depends on nothing else in this forest. |
| `app/.../database` | package boundary (within `app`) | `grep -rl "SignalDatabase\."` returns 551 files. The single SQLCipher-backed persistence layer, aggregating ~45 table objects behind one facade (`SignalDatabase`), with a shared base type (`DatabaseTable`) and change-notification hub (`DatabaseObserver`) every table uses identically. |
| `app/.../dependencies` | package boundary (within `app`) | `AppDependencies` is the static service-locator every other subsystem reads cross-cutting singletons through (job manager, database observer, recipient cache, billing, network clients). The root of this forest's dependency graph — imports from 4 other cells, is imported by none. |
| `lib/libsignal-service` (`.../api` package) | Gradle-module boundary | A standalone library module (no dependency on the `app` module) — the network/protocol client the app talks to the Signal service through (`SignalServiceMessageSender`, `SignalServiceMessageReceiver`, `SignalServiceAccountManager`). |
| `core/util` (`.../billing` package) | Gradle-module boundary | Declares the `BillingApi` interface: a real, designed, swappable extension point (in-app-purchase backend), with a built-in `Empty` no-op default. |
| `lib/billing` | Gradle-module boundary | The concrete Google-Play-specific implementation (`BillingApiImpl`) of `core/util`'s `BillingApi`, selected at runtime by `BillingFactory` — the other half of the billing extension point, deliberately kept in a separate, swappable Gradle module. |
| `feature/registration` | Gradle-module boundary | A self-contained feature module (its own `RegistrationRepository`/`RegistrationDependencies`/`RegistrationViewModel`), verified fully decoupled from `AppDependencies`/`SignalDatabase`/`jobmanager` by reading every import in its top-level files. |
| `feature/media-send` | Gradle-module boundary | A second, independently-verified self-contained feature module, following the identical Repository+Dependencies+ViewModel convention as `registration`. |

Both `feature/registration` and `feature/media-send` were verified to have zero imports of
`AppDependencies`, `SignalDatabase`, or `org.thoughtcrime.securesms.jobmanager` anywhere in their
top-level source files — this is a genuine, load-bearing fact about Signal-Android's real module
boundary discipline (each `feature/*` module declares its own `NetworkController`/
`StorageController`/`Provider` interfaces for the host app to implement, rather than reaching
into `app`-module internals), not an artifact of under-scoping the forest.

## Language mix (per `TREATMENT_DESIGN.md`'s language-scoping note)

- **Kotlin-only cells** (safe for `goga contract --lang kotlin`): `recipients` (mostly Kotlin,
  2 Java files documented — see below), `core/util/billing`, `lib/billing`, `feature/registration`,
  `feature/media-send`, `dependencies`.
- **Mixed Java/Kotlin cells** (documented per the DSL, which is language-agnostic; `goga contract`
  spot-checks were skipped for these — see `SETUP_COST.md`): `jobmanager` (mostly Java: `Job.java`,
  `JobManager.java`, `Constraint.java`, `ConstraintObserver.java`, `Scheduler.java`,
  `JobTracker.java`, `JsonJobData.java`; one Kotlin file, `CoroutineJob.kt`), `database` (Java:
  `DatabaseTable.java`, `DatabaseObserver.java`; Kotlin: `SignalDatabase.kt`, `RecipientTable.kt`),
  `lib/libsignal-service/.../api` (mostly Java, with a handful of Kotlin extension/store files not
  documented as full entities here).
- Within the otherwise-Kotlin `recipients` cell, `LiveRecipient.java` and `LiveRecipientCache.java`
  are Java — documented, but `goga contract --lang kotlin` naturally could not resolve their
  Java implementations (see `SETUP_COST.md` contract findings).

## Deliberately excluded / deprioritized

- **The other ~90 table classes in `app/.../database`** (`MessageTable`, `ThreadTable`,
  `GroupTable`, `AttachmentTable`, etc.) — each extends the same `DatabaseTable` base and follows
  the identical `(context, databaseHelper)` constructor shape as the one representative table
  documented (`RecipientTable`). Given the "roughly 6-10 cells, not an exhaustive catalog" budget
  and the CODEMANIFEST `location` constraint (one file per declared type, same directory as the
  `CODEMANIFEST`), documenting all ~90 would have consumed the entire cell budget on one
  architectural idea already covered by one representative example.
- **The ~193 concrete `Job` subclasses in `app/.../jobs`** — each is exactly the kind of
  extension-point consumer the `jobmanager` cell documents generically (subclass `Job`, implement
  `getFactoryKey`/`run`/`onFailure`, register a `Job.Factory`); none is individually documented,
  since the point of this cell is the reusable mechanism, not any one job.
- **`feature/app-settings`, `feature/camera`** — real feature modules, but smaller and less
  structurally distinctive than `registration`/`media-send`; two independently-verified examples
  of the same module convention were judged sufficient coverage without adding a third and fourth
  that would repeat the same pattern.
- **`core/models`, `core/network`, `core/serialization`, `core/ui`, `core/util-jvm`,
  `core/models-jvm`** — real modules, but on inspection either contain no substantial Kotlin/Java
  source directly at their own top level (e.g. `core/models`/`core/network` at this commit consist
  almost entirely of Gradle/manifest/proto-schema plumbing with real code living in submodules not
  reached from the top level) or are thin, single-purpose utility grab-bags (`core/util`'s ~70
  files outside the `billing` subpackage: `DimensionUnit`, `ThreadUtil`, `Serializer`, etc.) without
  an independent multi-type public surface of their own — the same exclusion rationale
  `architecture/R01/SCOPE.md` used for freqtrade's thin utility modules.
- **`lib/contacts`, `lib/emoji`, `lib/donations`, `lib/device-transfer`, and the remaining
  `lib/*` modules** — real, self-contained modules, but `libsignal-service` (the most
  structurally central library — everything else eventually calls through it to reach the
  network) and `billing` (the clearest example of a designed, swappable interface/implementation
  split across two modules) were judged the two most architecturally representative library
  modules to document in depth, within the fixed cell budget.

This scoping was performed and frozen before `tasks/R08/task_A.md`–`task_D.md` were read (see
`PLAUSIBILITY_CHECK.md`).
