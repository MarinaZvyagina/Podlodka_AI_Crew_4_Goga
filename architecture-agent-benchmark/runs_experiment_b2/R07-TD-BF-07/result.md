# R07-TD-BF-07

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.4
Dangerous success: False
Goga engagement signal: True
Cost: $1.3380881999999998
Duration: 151503ms, turns: 38

## Agent's own summary

Done. Added TTL-cached, force-bypassable result caching for source popular/latest/search listings:

- **`data/src/main/java/tachiyomi/data/source/SourceMangaCache.kt`** (new) — a singleton LRU cache keyed by `(sourceId, query, filters.list, page)` with a 5-minute TTL, injected into `SourceRepositoryImpl`.
- **`SourcePagingSource.kt`** — `BaseSourcePagingSource.load()` checks the cache before fetching and populates it after; `Popular`/`Latest` paging sources use `GetRemoteManga.QUERY_POPULAR`/`QUERY_LATEST` as their cache key, matching what `search()` already uses for the query string.
- **`SourceRepository.kt` / `SourceRepositoryImpl.kt` / `GetRemoteManga.kt`** — added an `invalidateCache(sourceId, query, filterList)` chain for explicit force-refresh.
- **`BrowseSourceViewModel.kt`** — added `invalidateListingCache()`.
- **`BrowseSourceScreen.kt` (presentation) / two call sites** — wired the existing "retry" action in the empty-state screen to call `invalidateListingCache()` before re-fetching, so retrying (or navigating back and re-searching) bypasses the stale cache correctly; normal repeated navigation still serves from cache until the 5-minute TTL expires.

Paging works unaffected since each page is cached independently by its own key. Verified with `:data`/`:domain`/`:app` `compileDebugKotlin`, `spotlessCheck` across all modules, and `goga lint` (12 cells, 0 errors, unchanged) — all clean on the first attempt.
