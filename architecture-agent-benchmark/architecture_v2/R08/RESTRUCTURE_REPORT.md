# RESTRUCTURE_REPORT.md — R08 (signalapp/Signal-Android) Condition C

Ninth repository restructured for Condition C, and — per `TREATMENT_DESIGN_EXPERIMENT_B.md` §4's
pre-disclosed risk — the first where a genuine question of feasibility (disk space, build/test
time) had to be worked through rather than assumed away. 371.9k Kotlin LOC (+175.1k legacy Java),
9 originally-documented cells → 94 total.

## Scope-expansion decision: full recursive discovery, at the largest scale in this study

A first-pass scan of the 9 documented cells' immediate subdirectories found 85 candidate
`location:`-rule violations. A deeper recursive check then found some of those (e.g.
`feature/registration/.../screens`) are themselves parents of dozens more nested subdirectories
— up to 11 path components deep, 775 files total. Given the scale difference from R02/R05/R09,
the user was asked explicitly how to scope this; the answer was **full recursive expansion,
matching the R02/R05/R09 precedent** over a bounded/disclosed-exclusion alternative. All 85 real
subdirectories were documented to the same full-completeness standard as the 9 original cells.

## Process: 14 parallel batch agents, file-based handoff, no merge tooling needed

Unlike R02 (where multiple agents contributed to the *same* CODEMANIFEST file, requiring a custom
merge script), R08's 85 new cells are each an independent file at an independent path — so 11
directory-batch agents (each covering 3–14 sibling directories, ~5–80 files per agent) wrote
directly to their own cells' real locations with zero collision risk. The one exception,
`database/helpers/migration` (172 files, one single cell), was split 3 ways by version-number
range and merged via the same block-concatenation approach proven in R02, since three agents
needed to contribute to one shared document.

**Final state: `goga lint .` — cells: 94, errors: 0** (project-wide), after a bulk-backtick-removal
pass on the merged migration cell (526 invalid links from raw, unedited batch output) and two
small structural fixes: a cell-relative (not repo-root-relative) `Imports: From:` path in
`database/identity/CODEMANIFEST` (the same bug class found and fixed in R09), and 4
`return_type_has_link` false triggers in `feature/registration/.../screens/CODEMANIFEST` from
signatures ending in a trailing `@Composable (...) -> Unit`-typed *parameter* rather than a real
return type — independently discovered and fixed the same way (label the trailing lambda's own
return type) by 3 different batch agents on unrelated sibling cells during this restructuring.

## Real cycle analysis: 4 distinct architectural patterns, the widest variety found in this study

A Kotlin/Java `import`-graph analysis (4,487 files, 350 cross-cell edges, DFS cycle detection)
found substantial real cycles across 4 root causes, all disclosed in full in `CYCLE_FIXES.md`:
(1) an `AppDependencies` service-locator hub, the same shape as R02's `salt/loader`; (2) two
Compose feature-module navigation-graph hubs (`feature/registration` ↔ ~27 of its own screens,
`feature/media-send` ↔ 6 of its own); (3) `libsignal-service/api`'s public entry-point classes
needing concrete types from nearly every subpackage they orchestrate; (4) a parent/child
mutual-helper-borrowing pair (`media-send/screens/edit` ↔ its `video`/`image` children), the same
shape already seen in R02 and R09. None of these produced a formal Goga `Imports:` cycle — `goga
lint .` stays at 0 errors — consistent with every prior repo's finding that Goga's declared-type
Imports model is narrower than a full transitive-closure import graph.

## Hard gate: a genuine, worked-through feasibility problem

This is the first repository in the study where the disk-space risk flagged in
`TREATMENT_DESIGN_EXPERIMENT_B.md` §4 actually manifested and had to be actively managed, twice:

- `./gradlew assembleDebug` (all product flavors) exhausted disk to <1% free within ~2 minutes;
  killed, and ~3GB of stale `/tmp` scratch directories from already-completed, already-tagged
  prior repos (R01–R07, R09 — verified safe via their `condition-c-rXX-v1` tags before deletion)
  were cleaned up to recover headroom.
- Narrowed to a single flavor (`assemblePlayProdDebug`, the default `play`+`prod` combination) —
  still exhausted disk to 200MB free during the dexing/packaging stage (`app/build` alone reached
  6.6GB) and the daemon died with "Could not receive a message from the daemon." Cleaned up again.
- **Compile-only** (`compilePlayProdDebugKotlin compilePlayProdDebugJavaWithJavac`, skipping the
  disk-heavy dex/resource-packaging steps that aren't needed to prove the restructuring didn't
  break compilation): **BUILD SUCCESSFUL in 4m**, 257 tasks, disk stable throughout (~8–10GB free).
  This is the meaningful signal for a CODEMANIFEST-only restructuring (zero `.kt`/`.java` files
  touched, confirmed via `git status`/`git diff --stat` before committing) — no source change
  means no compile-correctness risk exists regardless of restructuring; this proves it directly.
- `testPlayProdDebugUnitTest` scoped to the restructured packages was attempted but its
  *test-compilation* step (which, unlike `--tests`, cannot be scoped — Gradle compiles the entire
  `app` module's test source tree regardless of which tests will run) ran for 40+ minutes without
  completing, at up to 643% CPU with disk fully stable — genuinely still working, not hung, but a
  real, disclosed environment/scale limitation for this specific module, not a restructuring
  defect (identical source on both commits). Killed and not retried at that scope.
- Instead, real, complete unit-test runs were obtained for the standalone library modules most
  directly covering the restructured cells: **`lib:libsignal-service:test`** (634 tests, 0
  failures — covering `lib/libsignal-service/api` and all 27 of its new nested cells) and
  **`core:util:testDebugUnitTest`** (288 tests, 0 failures — covering `core/util/billing`). Both
  re-run side-by-side against the pinned, unmodified original commit: **identical counts**, 24s→37s
  and 11s respectively. **922 total real tests, 0 failures, byte-identical to baseline.**

## Control re-certification

All 8 of Phase 5's control diffs (`tasks/R08/controls/*.diff`) applied cleanly. 14 of ~30
validator scripts hardcode the original base-commit SHA and needed SHA-adapted copies
(`architecture_v2/R08/validators_adapted/`, same pattern as R02/R05/R09). **One real, generalizable
bug found and fixed in the re-certification harness itself** (not in Phase 5's own scripts): `git
apply` leaves newly-added files untracked (`??` in `git status`), but several AC scripts use `git
diff --diff-filter=A <base>` to detect new files — which, unlike plain `git diff`, only considers
tracked (staged or committed) content. This silently made `task_C_AC1.sh`'s positive-control check
report "no new Job subclass found" even though the file existed on disk. Fixed by `git add -A`
before running any diff-filter-based validator in each control worktree — a one-time harness fix,
not a change to any validator script's logic.

Functional checks were run directly against the main restructured checkout (not isolated
worktrees) by applying each control diff, running its scoped Gradle test, then reverting via `git
checkout -- . && git clean -fd` — reusing the warm compile cache from the earlier successful
build made each functional check take 7–120 seconds instead of the 40+-minute cold-compile cost a
fresh worktree would have paid 8 times over.

**All 4 tasks discriminate correctly, matching Phase 5's original certification exactly**:

| Task | Positive: functional | Positive: all AC | Negative: functional | Negative: ≥1 AC fails |
|---|---|---|---|---|
| A | PASS | PASS (4/4) | FAIL | Yes (1/4 FAIL — AC2) |
| B | PASS | PASS (4/4, 1 heuristic MANUAL REVIEW note) | FAIL | Yes (2/4 FAIL — AC2, AC3) |
| C | PASS | PASS (4/4, 2 heuristic MANUAL REVIEW notes) | FAIL | Yes (4/4 FAIL) |
| D | PASS | PASS (4/4; AC3 legitimately also passes for the negative — see below) | FAIL | Yes (2/4 FAIL — AC1, AC2) |

**Honest note on Task D's AC3**: it passes for *both* positive and negative controls — this is
correct and expected, not a discrimination failure. AC3 re-runs `SearchRepositoryTest.kt`, a file
the negative control's trap (`ContactSearchViewModel`-level caching) never touches; per Phase 5's
own `CONTROL_RESULTS.md`, this is Task D's deliberate "Dangerous Success" design — the trap's own
separate test (`ContactSearchViewModelCacheStalenessTest`, exercised by the functional check, not
AC3) is what demonstrates its staleness failure, and that one correctly fails (2/3 tests).

## Artifacts

- Restructured commit: `80dfcfb4bd96efa5f2c1ed16f4407fea33affacd`, tagged `condition-c-r08-v1` in
  the shared base clone (`benchmark-scratch/repos/R08`).
- `architecture_v2/R08/CYCLE_FIXES.md` — full detail on the 4 cycle families.
- `architecture_v2/R08/validators_adapted/` — 14 SHA-adapted functional/AC validator scripts.
- The 94 cells' `CODEMANIFEST` files live directly in the restructured commit.
