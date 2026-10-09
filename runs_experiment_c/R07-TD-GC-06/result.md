# R07-TD-GC-06

Condition: goga_native_architecture
Base tag: condition-c-r07-v1
Functional success: False
Full architecture conformance: False
ACR: 0.4
Dangerous success: False
Goga engagement signal: True
Cost: $1.1006586
Duration: 150871ms, turns: 34

## Agent's own summary

Added a TTL-based `SourceMangaCache` (5-minute expiry, 60-entry LRU) keyed by `(sourceId, query, filters, page)`:

- **`data/.../source/SourceMangaCache.kt`** (new) — the cache itself, `@Synchronized` get/put/invalidate.
- **`SourcePagingSource.kt`** — `BaseSourcePagingSource.load()` checks the cache before hitting the network and populates it on fetch; Popular/Latest/Search subclasses pass their cache key (query + filters) through the constructor.
- **`SourceRepositoryImpl.kt` / `SourceRepository.kt` / `GetRemoteManga.kt`** — wire the cache in, plus an `invalidateCache`/`invalidate` path for forcing a fresh fetch.
- **`BrowseSourceViewModel.kt`** — new `invalidateListingCache()`.
- **`BrowseSourceScreen.kt` (presentation) + both call sites** (`ui/browse/source/browse/BrowseSourceScreen.kt`, `MigrateSourceSearchScreen.kt`) — the existing "retry" empty-state action now invalidates the cache before refreshing, so pull-to-retry always forces a fresh fetch while normal re-navigation reuses cached results. Pagination is unaffected since each page is cached/keyed independently.

Compiled (`:data`/`:domain`/`:app`), `spotlessCheck`, and `goga lint` (12 cells, 0 errors) all passed first try.
