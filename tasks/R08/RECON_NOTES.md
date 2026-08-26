# R08 — signalapp/Signal-Android — Recon Notes

Pinned commit: `441ba42c3f3175476a1f54eba8e72d8d6d304db7` (verified: 40 hex chars, resolves via GitHub API — all
`gh api repos/signalapp/Signal-Android/contents/...?ref=441ba42c3f3175476a1f54eba8e72d8d6d304db7` and raw.githubusercontent.com
fetches below succeeded against this ref).

Method: no local clone (disk constraint). All evidence gathered via `gh api` (recursive tree fetch, `contents` endpoint,
`search/code`) and `raw.githubusercontent.com` fetches of individual files at the pinned commit. Recursive tree
(`git/trees/<sha>?recursive=1`) returned 12,564 paths, confirming this is genuinely the Kotlin/Java Android repo (not, e.g., a
stray iOS mirror — an initial zsh globbing mistake on the `?` in the URL briefly pulled an unrelated cached file; re-run with
quotes gave the correct 12,564-path tree with `.idea/fileTemplates/Kotlin Class.kt` etc. confirming Android/Kotlin).

## Module structure (from settings.gradle.kts)

Confirmed real module list at pinned commit:
- `:app` (top-level, largest, contains almost all business logic incl. `jobmanager/`, `jobs/`, `database/`, `search/`, `blocked/`, `mediasend/`)
- `core:util`, `core:util-jvm`, `core:models`, `core:models-jvm`, `core:network`, `core:ui`, `core:serialization`
- `lib:libsignal-service`, `lib:network`, `lib:glide`, `lib:photoview`, `lib:sticky-header-grid`, `lib:billing`, `lib:paging`,
  `lib:device-transfer`, `lib:donations`, `lib:contacts`, `lib:qr`, `lib:spinner`, `lib:video`, `lib:image-editor`,
  `lib:debuglogs-viewer`, `lib:blurhash`, `lib:apng`, `lib:emoji`, `lib:archive`, `lib:ui-components`
- `feature:app-settings`, `feature:registration`, `feature:camera`, `feature:media-send`
- `demo:*`, testing/lint modules (not relevant to tasks)

Dependency direction confirmed by reading `feature/media-send/build.gradle.kts` (depends on `core:*`, `lib:image-editor`,
`lib:glide`, `lib:video`, `feature:camera` only — **not** `:app`) versus `app/build.gradle.kts` (line ~816:
`implementation(project(":feature:media-send"))`). So `:app` depends on feature modules, never the reverse. This is load-bearing
for Task B's forbidden-dependency rule.

Language mix confirmed directly: `blocked/` package and `search/SearchRepository.java` are legacy **Java**;
`jobmanager/CoroutineJob.kt`, `jobs/AnalyzeDatabaseJob.kt`, `jobmanager/impl/*Constraint.kt` (newer ones),
`feature/media-send/**/*.kt`, `core/models/.../TransformProperties.kt` are **Kotlin**. Both eras coexist in the same packages
(e.g. `jobs/` has both `.java` and `.kt` job classes side by side), matching the brief's note about ~175k LOC legacy Java.

## Task A — Local Change: blocked-contacts sort order

Evidence:
- `app/src/main/java/org/thoughtcrime/securesms/blocked/BlockedUsersRepository.java` — calls
  `SignalDatabase.recipients().getBlocked()`, maps to `Recipient`, no ordering applied.
- `app/src/main/java/org/thoughtcrime/securesms/database/RecipientTable.kt:729-736` — `fun getBlocked()`:
  `.select().from(TABLE_NAME).where("$BLOCKED = 1").run()` — **no `ORDER BY`**, confirmed unsorted at the DB layer.
- `BlockedUsersViewModel.java` / `BlockedUsersFragment.java` — classic Fragment→ViewModel→Repository MVVM triangle, all Java,
  entirely inside `:app`, no cross-module surface at all.
- Confirmed via `search/code` that `getBlocked()` on `RecipientTable` has no other in-tree callers besides
  `BlockedUsersRepository.java` at this commit (not exhaustively re-verified with a second search pass, so the task explicitly
  asks the agent to verify this itself rather than trust it).

Why this is genuinely "local": no schema/migration needed (pure query/sort change), single Gradle module, single narrow package.
Good baseline-difficulty task — the main things a benchmark can still catch are wrong-layer placement (sorting in
Adapter/Fragment instead of Repository/data layer) and duplicated sort logic.

## Task B — Cross-module Feature: per-attachment "send full quality" in a batch

This is the strongest cross-module boundary I found, with a concrete real chain of evidence:

1. `feature/media-send/src/main/java/org/signal/mediasend/MediaSendDependencies.kt` — feature module defines a `Provider`
   interface (dependency-inversion boundary) for everything it needs from the host app.
2. `feature/media-send/src/main/java/org/signal/mediasend/preupload/PreUploadRepository.kt` — interface with an explicit doc
   comment: *"Callbacks that perform the real side-effects (DB ops, job scheduling/cancelation, etc). This keeps
   feature/media-send free of direct dependencies on app-specific systems."* This is about as explicit as a codebase gets about
   an intentional architectural boundary, and the task prompt does **not** quote or reference this comment or the class name.
3. `app/src/main/java/org/thoughtcrime/securesms/dependencies/MediaSendDependenciesProvider.kt` implements
   `MediaSendDependencies.Provider`, wiring in app-side concrete repositories.
4. `app/src/main/java/org/thoughtcrime/securesms/mediasend/v3/MediaSendV3PreUploadRepository.kt` implements
   `PreUploadRepository`, and its methods call `AppDependencies.jobManager`, `SignalDatabase.attachments`, and
   `MessageSender.preUploadPushAttachment` — i.e. the actual job-manager and database boundaries live here, app-side.
5. `app/src/main/java/org/thoughtcrime/securesms/jobs/AttachmentCompressionJob.java` (Java) already reads
   `databaseAttachment.transformProperties` and explicitly logs *"Skipping at the direction of the TransformProperties"*
   (line ~164) when `TransformProperties.skipTransform` is set.
6. `core/models/src/main/java/org/signal/core/models/media/TransformProperties.kt` — the `skipTransform` field, plus
   `withSkipTransform()`/`forSkipTransform()` helpers, already exist at the shared `core:models` layer.
7. Confirmed the gap: `feature/media-send/.../screens/edit/QualitySelectorSheetContent.kt`'s `QualitySelectorBottomSheet` takes a
   single `quality: SentMediaQuality` parameter applied to the whole batch — there is no existing per-attachment override UI in
   the multi-select review screen. So the task describes a real, currently-missing capability, not something already implemented.

This grounds a genuine 3-boundary cross-module task: feature-module UI/interface, app-side Provider implementation +
persistence, and the pre-existing job (`AttachmentCompressionJob`) that will automatically honor the flag once it's set
correctly upstream — the agent must understand this chain rather than reinvent compression-skipping logic.

## Task C — Existing Extension Point: background job framework (`jobmanager/`)

Confirmed the `jobmanager/` package is real, substantial, and entirely inside `:app`
(`app/src/main/java/org/thoughtcrime/securesms/jobmanager/`, ~30 files) with a separate `jobs/` package of ~200+ concrete job
implementations (`app/src/main/java/org/thoughtcrime/securesms/jobs/`).

Key evidence:
- `Job.java` class doc: *"A durable unit of work... State that you want to save is persisted to a JsonJobData object in
  serialize(). Your job is then recreated using a Factory that you register in
  JobManager.Configuration.Builder#setJobFactories."* — explicit registry/factory pattern.
- `app/src/main/java/org/thoughtcrime/securesms/jobs/JobManagerFactories.java` — central registration point,
  **333 `.put(...)` factory registrations** counted at the pinned commit (`grep -c "put("`), covering both `Job.Factory` and
  `Constraint.Factory` entries.
- `app/src/main/java/org/thoughtcrime/securesms/jobs/AnalyzeDatabaseJob.kt` — near-perfect precedent for the shape of Task C's
  request: analyzes one DB table per invocation, persists `lastCompletedTable` via `serialize()`, and calls
  `Result.retry(1.seconds)` to resume — i.e. an existing "large scan, chunked, resumable, retryable maintenance job."
- `app/src/main/java/org/thoughtcrime/securesms/jobmanager/impl/NotInCallConstraint.java` and
  `.../BatteryNotLowConstraint.kt` — existing, registered `Constraint` implementations for exactly the two gating conditions
  Task C's prompt asks for ("not on a call," "not low battery"), attachable via `Parameters.Builder().addConstraint(...)`.
- `DiskSpaceNotLowConstraint.kt` also exists (considered for Task C but intentionally not used in the final constraint set,
  since "skip cleanup when disk is low" is a slightly awkward fit for a disk-freeing cleanup task — chose call/battery
  constraints instead for narrative coherence).

The task prompt for Task C avoids every internal term: no "Job," "JobManager," "Constraint," "jobmanager," "Factory," or any
class name appears in `task_C.md`. It's phrased purely as a product/ops requirement (periodic cleanup, must not run during a
call or on low battery, must survive process death and resume).

## Task D — Architecture Trap: search result caching

This directly instantiates the canonical example given in the design brief ("add caching for repeated search results,
invalidate on data changes") — grounded in real code rather than invented:

- `app/src/main/java/org/thoughtcrime/securesms/search/SearchRepository.java` (Java) — the actual, sole data-access layer for
  message/thread/conversation search; queries `SearchTable`, `ThreadTable`, `MessageTable`, `RecipientTable`, `MentionTable` via
  `SignalDatabase`.
- Confirmed the caller chain via `gh api search/code -f q="SearchRepository ..."`:
  `app/src/main/java/org/thoughtcrime/securesms/conversationlist/ConversationListFragment.java` constructs
  `new SearchRepository(...)` (line ~340) and hands it into `ContactSearchViewModel.Factory`, i.e. genuine
  Fragment → ViewModel → Repository → Database layering exists and is exercised on the main chat-list search screen.
- `app/src/main/java/org/thoughtcrime/securesms/database/DatabaseObserver.java` — *"Allows listening to database changes to
  varying degrees of specificity"* — a real, general reactive invalidation mechanism with named registration points
  (`registerConversationListObserver`, message insert/update observers, etc.).
- Confirmed `registerConversationListObserver` is actually used elsewhere for reactive UI updates, e.g.
  `app/src/main/java/org/thoughtcrime/securesms/stories/archive/StoryArchiveViewModel.kt` (found via `search/code`), so citing
  it as "the existing pattern for this kind of invalidation" is not speculative.

The trap: a cache added directly inside `ConversationListFragment.java` or `ContactSearchViewModel.kt` (UI/presentation layer)
with a naive invalidation heuristic (TTL, `onResume`/`onPause`) will pass a shallow functional test ("type the same query twice,
it's fast") while failing to reflect data changes made through other paths — exactly the "Dangerous Success" state the overall
benchmark is designed to surface. AC3 in `metadata_D.yaml` is specifically written as a staleness test to separate these two
outcomes, per the protocol's requirement that positive and negative controls must be distinguishable by the validators.

## Confirmation: no leakage of internal identifiers in task prompts

Re-read `task_A.md`, `task_B.md`, `task_C.md`, `task_D.md` against the class/package/pattern names used as evidence above:
- No mention of `BlockedUsersRepository`, `RecipientTable`, `Job`, `JobManager`, `Constraint`, `jobmanager`,
  `JobManagerFactories`, `SearchRepository`, `DatabaseObserver`, `PreUploadRepository`, `MediaSendDependencies`,
  `TransformProperties`, `AttachmentCompressionJob`, `ConversationListFragment`, `ContactSearchViewModel`, or any Gradle module
  path (`feature:media-send`, `:app`, etc.) anywhere in the four task prompts.
- All four prompts are phrased as product/support tickets in plain engineering English (ordering complaint, feature request,
  storage-hygiene request, search-performance complaint), matching the "good" example style in the design brief rather than the
  "bad" example that names classes directly.
- All internal names, file paths, and the specific mechanism identity are confined to the `metadata_*.yaml` files (ground truth,
  not shown to the agent) and this RECON_NOTES.md file.

## Known limitations of this recon pass

- No local build/test execution was possible (no Android SDK/JDK on this machine, and cloning was explicitly disallowed by the
  disk constraint). All `functional_check_command` / `architecture_check_command` entries in the four `metadata_*.yaml` files are
  therefore precise descriptions of the intended check (including target Gradle test invocations) rather than commands verified
  to actually pass on this machine. Before Phase 5 (positive/negative control verification), these should be executed for real
  on a machine with the Android toolchain.
- `getBlocked()` single-caller claim (Task A) was checked with one `search/code` query and one tree grep, not cross-verified a
  second way; flagged explicitly in `metadata_A.yaml` as something the agent should re-verify rather than trust.
- I did not verify whether `AttachmentUploadJob` (as opposed to `AttachmentCompressionJob`) has any independent
  quality/compression logic that would also need to respect `skipTransform` for Task B's "full quality" requirement to be fully
  correct end-to-end; `AttachmentCompressionJob` was sufficient to establish the architectural point (existing flag + existing
  job already do the right thing once set), which is what the metadata's architectural_constraints rely on — the exact set of
  jobs touched is left for the benchmark agent to discover, consistent with "not a single reference diff."
