# R08 (signalapp/Signal-Android @ 441ba42c3f3175476a1f54eba8e72d8d6d304db7) — Phase 4/5 Control Results

## Environment notes (apply to all four tasks)

- Repo cloned (depth 1, then fetched the pinned commit) into `/tmp/benchmark-repos/R08`, with additional `git worktree` checkouts at `/tmp/benchmark-repos/R08-taskB`, `-taskC`, `-taskD` for parallel work on Tasks B/C/D (cheap: worktrees share the single `.git` object store).
- **JDK toolchain**: the machine's default `openjdk` (Homebrew keg-only) is JDK 26. Two real incompatibilities were found and worked around:
  1. `build-logic`'s `kotlin-dsl` plugin requires a JDK 21 toolchain; JDK 26 is not auto-provisionable (no toolchain download repository configured in this repo). Fixed by `brew install openjdk@21` and registering it globally via `~/.gradle/gradle.properties`: `org.gradle.java.installations.paths=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home,/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home`.
  2. Robolectric's bundled ASM library cannot parse JDK 26 class files (`Unsupported class file major version 70`), so any unit test that touches Robolectric fails outright if the Gradle daemon/test-worker JVM itself is JDK 26. Fixed by exporting `JAVA_HOME` to the JDK 21 install (not JDK 26) before invoking `./gradlew` for any test-running command. This is a real, load-bearing environment finding, not a style preference — using JDK 26 as instructed by the base task brief produces a false "BUILD FAILED" on every Robolectric-based test in this repo.
- **Module naming gotcha**: `settings.gradle.kts` declares `include(":app")` but then renames it: `project(":app").name = "Signal-Android"`. So all Gradle task paths use `:Signal-Android:...`, not `:app:...`, e.g. `./gradlew :Signal-Android:testPlayProdDebugUnitTest --tests "org.thoughtcrime.securesms.blocked.*"`. The `functional_check_command`/`architecture_check_command` strings in the metadata files use `:app:...` — these are correct in spirit but need this substitution to actually run.
- **Build scope**: per the task brief, no full `:assembleDebug` was attempted anywhere. All compilation/testing was scoped to `:Signal-Android:compilePlayProdDebugUnitTestSources` / `:Signal-Android:testPlayProdDebugUnitTest --tests "<package>.*"` (variant `playProdDebug`). A cold scoped build (first run, no cache) took ~12–15 minutes; incremental re-runs after a small source edit took ~1–3 minutes.
- **Shared-machine contention**: this environment was concurrently running several other unrelated benchmark tasks (R01–R10) building their own large Android/other repos throughout this session. This caused real, observed disk-space swings (34 GiB → <1 GiB free → recovered) and at least one corrupted/missing Gradle transform-cache entry (`~/.gradle/caches/9.4.1/transforms/.../plugins.jar` went missing mid-build, most likely evicted or raced by another concurrent session sharing the same `~/.gradle` cache) that required deleting the stale cache entry and retrying. This is noted here because it is a genuine property of the execution environment, not of Signal-Android or the task design, and it added significant wall-clock time to getting a first successful build.
- Disk stayed above the ~5 GiB floor throughout; no cleanup of `/tmp/benchmark-repos/R08*` build artifacts was needed.

---

## Task A — R08-TA (blocked-contacts alphabetical sort)

### Validators (Phase 4)
`validators/task_A_AC1.sh` .. `task_A_AC4.sh` — all four are fully automatable via `git diff` + `grep` against the pinned commit; no manual-review fallback needed for this task. **One real calibration bug was found and fixed during Phase 5**: the original `task_A_AC2.sh` only counted *how many* files contained new sorting logic (PASS if exactly 1), without checking *which* file. A negative control that adds sorting only inside `BlockedUsersFragment.java` (single file, not duplicated) would have incorrectly PASSed the original AC2. Fixed by additionally requiring the single sorting-logic file to be `BlockedUsersRepository.java` or `RecipientTable.kt` (the repository/data layer), matching AC2's own `expected_result_if_correct` text ("Exactly one file **(repository or RecipientTable query layer)**"). Re-verified against both controls after the fix (see below).

### Positive control
Sorting added in `BlockedUsersRepository.getBlocked()`: recipients are mapped from `RecipientRecord` and then sorted via `Comparator.comparing(r -> r.getDisplayName(context), String.CASE_INSENSITIVE_ORDER)`. No other file touched except a new test file.

Functional check: authored `app/src/test/java/org/thoughtcrime/securesms/blocked/BlockedUsersRepositoryTest.kt` (Robolectric, using the existing `RecipientTestRule` DB-fixture pattern from `RecipientTableTest.kt`) — creates recipients "Zoe", "Amy", "Mike" in that (non-alphabetical) order, blocks them via `SignalDatabase.recipients.setBlocked(...)`, calls the real `BlockedUsersRepository.getBlocked()` async API synchronously via a `CountDownLatch`, and asserts the returned order is `[Amy, Mike, Zoe]`; a second test checks case-insensitivity (`"bob"` vs `"Alice"`). Ran via `./gradlew :Signal-Android:testPlayProdDebugUnitTest --tests "org.thoughtcrime.securesms.blocked.*"`.

Diff: `controls/task_A_positive.diff`

### Negative control (the trap)
Sorting added only inside `BlockedUsersFragment`'s `subscribe` callback, right before `adapter.submitList(...)` — the repository/data layer is left untouched and unsorted, exactly as described in `notes_for_positive_negative_control`. (The sort was factored into a small package-visible static helper, `BlockedUsersFragment.sortForDisplay(...)`, purely so it could be unit-tested directly without standing up a full Fragment/RecyclerView — the *architecturally relevant* fact, that the sort lives in the Fragment and not the repository, is unchanged by that refactor.)

Two functional tests were run against this control to get the full picture:
1. **The same `BlockedUsersRepositoryTest.kt` used for the positive control** (i.e. the literal `functional_check_command` from `metadata_A.yaml`, which explicitly tests `BlockedUsersRepository.getBlocked()` directly) — **FAILS** (2/2 tests fail: repository still returns `[Zoe, Amy, Mike]` unsorted).
2. **A supplementary `BlockedUsersFragmentSortTest.kt`**, added only for Phase-5 diagnostic purposes, calling the trap's own `sortForDisplay(...)` helper directly — **PASSES**, confirming the trap does satisfy the ticket's literal product-facing acceptance criterion ("opening the screen shows entries in alphabetical order") even though the data layer is unsorted.

**Honest task-design note**: `metadata_A.yaml`'s `functional_check_command` is written to test the repository/ViewModel layer directly rather than the final rendered/UI-observable list. For Task A this happens to make the "functional check" itself already reject the trap (test #1 above fails), which is stricter than the `notes_for_positive_negative_control` paragraph implies ("this passes any functional 'is the visible list alphabetical' check"). Both are true statements about different things: it fails the *specified* functional_check_command, but passes the more literal, black-box *product* acceptance criterion from `task_A.md`. This is flagged here rather than silently choosing one interpretation — the architecture checks (specifically the fixed AC2) are what reliably catch this trap regardless of which functional-check flavor is used, which is the actually load-bearing property for Phase 5.

Diff: `controls/task_A_negative.diff`

### Results table

| Check | Positive control | Negative control |
|---|---|---|
| Functional (`BlockedUsersRepositoryTest`, literal `functional_check_command`) | PASS (2/2) | **FAIL** (0/2) |
| Functional (supplementary UI-visible-order check) | PASS | PASS |
| AC1 (no new Gradle module dep) | PASS | PASS |
| AC2 (sort logic in exactly one place, correct layer) | PASS | **FAIL** |
| AC3 (Fragment/Adapter no direct DB access) | PASS | PASS |
| AC4 (ViewModel no direct DB access) | PASS | PASS |

### Verdict: **DISCRIMINATES**

Both the literal functional check and AC2 independently separate positive from negative. AC3/AC4 correctly stay PASS for both (this trap doesn't add DB access anywhere — it's a wrong-layer/duplication trap, not a DB-bypass trap — so it's expected and correct that those two checks don't fire here; they exist to catch a *different* plausible trap variant).

---

## Task B — R08-TB (per-attachment full-quality override in media-send batch)

Work for Tasks B–D was parallelized across separate `git worktree` checkouts of the same pinned commit (`R08-taskB/C/D`) to save wall-clock time on this large repo; each worktree was reset to clean and then removed after its diffs were captured, leaving only the single `/tmp/benchmark-repos/R08` clone.

### Validators (Phase 4)
`validators/task_B_AC1.sh` .. `task_B_AC4.sh`. No calibration bugs found — all four discriminated correctly as originally written; none were modified.

### Positive control (files touched)
- `feature/media-send/.../preupload/PreUploadRepository.kt` — new interface method `setSendAtFullQuality(context, attachmentId, fullQuality)` (extends the existing Provider/Repository boundary, per architectural_constraints).
- `app/.../mediasend/v3/MediaSendV3PreUploadRepository.kt` — implements it via `SignalDatabase.attachments.setSkipTransform(...)`.
- `app/.../database/AttachmentTable.kt` — new `setSkipTransform(id, skipTransform)`, a read-modify-write of the persisted `TransformProperties` (single persistence path, no new migration).
- `feature/media-send/.../preupload/PreUploadController.kt` — `setFullQuality(media, fullQuality)` serialized on the same executor as upload/cancel, so the override applies even if pre-upload already started (functional requirement).
- Minimal UI hook in `MediaSendFlowState.kt` / `MediaSendFlowViewModel.kt` wiring a per-attachment toggle to the controller (full production Compose UI was explicitly out of scope per instructions — the data/interface layer is what the architecture checks and persistence requirement actually exercise).
- Test: `app/src/test/.../mediasend/v3/MediaSendV3PreUploadRepositoryFullQualityTest.kt` (Robolectric, real SQLite via `SignalDatabase`).

### Negative control (the trap)
- `feature/media-send/.../preupload/FullQualityCompressionOverride.kt` — new bespoke `object` singleton holding the choice in transient in-memory state, and re-implementing the "skip compression" decision itself by copying the original file bytes over the compressed output directly (`java.io.File`/`FileInputStream`/`FileOutputStream`) — never touches `PreUploadRepository`, `TransformProperties`, or `AttachmentCompressionJob`.
- Same UI wiring points, routed to the bespoke object instead of the repository.
- Test: `feature/media-send/src/test/.../FullQualityCompressionOverrideTest.kt`.

### Functional check
Metadata's ideal is an instrumented `androidTest` driving the real multi-select Compose flow and a real process kill — **not runnable in this environment (no emulator/instrumentation available)**. The closest feasible JVM equivalent was used instead, against a real Robolectric-backed `SignalDatabase`:
- Positive: `./gradlew :Signal-Android:testPlayProdDebugUnitTest --tests "org.thoughtcrime.securesms.mediasend.v3.*"` → **PASS, 3/3.** Confirms the marked attachment persists `transformProperties.skipTransform == true`, the sibling stays `false`, and the value round-trips through a fresh DB read (a JVM-level proxy for process-recreation).
- Negative: `./gradlew :feature:media-send:testDebugUnitTest --tests "...FullQualityCompressionOverrideTest"` → **PASS** for in-process behavior, but a second assertion explicitly shows the choice is **lost after simulated process death** — i.e. the negative control's own test honestly demonstrates the functional persistence requirement failing, in addition to the architecture checks failing.

### Results table

| Check | Positive control | Negative control |
|---|---|---|
| Functional (in-process) | PASS | PASS |
| Functional (process-death persistence) | PASS | **FAIL** |
| AC1 (no `feature:media-send` → `:app` dependency) | PASS | PASS |
| AC2 (routed through Provider/Repository interface, not a bespoke singleton) | PASS | **FAIL** |
| AC3 (reuses `TransformProperties.skipTransform`, no new migration) | PASS | **FAIL** |
| AC4 (no duplicate compression-decision logic outside `AttachmentCompressionJob`) | PASS | **FAIL** |

### Verdict: **DISCRIMINATES**
The trap's in-the-moment behavior looks correct (a naive "does the marked item send uncompressed" check would pass), but it fails the persistence requirement and three of four architecture checks. One diagnostic wrinkle reported by the implementing agent: an early draft of the negative-control test file happened to contain the literal string "TransformProperties" in a comment, which caused an incidental AC3 false-PASS purely from comment text — this was a self-authoring artifact, not a validator flaw (AC3's grep is over raw diff text, comments included, per its literal specified method), and was fixed by rewording the comment rather than touching the validator.

---

## Task C — R08-TC (thumbnail cache cleanup job)

### Validators (Phase 4)
`validators/task_C_AC1.sh` .. `task_C_AC4.sh`. **One real calibration bug found and fixed**: `task_C_AC1.sh`'s check for a new `JobManagerFactories.java` registration originally grepped added lines for `\.put\(` (dot-prefixed). But this file's registrations are bare `put(KEY, new Factory())` statements inside a `new HashMap<>() {{ ... }}` double-brace initializer — no receiver/dot — so the original regex could never match a real, correct registration, meaning AC1 would have falsely FAILed even a fully correct positive-control implementation. Fixed to `(^|[^A-Za-z0-9_.])put\(`. This is a pure calibration fix (it does not touch the Job-subclass-detection or red-flag branches of AC1, both of which still independently gate the check).

### Positive control (files touched)
Thumbnail-cache-location assumption (load-bearing, documented explicitly): thumbnail/preview cache files live in the same private `context.getDir("parts", MODE_PRIVATE)` directory as attachment data files, per the existing precedent `AttachmentTable.deleteAbandonedAttachmentFiles()`, which already defines "orphan" as "file in that directory not referenced by any row's `DATA_FILE`/`THUMBNAIL_FILE` column." The new job reuses that exact definition rather than inventing a new one.
- `app/src/main/java/org/thoughtcrime/securesms/jobs/ThumbnailCleanupJob.kt` (new) — Kotlin `Job` subclass mirroring `AnalyzeDatabaseJob.kt`'s shape: one file checked per `run()`, progress cursor (`lastCheckedFile`) persisted via `serialize()`/`JsonJobData` and restored in `Factory#create`, `Result.retry(1.seconds)` to continue, `Result.success()` when a full pass completes. `Parameters.Builder()` declares both `NotInCallConstraint.KEY` and `BatteryNotLowConstraint.KEY`.
- `.../jobs/JobManagerFactories.java` — new `put(ThumbnailCleanupJob.KEY, new ThumbnailCleanupJob.Factory())` registration.
- `.../service/AnalyzeDatabaseAlarmListener.kt` — enqueues `ThumbnailCleanupJob()` alongside the existing daily `AnalyzeDatabaseJob`, i.e. a real, automatic, periodic, non-UI-triggered path.
- `.../database/AttachmentTable.kt` — new `isAttachmentFilePathReferenced(path)` helper reused by the job.
- Test: `app/src/test/.../jobs/ThumbnailCleanupJobTest.kt`.

### Negative control (the trap)
- `.../cleanup/ThumbnailCleanupManager.kt` (new) — a Kotlin `object` singleton, **not** a `Job`: a raw `Handler.postDelayed` loop, manual `TelephonyManager`/`BatteryManager` polling instead of the existing Constraints, progress cursor stored in `SharedPreferences`. Performs the same real orphan-deletion logic.
- `.../ApplicationContext.java` — `ThumbnailCleanupManager.start(this)` kicked off once from `onCreate`.
- Test: `.../test/.../cleanup/ThumbnailCleanupManagerTest.kt` (a simpler, isolated test of the cleanup batch logic only, since there is no Job API to round-trip).

### Functional check
- Positive: `./gradlew :Signal-Android:testPlayProdDebugUnitTest --tests "org.thoughtcrime.securesms.jobs.ThumbnailCleanupJobTest"` → **PASS, 3/3** — factory registration present, run/serialize/Factory#create resume round-trip verified across a simulated interruption, call+battery constraint keys present (checked via reflection on the built `Parameters`).
- Negative: `./gradlew :Signal-Android:testPlayProdDebugUnitTest --tests "org.thoughtcrime.securesms.cleanup.ThumbnailCleanupManagerTest"` → **PASS, 1/1** — orphans deleted, referenced files kept, SharedPreferences-style cursor advances.

### Results table

| Check | Positive control | Negative control |
|---|---|---|
| Functional | PASS (3/3) | PASS (1/1) |
| AC1 (Job subclass registered in JobManagerFactories, no Service/Thread/Handler/WorkManager) | PASS | **FAIL** |
| AC2 (resumable via serialize()/Factory#create, not SharedPreferences) | PASS | **FAIL** |
| AC3 (call/battery gating via existing Constraints, not hand-rolled polling) | PASS | **FAIL** |
| AC4 (enqueued via jobManager on an automatic/periodic path) | PASS | **FAIL** |

### Verdict: **DISCRIMINATES**
The trap functionally cleans up files and respects the stated conditions, but every architecture check fails, cleanly separating it from the positive control. One honest caveat from the implementing agent: AC1's red-flag greps (`extends Service`, `new Thread(`, `new Handler(`) are Java-idiom patterns; the Kotlin trap (`Handler(...)` without `new`, an `object` singleton rather than `extends Service`) doesn't trip those specific red flags, but AC1 still correctly fails it via the "no new Job subclass / no registration" branch — discrimination holds either way, though the red-flag regexes could be broadened to Kotlin idioms in a future pass for extra robustness (not required for this task's verdict).

---

## Task D — R08-TD (search result caching — `architecture_trap` category)

### Validators (Phase 4)
`validators/task_D_AC1.sh` .. `task_D_AC4.sh`. No calibration bugs found; none modified. AC3 is implemented as a script that actually runs `./gradlew :Signal-Android:testPlayProdDebugUnitTest --tests "org.thoughtcrime.securesms.search.SearchRepositoryTest"` — i.e. it executes the real staleness test rather than grepping for one.

### Positive control (files touched)
- `app/src/main/java/org/thoughtcrime/securesms/search/SearchRepository.java` — two bounded LRU caches (`threadResultCache`, `messageResultCache`; `LinkedHashMap` in access-order mode, capacity 50, wrapped `synchronizedMap`) keyed by (query text + filters), populated inside `queryThreadsSync()`/`queryMessagesSync()`. Invalidation is wired in the constructor via the existing mechanism: `AppDependencies.getDatabaseObserver().registerConversationListObserver(...)` and `registerMessageUpdateObserver(...)`, both of which clear the caches. `ConversationListFragment.java` and `ContactSearchViewModel.kt` are untouched, per the layering constraint.
- `app/src/test/java/org/thoughtcrime/securesms/search/SearchRepositoryTest.kt` — extended (not replaced) with 3 new tests following the file's existing Robolectric+mockk conventions: repeated identical query hits the cache (underlying table-query method invoked exactly once across two calls), different queries cache independently, and — the critical one — a query followed by a data mutation (via a DatabaseObserver-notifying path other than the cached call) followed by a repeat of the same query reflects the mutation.

### Negative control (the trap)
- `app/src/main/java/org/thoughtcrime/securesms/contacts/paged/ContactSearchViewModel.kt` — a UI-layer `ThreadSearchResultCache` (plain `HashMap`) with a fixed 60-second TTL, used inside the ViewModel's chat-search query path. No `DatabaseObserver` involvement anywhere. `SearchRepository.java` is completely untouched.
- New test `app/src/test/java/org/thoughtcrime/securesms/contacts/paged/ContactSearchViewModelCacheStalenessTest.kt`: demonstrates the full "Dangerous Success" signature in 3 tests — repeat-query-is-fast (served from cache, would pass a naive functional check), a mutation made through the repository is **not** reflected within the TTL window (stale — the architectural failure made concrete), and the cache does eventually refresh but only on blind time expiry, independent of whether data actually changed.

### Functional check
- Positive: `./gradlew :Signal-Android:testPlayProdDebugUnitTest --tests "org.thoughtcrime.securesms.search.SearchRepositoryTest"` → **PASS, 12/12** (9 pre-existing + 3 new, including the staleness test).
- Negative (separate test class, since the trap never touches `SearchRepository`): `./gradlew :Signal-Android:testPlayProdDebugUnitTest --tests "org.thoughtcrime.securesms.contacts.paged.ContactSearchViewModelCacheStalenessTest"` → **PASS, 3/3** — meaning the trap's naive "fast on repeat" behavior demonstrably works AND its staleness-within-TTL failure is demonstrably real (both proven, not asserted).

### Results table

| Check | Positive control | Negative control |
|---|---|---|
| Functional / staleness (own test class) | PASS (12/12) | "fast on repeat" PASS; staleness-within-TTL **FAIL** (proven by dedicated test) |
| AC1 (cache lives inside `search/` data layer, not UI) | PASS | **FAIL** |
| AC2 (invalidation via `DatabaseObserver`, not TTL/lifecycle) | PASS | **FAIL** |
| AC3 (runs `SearchRepositoryTest`, the fixed script target) | PASS | PASS* |
| AC4 (no new Gradle dependency) | PASS | PASS |

\* AC3's script is pinned to run the fixed class `SearchRepositoryTest`, which the negative control never touches (its cache lives entirely in `ContactSearchViewModel`), so that specific test trivially still passes for the trap — it isn't testing the trap's code at all. The trap's real functional failure (stale results within the TTL window) is demonstrated by the separate `ContactSearchViewModelCacheStalenessTest`, exactly as anticipated in `notes_for_positive_negative_control`. This is noted as an inherent property of AC3 being scoped to one fixed test class rather than a flaw to fix — AC1 and AC2 are what actually catch this trap architecturally, which is the primary thing Phase 5 needed to confirm.

### Verdict: **DISCRIMINATES**
AC1 and AC2 cleanly separate the two implementations, and the dedicated staleness test makes the trap's real-world consequence (returning stale search results after data changes made outside the TTL-refresh window) concrete and demonstrated rather than theoretical. One environment gotcha worth recording: an early draft of the positive-control diff accidentally contained two literal NUL bytes inside a cache-key string literal, which made `git diff` treat `SearchRepository.java` as a binary file — silently blinding AC1/AC2's grep-based checks (they'd have seen "no changes" and AC1 would have falsely FAILed). This was caught and fixed by removing the NULs; it's flagged here as a real, if unusual, way a grep-based validator can be silently defeated by non-ASCII/binary content landing in a diff, independent of any actual architecture violation.
