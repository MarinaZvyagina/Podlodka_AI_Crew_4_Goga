# R07-TB-G-06

Condition: goga
Functional success: False
Full architecture conformance: False
ACR: 0.4
Dangerous success: False
Cost: $0.9008667
Duration: 140701ms, turns: 36

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add a per-series "snooze" (remind-me-later) capability for the Updates feed: a user can hide a favorited manga from the in-app Updates list until a chosen date/time, from either the Updates feed or the manga details screen. While snoozed, chapter fetching, downloading, and system notifications continue unaffected — only the Updates-feed list query is suppressed for that manga. The snooze auto-expires (no explicit unsnooze needed) and can also be cleared manually. It must compose correctly with the feed's existing read/unread, started, bookmarked, and category filters.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `domain/manga/repository` (`MangaRepository`) | Candidate for storing snooze state via existing `MangaUpdate`/`update()` mechanism | Medium |
| `domain/manga/model` (`Manga`, `MangaUpdate`) | Candidate for adding a `snoozedUntil`-style field to the aggregate | Medium |
| `data/manga` (`MangaRepositoryImpl`, `MangaMapper`) | Would implement the above if chosen | Medium |

## Included Dependencies

*(none — see Semantic Participation Summary)*

| Cell | Behavioral Relevance |
|---|---|
| — | — |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `domain/manga/model` | The `excluded_scanlators` table is the codebase's existing precedent for "auxiliary per-manga state that isn't part of the core aggregate": a separate SqlDelight table keyed by `manga_id`, with its own repository, joined in at the query site. Snooze state fits this precedent exactly — it is read by exactly one consumer (the updates query), never by `Manga`/`MangaUpdate` consumers generally. Folding it into `Manga`'s contract would mutate a heavily-documented, widely-imported constructor signature (every layer above the source boundary depends on it) purely to serve one downstream query — disproportionate blast radius for no behavioral gain, and pure speculative coupling. |
| `domain/manga/repository`, `data/manga` | Same reasoning — `MangaRepository`/`MangaRepositoryImpl` need not change; a new, undocumented sibling repository is the minimal-scope choice. No behavioral participation required from these cells. |
| `domain/chapter/*`, `domain/track/*`, `domain/source/service`, `source-api/*`, `data/track`, `app/.../data/track` | No data-flow or behavioral participation: the task explicitly requires chapter fetch/download/tracking to continue unchanged. These cells are infrastructural-only relative to this task. |

## Usage Relationships

| Usage | Relevance |
|---|---|
| `chapter_flags_bitmask` (domain/manga/model) | Not relevant — snooze is a timestamp, not a packed flag; no precedent reuse applies here. |
| `sqldelight_row_mapper` (data/manga) | Not directly imported (no manifest-documented cell is touched), but the same SqlDelight row-mapper convention applies by codebase-wide pattern to the new, undocumented snooze cell. |

## Semantic Participation Summary
No documented (CODEMANIFEST-governed) cell has genuine behavioral participation in this feature. The entire implementation surface — a new manga-snooze storage port + SqlDelight table, the Updates SQL view/query filter, the Updates feed presentation layer (list + filter dialog), and the manga details screen's "remind me later" entry point — lives outside the frozen architecture forest. This keeps the change fully additive: no existing contract's constructor signature, method set, or behavioral guarantee is touched.

## Final Investigation Scope
- `domain/updates/repository/UpdatesRepository.kt`, `domain/updates/interactor/GetUpdates.kt`, `domain/updates/model/UpdatesWithRelations.kt` (undocumented — investigate as plain code, not via manifest)
- `data/updates/UpdatesRepositoryImpl.kt` and `data/src/main/sqldelight/tachiyomi/view/updatesView.sq` (undocumented)
- `data/src/main/sqldelight/tachiyomi/data/mangas.sq` / `excluded_scanlators.sq` as the precedent for a new `manga_snooze` (or similar) table
- New undocumented domain+data cell for snooze storage (interactor + repository), modeled after the `excluded_scanlators` pattern
- `app/src/main/java/eu/kanade/tachiyomi/ui/updates/*`, `app/src/main/java/eu/kanade/presentation/updates/*` (Updates feed UI, filter dialog, entry point for "remind me later")
- Manga details screen (undocumented — locate via investigation) for the second entry point
- `domain/updates/service/UpdatesPreferences.kt` — check whether snooze duration options belong here or as a new preference

## Scope Risks
- **Under-scoping risk**: if a future change ever needs snooze state visible to `Manga`/`MangaRepository` consumers generally (e.g. library screen badge), this decision would need revisiting — but nothing in the current requirements calls for that.
- **Over-scoping risk avoided**: not touching `domain/manga/model`/`MangaRepository` avoids triggering the Compatibility Guard over a constructor-signature mutation that provides no cross-cutting benefit.
- **Investigation risk**: since none of the touched code is manifest-governed, the Investigation step must rely on direct code tracing (`goga-change-tracer`) rather than manifest annotations — extra care needed to find *all* consumers of `updatesView`/`UpdatesRepository` so filtering isn't bypassed by an unnoticed second query path.

## Notes
- No `.goga/config.yml` exists in this repo, so there are no project-wide base usages/annotations constraining this design.
- Because the minimal-scope implementation touches zero documented cells, Step 4 (Compatibility Guard) is expected to clear trivially — but must still run, since the guard also checks for accidental drift in cells like `domain/manga/model` if the investigation later reveals the separate-table approach isn't viable.
- If Investigation surfaces a reason the separate-table approach is infeasible (e.g. the SqlDelight join layer can't cleanly express it), the fallback of adding a field to `Manga`/`MangaUpdate` becomes in-scope and the Compatibility Guard step must treat it as a manifest mutation, not a breaking change, provided the new field is appended with all call sites updated for named/positional-safe construction.
