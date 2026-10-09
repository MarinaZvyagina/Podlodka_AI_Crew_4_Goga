# RESTRUCTURE_REPORT.md — R07 (mihon/mihon) Condition C

Fourth repository restructured for Condition C, and the smoothest of the four so far. Kotlin
(Gradle multi-module Android app), 77.4k LOC, 12 originally documented cells (Phase 8).

## Scope: near-complete before Condition C work even began

Unlike R01 (13 new nested cells surfaced) and R06 (50 hideable exports found), R07's Phase 8
documentation was already close to fully facade-complete. Auditing all 12 cells' real top-level
declarations (~39-43 across `data/track`, `data/manga`, `app/data/track`, `domain/manga/model`,
`domain/manga/repository`, `source-api/source`, `source-api/source/model`, `domain/track/model`,
`domain/track/repository`, `domain/source/service`, `domain/chapter/model`,
`domain/chapter/repository`) against each CODEMANIFEST found:

- **0 hideable** — no internal-only symbols were mistakenly declared as public surface.
- **1 genuinely missing export**: `sourcePreferences()` (plus its `key: String` overload) and
  `preferenceKey()`, extension functions in `source-api/.../source/ConfigurableSource.kt` — added
  to the `source-api/.../source` CODEMANIFEST.
- **7 of 8 initially-flagged "undeclared" symbols were false positives**: a simple audit script
  looking only for plain `"Name(...)"` manifest keys misses Goga's `Base::Derived` type-mutation
  syntax (e.g. `"Source::CatalogueSource()"`), under which most of these symbols were already
  correctly declared. Each flagged symbol was manually re-checked against the raw manifest text
  before being treated as genuinely missing, avoiding the false-positive pattern seen repeatedly
  in R06 and R01.

## Zero circular dependencies

Full direct-import analysis across all 12 cells found the graph already acyclic — see
`CYCLE_FIXES.md`. This is the first repository in Condition C with no cycle work required at all
(R06 had a legitimate shared-constant edge worth documenting; R03 had 1 real cycle; R01 had 5
apparent cycles, 2 requiring real fixes).

## Process

- One minor self-correcting editing mistake: an Edit call's imprecise text match briefly
  corrupted an adjacent, unrelated manifest key (`"Source::CatalogueSource()":` →
  `"CatalogueSource::ConfigurableSource()":`); caught immediately on the next file read and fixed
  with a follow-up targeted Edit.
- Final full-repo `goga lint`: **0 errors across 12 cells** (after removing a small number of
  invalid backtick cross-references — sibling method names and prose words are not valid
  backtick targets — the same recurring lint-error class seen in every prior repo).

## Hard gate: build + test

- `repos.yaml`'s documented build command, `./gradlew assembleStandardDebug`, does not exist in
  this commit's Gradle task graph ("Task 'assembleStandardDebug' not found") — a pre-existing
  metadata/build-config mismatch unrelated to the restructuring (no "standard" product flavor is
  configured at this commit). Located the real equivalent via `./gradlew tasks --all`:
  **`app:assembleDebug`**, which ran successfully: `BUILD SUCCESSFUL in 1m 25s` (268 actionable
  tasks: 125 executed, 139 from cache, 4 up-to-date).
- `./gradlew test`: `BUILD SUCCESSFUL in 21s`, all tests passing across the touched modules
  (`domain`, `data`, `source-api`, `app`), including the full `MigratorTest` suite.

## Control re-certification

All 8 of Phase 5's control diffs (`tasks/R07/controls/*.diff`) applied cleanly against the
restructured commit with no adaptation needed — no hardcoded base-commit SHAs in any R07
validator, and no renamed identifiers since 0 exports were hidden. Gradle/Android toolchain paths
needed for the throwaway recertification worktrees (separate from the ones already pinned for the
main build) were `JAVA_HOME=/opt/homebrew/opt/openjdk@21/...`,
`ANDROID_SDK_ROOT=/opt/homebrew/share/android-commandlinetools` — neither the default
`java_home -v 21` lookup nor `~/Library/Android/sdk` resolved on this machine; this is purely a
local-environment quirk, not a restructuring artifact. **All 4 tasks discriminate correctly**:

| Task | Positive: functional | Positive: all AC | Negative: functional | Negative: ≥1 AC fails |
|---|---|---|---|---|
| A | PASS | PASS (4/4) | FAIL | Yes (1/4 FAIL) |
| B | PASS | PASS (5/5) | FAIL | Yes (3/5 FAIL) |
| C | PASS | PASS (4/4) | FAIL | Yes (3/4 FAIL) |
| D | PASS | PASS (5/5) | FAIL | Yes (3/5 FAIL) |

## Artifacts

- Restructured commit: `fe4f87f4e5445cfbcf0294eac7aae797a74b3142`, tagged `condition-c-r07-v1`
  in the shared base clone (`benchmark-scratch/repos/R07`).
- `architecture_v2/R07/CYCLE_FIXES.md` — confirms 0 real cycles, brief by design.
- No `controls_adapted/`/`validators_adapted/` directories needed — all 8 original control diffs
  and all validator scripts worked unmodified.
- The 12 cells' `CODEMANIFEST` files live directly in the restructured commit.
