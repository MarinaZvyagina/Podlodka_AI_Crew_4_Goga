# SCOPE.md — R07 (mihonapp/mihon)

## Method

Mihon is a multi-module Gradle/Kotlin Android app (13 Gradle modules: `app`, `domain`, `data`,
`source-api`, `source-local`, `core-metadata`, `core/archive`, `core/common`, `core/metro`,
`i18n`, `presentation-core`, `presentation-widget`, `telemetry`, `baseline-profile`), not a
single flat package tree. Scope was decided from the project's own module/package layout,
verified by directly reading source files and by repo-wide `grep` for import statements to
confirm which packages are genuinely load-bearing (actually depended upon by other parts of the
codebase), not just present. This was done **before** reading `tasks/R07/task_A.md`–`task_D.md`
(see `PLAUSIBILITY_CHECK.md` for the post-hoc self-check, performed only after this scoping and
authoring work was complete).

### Operationalizing "depth ≤ 3" for a Kotlin/Gradle project

`TREATMENT_DESIGN.md` §4's "depth ≤ 3 from the relevant source root" was written with a flat
Python package layout in mind (as in R01/freqtrade). Kotlin/Gradle projects nest more deeply by
convention (reverse-domain package prefixes, then a `<feature>/model` / `<feature>/repository` /
`<feature>/interactor` split within each domain aggregate), and Goga's own `CODEMANIFEST`
`location:` rule additionally requires every documented file to sit **flat, directly** inside the
cell's own directory (no subdirectory traversal) — the same rule that made R01 exclude nested
`optimize/`/`data/` subpackages. Applying that rule literally to Mihon means a cell boundary must
be drawn at the actual flat leaf directory containing real `.kt` files, not at the higher
"feature" grouping directory that only contains further subdirectories. Concretely:
`domain/src/main/java/tachiyomi/domain/manga/` itself contains no `.kt` files — `Manga.kt` lives
in `domain/.../manga/model/`, the repository interface in `domain/.../manga/repository/`, and
the interactors in `domain/.../manga/interactor/`. So "the top-level architectural spine at depth
≤ 3" is operationalized here as: the Gradle module root for module-sized concerns, and the
nearest flat leaf package for finer components — chosen by the same genuinely-load-bearing
(import fan-in) test used for R01 — landing one package segment deeper than a literal depth-3
count from the module root would suggest. This is a scoping-methodology adaptation, not a
task-driven one; it is recorded here for transparency alongside the cell list.

## Cells covered (12) and why

| Cell | Evidence it's load-bearing |
|---|---|
| `domain/.../track/model` (`Track`) | Imported by `domain/track/repository`, `data/track` (impl), `app/.../data/track` (the `Tracker` extension point), and by track-related interactors/presentation not documented here. The shared shape every part of the tracking subsystem agrees on. |
| `domain/.../chapter/model` (`Chapter`, `ChapterUpdate`, `NoChaptersException`) | Imported by `domain/chapter/repository` and by a `data/chapter` implementation, chapter-sorting/recognition services, and reader/library presentation code not documented here. |
| `source-api/.../source/model` (`SManga`, `SChapter`, `MangasPage`, `Page`, `FilterList`, `Filter`, `UpdateStrategy`, `SMangaUpdate`) | The data model half of the source contract; imported by `source-api/source`, by `domain/manga/model` (`Manga` is populated from `SManga`), and by every concrete source implementation (in-repo `LocalSource`, or an external extension). |
| `domain/.../manga/model` (`Manga`, `MangaCover`, `MangaUpdate`, `MangaWithChapterCount`, `TriState`) | `Manga` is the single most widely-imported domain type in the codebase — every repository, interactor, and presentation layer above the source boundary depends on it. |
| `domain/.../chapter/repository` (`ChapterRepository`) | The storage port every chapter-reading interactor programs against; implemented by a `data/chapter` cell not documented here (out of scope by the 6-12 cell budget, but structurally identical to the documented `data/manga`/`data/track`). |
| `domain/.../track/repository` (`TrackRepository`) | Storage port for track records; implemented by `data/track`; consumed by track interactors and by the `Tracker`/`BaseTracker` extension point when it persists a remote sync result locally. |
| `domain/.../manga/repository` (`MangaRepository`) | The single most-depended-upon repository interface in the codebase (19+ importing files at recon time); implemented by `data/manga`. |
| `source-api/.../source` (`Source`, `CatalogueSource`, `ConfigurableSource`, `UnmeteredSource`, `SourceFactory`) | The extension contract every manga/comic source implements. 36+ files import `Source`. Per prior reconnaissance (confirmed here), concrete catalogue sources are external extension APKs, not in-repo code — but the contract itself is genuinely in-repo, load-bearing, and is what `SourceManager`, `LocalSource`, and every consumer of a source programs against. |
| `domain/.../source/service` (`SourceManager`) | The runtime registry turning a numeric source id into a live `Source` instance; the join point between the source-extension mechanism and everything else that displays or fetches manga. |
| `data/.../manga` (`MangaRepositoryImpl`, `MangaMapper`) | The concrete, SqlDelight-backed implementation of `MangaRepository` — the data layer's half of the manga aggregate's storage. |
| `data/.../track` (`TrackRepositoryImpl`, `TrackMapper`) | The concrete, SqlDelight-backed implementation of `TrackRepository`. |
| `app/.../data/track` (`Tracker`, `BaseTracker`, `DeletableTracker`, `EnhancedTracker`, `TrackerManager`) | Confirmed by prior reconnaissance and re-verified here: this is a genuine **in-repo** extension point (unlike `Source`, which is externally implemented) — eleven concrete tracking-service integrations (AniList, MyAnimeList, Kitsu, Shikimori, Bangumi, Komga, MangaUpdates, Kavita, Suwayomi, Hikka, MangaBaka) already live in this exact package, each extending `BaseTracker` and registering in `TrackerManager`'s fixed `trackers` list. 25+ files import `Tracker`; 18+ import `TrackerManager`. |

## Deliberately excluded / deprioritized

- **`source-local` (`LocalSource`)** — a genuine, real concrete implementation of the `Source`
  contract, but it is one specific implementation among many (the others being external extension
  APKs), not a structural boundary the rest of the spine depends on; the contract cell
  (`source-api/source`) already documents what `LocalSource` implements. Left undocumented to
  keep the forest within a comprehensive-but-bounded cell count.
- **`domain/.../manga/interactor`, `domain/.../chapter/interactor`, `domain/.../track/interactor`**
  (11, 6, and 4 files respectively) — genuine use-case orchestration code, but each interactor is
  a thin, single-method wrapper directly composing the already-documented model + repository
  types; documenting them would multiply cell count without adding new architectural boundaries
  beyond what the model/repository cells already establish.
- **`domain/.../source/model` (`Source`, `Pin`, `StubSource`, `SourceWithCount`) and
  `domain/.../source/repository`/`interactor`** — real, but `SourceManager` (documented) is the
  cell most directly analogous to R01's most-central "manager" types, and `StubSource` is
  referenced generically in `SourceManager`'s own annotations without being separately
  contracted, matching how R01 treated genuinely out-of-scope sibling types.
- **`data/.../chapter`, `data/.../category`, `data/.../history`, `data/.../updates`,
  `data/.../release`, `data/.../source`** — structurally identical in shape to the documented
  `data/manga`/`data/track` (SqlDelight-backed repository implementation + mapper); left
  undocumented per the cell-count budget rather than for any architectural reason, and disclosed
  here rather than silently omitted.
- **`core/common`, `core/archive`, `core/metro`, `core-metadata`, `i18n`, `presentation-core`,
  `presentation-widget`, `telemetry`, `baseline-profile`** — cross-cutting infrastructure/utility
  modules (networking helpers, DI wiring via Metro, archive/zip/epub I/O, string resources, shared
  Compose UI primitives, analytics, benchmark harness) with no independent multi-type domain
  contract of their own comparable to the aggregates above; analogous to R01's exclusion of
  `enums`/`constants`/`exceptions`/`misc`/`util`-style thin utility packages.
- **Presentation layer (`app/.../ui/*`, `app/.../presentation/*`)** — real and large, but it is a
  *consumer* of the domain/data/source spine documented here, not a structural boundary other
  layers depend on; excluded on the same "consumer, not spine" basis R01 used for `freqai`.

This scoping was performed and frozen before `tasks/R07/task_A.md`–`task_D.md` were read (see
`PLAUSIBILITY_CHECK.md`).
