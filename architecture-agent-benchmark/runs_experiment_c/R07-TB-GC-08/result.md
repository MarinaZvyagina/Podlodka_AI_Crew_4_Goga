# R07-TB-GC-08

Condition: goga_native_architecture
Base tag: condition-c-r07-v1
Functional success: False
Full architecture conformance: False
ACR: 0.4
Dangerous success: False
Goga engagement signal: False
Cost: $2.2167916500000002
Duration: 444612ms, turns: 46

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add a per-manga "snooze" (remind-me-later) capability that hides a series from the Updates feed until a chosen expiry timestamp, without affecting downloads, background refresh, or any other feed's filtering, and composing correctly with existing Updates filters (read/unread, started, bookmarked, category, excluded-scanlator).

## Candidate Cells
| Cell | Reason | Priority |
|---|---|---|
| `domain/src/main/java/tachiyomi/domain/manga/model` | `Manga`/`MangaUpdate` must carry the new `snoozedUntil` field — this is the aggregate every other layer depends on | High |
| `data/src/main/java/tachiyomi/data/manga` | `MangaMapper`/`MangaRepositoryImpl` must read/write the new column | High |
| `domain/src/main/java/tachiyomi/domain/manga/repository` | `MangaRepository` interface imports `Manga`/`MangaUpdate`; no new method needed (reuse generic `update`) | Low |

## Included Dependencies
| Cell | Behavioral Relevance |
|---|---|
| `domain/manga/model` → `domain/manga/repository` → `data/manga` | Single dependency chain: field is declared on the model, threaded through the repository port unchanged, persisted by the impl |

## Excluded Dependencies
| Cell | Exclusion Reason |
|---|---|
| `domain/track/*`, `data/track/*`, `app/.../data/track` | No participation in manga snooze or Updates filtering |
| `domain/chapter/*` | Chapter aggregate unaffected — snooze is manga-scoped, chapter rows/columns untouched |
| `domain/source/service`, `source-api/*` | No participation |

## Usage Relationships
| Usage | Relevance |
|---|---|
| `chapter_flags_bitmask` (domain/manga/model) | Precedent reviewed, **not reused** — `snoozedUntil` is a plain nullable timestamp like `favoriteModifiedAt`/`lastUpdate`, not a toggleable display filter, so a bitmask is the wrong shape |
| `sqldelight_row_mapper` (data/manga) | Directly applicable — new column added as a mapper parameter |

## Semantic Participation Summary
Only 3 documented cells participate, and only 2 non-trivially (`domain/manga/model` gains the field; `data/manga` persists it). `domain/manga/repository`'s contract text is untouched since `update(MangaUpdate)` already exists and is generic. The actual feed-hiding behavior and all UI entry points live entirely **outside the documented forest** (no CODEMANIFEST governs them): SQLDelight `mangas.sq`/migrations/`updatesView.sq`, `domain/manga/interactor`, and the `app` module's Updates/Manga-details presentation layer. These are necessarily touched as plain application code, not under CODEMANIFEST reconciliation discipline.

## Final Investigation Scope
- `domain/src/main/java/tachiyomi/domain/manga/model` (documented)
- `data/src/main/java/tachiyomi/data/manga` (documented)
- `domain/src/main/java/tachiyomi/domain/manga/repository` (documented, read-only check)
- Undocumented, necessarily touched: `data/src/main/sqldelight/tachiyomi/data/mangas.sq`, `.../migrations/`, `.../view/updatesView.sq`, `domain/.../manga/interactor/`, `app/.../ui/updates/`, `app/.../presentation/updates/`, `app/.../ui/manga/`, `app/.../presentation/manga/`, i18n strings

## Scope Risks
- **Under-scoping**: forgetting `updatesView.sq`'s WHERE clause makes the whole feature a no-op.
- **Over-scoping**: no need to touch `chapterFlags`, categories, or scanlator-exclusion machinery — must not conflate with those filters.
- **Compatibility risk**: `mapManga`'s parameters are positional and must match `mangas` table column declaration order exactly (SqlDelight `SELECT *` mapper) — the new column/param must be appended strictly at the end everywhere.

## Notes
Manga refresh/download scheduling (`LibraryUpdateJob` et al.) reads `favorite`/`nextUpdate` directly from the `mangas` table, never through `updatesView` — confirmed no change needed there to keep downloads/background behavior unaffected by snooze.

---

# Investigation Report

## Task Summary
Requested: a per-series "remind me later" snooze on the Updates feed. Investigated how the Updates feed currently determines visibility, to find the minimal integration point for a snooze condition that composes with existing filters and doesn't touch download/refresh logic.

## Candidate Cells
| Cell | Reason | Priority |
|---|---|---|
| `domain/manga/model` | Home of `Manga`/`MangaUpdate` | High |
| `data/manga` | Persistence of the new field | High |
| `domain/manga/repository` | Pass-through only | Low |

## Tracing Summary
- `UpdatesViewModel` (app, undocumented) → `GetUpdates.subscribe(...)` (domain/updates/interactor, undocumented) → `UpdatesRepository.subscribeAll(...)` (domain/updates/repository, undocumented) → `UpdatesRepositoryImpl` (data/updates, undocumented) → SqlDelight `updatesViewQueries.getRecentUpdatesWithFilters` → SQL view `updatesView` (`data/src/main/sqldelight/tachiyomi/view/updatesView.sq`), which joins `mangas` + `chapters`, filtered by `favorite = 1 AND date_fetch > date_added`, further filtered by nullable-parameter predicates for read/started/bookmarked/excluded-scanlator/category membership.
- Separately: `mangas` row is read/written exclusively through `MangaRepositoryImpl` (data/manga, documented) using `MangaMapper::mapManga` (positional column mapping) and the generated `mangasQueries.update(...)` coalesce-based partial update.
- Library refresh scheduling (`LibraryUpdateJob`, out of scope, not touched) reads `favorite`/`nextUpdate` directly from `mangas`, never through `updatesView` — confirms downloads/background refresh are structurally decoupled from the Updates feed's visibility logic.

## Data Flow Analysis
`mangas.snoozed_until` (new nullable column) → `MangaMapper.mapManga` (new trailing param) → `Manga.snoozedUntil` (domain) → `MangaUpdate.snoozedUntil` (partial update) → `MangaRepositoryImpl.partialUpdate` (new coalesce column) → `mangasQueries.update` (new SQL param). Independently: `updatesView.sq`'s base view gains one more `AND` predicate comparing `mangas.snoozed_until` against "now", which is a value only the SQL layer needs (no new Kotlin query parameter required since it's not a user-togglable filter — it's always-on, like `favorite = 1`).

## Manifest Algorithm Analysis
- `domain/manga/model` CODEMANIFEST documents `Manga`'s full field list and per-field annotations inline in the signature; adding `snoozedUntil` requires updating the `Manga`/`MangaUpdate` signatures and adding one field annotation line, consistent with how `favoriteModifiedAt`/`notes` are already documented as simple nullable/bookkeeping fields.
- `data/manga` CODEMANIFEST's `mapManga` method annotation says it builds "a Manga from one mangas table row plus its remaining scalar columns ... not individually listed here for brevity" — the new column fits this existing "remaining scalar columns" umbrella; no restructuring of the annotation's algorithm is needed, only the signature line gains the parameter.
- `domain/manga/repository` CODEMANIFEST's `update`/`updateAll` methods already say "Apply one sparse partial update" generically — no text change required since `MangaUpdate` already covers arbitrary optional fields.

## Affected Usages
| Usage | Cell | Classification | Reason |
|---|---|---|---|
| `chapter_flags_bitmask` | domain/manga/model | INDIRECTLY AFFECTED | Reviewed as precedent, not modified — confirms bitmask is the wrong mechanism for this field |
| `sqldelight_row_mapper` | data/manga | DIRECTLY AFFECTED | New column added as one more mapper lambda parameter, per its existing pattern |

## Rejected Hypotheses
- **Reuse `chapterFlags` bitmask for snooze state** — rejected: bitmasks in this codebase encode small enumerated/tri-state display settings, not epoch-millisecond timestamps; would require lossy encoding and contradicts the "custom date" requirement.
- **Track snooze as a "seen chapter" ledger (per-chapter ack) so old chapters fetched during snooze never reappear** — rejected: no such per-chapter-acknowledgment mechanism exists anywhere in the codebase; the existing Updates feed already has no concept of "already shown," it re-derives visibility every query from `date_fetch`/`date_added`/read-state. Introducing one would be a disproportionate, un-precedented architecture change for a feature described as "remind me later." The minimal, consistent design is: hide while `now < snoozedUntil`, unhide unconditionally once `now >= snoozedUntil` (mirrors how every other filter in `updatesView` is a stateless predicate over current column values, not a historical ledger).
- **New dedicated repository method `setMangaSnoozedUntil`** — rejected in favor of reusing existing generic `MangaRepository.update(MangaUpdate)` / `UpdateManga` interactor pattern (same pattern `awaitUpdateFavorite`/`awaitUpdateLastUpdate` already use for single-field updates) — avoids widening the `MangaRepository` contract at all.

## Confirmed Root Cause
The Updates feed has no mechanism to exclude a favorited manga from `updatesView` other than permanently removing it from the library (`favorite = 0`) or toggling read state per chapter. There is no per-manga "temporarily suppress" column. Adding `mangas.snoozed_until` (nullable epoch millis) and one `AND` predicate in `updatesView.sq`'s base view is the minimal change that satisfies the requirement while every other consumer of `mangas`/`Manga` (library screen, downloads, refresh scheduling, tracking) ignores the new column entirely, since none of them read through `updatesView`.

## Confidence Level
**HIGH** — full evidence chain traced from UI-level feed query down to the SQL table, single narrow write path (`MangaRepositoryImpl.update`) confirmed as the only mutation point, no other consumer of `mangas` touches `updatesView`, and no existing tests construct `Manga` positionally in a way a trailing appended field would break.

## Breaking Change Assessment
1. **Existing function call, same arguments → different behavior?** NO. `snoozedUntil` defaults to `null` for every existing row and every existing `Manga(...)`/`MangaUpdate(...)` call site that doesn't set it (both direct constructor call sites are named-arg: `MangaMapper.mapManga` and `Manga.create()`); `updatesView`'s new predicate `(snoozed_until IS NULL OR snoozed_until <= :now)` is always true when `snoozed_until IS NULL`, so all pre-existing data and all existing query results are unchanged.
2. **Existing file paths change?** NO — only edits to existing files plus one new migration file (`15.sqm`) and new files (interactor, UI), no renames/moves.
3. **Output format change?** NO — `Manga`, `MangaUpdate`, `UpdatesWithRelations` each gain one new optional/nullable field appended at the end; `Manga` is `@Serializable`, so the new field needs a default value for the Java-serialization roundtrip (`writeReplace`/`readResolve` via kotlinx.serialization) to stay compatible — will set `= null` default at both declaration and `create()`.
4. **Return value semantics change?** NO for `MangaRepository`/`UpdateManga` methods (still `Boolean` success). Updates-feed query results change **only** for manga a user actively snoozes — a new state that could not previously exist, not an alteration of prior guarantees for existing data.
5. **Manifest-defined guarantees altered?** NO — additive field only; existing annotated algorithms (`mapManga` builds "the remaining scalar columns", `update` applies "one sparse partial update") remain true verbatim.
6. **Existing tests break?** NO — grep found zero test files under `domain/src/test` or `app/src/test` constructing `Manga` or touching `domain/manga/model`/`data/manga` (only unrelated `FetchIntervalTest.kt` exists in that area).

No breaking change detected. Proceeding to Planning.
