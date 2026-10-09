# R07-TD-BF-02

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.4
Dangerous success: False
Goga engagement signal: True
Cost: $1.1508611999999996
Duration: 183022ms, turns: 36

## Agent's own summary

Implementation complete. Summary of the change:

- **`SourceMangaCache`** (new, `data/source`): `@SingleIn(AppScope)` singleton, LRU (60 entries via access-order `LinkedHashMap`) keyed by `(sourceId, query, filters.list, page)`, 5-minute TTL via `TimeSource.Monotonic`, `@Synchronized` get/put/invalidate.
- **`SourcePagingSource.kt`**: `BaseSourcePagingSource.load()` checks the cache before calling `requestNextPage()` and populates it on a miss; popular/latest/search subclasses each pass their fixed `query`/`FilterList` in as constructor params so cache keys stay consistent across pages.
- **`SourceRepositoryImpl`/`SourceRepository`/`GetRemoteManga`**: added `invalidateCache(sourceId, query, filterList)` threaded down to the cache, for explicit force-refresh.
- **`BrowseSourceViewModel.invalidateListingCache()`** wired to the existing "retry" `EmptyScreenAction` in `BrowseSourceContent` (via a new `onRefresh` param), used at both call sites (`BrowseSourceScreen`, `MigrateSourceSearchScreen`).

Verified `goga schema`/`ARCHITECTURE_CONTRACTS.md` confirmed this file set falls outside the 12 documented cells, so this was implemented as plain code (no `goga-brainstorm`/`apply` needed). `:data`/`:domain`/`:app` `compileDebugKotlin`, `spotlessCheck`, and `goga lint` (cells:12 errors:0, unchanged) all pass.
