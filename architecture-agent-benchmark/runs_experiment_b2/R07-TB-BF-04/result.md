# R07-TB-BF-04

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.4
Dangerous success: False
Goga engagement signal: True
Cost: $1.9396125000000002
Duration: 366221ms, turns: 43

## Agent's own summary

# Change Plan

## Task Classification
**Feature** (additive extension) — introduces a new nullable field and one new repository method; no existing behavior is modified.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| domain/src/main/java/tachiyomi/domain/manga/model | Manga.kt, MangaUpdate.kt, CODEMANIFEST | Add `snoozedUntil: Long?` to both data classes + default/copy wiring; document new property |
| domain/src/main/java/tachiyomi/domain/manga/repository | MangaRepository.kt, CODEMANIFEST | Add `setMangaSnooze(mangaId, snoozedUntil)` method signature; document it |
| data/src/main/java/tachiyomi/data/manga | mangas.sq, migrations/15.sqm (new), MangaRepositoryImpl.kt, MangaMapper.kt, CODEMANIFEST | New column, migration, query, repository impl method, mapper param; document algorithm/method updates |

## Root Cause Analysis
Not a defect — the Updates-feed snooze feature requires persistent, per-manga state. No existing column/field can represent "hidden until timestamp," so a new nullable field/column/method must be added across the model → port → implementation chain, confirmed additive with HIGH confidence in the Investigation Report.

## Trace Summary
- `Manga`/`MangaUpdate` have exactly two construction sites each in scope (`Manga.create()`, `MangaMapper.mapManga`; `Manga.toMangaUpdate()`), all confirmed append-safe.
- `MangaMapper.mapManga` is called positionally from `mapLibraryManga` and `mapMangaWithChapterCount`; both must gain the new param in the same position and forward it.
- `setMangaSnooze` is a standalone write path (precedent: `setMangaCategories`), not routed through `MangaUpdate`/`partialUpdate`, so `partialUpdate`/`insertNetworkManga` bodies need no logic changes — only the table/mapper shape changes underneath them.

## Change Strategy

1. **domain/manga/model — Manga.kt**: append `val snoozedUntil: Long?,` as the new last constructor parameter (after `memo`); add `snoozedUntil = null` to `create()`'s default instance.
2. **domain/manga/model — MangaUpdate.kt**: append `val snoozedUntil: Long? = null,` as the new last parameter; add `snoozedUntil = snoozedUntil,` to `toMangaUpdate()`'s copy body.
3. **domain/manga/repository — MangaRepository.kt**: add `suspend fun setMangaSnooze(mangaId: Long, snoozedUntil: Long?)` near `setMangaCategories` (same "standalone per-manga mutator" grouping).
4. **data/manga — mangas.sq**: append `snoozed_until INTEGER` as the new last column in `CREATE TABLE mangas`; add a new query `setMangaSnooze: UPDATE mangas SET snoozed_until = :snoozedUntil WHERE _id = :mangaId;`; append `snoozed_until` to `insertReturningId`'s column list with a literal `NULL` value (new library entries are never pre-snoozed); leave `insertNetworkManga`/`update` untouched (new column simply defaults to NULL, consistent with how `favorite_modified_at` is handled today — no explicit param).
5. **data/manga — migrations/15.sqm (new file)**: `ALTER TABLE mangas ADD COLUMN snoozed_until INTEGER;` — matches the precedent style of `2.sqm`/`5.sqm`.
6. **data/manga — MangaMapper.kt**: append `snoozedUntil: Long?` as `mapManga`'s new last parameter, forwarded into `Manga(...)`; add `snoozedUntil` as a new parameter to `mapLibraryManga`/`mapMangaWithChapterCount` positioned immediately after the base columns (before their own trailing aggregate params), and thread it through their internal `mapManga(...)` calls.
7. **data/manga — MangaRepositoryImpl.kt**: implement `override suspend fun setMangaSnooze(mangaId: Long, snoozedUntil: Long?)` calling `database.mangasQueries.setMangaSnooze(snoozedUntil, mangaId)` (or matching generated param order), no try/catch (matches `setMangaCategories`'s un-caught style, since it has no Boolean-result contract).
8. **CODEMANIFEST reconciliation** (Step 7 of the outer pipeline, not this plan) will update all three manifests' Body sections to document the new property/method per `goga-cookbook` annotation standards.

## Specification Impact
- `domain/manga/model/CODEMANIFEST`: `Manga` signature string gains `snoozedUntil: Long?` at the end; add one property-description line ("`snoozedUntil`: epoch millis this manga's updates are hidden from the Updates feed until, or null if not snoozed") to the Manga type's annotation body (matching the existing per-field bullet style). `MangaUpdate` signature string gains `snoozedUntil: Long?` at the end.
- `domain/manga/repository/CODEMANIFEST`: `MangaRepository` gains a new `methods` entry: `"setMangaSnooze(mangaId: Long, snoozedUntil: Long?)": | Set or clear (pass null) the timestamp until which this manga's updates are hidden from the Updates feed.`
- `data/manga/CODEMANIFEST`: `MangaMapper.mapManga`'s documented signature/param list already elides some columns "for brevity" — no strict signature update required, but its annotation's parenthetical list should additionally mention `snoozedUntil`. `MangaRepositoryImpl::MangaRepositoryImpl`'s Algorithm section needs no new numbered step (matches precedent: `setMangaCategories` isn't separately enumerated either) — the existing step 1 ("Read methods run a generated query with the matching MangaMapper function as row mapper") already covers the mapper-shape change generically.

## Usage Impact
No `.usages/*.md` files exist in any of the three cells (confirmed via directory listing in Investigation). No usage-file changes required. The single connected practice (`sqldelight_row_mapper` in data/manga's inline `Usages`) needs no textual change — the new column/mapper param follows the exact convention it already describes.

## Compatibility Verification
**Backward compatible.** All changes are additive (new trailing constructor params with defaults where nullable-typed, one new interface method, one new nullable column, one new SQL query, one new migration file). No existing signature, return type, or persisted-column semantics change. Confirmed via Investigation Report's Breaking Change Assessment (all six questions answered NO).

## Test Strategy
No existing test files were found for these three cells (Investigation Report, Breaking Change Assessment item 6), so there is no existing suite to extend within strict scope. Per the outer pipeline's Step 6 (Testing), the goga-change-test-engineer will assess whether new tests are warranted for `setMangaSnooze`'s round-trip behavior (set → read back via `getMangaById` → clear via null) — this is a judgment call for that step, since introducing a test harness where none exists for sibling methods (`setMangaCategories` also has no dedicated test) may exceed minimal scope.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Missing a `mapManga(...)` positional call site outside the two identified in `MangaMapper.kt` | Low | High (compile break) | Tracer already grepped and confirmed only 2 call sites in scope; re-verify compile after edit |
| Migration file numbering collision (another `15.sqm` added concurrently) | Low | Medium | Directly check migrations directory immediately before creating the file |
| `insertReturningId` column-list edit introduces a values/columns count mismatch | Low | High (SQL error) | Append column and value in matching position at the end of both lists, verify count equality before finishing |
| CODEMANIFEST drift if manifest text isn't updated in the same change | Medium (multi-step pipeline) | Medium | Explicit Step 7 (Manifest Reconciliation) later in the outer pipeline enforces this |

Do you approve the plan? Proceed to implementation?
