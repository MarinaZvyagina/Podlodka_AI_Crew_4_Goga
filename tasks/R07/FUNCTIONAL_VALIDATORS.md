# FUNCTIONAL_VALIDATORS.md — R07 (mihonapp/mihon)

This documents the 4 standalone **functional** validator scripts
(`validators/task_A_functional.sh` .. `task_D_functional.sh`) built to complement the existing
architecture validators (`validators/task_X_AC*.sh`). Each script takes a repo path as `$1`
(default `.`), injects a fixture JUnit5 test file into the target checkout, runs a scoped Gradle
test task, prints `PASS: ...`/`FAIL: ...`, exits 0/1, and cleans up after itself (restoring any
file it had to back up).

## Environment used

- `JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home` (JDK 21, confirmed
  present at this exact path — no fallback needed).
- `ANDROID_SDK_ROOT=ANDROID_HOME=/opt/homebrew/share/android-commandlinetools`.
- Repo: `/tmp/benchmark-repos/R07`, pinned commit `ac249e3668a57f24782a49218834064459ba2d09`.
- `~/.gradle` already had a warm dependency cache (~7.5 GB); all scripts try `--offline` first
  and transparently fall back to a networked run only if the offline attempt fails for a
  network/cache-miss reason (`could not resolve`, `no cached version`, DNS/socket errors, etc.).
- No Robolectric anywhere in this project (`libs.bundles.test = [junit-jupiter, kotest-assertions,
  mockk]`) — all unit tests (domain, data, app) run as plain JVM JUnit5, no Android runtime/
  emulator required. This made real, scoped `./gradlew :<module>:testDebugUnitTest --tests <FQCN>`
  execution feasible for all 4 tasks; no compile-only fallback was needed anywhere.
- Disk stayed above ~6 GB free throughout (started at 9.5 GB, ended at 6.7 GB after populating
  build caches for `domain`, `data`, and `app`); no cache cleanup was required.

## Design note that applies to all 4 tasks: why negative controls don't "functionally pass" here

The benchmark brief's general expectation is that architectural-trap negative controls
"functionally pass" (the feature works, just in the wrong place). For R07 specifically, the
*actual* negative-control diffs in `controls/task_{B,C,D}_negative.diff` do not merely put the
right feature in the wrong layer — they reroute the feature through an **entirely separate,
non-corresponding code path** (a SharedPreferences map in the app module for B, a standalone
`SelfHostedSyncManager` wired into `ReaderViewModel` for C, a `mutableMapOf` field inside
`BrowseSourceViewModel` for D) that never touches the interfaces/classes this task's
`required_existing_abstractions` designate as the entry point (`GetUpdates`/`UpdatesRepository`
for B, `TrackerManager` for C, `SourceSearchPagingSource`/`SourceRepositoryImpl` for D).

Because each functional test here is deliberately scoped to that designated entry point (per the
task instructions: black-box, but through the *real public entry point* — not one candidate's
private helpers), injecting it against these negative diffs produces a **compile error**, not a
graceful "feature absent" runtime result: the fixture references parameters/classes
(`currentTime`, `SourceSearchCache`, a new `TrackerManager` property) that simply don't exist in
that variant. This was verified empirically (see per-task sections below) rather than assumed.
Task A is the one exception: its two controls differ only in *where* validation lives while
keeping `AddExtensionStore`'s signature identical, so both compile against the same fixture.

This is treated as an honest, expected limitation, not a bug: a functional check that is scoped
to the architecturally-mandated entry point (as instructed) cannot observe a feature that a trap
implementation deliberately built somewhere else entirely. The pre-existing `task_X_AC*.sh`
architecture scripts already independently confirm *where* the trap put its logic; this
functional layer confirms *that the reference-shaped entry point genuinely works* when present.

## Task A — Reject invalid custom extension repository URLs early

**Checks:** `domain/src/test/java/mihon/domain/extension/interactor/AddExtensionStoreTest.kt`
(fixture: `validators/fixtures/task_A_test.kt`), reused verbatim from the positive control's own
diff (already black-box: only touches `AddExtensionStore.invoke(indexUrl): Result<Unit>` and the
`ExtensionStoreRepository` interface via a plain `mockk()`, no candidate-specific internals).
Asserts `""`, `"not a url"`, `"javascript:alert(1)"`, `"ftp://example.com/repo"` all yield
`Result.isFailure` without the repository's `insert()` ever being called, and that
`"https://example.com/repo.json"` succeeds and reaches `repository.insert()` exactly once.

**Command:**
```
./gradlew :domain:testDebugUnitTest --tests mihon.domain.extension.interactor.AddExtensionStoreTest
```

**Observed results:**
| Scenario | Result |
|---|---|
| Baseline (unmodified pinned commit) | **FAIL** — `4 failed` (`io.mockk.MockKException`, unstubbed `repository.insert()` call), as expected since no validation exists yet. |
| Positive control (`task_A_positive.diff`) | **PASS** — `BUILD SUCCESSFUL`, all 5 tests green. |
| Negative control (`task_A_negative.diff`) | **FAIL** — same `4 failed`/`MockKException` pattern as baseline, since `AddExtensionStore.kt` is untouched by this diff (validation was moved into `ExtensionStoreRepositoryImpl.insert()` instead). |

**Implementation-agnosticism / honesty note:** this is a deliberate, documented tradeoff
acknowledged even in the negative control diff's own (unused) test file comment: a domain-scoped
unit test that mocks `ExtensionStoreRepository` cannot observe validation logic implemented
inside a concrete data-layer class it isn't wired to. Discovering "the app still shows a friendly
error, just via a different layer" would require a heavier integration test constructing the real
`ExtensionStoreRepositoryImpl` (SQLDelight `Database`, `ExtensionStoreService`, real/mocked
network) — out of proportion to this task's own `functional_check_command`, which explicitly
specifies exactly this domain-scoped test shape. Architecturally, this also means Task A's
functional and architectural checks are highly correlated for this task's particular negative
control (both fail it) — this is inherent to where the trap was placed, not an artifact of test
design.

## Task B — Let users temporarily hide a series from the Updates feed

**Checks:**
`domain/src/test/java/tachiyomi/domain/updates/interactor/GetUpdatesSnoozeTest.kt` (fixture:
`validators/fixtures/task_B_test.kt`), reused verbatim from the positive control's own diff.
Exercises `tachiyomi.domain.updates.interactor.GetUpdates` (this task's designated entry point)
against a hand-written `FakeUpdatesRepository` (implements the `UpdatesRepository` interface, not
an internal helper). Asserts a manga snoozed until a future time is excluded from
`GetUpdates.await()`/`subscribe()`, one whose snooze has passed is included again, a never-snoozed
manga is unaffected, and snoozing one manga doesn't affect another's visibility.

**Command:**
```
./gradlew :domain:testDebugUnitTest --tests tachiyomi.domain.updates.interactor.GetUpdatesSnoozeTest
```

**Observed results:**
| Scenario | Result |
|---|---|
| Baseline (unmodified pinned commit) | **FAIL** — compile error (`No parameter with name 'currentTime' found`) against `GetUpdates`/`UpdatesRepository`, since neither has the parameter yet. |
| Positive control (`task_B_positive.diff`) | **PASS** — `BUILD SUCCESSFUL`, all 4 tests green. |
| Negative control (`task_B_negative.diff`) | **FAIL** — same compile error as baseline, since this diff implements snoozing entirely via a new `UpdatesSnoozePreferences` (SharedPreferences) class and a client-side filter in `UpdatesViewModel`, never touching `GetUpdates`/`UpdatesRepository`. |

**Implementation-agnosticism note:** per the design note above — the negative control's own
`app/src/test/java/eu/kanade/tachiyomi/data/updates/UpdatesSnoozePreferencesTest.kt` (part of that
diff) does independently prove its SharedPreferences-based snooze predicate works; that's a
genuinely working feature, just reachable only from `UpdatesViewModel`, not from
`GetUpdates`/`UpdatesRepository` or any other consumer — which is exactly the architectural
problem Task B's negative control is designed to represent (see `CONTROL_RESULTS.md`'s note that
this trap "omit[s] the cross-layer plumbing" rather than duplicating it elsewhere reachable).

## Task C — Sync reading progress with a self-hosted library server

**Checks:** `app/src/test/java/eu/kanade/tachiyomi/data/track/TrackerRegistrationTest.kt`
(fixture: `validators/fixtures/task_C_test.kt`), newly written (the positive control's own
`KomfTest.kt` only tests a private `resolveStatus()` helper specific to that one candidate
tracker, which would not generalize). This fixture is **reflection-only and never instantiates
`TrackerManager` or any tracker**: `eu.kanade.tachiyomi.data.track.anilist.Anilist` has an
`init {}` block that eagerly touches `BaseTracker`'s Injekt/`appGraph`-backed preference
plumbing, which throws `uy.kohesive.injekt.api.InjektionException` outside a fully initialized
Android app graph — confirmed empirically (first fixture draft did instantiate `TrackerManager()`
directly and failed this way even for a legitimately-passing scenario). Instead it inspects
`TrackerManager`'s compiled shape via `java.lang.reflect`: every existing tracker is exposed as
its own public, zero-arg property getter (`getMyAnimeList()`, ..., `getMangaBaka()`) whose return
type implements `Tracker`; a correctly-registered new integration adds one more such getter,
extending `BaseTracker`, with `trackers` itself remaining list-shaped.

**Command:**
```
./gradlew :app:testDebugUnitTest --tests eu.kanade.tachiyomi.data.track.TrackerRegistrationTest
```

**Observed results:**
| Scenario | Result |
|---|---|
| Baseline (unmodified pinned commit) | **FAIL** — `1 failed` (`a new tracker property beyond the baseline 11 is declared on TrackerManager`), as expected (only 11 baseline getters exist). |
| Positive control (`task_C_positive.diff`) | **PASS** — `BUILD SUCCESSFUL`, all 3 tests green (finds `getKomf()`, extends `BaseTracker`). |
| Negative control (`task_C_negative.diff`) | **FAIL** — same single-assertion failure as baseline, since `TrackerManager.kt` is untouched by this diff (`SelfHostedSyncManager` is wired directly into `ReaderViewModel` instead). |

**Feasibility note:** full app-module compile+test (`:app:testDebugUnitTest`) took ~1m20s cold and
well under a minute incrementally — feasible for repeated benchmark runs, no compile-only
fallback needed.

**Honesty note on scope:** per this task's own `functional_check_command`, true end-to-end
verification (log into the new integration, mark a chapter read, observe an outbound network call
specifically from the new tracker's `update()`/`setRemoteLastChapterRead()` path, as opposed to
from new code bolted onto the reader) is explicitly framed as a *manual* step — there is no
OkHttp-interceptor/mock-server test harness for trackers anywhere in this repo to automate this
against an arbitrary, unknown new tracker implementation. The automated check here targets the
part of the spec that *is* generically automatable: is a new tracker genuinely registered through
`TrackerManager` (the thing that makes the existing generic chapter-read-sync call sites pick it
up with zero reader/chapter-list code changes), the same question Task C's own metadata poses as
check (a). One known blind spot: a candidate that adds its new tracker instance **inline** inside
the `trackers = listOf(...)` list literal (no dedicated named `val` property, unlike all 11
existing trackers) would not produce a new getter and would be missed by this reflection-based
check; this was judged an acceptable, documented risk given it would also contradict the
convention every existing tracker follows.

## Task D — Cache repeated source searches

**Checks:** `data/src/test/java/tachiyomi/data/source/SourceSearchCacheTest.kt` (fixture:
`validators/fixtures/task_D_test.kt`), reused verbatim from the positive control's own diff (6
test cases). Exercises caching through `tachiyomi.data.source.SourceSearchPagingSource` /
`SourcePopularPagingSource` (the paging sources `SourceRepositoryImpl` constructs for
`SourceRepository.search()`/`getPopular()`/`getLatest()`, this task's designated entry point) with
a mocked `Source` and a call counter. Asserts: repeat identical search/listing reuses cache (no
2nd network call); a different query is not served from another entry's cache; an entry past its
TTL is refetched; an explicit `invalidate()` forces a refetch; pagination through a cached search
still returns the correct page each time, including for a brand-new `PagingSource` session
against the same cache (simulating navigating away and back).

Since the `data` module has **no test sources or test dependencies at all** at the pinned base
commit, the validator script also temporarily appends
`testImplementation(libs.bundles.test)`/`kotlinx.coroutines.test`/`junit.platform.launcher` to
`data/build.gradle.kts` if not already present (checked via `grep`), and restores the original
file on exit. The positive control's own diff happens to add this itself, so no double-patching
occurred when testing it.

**Command:**
```
./gradlew :data:testDebugUnitTest --tests tachiyomi.data.source.SourceSearchCacheTest
```

**Observed results:**
| Scenario | Result |
|---|---|
| Baseline (unmodified pinned commit) | **FAIL** — compile error (`Unresolved reference 'SourceSearchCache'`, `Too many arguments for SourceSearchPagingSource(...)`), since no cache exists yet. |
| Positive control (`task_D_positive.diff`) | **PASS** — `BUILD SUCCESSFUL`, all 6 tests green. |
| Negative control (`task_D_negative.diff`) | **FAIL** — identical compile error to baseline, since this diff caches only inside `BrowseSourceViewModel` (a `mutableMapOf` field) and never touches `data/src/main/java/tachiyomi/data/source/**` at all. |

**Implementation-agnosticism / honesty note (the most significant caveat in this document):**
this fixture is tied to the specific caching shape used by the reference/positive-control
implementation — a dedicated `SourceSearchCache` class threaded through the paging sources'
constructors, the exact name/shape identified in this task's own `CONTROL_RESULTS.md` verdict
(`data/src/main/java/tachiyomi/data/source/SourceSearchCache.kt`). The task metadata's own
architecture-check command explicitly allows the cache to instead be "inside
`SourceRepositoryImpl.kt` itself" with a different shape/no dedicated class — such a
(still-architecturally-valid) alternative implementation would fail to compile against this exact
fixture, i.e. **a false negative is possible for a correct-but-differently-shaped solution**. A
fully implementation-agnostic version would need to construct `SourceRepositoryImpl` (and
whatever undetermined extra constructor parameter it gains) via runtime reflection with
per-parameter-type mock injection, rather than a compile-time-typed test — judged not worth the
added fragility/complexity for this benchmark given: (1) the reference shape is explicitly
named as the expected one in this task's own control-generation notes, (2) the companion
architecture-check scripts (`task_D_AC1..AC5.sh`) already independently verify structural
placement via `grep`/diff regardless of exact class shape, and (3) the instructions explicitly
permit reusing/generalizing an already-good positive-control test rather than re-deriving a fully
generic one from scratch. This tradeoff, and its scope, is recorded here rather than silently
assumed.

## Summary

| Task | Baseline | Positive | Negative | Discriminates as designed? |
|---|---|---|---|---|
| A | FAIL | PASS | FAIL | Yes — matches architecture-only discrimination (both controls tested against the same fixture; only the correct one passes). |
| B | FAIL (compile) | PASS | FAIL (compile) | Yes, with the documented "negative reroutes through a completely different subsystem → compile error" caveat above. |
| C | FAIL | PASS | FAIL | Yes, with the documented "manual" scope limit for real network verification. |
| D | FAIL (compile) | PASS | FAIL (compile) | Yes, with the documented shape-specific caveat above (possible false negative for a differently-shaped-but-correct cache). |

All 4 scripts were run to completion multiple times against `/tmp/benchmark-repos/R07` (baseline,
positive, negative, per task) with real Gradle test execution (no fabricated passes); the repo was
returned to a clean state (`git checkout -- .` + `git clean -fd` excluding pre-existing
`.goga/`/`docs/`, `local.properties` recreated) after each run and at the end of this work.
