# R07-TD-BF-05

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.4
Dangerous success: False
Goga engagement signal: True
Cost: $1.3324421999999996
Duration: 285726ms, turns: 43

## Agent's own summary

## Summary

Added result caching for browse-source popular/latest/search listings:

- **`data/src/main/java/tachiyomi/data/source/SourceMangaCache.kt`** (new) — `@Inject @SingleIn(AppScope::class)` LRU cache (60 entries, `LinkedHashMap` access-order), 5-minute TTL, keyed by `(sourceId, query, filters, page)`.
- **`SourcePagingSource.kt`** — `BaseSourcePagingSource.load()` now checks/populates the cache around the network call; popular/latest use `GetRemoteManga.QUERY_POPULAR`/`QUERY_LATEST` as their cache-query discriminator, keeping pagination correct per page.
- **`SourceRepositoryImpl.kt` / `SourceRepository.kt`** — added `invalidateCache(sourceId, query, filterList)` for the force-bypass path.
- **`GetRemoteManga.kt`** — added `invalidate(...)`; **`BrowseSourceViewModel.kt`** — added `invalidateListingCache()`.
- **`BrowseSourceContent`** — new `onRefresh` param wired into the existing "retry" empty-state action in both call sites (`BrowseSourceScreen.kt`, `MigrateSourceSearchScreen.kt`), so retry/refresh bypasses the cache and re-fetches.

Verified: `data`, `domain`, and `app` modules all compile, `spotlessCheck` and `goga lint` (0 errors across the 12 documented cells) both pass. The touched directories (`data/source`, `domain/source/*`, browse UI) have no CODEMANIFEST, so this was plain implementation work outside the documented architecture forest — no new cell needed.
