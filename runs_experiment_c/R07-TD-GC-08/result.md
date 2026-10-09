# R07-TD-GC-08

Condition: goga_native_architecture
Base tag: condition-c-r07-v1
Functional success: False
Full architecture conformance: False
ACR: 0.4
Dangerous success: False
Goga engagement signal: True
Cost: $1.1873786999999998
Duration: 189128ms, turns: 41

## Agent's own summary

Added caching for source browse/search/popular/latest results:

- **`SourceMangaCache`** (new file, `data/src/main/java/tachiyomi/data/source/`) — a `@SingleIn(AppScope::class)` singleton, LRU-capped (60 entries) `LinkedHashMap` keyed by `(sourceId, query, filters, page)`, 5-minute TTL.
- **`SourcePagingSource.kt`** — `BaseSourcePagingSource.load()` now checks the cache before calling `requestNextPage()` and populates it on a real fetch; empty/no-result pages are cached too so repeated "no results" doesn't re-hit the network either.
- **Force-bypass chain** — `SourceRepository.invalidateCache()` → `GetRemoteManga.invalidate()` → `BrowseSourceViewModel.invalidateListingCache()`, wired into the existing "Retry" empty-state action in `BrowseSourceContent` (both call sites: `BrowseSourceScreen.kt` and `MigrateSourceSearchScreen.kt`).
- Popular/Latest use `GetRemoteManga.QUERY_POPULAR`/`QUERY_LATEST` as the cache query key with empty filters, matching how `BrowseSourceViewModel.Listing` already models them — so pagination within a cached listing keeps working via the `(query, filters, page)` key.
- Avoided the `FilterList.equals()` trap (it's hardcoded to always return `false` for Compose recomposition) by keying on `filters.list` instead.

Caught and fixed one bug along the way: an elvis-chain shortcut would let a cached *empty* page bypass the `NoResultsException` throw due to Kotlin's right-associative `?:`; rewrote with explicit variables.

Verified: `:data:compileDebugKotlin`, `:domain:compileDebugKotlin`, `:app:compileDebugKotlin`, `spotlessCheck`, and `goga lint` (still 0 errors across the 12 documented cells, which this change doesn't touch) all pass.
