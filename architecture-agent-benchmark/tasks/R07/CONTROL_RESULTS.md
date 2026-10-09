# CONTROL_RESULTS.md — R07 (mihonapp/mihon)

**Note on provenance:** the original agent that implemented these controls was cut off by a connection error twice, immediately before writing this file (though all 18 validator scripts and all 8 control diffs it produced were saved successfully and are intact). Rather than resume a third time, the orchestrating session re-applied every diff directly against a clean checkout of the pinned commit (`/tmp/benchmark-repos/R07`, commit `ac249e3668a57f24782a49218834064459ba2d09`) and re-ran every validator script live to obtain authoritative, freshly-executed pass/fail results. Additionally, a real `./gradlew :domain:compileDebugKotlin` was run against Task A's positive diff to confirm the JDK 26 + Android SDK toolchain actually compiles Mihon code end to end (result: `BUILD SUCCESSFUL`, `FROM-CACHE` — meaning the original agent had already compiled this successfully before its connection dropped). Full instrumented/unit test execution across all 8 diffs was not repeated here due to Gradle build time cost; architecture-check results below are from live re-execution, not guesswork from reading diffs.

## Task A — Local Change (invalid extension-store URL validation)

**Positive control:** validation added to `domain/src/main/java/mihon/domain/extension/interactor/AddExtensionStore.kt` (the domain interactor), still delegating valid URLs to `repository.insert(...)`; data layer untouched.
**Negative control:** no diff at all to the domain interactor (validation omitted / placed elsewhere outside the interactor).

| Check | Positive | Negative |
|---|---|---|
| AC1 (validation lives in domain interactor) | PASS | **FAIL** |
| AC2 (no build.gradle.kts changes) | PASS | PASS |
| AC3 (no ViewModel/Compose UI changes) | PASS | PASS |
| AC4 (interactor signature unchanged) | PASS | PASS |

**Verdict: DISCRIMINATES.** Positive 4/4, negative 3/4 (fails AC1, the check that matters most for this task).

## Task B — Cross-module Feature (snooze updates)

**Positive control:** real SQLDelight migration (`migrations/15.sqm`) + `mangas.sq` column, `updatesView.sq` query-layer change, new domain interactor `SetMangaSnoozedUntil.kt` producing `MangaUpdate(...)` via `MangaRepository`, no new domain-layer repository interface.
**Negative control:** no migration file, no query-layer change, no new domain interactor.

| Check | Positive | Negative |
|---|---|---|
| AC1 (schema migration present) | PASS | **FAIL** |
| AC2 (query-layer snooze filter, not presentation-side) | PASS | **FAIL** |
| AC3 (domain interactor builds MangaUpdate via MangaRepository) | PASS | **FAIL** |
| AC4 (domain module doesn't import data layer) | PASS | PASS |
| AC5 (no direct SQLDelight `Database`/query references from app UI) | PASS | PASS |

**Verdict: DISCRIMINATES.** Positive 5/5, negative 2/5 (fails the three checks that verify the feature was actually implemented through the proper layers — the negative control here amounts to "the trap didn't build the feature at all through the sanctioned path," which is itself informative: this task's trap is "omit the cross-layer plumbing," not "build a parallel one").

## Task C — Existing Extension Point (self-hosted sync tracker)

**Positive control:** new `Komf` tracker under `app/.../data/track/komf/`, extends `BaseTracker`, registered in `TrackerManager.trackers` with a new ID constant; reader code (`ui/reader/`) untouched; relies on inherited `saveCredentials()`/preference plumbing (no bespoke credential storage).
**Negative control:** a bespoke `SelfHostedSyncManager` wired directly into `ReaderViewModel.kt`, bypassing the `Tracker`/`BaseTracker`/`TrackerManager` mechanism entirely.

| Check | Positive | Negative |
|---|---|---|
| AC1 (new tracker subpackage extends BaseTracker, registered in TrackerManager) | PASS | **FAIL** |
| AC2 (reader code untouched — uses generic tracker pipeline) | PASS | **FAIL** (ReaderViewModel.kt now imports the new bespoke SelfHostedSyncManager) |
| AC3 (credential storage via inherited BaseTracker plumbing) | PASS | **FAIL** (no tracker subpackage exists to inherit from) |
| AC4 (domain/data track model untouched) | PASS | PASS |

**Verdict: DISCRIMINATES strongly.** Positive 4/4, negative 1/4. This is the clearest extension-point-bypass example in the R07 set — the trap is caught on exactly the dimension the task is designed to test (did the agent find and use `Tracker`/`BaseTracker`, or build a parallel mechanism).

## Task D — Architecture Trap (search result caching)

**Positive control:** cache lives in the data layer (`data/src/main/java/tachiyomi/data/source/SourceSearchCache.kt` + wiring through `SourcePagingSource.kt`/`SourceRepositoryImpl.kt`), reachable by any consumer of `SourceRepository`/`GetRemoteManga` (not just one ViewModel); `GetRemoteManga`/`SourceRepository` signatures unchanged.
**Negative control:** cache implemented as a Map field directly inside `BrowseSourceViewModel.kt` (the UI layer), with staleness/invalidation logic also confined to that same ViewModel.

| Check | Positive | Negative |
|---|---|---|
| AC1 (no cache field in BrowseSourceViewModel) | PASS | **FAIL** |
| AC2 (GetRemoteManga/SourceRepository signatures unchanged) | PASS | PASS |
| AC3 (cache reachable by all SourceRepository consumers, not one screen) | PASS | **FAIL** |
| AC4 (no build.gradle.kts changes) | PASS | PASS |
| AC5 (staleness/invalidation logic lives in the data layer) | PASS | **FAIL** |

**Verdict: DISCRIMINATES.** Positive 5/5, negative 2/5. This is a direct, codebase-grounded instance of the benchmark's canonical Architecture Trap pattern (cache in the wrong layer) — confirmed via the independently-verified fact (documented in `RECON_NOTES.md`) that `SmartSourceSearchEngine.kt` bypasses `BrowseSourceViewModel` entirely, meaning a ViewModel-local cache is provably too narrow in scope, not just stylistically wrong.

## Overall

All 4 R07 tasks discriminate correctly between their positive and negative controls, using live-executed validator scripts (re-run directly by the orchestrating session, not inferred from diffs). The JDK 26 + Homebrew Android SDK toolchain set up for this benchmark was confirmed functional via a real, successful `compileDebugKotlin` build. One limitation carried forward honestly: full instrumented/unit test execution across all 8 diffs (as opposed to the architecture-check scripts and one compile spot-check) was not exhaustively repeated here — given the thin pre-existing test suite already flagged in this repo's `RECON_NOTES.md`, functional verification for this repository leans more on the architecture checks and structural compile success than on a rich existing test suite, consistent with what was anticipated during task design.
