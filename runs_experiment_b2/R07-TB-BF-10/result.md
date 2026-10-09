# R07-TB-BF-10

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.4
Dangerous success: False
Goga engagement signal: True
Cost: $2.5919287499999997
Duration: 441489ms, turns: 38

## Agent's own summary

# Change Plan

## Task Classification
Feature (new capability) — introduces one new architectural surface (manga-snooze storage/domain cell) plus additive, backward-compatible extensions to the existing (undocumented) Updates feed and Manga details cells.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| **NEW** `domain/.../manga/model` (snooze) | `MangaSnooze.kt` (new file, or reuse `manga/model` dir) | New tiny value type, `mangaId: Long`, `snoozedUntil: Long` |
| **NEW** `domain/.../manga/repository` (snooze) | new `MangaSnoozeRepository.kt` or plain interactors | Read/write port for snooze state |
| **NEW** `data` (snooze) | `data/src/main/sqldelight/tachiyomi/data/manga_snooze.sq`, migration `15.sqm` | New table `manga_snooze(manga_id PK, snoozed_until)`, upsert/remove/get queries |
| `app/.../domain/manga/interactor` (undocumented) | new `SetMangaSnooze.kt`, `GetMangaSnooze.kt` | Mirrors `SetExcludedScanlators.kt` pattern; direct `Database` dependency |
| `data/.../view/updatesView.sq` (undocumented) | `updatesView.sq` | Add `LEFT JOIN manga_snooze`, expose `snoozedUntil`; add always-on `AND (snoozedUntil IS NULL OR snoozedUntil <= :now)` to `getRecentUpdatesWithFilters` (and `getRecentUpdates`/`getUpdatesByReadStatus` for consistency) |
| `domain/.../updates/interactor/GetUpdates.kt`, `domain/.../updates/repository/UpdatesRepository.kt`, `data/.../updates/UpdatesRepositoryImpl.kt` (undocumented) | all three | Add a `now: Long` param threaded through, no default at repo boundary |
| `app/.../ui/updates/UpdatesViewModel.kt` (undocumented) | same file | Inject `SetMangaSnooze`/`GetMangaSnooze`; pass fresh `now` at subscription; add `Dialog.Snooze` variant; add `snoozeUpdates(items, duration)` / `clearSnooze(items)` actions mirroring `bookmarkUpdates` |
| `app/.../presentation/updates/UpdatesScreen.kt` | same file | Wire new toolbar action + render `Dialog.Snooze` |
| `app/.../ui/manga/MangaViewModel.kt` + `presentation/manga/.../MangaToolbar.kt` + `MangaScreen.kt` (both) | those files | Add "Remind me later" / "Clear snooze" overflow menu item, `Dialog.SetSnooze`, `setSnooze()`/`clearSnooze()` methods, subscribe snooze state in `init{}` |
| New dialog composable | `app/src/main/java/eu/kanade/presentation/updates/SnoozeDialog.kt` (new) | Preset durations (tomorrow / next week) + custom date via reused `TrackDateSelector`/`DatePicker` pattern |

## Root Cause Analysis
Greenfield feature — no existing snooze/remind/mute concept (confirmed via grep). Only 11 cells are governed by the frozen architecture forest (`goga schema`); the entire Updates feature and manga-details UI are undocumented, so most of this work has no CODEMANIFEST to reconcile against. The three documented cells this touches (`manga/model`, `manga/repository`, `data/manga`) are **read-only dependencies** — `Manga` itself is deliberately NOT modified (avoids widening the most-imported contract in the codebase); snooze state lives in an independent side table, mirroring the `excluded_scanlators` precedent.

## Trace Summary
`UpdatesViewModel` → `GetUpdates.subscribe(...)` → `UpdatesRepository.subscribeAll(...)` → `UpdatesRepositoryImpl` → SqlDelight `updatesView.getRecentUpdatesWithFilters`. Snooze exclusion is inserted at the SQL layer via a `LEFT JOIN manga_snooze`, gated by a fresh `:now` param threaded through all four layers (unlike `hideExcludedScanlators`, this is always-on, not a stored preference — no `UpdatesPreferences` change). Manga-details write path: `MangaViewModel.setSnooze()` → new `SetMangaSnooze` interactor → `manga_snoozeQueries.upsert`/`remove`. Downloads/background chapter fetching are untouched — they don't read `manga_snooze` at all, satisfying "chapters still download normally."

## Change Strategy
1. Add SqlDelight table + migration 15 + `manga_snooze.sq` queries (upsert/remove/getByMangaId).
2. Add `SetMangaSnooze`/`GetMangaSnooze` interactors (direct `Database` dependency, same shape as `SetExcludedScanlators`).
3. Extend `updatesView.sq`: join `manga_snooze`, add `:now`-gated WHERE clause to all three queries.
4. Thread `now: Long` through `UpdatesRepository`/`UpdatesRepositoryImpl`/`GetUpdates`.
5. `UpdatesViewModel`: inject new interactors, compute `now` fresh per `flatMapLatest` cycle (same spot `Clock.System.now()` is already computed for the 3-month window), add `Dialog.Snooze`, add `snoozeUpdates`/`clearSnooze` bulk actions operating on distinct `mangaId`s from selected `UpdatesItem`s.
6. `UpdatesScreen.kt`: add toolbar button + dialog rendering, new `SnoozeDialog` composable (presets: tomorrow, next week; custom via `TrackDateSelector`'s `DatePicker`).
7. `MangaViewModel`/`MangaToolbar`/`MangaScreen`: add "Remind me later"/"Clear snooze" overflow action, `Dialog.SetSnooze`, subscribe `GetMangaSnooze.subscribe(mangaId)` into `State.Success.snoozedUntil`.
8. Add string resources (`action_snooze`, dialog copy) to `i18n`.

## Specification Impact
No existing CODEMANIFEST is modified — `Manga`/`MangaRepository`/`MangaRepositoryImpl` contracts are read-only dependencies, untouched. A **new** CODEMANIFEST will be authored (via `goga-brainstorm`/`goga-apply`) for the new snooze domain+data cells only, since those are the one genuinely new architectural surface introduced.

## Usage Impact
No existing `.usages/*.md` files require changes (no documented cell's public contract changes). A new `.usages/` file will be written for the new snooze cell once its CODEMANIFEST is created, describing how a consumer (e.g. `UpdatesViewModel`, `MangaViewModel`) reads/writes snooze state.

## Compatibility Verification
**Backward compatible.** All existing method signatures gain new required params only within undocumented/internal cells I'm modifying directly and consistently (no external consumers outside this codebase call `GetUpdates`/`UpdatesRepository`). No documented cell's contract changes. No stored preference/UI default changes for existing users — snooze is opt-in and starts unset for every manga (`manga_snooze` has no row until a user snoozes something), so existing Updates-feed behavior is unaffected until a user explicitly snoozes a series.

## Test Strategy
- Unit test `SetMangaSnooze`/`GetMangaSnooze` interactors (set, clear, overwrite).
- Unit test `UpdatesRepositoryImpl.subscribeAll` snooze filtering: snoozed manga with `snoozed_until > now` excluded; expired snooze (`<= now`) included; unsnoozed manga unaffected; verify composition with existing filters (unread/bookmarked/category) — snoozing one manga doesn't affect others' visibility under those filters.
- ViewModel-level test for `snoozeUpdates`/`clearSnooze` dedup-by-mangaId logic.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Snooze doesn't auto-lift without a fresh `now` on each resubscription (stale flow) | Medium | Medium | Compute `now` at the same `flatMapLatest` recombination point already driven by `downloadCache.changes`/`downloadManager.queueState`, which fire often enough in practice; document as a known granularity tradeoff |
| Multi-select snooze across chapters from different manga confuses user (bulk snoozes N series at once) | Low | Low | Dedup by `mangaId`, dialog copy states series count explicitly |
| New required SQL param (`:now`) breaks any other caller of `getRecentUpdates`/`getUpdatesByReadStatus` | Low | Medium | Grep all callers before editing; update every call site in the same change |
| FK cascade delete not covering manga removal edge case | Low | Low | `ON DELETE CASCADE` on `manga_id` mirrors `excluded_scanlators`, already proven pattern |

---

Do you approve the plan? Proceed to implementation?
