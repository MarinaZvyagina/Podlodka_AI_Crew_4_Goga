# R08 (signalapp/Signal-Android @ 441ba42c3f3175476a1f54eba8e72d8d6d304db7) — Functional Validators (Phase 6)

This closes the gap flagged after Phase 4/5: each task previously had a real, runnable
*architecture* validator (`validators/task_X_AC*.sh`) but the *functional* check described in
`metadata_X.yaml`'s `functional_check_command` was prose only. This phase adds one standalone,
runnable functional validator per task:

- `validators/task_A_functional.sh` + `validators/fixtures/task_A_test.kt`
- `validators/task_B_functional.sh` + `validators/fixtures/task_B_test.kt`
- `validators/task_C_functional.sh` + `validators/fixtures/task_C_test.kt.template`
- `validators/task_D_functional.sh` + `validators/fixtures/task_D_test.kt`

## Conventions

Every `task_X_functional.sh` takes the repo path as `$1` (default `.`):

1. Injects a black-box Robolectric/JUnit test into the target repo's real Gradle source tree
   (either a static fixture copied in, or — for Task C only — a template with the discovered
   class name substituted in; see Task C below for why).
2. Runs a scoped `./gradlew :Signal-Android:testPlayProdDebugUnitTest --tests "..."` (module name
   is `:Signal-Android`, not `:app` — see the module-naming gotcha in `CONTROL_RESULTS.md`).
3. Prints `PASS: ...` / `FAIL: ...` and exits 0/1 accordingly, or `MANUAL REVIEW REQUIRED` with
   exit 1 if the environment itself is unusable (no `./gradlew`, wrong directory, etc.).
4. Cleans up (via a bash `trap ... EXIT`) whatever it injected, restoring any pre-existing file at
   the same path from a `.functional-validator.bak` backup if one existed.

Environment used for all verification below (same as Phase 4/5, required — JDK 26 breaks
Robolectric here with "Unsupported class file major version 70"):

```
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
export PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_SDK_ROOT=/opt/homebrew/share/android-commandlinetools
export ANDROID_HOME="$ANDROID_SDK_ROOT"
```

Verification method: for each task, `/tmp/benchmark-repos/R08` (Task A) or a scratch `git
worktree` at the pinned commit (Tasks B/C/D, removed afterward) was reset clean, the task's
`controls/task_X_positive.diff` was applied, the validator was run, the repo was reset, the
`controls/task_X_negative.diff` was applied, and the validator was run again. All repos were
confirmed back to a clean `git diff --stat` (empty) / `git status --porcelain` (no tracked
changes) after every step, including at the end of this phase.

---

## Task A — blocked-contacts alphabetical sort (`local_change`)

**What it checks:** drives `BlockedUsersRepository.getBlocked()` (the fixed, guaranteed-sole
data-access point for this screen per `required_existing_abstractions`) with recipients blocked
in non-alphabetical order ("Zoe", "Amy", "Mike"), and asserts the returned list is
`[Amy, Mike, Zoe]`, plus a case-insensitivity check (`"bob"` vs `"Alice"`). Implementation-agnostic
with respect to *which* allowed layer does the sorting (`BlockedUsersRepository` itself, or the
underlying `RecipientTable.getBlocked()` query it calls) — it only observes the method's return
value. It deliberately does **not** call any UI-layer sort helper, so a candidate that only sorts
in the Fragment/Adapter (the documented trap) is expected to fail this check even though it would
satisfy a naive "is the on-screen list alphabetical" check — this matches the stricter reading of
`functional_check_command` already documented in `CONTROL_RESULTS.md`.

**Command:** `./gradlew :Signal-Android:testPlayProdDebugUnitTest --tests "org.thoughtcrime.securesms.blocked.BlockedUsersRepositoryTest"`

**Verified:**
- Positive control (`controls/task_A_positive.diff`): **PASS** — `BUILD SUCCESSFUL`, both tests green.
- Negative control (`controls/task_A_negative.diff`, sort added only in
  `BlockedUsersFragment`): **FAIL** — both tests fail with
  `expected:<[Amy, Mike, Zoe]> but was:<[Zoe, Amy, Mike]>` (and the mixed-case test similarly).
  Matches `CONTROL_RESULTS.md`'s own finding for this exact test.

---

## Task B — per-attachment full-quality override in media-send batch (`cross_module_feature`)

**What it checks:** `metadata_B.yaml` fixes the *class* names a correct solution must use
(`PreUploadRepository` interface, app-side singleton implementation
`MediaSendV3PreUploadRepository`) but not the *name* of the new method added to that interface. So
the fixture:
1. Reflects on `PreUploadRepository` and finds whichever method is not one of the six that already
   existed at the pinned commit (`preUpload`, `cancelJobs`, `deleteAttachment`,
   `updateAttachmentCaption`, `updateDisplayOrder`, `deleteAbandonedPreuploadedAttachments`) —
   matched on the Kotlin-mangled name prefix, since `preUpload` itself gets a `-<hash>` JVM name
   suffix from its `MediaRecipientId` value-class parameter.
2. Invokes that method reflectively on `MediaSendV3PreUploadRepository`'s singleton `INSTANCE`,
   synthesizing arguments by parameter type (Context / attachment id as `Long` or `AttachmentId` /
   `Boolean` flag) against a real Robolectric-backed SQLite `SignalDatabase`.
3. Asserts `transformProperties.skipTransform == true` on the marked attachment only, and that the
   value survives a fresh DB re-read (the closest JVM-level proxy for "survives process death"
   available without an emulator — matching metadata's own note on this).

**Command:** `./gradlew :Signal-Android:testPlayProdDebugUnitTest --tests "org.thoughtcrime.securesms.mediasend.v3.MediaSendV3PreUploadRepositoryFullQualityTest"`

**Verified:**
- Positive control (`controls/task_B_positive.diff`, new method `setSendAtFullQuality`): **PASS**
  — `BUILD SUCCESSFUL`, both tests green.
- Negative control (`controls/task_B_negative.diff`, bespoke
  `FullQualityCompressionOverride` object, `PreUploadRepository` never touched): **FAIL** — the
  reflective discovery step correctly reports `AssertionError: No new method was added to
  PreUploadRepository ... beyond the 6 that already existed at the pinned commit`. Matches
  `CONTROL_RESULTS.md`'s finding that this trap never touches the required interface.

*Calibration note:* the first draft of this fixture initially mis-flagged `preUpload` itself as
"new" because of JVM name-mangling from its `MediaRecipientId` value-class parameter (Kotlin
compiles it to `preUpload-49-Suxc`), which produced a false FAIL on the positive control's `INSTANCE.preUpload(...)`
never being called and a false attempt to invoke `preUpload` as the "new" method. Fixed by
comparing method names on the substring before `-` when checking against the baseline set.
Re-verified against both controls after the fix.

---

## Task C — orphaned thumbnail cache cleanup job (`existing_extension_point`)

**What it checks:** unlike A/B/D, this task's `required_existing_abstractions` are the *Job
framework itself* (`Job`/`Job.Factory`, `JobManagerFactories`, `NotInCallConstraint`,
`BatteryNotLowConstraint`) — the new `Job` subclass a correct solution adds has no fixed name at
all (the positive control happens to call it `ThumbnailCleanupJob`, but nothing requires that
name). So `task_C_functional.sh` does dynamic discovery + code generation instead of using a
static fixture:

1. Diffs the repo against the pinned commit for a file **added** (covers both a committed diff and
   an untracked working-tree diff from `git apply` — `git diff` alone never reports untracked
   files, which was a real bug caught during verification and fixed) under `app/src/main/java`
   that declares a concrete class inheriting `Job` (`class X ... : Job(` or `class X extends Job`).
   The superclass declaration and the `class X` keyword can be many lines apart in this codebase's
   own style (see `AnalyzeDatabaseJob.kt`'s `class X private constructor(\n ... \n) : Job(...)`
   shape) — the discovery logic finds the superclass line first, then scans upward for the nearest
   preceding `class` declaration.
2. Substitutes the discovered package + class name into `fixtures/task_C_test.kt.template` and
   injects the result into that same package, so no import of the discovered class is needed.
3. The generated test then, using only `Job`'s own public API (`getFactoryKey()`, `run()`,
   `serialize()`, `getParameters()`, `setContext()` — all public, `setContext`'s own doc comment
   says exactly "if you ever run a job without submitting it to the JobManager, you'll need to
   invoke this yourself"):
   - confirms the job's factory key resolves inside `JobManagerFactories.getJobFactories(context)`
     (AC1-equivalent, executed rather than grepped),
   - reads `Parameters.getConstraintKeys()` via reflection (it's package-private, and the generated
     test's package is whatever the candidate chose, not necessarily `jobmanager`) and asserts both
     `"NotInCallConstraint"` and `"BatteryNotLowConstraint"` are present (AC3-equivalent),
   - sets up one orphaned file and one attachment-referenced file in the real, shared "parts"
     directory (`AttachmentTable.newDataFile(context)` — same directory/orphan-definition as the
     pre-existing `AttachmentTable.deleteAbandonedAttachmentFiles()` precedent, which
     `CONTROL_RESULTS.md` documents as the load-bearing convention this task's positive control
     itself relies on), runs the job (looping on `Result.retry()` up to 20 times to tolerate a
     chunked one-file-per-run implementation), and asserts the orphan is deleted while the
     referenced file survives,
   - recreates the job via its own `serialize()` / the registered `Factory#create` and confirms the
     recreated job also runs without failing (AC2-equivalent).

**Command:** `./gradlew :Signal-Android:testPlayProdDebugUnitTest --tests "<discovered-package>.FunctionalValidatorGeneratedThumbnailCleanupTest"`

**Verified:**
- Positive control (`controls/task_C_positive.diff`, `ThumbnailCleanupJob`): discovery correctly
  found `org.thoughtcrime.securesms.jobs.ThumbnailCleanupJob`; generated test run: **PASS** —
  `BUILD SUCCESSFUL`, registration/constraints/cleanup/resumability all confirmed.
- Negative control (`controls/task_C_negative.diff`, `ThumbnailCleanupManager` — a Kotlin `object`
  singleton with a `Handler.postDelayed` loop, not a `Job`): **FAIL** — discovery correctly finds
  *no* new `Job` subclass anywhere in the diff and reports so explicitly, without attempting a
  Gradle run.

**Deliberate scope boundary (please read before treating this as a gap):** `CONTROL_RESULTS.md`'s
own Phase-5 negative-control functional test (`ThumbnailCleanupManagerTest.kt`) is hand-authored
*specifically against the trap's own private class name* (`ThumbnailCleanupManager`) and shows
"orphans deleted, PASS 1/1" — i.e. the trap's cleanup logic does work when tested by a test that
already knows its exact class name. That bespoke test cannot be generalized into a reusable script
for arbitrary future candidates (there is no stable name or common interface to hang a generic
test off of once a candidate abandons the `Job` framework entirely). Given this task's own
`functional_check_command` and `required_existing_abstractions` are explicitly anchored to the
`Job` contract (registration / run-serialize-resume / constraints) — that contract *is* what
"correct" means for this specific `existing_extension_point` task — `task_C_functional.sh`
deliberately reports FAIL rather than fabricating a PASS for a mechanism it cannot safely
introspect. This is a documented, intentional deviation from the Task-C row of
`CONTROL_RESULTS.md`'s results table (which shows "Functional: PASS" for the negative control,
from that bespoke test); it does not weaken overall detection, since AC1 (no `Job` subclass /
registration found) already independently and reliably fails this exact trap and is the primary
documented discriminator for this task's `DISCRIMINATES` verdict.

---

## Task D — search result caching (`architecture_trap`)

**What it checks:** drives `SearchRepository.queryThreadsSync()` (the fixed, sole data-access
layer per `required_existing_abstractions`) with `SignalDatabase`'s table accessors and
`AppDependencies.databaseObserver` mocked out (mockk), asserting:
1. an identical repeated query does not re-invoke the underlying table query a second time,
2. distinct queries are cached independently,
3. after a data-change notification fires through the real `DatabaseObserver` mechanism, a
   repeated identical query reflects the change instead of returning stale cached data — the
   "Dangerous Success" staleness signature this task specifically targets.

Point 3 does not hardcode a single observer-registration method: it captures both
`registerConversationListObserver` and `registerMessageUpdateObserver` (the two hooks metadata
calls out as acceptable) and fires whichever one(s) the candidate actually registered, so either
choice — or both — is credited. It is injected as a **new, standalone** test class
(`SearchRepositoryCachingFunctionalTest`) alongside the pre-existing `SearchRepositoryTest.kt`
rather than editing that file, to avoid any risk of clobbering a candidate's own valid edits to it.

**Command:** `./gradlew :Signal-Android:testPlayProdDebugUnitTest --tests "org.thoughtcrime.securesms.search.SearchRepositoryCachingFunctionalTest"`

**Verified:**
- Positive control (`controls/task_D_positive.diff`): **PASS** — `BUILD SUCCESSFUL`, all 3 tests green.
- Negative control (`controls/task_D_negative.diff`, TTL cache added inside
  `ContactSearchViewModel`, `SearchRepository.java` never touched): **FAIL** — 2 of 3 tests fail
  (`repeatedIdenticalThreadQueryIsServedFromCache` and `differentQueriesAreCachedIndependently`,
  both because the mocked table query is invoked twice instead of once — there is no caching at
  this layer at all); the third (`...ReflectsMutationAfterDatabaseChangeNotification`) trivially
  passes since an uncached query can never go stale. Gradle reports the overall test task FAILED,
  so the validator correctly outputs FAIL.

**Note on why this is a *stronger* result than `CONTROL_RESULTS.md`'s framing implies:**
`CONTROL_RESULTS.md`'s own negative-control functional test targets the trap's `ContactSearchViewModel`
directly and shows "fast on repeat: PASS; staleness-within-TTL: FAIL" — i.e. a naive
"is it fast the second time" check would be fooled, and only the staleness-specific assertion
catches the trap. Because this validator is scoped to the architecturally-*correct* layer
(`SearchRepository`, per `required_existing_abstractions`) rather than to whatever class the
candidate happened to put a cache in, it does not even need the staleness-specific assertion to
catch this particular trap: since `SearchRepository` has no caching behavior at all, even the
naive "does repeating the query skip the underlying work" check already fails. The staleness
assertion (test 3) remains in the fixture because it is still the correct, general-purpose
discriminator for the *harder* case metadata describes — a trap that *does* correctly cache in
`SearchRepository` (satisfying tests 1–2) but invalidates on a timer instead of on
`DatabaseObserver` — which is a real possible variant this validator would still catch that
AC1 alone (which just checks *where* the cache lives) would not.

---

## Summary table

| Task | Functional validator | Positive control | Negative control | Matches `CONTROL_RESULTS.md`? |
|---|---|---|---|---|
| A | `task_A_functional.sh` | PASS (2/2) | FAIL (0/2) | Yes, exactly (same test class, same result) |
| B | `task_B_functional.sh` | PASS (2/2) | FAIL (interface method never added) | Yes (trap never touches `PreUploadRepository`) |
| C | `task_C_functional.sh` | PASS (registration+constraints+cleanup+resume) | FAIL (no `Job` subclass found) | Deviates from CONTROL_RESULTS' bespoke trap-specific test (documented above); AC1 remains the reliable discriminator either way |
| D | `task_D_functional.sh` | PASS (3/3) | FAIL (2/3, cache-hit tests) | Stronger/broader than CONTROL_RESULTS' framing (documented above); same underlying trap correctly rejected |

All four validators are real, executed Gradle/Robolectric runs (no static-heuristic fallback was
needed in the end for any of the four positive/negative control pairs above). Both
`/tmp/benchmark-repos/R08` and the three scratch worktrees used for B/C/D (`R08-taskB`,
`R08-taskC`, `R08-taskD`, since removed via `git worktree remove`) were confirmed back to a clean
`git diff --stat` / `git status --porcelain` after every apply-and-test cycle.
