# R07 recon notes — mihonapp/mihon @ ac249e3668a57f24782a49218834064459ba2d09

All exploration below used `gh api repos/mihonapp/mihon/...` (contents/tree endpoints) and
`gh api -X GET "search/code?q=...repo:mihonapp/mihon"` plus raw.githubusercontent.com fetches
pinned to the commit. No local clone was performed, per the disk constraint. The recursive tree
listing (1885 paths) was cached at `/tmp/mihon_tree.txt` during the session.

## Module layout confirmed

Top-level Gradle modules (settings.gradle.kts): `app`, `baseline-profile`, `core-metadata`,
`core:archive`, `core:common`, `core:metro`, `data`, `domain`, `i18n`, `presentation-core`,
`presentation-widget`, `source-api`, `source-local`, `telemetry`.

Dependency edges verified by grepping each module's `build.gradle.kts` for `projects.*`:
- `source-api` → `core:common` only.
- `domain` → `source-api`, `core:common` only (does **not** depend on `data`).
- `data` → `source-api`, `domain`, `core:common`.
- `presentation-core` → `core:common`, `i18n` only (does **not** depend on `domain`/`data`).
- `app` → everything (i18n, core:archive, core:common, core:metro, core-metadata, source-api,
  source-local, data, domain, presentation-core, presentation-widget, telemetry).

Important nuance: `eu.kanade.presentation.*` (ViewModels, Composables/Screens) is **not** a
separate Gradle module — it lives inside `app`, alongside `eu.kanade.tachiyomi.data.*`
(infrastructure/data-adapter code also in `app`) and DI wiring. So "presentation must not depend
on data" cannot be checked as a Gradle module-dependency-graph fact for app-module code; it has to
be checked as a *package-level import convention* (grep for `import tachiyomi.data.*` /
`Database` inside `eu/kanade/presentation/**`). I verified this convention holds almost
universally (`ExtensionStoresViewModel.kt`, `BrowseSourceViewModel.kt` only import domain
interactors / models), with one known, narrow exception: `ClearDatabaseScreen.kt`
(`app/src/main/java/eu/kanade/presentation/more/settings/screen/advanced/ClearDatabaseScreen.kt`)
injects `tachiyomi.data.Database` directly into `ClearDatabaseViewModel` for a bulk
admin/maintenance "wipe selected rows" operation with no real per-entity business semantics. I
treated this as a pre-existing, narrow, admin-only exception — not a precedent that undermines
Task D's architecture check, since Task D's feature (search caching) has clear business semantics
and an existing layered call chain to reuse, unlike raw DB wipe.

## Task A evidence — `mihon.domain.extension.interactor.AddExtensionStore`

- `domain/src/main/java/mihon/domain/extension/interactor/AddExtensionStore.kt`: `suspend
  operator fun invoke(indexUrl: String): Result<Unit> = repository.insert(indexUrl)` — a bare
  pass-through, **no validation today**.
- `data/src/main/java/mihon/data/extension/repository/ExtensionStoreRepositoryImpl.kt`:
  `insert()` calls `service.fetch(indexUrl).mapCatching { upsert(it) }`.
- `data/src/main/java/mihon/data/extension/service/ExtensionStoreService.kt`: `fetch()` does
  `network.client.newCall(GET(updatedIndexUrl)).awaitSuccess()` — i.e. a malformed URL fails deep
  inside an OkHttp/network call, confirming the ticket's premise ("fails with a confusing
  low-level error").
- `app/src/main/java/eu/kanade/presentation/more/settings/screen/browse/ExtensionStoresViewModel.kt`:
  `createRepo(baseUrl)` calls `addExtensionStore(baseUrl).onSuccess {...}.onFailure { throwable ->
  ... errorMessage = throwable.message ?: "unknown error" }` — confirms the UI already has a
  working error-display path fed straight from the interactor's `Result`, so a purely
  domain-layer fix requires zero UI changes. This is what makes the task genuinely a bounded,
  single-component "local change" rather than something that ripples into presentation.

## Task B evidence — Updates feed / snooze

- `data/src/main/sqldelight/tachiyomi/view/updatesView.sq`: `updatesView` + queries
  `getRecentUpdates`, `getRecentUpdatesWithFilters` (has WHERE-clause params for `read`,
  `started`, `bookmarked`, `hideExcludedScanlators`, `includedCategories`, `excludedCategories`),
  `getUpdatesByReadStatus`. This is the exact SQL-level precedent a snooze filter should follow.
- `domain/src/main/java/tachiyomi/domain/updates/repository/UpdatesRepository.kt` and
  `domain/src/main/java/tachiyomi/domain/updates/interactor/GetUpdates.kt`: confirm the
  flow-through-parameters pattern from domain down to the SQL query.
- `data/src/main/sqldelight/tachiyomi/data/mangas.sq`: current `mangas` table schema (confirmed
  columns incl. `notes TEXT NOT NULL DEFAULT ""`, `memo BLOB AS JsonObject ...`). Migrations
  directory `data/src/main/sqldelight/tachiyomi/migrations/` currently has files `1.sqm`
  through `14.sqm` — next migration would be `15.sqm`.
- `domain/src/main/java/tachiyomi/domain/manga/model/Manga.kt`,
  `domain/src/main/java/tachiyomi/domain/manga/model/MangaUpdate.kt`,
  `domain/src/main/java/tachiyomi/domain/manga/repository/MangaRepository.kt` (`update(update:
  MangaUpdate): Boolean`): confirm the existing partial-update DTO pattern (used for `notes`,
  `memo`, etc.) that a new `snoozedUntil` field should reuse, rather than inventing a new
  repository.
- Confirmed via GitHub code search that no "statistics"/"snooze"/similar reminder feature exists
  yet in the repo, so this is a genuinely new feature, not a duplicate of something already built.
- This task requires touching **3 real boundaries**: data (SQL schema + view/query changes),
  domain (model + DTO + repository + new interactor), presentation (Updates screen action + manga
  details screen action) — satisfying the "≥3 preferred" bar in the protocol.

## Task C evidence — Tracker / TrackerManager (chosen over Source/CatalogueSource/SourceFactory)

Per the assignment brief, `Source`/`CatalogueSource`/`SourceFactory` in `source-api` was the
candidate extension point to verify. I read all four files
(`source-api/src/main/kotlin/eu/kanade/tachiyomi/source/{Source.kt,CatalogueSource.kt,SourceFactory.kt,online/HttpSource.kt}`)
and the manager that consumes them,
`app/src/main/java/eu/kanade/tachiyomi/source/AndroidSourceManager.kt`. Finding: this mechanism is
real, but concrete `Source`/`HttpSource` implementations for actual manga/comic websites are
**not present in this repo at all** — they ship as separate installable extension APKs, and
`AndroidSourceManager` discovers them at runtime via `extensionManager.installedExtensionsFlow`
(the only in-repo `Source` implementation is `LocalSource`, for on-device files, plus stub
sources). This means "add a new content source" cannot be posed as a realistic, self-contained,
verifiable in-repo coding task (there's no scraping target to implement against without inventing
a fictitious website, and the actual extension lives in a different repository/build entirely).

I therefore searched for a better-fitting, equally real, in-repo extension point and found
**`eu.kanade.tachiyomi.data.track.Tracker`** (interface,
`app/src/main/java/eu/kanade/tachiyomi/data/track/Tracker.kt`), its shared implementation
**`BaseTracker`** (`app/src/main/java/eu/kanade/tachiyomi/data/track/BaseTracker.kt`), and the
registry **`TrackerManager`** (`app/src/main/java/eu/kanade/tachiyomi/data/track/TrackerManager.kt`).
`TrackerManager` hardcodes one instance per tracker into `val trackers = listOf(myAnimeList,
aniList, kitsu, shikimori, bangumi, komga, mangaUpdates, kavita, suwayomi, hikka, mangaBaka)` — 11
real, fully in-repo implementations, three of which (`Kavita`, `Komga`, `Suwayomi`) are
specifically self-hosted-server integrations, an exact real-world precedent for the task's "sync
with a self-hosted server" premise. I read `Kavita.kt` in full
(`app/src/main/java/eu/kanade/tachiyomi/data/track/kavita/Kavita.kt`) and `BaseTracker.kt` in full
to confirm the shared contract (credential storage via `trackPreferences`, generic
`setRemoteLastChapterRead`/`setRemoteStatus`/`setRemoteScore` plumbing in `BaseTracker`, with only
`update()`/`login()`/`search()`/`refresh()` needing per-tracker implementation). This is a
significantly stronger, betterverified extension point for a self-contained benchmark task than
`Source`/`CatalogueSource`/`SourceFactory`.

**Prompt leak check for Task C**: `task_C.md` was written without using the words "Tracker",
"TrackerManager", "BaseTracker", "interface", "registry", or naming Kavita/Komga/Suwayomi
specifically (it says only "a few similar setups the app already talks to"). It describes the
feature purely in user-facing terms (self-hosted server, login, sync reading progress).

## Task D evidence — search-result caching (Research.md's own canonical example, grounded in real code)

Traced the actual call chain for source browsing/search:
1. **Presentation**: `app/src/main/java/eu/kanade/tachiyomi/ui/browse/source/browse/BrowseSourceViewModel.kt`
   — `mangaPagerFlowFlow` builds `Pager(PagingConfig(pageSize = 25)) { getRemoteManga(sourceId,
   listing.query ?: "", listing.filters) }.flow...cachedIn(viewModelScope)`. Note:
   `.cachedIn(viewModelScope)` only keeps Paging data alive across configuration changes within
   one ViewModel instance — it does **not** persist across navigating away and back (a new
   ViewModel/Pager re-triggers network fetches), so there is a genuine, verified gap matching the
   ticket's premise.
2. **Domain**: `domain/src/main/java/tachiyomi/domain/source/interactor/GetRemoteManga.kt` — single
   entry point (`operator fun invoke(sourceId, query, filterList): SourcePagingSource`), delegates
   to `SourceRepository.getPopular/getLatest/search`.
3. **Domain interface**: `domain/src/main/java/tachiyomi/domain/source/repository/SourceRepository.kt`.
4. **Data impl**: `data/src/main/java/tachiyomi/data/source/SourceRepositoryImpl.kt` (`search()`
   returns `SourceSearchPagingSource(...)`) and
   `data/src/main/java/tachiyomi/data/source/SourcePagingSource.kt` (`BaseSourcePagingSource.load()`
   calls `requestNextPage()` → `source.getSearchManga(...)`/`getPopularManga(...)`/`getLatestUpdates(...)`).
5. **source-api**: `source-api/src/main/kotlin/eu/kanade/tachiyomi/source/{Source.kt,CatalogueSource.kt}`
   define the actual network-hitting methods.

Corroborating evidence that a *ViewModel-local* cache would be an architecturally narrow, wrong
fix: `app/src/main/java/mihon/feature/migration/list/search/SmartSourceSearchEngine.kt` (used
during library migration between sources) calls `source.getSearchManga(1, query,
source.getFilterList())` **directly**, entirely independent of `BrowseSourceViewModel`/`GetRemoteManga`.
A cache trapped inside `BrowseSourceViewModel` would never help this second real, in-repo
consumer, whereas a cache placed at/below `SourceRepositoryImpl` structurally could.

Also found the existing convention for where caches belong in this codebase:
`eu.kanade.tachiyomi.data.cache.CoverCache` (`app/src/main/java/eu/kanade/tachiyomi/data/cache/CoverCache.kt`)
is a dedicated class, injected into `BrowseSourceViewModel` as `coverCache` (constructor param),
not implemented inline in the ViewModel — this is the concrete "correct pattern" precedent cited
in the metadata's architectural_constraints and used to distinguish positive vs. negative control.

This task maps directly onto Research.md §22's own canonical example ("Add caching for repeated
search results... invalidate after changes") — which is a coincidence of the general pattern
matching mihon's real architecture well, not a case of designing the task around the example text;
the underlying `BrowseSourceViewModel → GetRemoteManga → SourceRepository → SourcePagingSource →
Source` chain and the `.cachedIn(viewModelScope)` gap were independently verified in the actual
source before drafting the task.

## Thin test suite — impact on functional_check_command design

Confirmed via `grep -i '/test/' ` over the full tree: only 7 unit test files exist in the entire
repo:
- `app/src/test/java/mihon/core/migration/MigratorTest.kt`
- `core/common/src/test/java/tachiyomi/core/common/util/system/TallImageSplitCalculatorTest.kt`
- `domain/src/test/java/tachiyomi/domain/chapter/service/ChapterRecognitionTest.kt`
- `domain/src/test/java/tachiyomi/domain/chapter/service/MissingChaptersTest.kt`
- `domain/src/test/java/tachiyomi/domain/library/model/LibraryFlagsTest.kt`
- `domain/src/test/java/tachiyomi/domain/manga/interactor/FetchIntervalTest.kt`
- `domain/src/test/java/tachiyomi/domain/release/interactor/GetApplicationReleaseTest.kt`

There is **no** existing test for extension repositories (Task A), the updates feed or manga
repository (Task B), any tracker (Task C — only a `DummyTracker` *test double* exists at
`app/src/main/java/eu/kanade/test/DummyTracker.kt`, used elsewhere, not a tracker unit test), or
source browsing/search/paging (Task D — `data/src/test/` does not exist at all in the tree
listing). Consequently, every `functional_check_command` in this batch is written as: (a) a
concrete, precise description of a **new** test file to add (naming its path and what it should
assert, modeled on the style of the nearest existing analogous test, e.g.
`GetApplicationReleaseTest.kt` for Task A), plus the exact Gradle test-task invocation
(`./gradlew :domain:testDebugUnitTest`, `:data:testDebugUnitTest`, `:app:compileDebugKotlin`, as
appropriate — module test tasks are `testDebugUnitTest` because all these modules use the
`android.library`/`android.application` Gradle plugin, confirmed by reading `domain/build.gradle.kts`'s
`plugins { alias(mihonx.plugins.android.library) ... }` block and `android { namespace = ... }`
block), and (b) an explicit manual-verification procedure as a fallback/complement, since no
existing automated harness will catch a wrong implementation for these features out of the box.
This directly follows the task brief's instruction to "describe what a new test would look like
rather than pointing to an existing one."

## Prompt-leak self-check (Research.md §22 requirement)

Re-read all four `task_*.md` files after drafting metadata and confirmed none of them contain:
class names (`AddExtensionStore`, `Tracker`, `TrackerManager`, `BaseTracker`, `SourceRepository`,
`GetRemoteManga`, `BrowseSourceViewModel`, `CoverCache`, `UpdatesRepository`, `MangaUpdate`, etc.),
package names (`tachiyomi.domain.*`, `eu.kanade.tachiyomi.*`), file paths, Gradle module names, or
architecture-pattern vocabulary ("interactor", "repository", "interface", "registry", "provider",
"factory", "extension point"). All four are phrased purely as user-facing feature requests/bug
reports, consistent with the "good" example in Research.md §22 ("Add caching for repeated search
results for identical parameters; invalidate after data changes") rather than the "bad" example
that names internal classes.
