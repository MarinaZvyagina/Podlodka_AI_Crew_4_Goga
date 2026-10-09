# R07-TB-BF-06

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.4
Dangerous success: False
Goga engagement signal: False
Cost: $2.3097775499999997
Duration: 148689ms, turns: 31

## Agent's own summary

# Investigation Report

## Task Summary
The task requests adding a nullable `snoozedUntil: Long?` field to the manga domain model (epoch-millis timestamp marking when a per-series "snooze" of the Updates feed expires), threaded through `MangaMapper` and `MangaRepositoryImpl.partialUpdate` in the `data/manga` cell so it round-trips through SqlDelight persistence. This is prerequisite plumbing for a separate (non-cell) piece of work that will add an interactor and UI to set/clear the snooze and filter it out of the Updates feed query.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `domain/src/main/java/tachiyomi/domain/manga/model` | `Manga`/`MangaUpdate` entities gain the new field | High |
| `data/src/main/java/tachiyomi/data/manga` | `MangaMapper`/`MangaRepositoryImpl` must read/write the new column | High |
| `domain/src/main/java/tachiyomi/domain/manga/repository` | Verification-only — confirms `MangaRepository`'s interface (which passes `Manga`/`MangaUpdate` by type, not by enumerated field) needs no textual change | Medium |

## Tracing Summary
- **Write path**: `MangaRepository.update(update: MangaUpdate)` → `MangaRepositoryImpl.update()` → `partialUpdate(vararg mangaUpdates: MangaUpdate)` → `database.mangasQueries.update(...)` (SqlDelight-generated from `mangas.sq`'s `update:` query, one named param per settable column, `coalesce(:param, column)` pattern) → `UPDATE mangas SET ... WHERE _id = :mangaId`.
- **Read path**: `MangaRepository.getMangaById`/`getMangaByIdAsFlow`/`getFavorites`/etc. → `database.mangasQueries.<query>(..., MangaMapper::mapManga)` → SqlDelight binds each `SELECT *` column positionally to `mapManga`'s parameter list in table-column order → `Manga(...)` construction.
- **Construction sites for `Manga(...)` (full positional/named constructor)**: only `Manga.kt`'s own `create()` companion factory and `MangaMapper.kt`'s `mapManga`. No other file in the repo constructs `Manga(...)` directly (confirmed via `grep -rln "= Manga(" --include="*.kt"`).
- **Construction sites for `MangaUpdate(...)`**: many (11 files), all using named arguments and relying on the existing `= null` defaults for unspecified fields (`LibraryViewModel.kt`, `SetMangaViewerFlags.kt`, `UpdateManga.kt`, `FetchInterval.kt`, `UpdateMangaNotes.kt`, `SetMangaChapterFlags.kt`, `MigrateMangaUseCase.kt`). None enumerate every field, so a new defaulted field is additive-only to all of them.

## Data Flow Analysis
`mangas` table row → SqlDelight-generated `SELECT *` column tuple → `MangaMapper::mapManga(id, source, ..., memo)` (positional-by-declaration-order lambda) → `Manga` domain instance. In the write direction: `MangaUpdate` (all-nullable partial update) → `MangaRepositoryImpl.partialUpdate` → `mangasQueries.update(...)` named params → `coalesce(:param, column)` SQL, so a `null` field leaves the existing column value untouched. Adding `snoozed_until` requires: (1) new column on `CREATE TABLE mangas` + matching `ALTER TABLE` migration, (2) new trailing parameter on `mapManga`/`mapLibraryManga`/`mapMangaWithChapterCount` matching the new trailing table column, (3) new param threaded into the `update:` and (optionally) `insertReturningId:`/`insertNetworkManga:` `.sq` queries, (4) new field on `Manga` and `MangaUpdate` domain types, (5) new field pass-through in `MangaRepositoryImpl.partialUpdate`'s call to `mangasQueries.update(...)`.

## Manifest Algorithm Analysis
- `domain/manga/model` CODEMANIFEST documents `Manga`'s full field list and each field's meaning inline (`lastModifiedAt`, `favoriteModifiedAt`, `version` described as "sync/conflict-resolution bookkeeping"; `notes` as "free-form user notes"). `snoozedUntil` fits the same textual pattern as `favoriteModifiedAt` (nullable epoch-millis bookkeeping field) and must be added to both the `Manga(...)` signature string and its field-description prose, and to the `MangaUpdate(...)` signature string, per the manifest's own documented convention of listing every field.
- `data/manga` CODEMANIFEST's `mapManga` annotation already says extra scalar columns are "not individually listed here for brevity" — so the new column does not strictly require prose changes there, but the signature line for `mapManga` (which currently lists only a partial explicit signature: `id, source, url, title, status, updateStrategy, calculateInterval, notes -> manga:Manga`) is already abbreviated and doesn't enumerate every real parameter (e.g. `artist`, `favoriteModifiedAt`, `memo` aren't in the manifest's signature string either, despite being real params in code) — so no manifest signature-string edit is strictly required for `mapManga`, only the reconciler step should confirm this abbreviation convention still holds.
- `MangaRepositoryImpl`'s Algorithm block ("Read methods run a generated query with the matching MangaMapper function...") is unaffected — no algorithmic change, only a data-shape addition.

## Affected Usages
| Usage | Cell | Classification | Reason |
|---|---|---|---|
| `chapter_flags_bitmask` | `domain/manga/model` | NOT AFFECTED | Unrelated to `snoozedUntil`; governs `chapterFlags` bit-packing only |
| `sqldelight_row_mapper` | `data/manga` | INDIRECTLY AFFECTED | The new column becomes one more scalar the mapper lambda receives; the existing "individual typed parameters" pattern already covers this without needing a new usage |

## Rejected Hypotheses
- **Hypothesis: store snooze state in a separate table/repository instead of a `mangas` column.** Rejected — the task explicitly asks for a field on the manga domain model threaded through the existing `MangaMapper`/`MangaRepositoryImpl` cell, and every other per-manga timestamp (`favoriteModifiedAt`, `lastModifiedAt`) already lives as a plain nullable column on `mangas`; a separate table would be architecturally inconsistent with zero benefit for a single scalar value.
- **Hypothesis: give `Manga.snoozedUntil` a default value (`= null`) in the data class itself.** Rejected — none of the other comparable nullable fields (`favoriteModifiedAt`, `artist`, `author`) have defaults on `Manga` (defaults only exist on `MangaUpdate`, and separately inside `Manga.create()`); since the only two `Manga(...)` construction sites (`Manga.create()`, `MangaMapper.mapManga`) are both being edited in this same change, a default is unnecessary and would break the established no-default convention on the entity itself.

## Confirmed Root Cause
Not a bug fix — this is a net-new field addition. Root implementation locus: `mangas` table schema (`data/src/main/sqldelight/tachiyomi/data/mangas.sq`) is the single source of truth that both `MangaMapper`'s positional row-mapping and `MangaRepositoryImpl`'s `update` query bind against; the domain types (`Manga`, `MangaUpdate`) are the cell-governed surface that must mirror it. Evidence chain: CODEMANIFEST signature strings for both cells enumerate every domain field ↔ `mangas.sq` `CREATE TABLE` enumerates every column ↔ `MangaMapper.mapManga`'s parameter list is positionally bound to `SELECT *` column order ↔ `MangaRepositoryImpl.partialUpdate` passes every `MangaUpdate` field into `mangasQueries.update(...)`'s named params.

## Confidence Level
**HIGH** — full evidence chain traced from CODEMANIFEST → domain model source → data-layer mapper/repository source → SqlDelight `.sq` schema/query source, with all `Manga(...)`/`MangaUpdate(...)` construction sites enumerated via grep and confirmed non-breaking.

## Breaking Change Assessment
1. Will existing function call with same arguments produce different behavior? **NO** — the new field is nullable/optional everywhere (default `null` on `MangaUpdate`, and both `Manga(...)` construction sites are updated in this same change), so no existing call with the same arguments changes behavior.
2. Will existing file paths change? **NO** — no files are moved or renamed; one new migration file (`15.sqm`) is added.
3. Will output format change? **NO** — `Manga`/`MangaUpdate` gain an additional field but existing fields/serialization shape for prior fields is unchanged (Kotlin `@Serializable` data class adds a new JSON key, which is additive, not breaking, for both encode and decode of existing data — SqlDelight `SELECT *` gains one more trailing column, additive to positional mapping since it's appended at the end).
4. Will return value semantics change? **NO** — all existing repository method contracts (`getMangaById`, `update`, etc.) keep identical semantics; they just carry one more optional field through.
5. Will manifest-defined guarantees be altered? **NO** — no documented algorithm, precondition, or postcondition in either CODEMANIFEST is changed; only the `Manga`/`MangaUpdate` signature strings and field-description prose gain one more entry, consistent with the manifest's existing convention of enumerating fields.
6. Will existing tests break? **NO** — verified no test file constructs `Manga(...)`/`MangaUpdate(...)` exhaustively without named-arg defaults that would need updating (no test directory hits found for full-arity `Manga(...)` construction outside the two known cell-internal sites).

No YES answers — **NOT a breaking change**. Proceeding to Planning.
