# R07-TB-BF-07

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.4
Dangerous success: False
Goga engagement signal: False
Cost: $1.3420663500000003
Duration: 66683ms, turns: 9

## Agent's own summary

# [INTAKE_REPORT]

## Task Summary
Design the new domain/data architecture (cells, CODEMANIFEST, usages) needed to let a user snooze ("remind me later") a library series from the Updates feed for a chosen duration. While snoozed, the series' new chapters are hidden from the Updates feed only — downloads, notifications, and library membership are unaffected. The snooze auto-expires (series reappears in Updates on its next update after expiry) or can be cleared manually. Must compose with existing Updates filters (read/unread, category, bookmarked) without affecting other series.

## Description Type
Detailed

## Task-File Sections
N/A (no task file provided; description given inline with requirements, constraints, and pointers to existing relevant code)

## Original Description
Design new architectural surface for a "snooze a series from the Updates feed" feature in the Mihon Android app.

Feature requirements:
- From the Updates feed (list of new chapters for library series) or from a series' details page, the user can pick "remind me later" and choose a duration (fixed presets like tomorrow/next week, or a custom date).
- While snoozed, new chapters for that series must not appear in the Updates feed, but everything else (downloading, notifications, library membership) behaves normally and unaffected.
- Once the snooze period passes, the series automatically reappears in Updates next time it has new content — no user action needed.
- User can manually clear an active snooze before it expires.
- Must compose correctly with existing Updates feed filters (read/unread, category, bookmarked) — snoozing one series must not affect others, and existing filters keep working.

Existing relevant architecture (already researched, out of scope of the current frozen forest of 12 documented cells which only covers track/manga/chapter/source-api domains):
- Updates feed query: data/src/main/sqldelight/tachiyomi/view/updatesView.sq, view `updatesView` joins mangas+chapters, LEFT JOINs `excluded_scanlators` table to filter out rows; `getRecentUpdatesWithFilters` query adds nullable-bind-param filters (read/started/bookmarked/category via EXISTS subqueries).
- Precedent for new per-manga table: data/src/main/sqldelight/tachiyomi/data/excluded_scanlators.sq (manga_id + value column, FK cascade on mangas, indexed on manga_id), with a small repository/interactor pair in app/src/main/java/eu/kanade/domain/manga/interactor (SetExcludedScanlators.kt / GetExcludedScanlators.kt) wrapping the generated SQLDelight queries.
- domain/src/main/java/tachiyomi/domain/updates/repository/UpdatesRepository.kt + data/src/main/java/tachiyomi/data/updates/UpdatesRepositoryImpl.kt is the port/adapter for the updates feed itself.
- domain/src/main/java/tachiyomi/domain/manga/model/Manga.kt is the frozen Manga aggregate — should NOT be modified; snooze state should live in its own table/cell, analogous to excluded_scanlators, not as a new field on Manga.
- UI: app/src/main/java/eu/kanade/presentation/updates/UpdatesScreen.kt + UpdatesViewModel.kt (app/src/main/java/eu/kanade/tachiyomi/ui/updates/).
- SQLDelight migrations are numbered .sqm files under data/src/main/sqldelight/tachiyomi/migrations/, currently up to 14.sqm.

Please design the new cell(s) (domain model + repository port, data implementation, and the interactor(s) needed to set/clear/query a manga's snooze-until timestamp) needed to support this feature, keeping it decoupled from the frozen Manga/track/chapter forest. Produce the architecture plan for these new cells only.

## Scope Split Decision
Single subsystem — proceed. This is one coherent capability (persist + query + expire a per-manga "snoozed until" timestamp, and have the Updates query honor it), not multiple independent subsystems. The UI wiring (dialog, ViewModel calls) is a downstream consumer of this new cell, not a separate architectural surface — proceed with a single brainstorm pass covering the domain/data cell(s), and treat UI wiring as implementation that consumes the resulting contract.
