# R07-TD-BF-09

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.4
Dangerous success: False
Goga engagement signal: True
Cost: $0.9780854999999998
Duration: 128011ms, turns: 33

## Agent's own summary

Implementation complete. Summary of the change (8 files):

- **New**: `data/.../SourceMangaCache.kt` — a `@SingleIn(AppScope::class)` LRU cache (60 entries, `LinkedHashMap` access-order) keyed by `(sourceId, query, filters.list, page)`, with a 5-minute TTL via `TimeSource.Monotonic`, and `@Synchronized` get/put/invalidate.
- **`SourcePagingSource.kt`**: `BaseSourcePagingSource.load()` now checks the cache before calling `requestNextPage()` and populates it after a network fetch; Popular/Latest paging sources hardcode their cache query/filters as constructor params.
- **`SourceRepositoryImpl.kt`** / **`SourceRepository.kt`** (domain) / **`GetRemoteManga.kt`**: thread the cache through, and add an `invalidateCache`/`invalidate` force-bypass path.
- **`BrowseSourceViewModel.kt`**: `invalidateListingCache()` clears the cache entry for the current listing.
- **`BrowseSourceScreen.kt`** (presentation) + its two callers (`BrowseSourceScreen.kt`, `MigrateSourceSearchScreen.kt`): added `onRefresh` param wired into the existing "retry" empty-state action, so retrying explicitly bypasses the cache; normal pagination/back-navigation reuse still hits the cache.

Verified: `:data:compileDebugKotlin`, `:domain:compileDebugKotlin`, `:app:compileDebugKotlin`, `spotlessCheck`, and `goga lint` (cells:12 errors:0, unchanged) all passed first try.
