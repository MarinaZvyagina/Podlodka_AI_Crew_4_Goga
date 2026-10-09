# STATUS.md

Last updated: 2026-10-08 (Condition D — interactive Goga pipeline — complete, all 28 tasks across R01-R07)

## Condition D: Interactive Goga Development Pipeline (post-study addendum, complete)

Per explicit user request (2026-09-22): re-run tasks through Goga's real `development.yml`
pipeline (9 stages, interactive WAIT gates), one task at a time with a check-in between each, to
see whether a human-in-the-loop workflow catches defects the non-interactive primary study
couldn't diagnose. **Not pooled** with any other condition — n=1 per task (n=28 total across 7
repositories), reported as a qualitative case series. **All 28 tasks complete**: R01 (freqtrade,
4 tasks), R02 (salt, 4 tasks), R03 (nestjs/nest, 4 tasks), R04 (excalidraw, 4 tasks), R05
(VictoriaMetrics, 4 tasks), R06 (etcd, 4 tasks), R07 (mihon, 4 tasks) — every task ultimately
reached functional PASS + full architecture conformance + `dangerous_success = False`.
R01-D (short-lived price-fetch caching) remains the single most methodologically interesting
result within R01/R02: `code-design` found the requested caching already existed but misconfigured
(300s TTL); fixing it and routing the real call sites through it caused 14 real
trailing-stop-loss test regressions, reverted after proving those mechanisms need always-fresh
prices; then the study's own functional validator revealed both rounds had targeted the wrong
method entirely (`Exchange.get_rate` instead of the real `Exchange.fetch_ticker` /
`DataProvider.ticker()` entry point the task's own scoring fixture drives) — three different real
defects, each caught by a different verification mechanism (source reading, test execution,
external black-box oracle) that would have missed the other two.

R03/R04 add a genuinely new nuance rather than just more data points: R03-B (a Socket.IO
write/close race condition) and R03-D (a NestJS global-enhancer DI-scope resolution bug) are both
runtime-only defects no design-level trace could have found by reading alone — but both were
caught **before** formal acceptance, by actually executing the code as an ordinary part of
finishing the task (R03-B via the study's own functional fixture run in-session; R03-D via the TDD
`implement` stage's own integration test). This refines, rather than contradicts, the original
finding: it isn't that internal review can never catch runtime-only defects — it's that
**design-level tracing** specifically (brainstorm/code-design/design-review reading source without
executing it) never does; *running* the code, whether via the task's own TDD tests, a full
regression suite, or the external black-box oracle, sometimes does, and whether that happens
before or after formal acceptance depends on whether the specific scenario exercised happens to
hit the affected code path — not something following the pipeline correctly guarantees on its own.
R04's four tasks needed no correction beyond design-level tracing, the TypeScript compiler, or the
pipeline's own accept-stage review — the first repository in this condition where that was true
for every task.

Condition D was extended to R05 (VictoriaMetrics) per further explicit user request
(2026-09-28), using the same 9-cell static CODEMANIFEST overlay treatment as R01-R04 (**not**
R05's separate, independent 55-cell Condition C restructuring — an earlier draft of this note
conflated the two; corrected after direct verification that each R05-T? worktree has exactly the
original 9 `CODEMANIFEST` files). R05-A was a second zero-correction run; R05-B and R05-C each found
real defects purely via `code-design`/`design-review`'s own source tracing before any code was
written (a wrong job-identity discriminant and a wasteful check-ordering choice in B; an
unprecedented hardcoded default and dangling unused fields in C); R05-D — drawn from the
`architecture_trap` category — is the first task in this condition where `brainstorm` itself
avoided a named trap (bolting unbounded raw state onto a god-struct) before any design was
drafted, purely by finding and modeling a real in-codebase precedent (`metricnamestats`), then had
every one of its remaining five pipeline stages each independently catch one further real,
disclosed issue (a naming collision, a stale-variable correctness finding, a self-caught
negative-limit panic, a missing-test plan/implementation gap, and a doc-accuracy fix). R05-D also
carries a disclosed methodological wrinkle unique to this task: the orchestrating session
inadvertently read the task's own hidden answer key before starting, so all actual design/
implementation work was delegated to a fresh, uncontaminated subagent, with gate-by-gate human
decisions relayed in both directions — preserving this condition's human-in-the-loop structure
without the answer key leaking into the work. Across all four R05 tasks, every real correction was
caught somewhere inside the pipeline itself, with zero reliance on an external black-box oracle or
a post-acceptance catch — the cleanest repository-wide result in this condition so far. Full
detail, including per-task narratives and an updated cross-task synthesis table covering all 20
tasks: `results/CONDITION_D_INTERACTIVE_PIPELINE.md`.

Condition D was extended to R06 (etcd) and R07 (mihon) per further explicit user requests
(2026-10-08), with one disclosed protocol difference from R01-R05: direct verification found
neither repository's shared base commit had a pre-built CODEMANIFEST overlay at all (unlike
R01-R05) — each of the 8 tasks built its own forest live, during its own
`brainstorm`→`apply-architecture` stages. For R06 this converged independently on the same real
10-cell spine across Tasks A/B/C (11 once D added its own leaf cell); for R07, mihon's larger,
more multi-faceted real architecture meant no such convergence happened, and forest size varied
genuinely by task (12-17 cells). R06 reproduced R04/R05's cleanest pattern: all four tasks'
real corrections were caught somewhere inside the pipeline itself, including this condition's
most severe self-caught defect — R06-D's `coding-plan` stage catching its own cache-before-
authorization-check ordering bug (a real cross-caller data-exposure risk), later proven by a
dedicated test added at `accept-result` specifically because no prior test had ever exercised the
fix with real authorization enabled. R06-C is a sharper version of the "design-level tracing
catches self-consistency defects" pattern: `architecture-review` overturned a cell's own
documented self-suggestion (`apply`'s CODEMANIFEST plausibly, but wrongly, suggested itself as the
audit-logging home) once tracing proved reads never reach that cell at all. R07-A/B/C reproduced
the by-now-familiar pattern (two critical `interceptor.newAuth()` catches by `design-review` in
Task C, before any code existed; a JUnit-silent-skip false-negative and a pre-existing
test-infrastructure gap both found only by actually running the code, in Tasks A and B
respectively). R07-D is this condition's first task where the orchestrating human process itself,
not the Goga pipeline, introduced a defect — a delegated subagent fabricated an "architecture
hint" during Intake, caught only by a human directly re-reading the real ticket file and
cross-checking a tool-call transcript to rule out contamination — disclosed as a hallucination
incident, distinct from R04-A's inadvertent-fixture-read incident but illustrating the same
underlying point: the human-in-the-loop guarantee is only as strong as the verification the human
actually performs. Once corrected, R07-D's own pipeline ran at the high end of this condition's
range (an independently re-derived `FilterList.equals`-always-`false` cache-key trap; a
`design-review` catch of a contract bug the design's own test traces would have introduced; a
`plan-review` catch of real plan-vs-implementation scope drift). Full detail, including per-task
narratives and an updated cross-task synthesis table covering all 28 tasks:
`results/CONDITION_D_INTERACTIVE_PIPELINE.md`.

## Extended study: Experiment B (post-primary-study addition)

Per explicit user request (2026-09-13), two additional conditions are being run beyond the
primary 800-run study (see `TREATMENT_DESIGN_EXPERIMENT_B.md` for full design). These are
**separate, more confounded experiments** — never pooled with the primary Dangerous-Success-Rate
result.

- **Condition B′ (Goga Full Workflow, optional use)**: same repos/tasks/model as the primary
  study, plus live `goga` CLI + connected skills available, with a neutral "available if useful"
  prompt sentence. Stopped (not discarded) at **91/400 VALID** once it became clear organic
  engagement was very low (only 1/79 runs checked at the time showed clear tool-use signal) — a
  real, valid finding about voluntary-adoption rate, kept as-is in `results/runs_experiment_b.csv`.
- **Condition B″ (Goga Forced Workflow, explicit instruction)**: added per explicit user request
  (2026-09-14) as a genuinely separate condition (not a mid-batch mutation of B′, which would
  have mixed two treatments under one label). Same setup as B′, but the prompt explicitly
  instructs the agent to use `goga schema`/`goga lint`/relevant skills as part of its process, not
  merely as an optional aid. 400-run batch (`experiment_plan_b2.csv`, seed=44) in progress via
  `scripts/run_batch_b2.sh`.
- **Condition C (Goga-Native Architecture)**: real restructuring of a repository's actual source
  into Goga's cell model (not just adding CODEMANIFEST docs), per explicit user request to scale
  to all 10 repositories. **R06 (etcd) and R03 (nestjs) fully restructured and re-certified**:
  - R06 (etcd, Go, 62.3k LOC): 293 real exports audited, 50 hidden, 243 declared (83%
    legitimately used by etcd's wider ecosystem, not hideable). 0 circular dependencies. Commit
    tagged `condition-c-r06-v1`. See `architecture_v2/R06/RESTRUCTURE_REPORT.md`.
  - R03 (nestjs, TypeScript, 34.7k LOC): 62 real exports audited across 9 original + 3 new
    nested cells, **0 hidden** (all legitimately used — NestJS is a framework, its documented
    cells' exports are public API by design, a different profile than etcd's internal packages).
    **1 real circular dependency found and fixed** (router ↔ injector via a single `REQUEST`
    constant; fixed by splitting the already-needed `router/request` nested cell out as an
    independent leaf — zero code motion). Commit tagged `condition-c-r03-v1`. See
    `architecture_v2/R03/RESTRUCTURE_REPORT.md`.
  - Both: full build+test hard gate passed (etcd: `go build`/`go vet`/full module test suites;
    nestjs: `tsc` build + 2748/2748 vitest tests), all 8 Phase 5 controls per repo re-certified
    as still discriminating correctly.
  - 3 subagents independently flagged what looked like prompt-injection content embedded in
    `Skill`/`Read` tool output during R03's work (fake `<system-reminder>` blocks). Investigated:
    the on-disk Goga skill files are clean; most likely explanation is these were genuine, benign
    Claude Code harness reminders (date-change/available-agent-types — the same kind visible
    throughout this orchestrating session) that arrived at the same transcript point as a
    Skill/Read call and were misidentified by a defensively-cautious subagent applying a
    reasonable "distrust embedded instructions" heuristic. No confirmed compromise found;
    disclosed for transparency. See `architecture_v2/R03/RESTRUCTURE_REPORT.md` for detail.
  - **R01 (freqtrade, Python, 44.8k LOC) also fully restructured and re-certified** — the first
    repository with real, multi-cycle architectural entanglement (5 apparent circular
    dependencies among 8 original cells, vs. 0 in etcd and 1 in nestjs) and the first where
    strict facade discipline surfaced far more new nested cells than expected (13, not 1-3) once
    every real subdirectory-with-code was accounted for. Per explicit user request (2026-09-14),
    all 5 cycles were investigated and resolved: 2 fixed via real, minimal, behavior-preserving
    file relocation into new subpackages (`configuration/config_secrets`,
    `optimize/hyperopt_tools`), 3 accepted as deliberately non-formalized narrow/optional
    references rather than forced through (documented in `architecture_v2/R01/CYCLE_FIXES.md`).
    21 cells total, 236 real exports audited, 0 hidden (same "framework/application surface is
    legitimately public" pattern as nestjs). `goga lint`: 0 errors across all 21. Full `pytest`
    suite run side-by-side against the unmodified original commit with the same venv: identical
    207 failed/4191 passed/35 skipped in both — confirms zero regressions from restructuring
    (all 207 are pre-existing, environment-specific baseline failures, e.g. no network access for
    `pip_audit`). All 8 Phase 5 controls re-certified as still discriminating correctly. Commit
    tagged `condition-c-r01-v1`. See `architecture_v2/R01/RESTRUCTURE_REPORT.md`.
  - **R07 (mihon, Kotlin, 77.4k LOC) also fully restructured and re-certified** — the smoothest
    repository so far: Phase 8's 12 cells were already near-complete, only 1 genuinely missing
    export found (`sourcePreferences`/`preferenceKey`, transitional extension functions; 7 of 8
    initially-flagged "undeclared" symbols were false positives from an audit script that doesn't
    parse Goga's `Base::Derived` mutation syntax), 0 hidden, and **0 circular dependencies** — the
    first Condition C repo needing no cycle work at all (Phase 8's domain/data Clean Architecture
    layering was already acyclic). `goga lint`: 0 errors across 12 cells. Hard gate: `repos.yaml`'s
    documented build command (`assembleStandardDebug`) doesn't exist at this commit (pre-existing
    metadata drift, not a restructuring artifact) — used the real equivalent `app:assembleDebug`
    instead (`BUILD SUCCESSFUL in 1m 25s`), then `./gradlew test` (`BUILD SUCCESSFUL in 21s`). All
    8 Phase 5 controls re-certified as still discriminating correctly. Commit tagged
    `condition-c-r07-v1`. See `architecture_v2/R07/RESTRUCTURE_REPORT.md`.
  - **R04 (excalidraw, TypeScript, 106.5k LOC) also fully restructured and re-certified** — by
    far the largest single-cell facade job so far: `element/src` alone has ~500 real exports
    (larger than R01's *entire* 21-cell restructuring), requiring 4 parallel agent passes to
    complete. 1 new nested cell (`element/src/arrows`, per the `location:` rule). **0 hidden**
    across all 6 cells (same "foundational library, broad legitimate public surface" pattern as
    R03/R01). **1 real, disclosed bidirectional dependency** (`common/src` ↔ `math/src`, both
    directions genuine — documented in prose in both cells rather than forced into a formal,
    lint-rejected two-cell cycle; see `architecture_v2/R04/CYCLE_FIXES.md`). `goga lint`: 0
    errors across 6 cells (247 lint errors resolved during authoring, mostly the same recurring
    invalid-backtick class as every prior repo). Full `vitest` suite: 122/122 test files,
    1860/1908 tests passed — identical to a from-scratch unmodified-commit comparison run,
    confirming zero regressions. All 8 Phase 5 controls re-certified as still discriminating
    correctly, matching the original certification exactly. Commit tagged `condition-c-r04-v1`.
    **Two real incidents occurred and were fully recovered from, both disclosed in
    `architecture_v2/R04/RESTRUCTURE_REPORT.md`**: (1) an operator flat-directory-backup mistake
    silently overwrote 5 of 6 identically-named CODEMANIFEST files, caught immediately and
    recovered — 2 files recoverable from other on-disk copies, 3 redone from scratch by fresh
    agents; (2) a stray `dist/` build-output directory from an intermediate build check caused a
    spurious React-context-identity test failure (10 tests) misleadingly correlated with (but not
    caused by) the restructuring — diagnosed via unmodified-commit comparison and a
    docs-removed bisection, then fixed by cleaning the build artifacts before testing.
  - **R05 (VictoriaMetrics, Go, 120.1k LOC) also fully restructured and re-certified** — the
    largest by cell count so far: 55 cells (9 originally documented + **46 new**). Phase 8's own
    `SCOPE.md` had disclosed leaving ~47 real subdirectories under `app/vminsert`/`app/vmagent`/
    `app/vmselect` undocumented for cost reasons (a real `location:`-rule tension); presented
    with this tradeoff, the user explicitly chose to **expand scope and fully formalize it**
    rather than preserve the disclosed exclusion (the opposite choice from R04's analogous
    `packages/excalidraw` cut) — making R05 the first Condition C repo whose restructured scope
    is larger than Condition B's static docs, not just more correct within the same scope. **0
    hidden** across all 55 cells. **0 circular dependencies**, verified for the first time in
    this study via real `go list`-based import-graph analysis + DFS cycle detection rather than
    grep (see `architecture_v2/R05/CYCLE_FIXES.md`). Surfaced a **new class of `goga lint` tool
    limitation** (`import_has_not_duplicate` compares pre-alias names across cross-cell Imports
    rather than resolved `AS` aliases — independently discovered by two separate agents,
    empirically confirmed, worked around by disclosing the affected dependencies in prose).
    `go build ./...`: clean. `go test ./...`: 129/129 real test packages passed, identical to an
    unmodified-commit comparison run (the only failures, 97 sub-tests in one `apptest` e2e
    package, need pre-built race binaries via a separate `make` target — confirmed identical on
    the original commit too). All 8 Phase 5 controls re-certified as discriminating correctly,
    including catching a genuine pre-existing staleness in Phase 5's own `CONTROL_RESULTS.md`
    (Task A's negative control was documented as functional-passing but actually fails
    identically on both the original and restructured commit — not a regression). Commit tagged
    `condition-c-r05-v1`. See `architecture_v2/R05/RESTRUCTURE_REPORT.md`.
  - **R09 (firefox-ios, Swift, 245.2k LOC) also fully restructured and re-certified** — the first
    Swift repo, and the first with a real, disclosed two-tier facade rule: standard `public`-only
    for `BrowserKit` SwiftPM library cells, but `internal`-is-the-facade for `firefox-ios/Client`'s
    two cells (a single app target with no external consumers, per the original `SCOPE.md`'s own
    disclosure). 9 original cells → **33 total** (24 new, in continuity with R05's
    "expand fully" precedent — but here mostly `location:`-rule-driven since most of R09's other
    disclosed exclusions are sibling targets, not subdirectories of documented cells). A two-pass
    discovery method (shallow scan → targeted recursive re-scan) found 10 more real subdirectories
    nested one level deeper than the first pass caught. **0 hidden**, 3 real bidirectional
    dependencies resolved by formalizing the structurally-heavier direction (see
    `architecture_v2/R09/CYCLE_FIXES.md`). `goga lint`: 0 errors across 33 cells (after fixing 3
    cell-relative-instead-of-repo-root-relative `From:` paths — a genuine, not false-positive,
    lint catch). Hard gate: plain `swift build`/`swift test` fail identically on both commits
    ("no such module 'UIKit'" — needs an explicit iOS SDK/triple, a pre-existing invocation
    nuance Phase 5's own validators already worked around via `xcodebuild test`); with the correct
    invocation, `swift build` succeeds and `xcodebuild test` passes every test suite in the entire
    BrowserKit package (18+ suites, 0 failures) — not just the 7 documented cells' own targets. A
    real disk-space incident (98% full, caused by accumulated build caches plus 4 stale/hung
    `xcodebuild` processes from before this session) was diagnosed and resolved mid-recertification
    (not a restructuring defect). All 8 Phase 5 controls re-certified as discriminating correctly,
    including reproducing 2 disclosed pre-existing environment limitations (manual-review-only
    functional checks for Tasks B/D, already documented as such in Phase 5's own
    `CONTROL_RESULTS.md`) and one pre-existing documentation staleness (Task C, same category as
    R05's Task A finding — confirmed non-regression via side-by-side original-commit comparison).
    Commit tagged `condition-c-r09-v1`. See `architecture_v2/R09/RESTRUCTURE_REPORT.md`.
  - **R02 (salt, Python, 275.5k LOC) also fully restructured and re-certified** — the largest
    single-repo full-completeness expansion in the study, per explicit user decision: 5 of R02's
    9 original cells (`modules`, `utils`, `states`, `runners`, `grains`) were deliberately written
    in Phase 8 as curated representative samples rather than complete facades, and the user chose
    "expand everything to full completeness" over preserving that philosophy. Verified Salt's real
    facade convention directly from source (`salt/loader/lazy.py`'s `LazyLoader`: every
    non-underscore top-level function/class in a loader-managed file is real dispatched API, no
    separate usage check needed — unlike `utils`, consumed via ordinary static imports). Scaled a
    new methodology to hundreds of files/thousands of declarations: parallel batch agents with
    file-based handoff (avoids blowing up the orchestrating session's context) + a custom
    regex-based merge tool (strict YAML parsing breaks on real Salt signatures exceeding the
    1024-char simple-key spec limit) + a proven 4-pass lint-convergence pipeline (strip Python
    default values → bulk backtick removal → bare-return-type labeling → spot-fix structural
    errors). Result: 266-file `modules` (~3,400 declarations), 172-file `utils` (1,180, + 5 new
    nested `location:`-rule cells per the R05 precedent), 132-file `states` (550), 30-file
    `runners` (176), 12-file `grains` (48) — **9 → 14 cells total**, `goga lint .`: 0 errors
    project-wide. A real Python `ast`-based cross-cell import-graph analysis (662 files, DFS cycle
    detection) found a genuine 11-cell strongly-connected component centered on `salt/loader`'s
    dynamic-plugin-loading-hub role — disclosed in full in `architecture_v2/R02/CYCLE_FIXES.md`
    rather than hidden, reflecting Salt's real dependency-injection-container architecture (`goga
    lint` itself doesn't check for cycles and stays 0-errors; the SCC is in the real source graph,
    not a formal DSL conflict). Whole-project linting also caught 2 real facade gaps (`fopen`/
    `is_windows`, imported by `salt/grains` but never declared in `salt/utils`) invisible to
    single-cell linting — fixed. Hard gate: `pip install -e .` clean; `pytest tests/pytests/unit/`
    hit 2 pre-existing environment issues identical on both commits (a `pytest-system-statistics`/
    pytest-8.4 plugin-registration incompatibility, worked around with `-p no:system-statistics`;
    a missing-optional-dependency collection error in `test_vmware.py`) — full run then matched
    **byte-for-byte identical** across all 159 individual failing/erroring test IDs between the
    restructured and unmodified-original commits (23 failed, 8356 passed, 2720 skipped, 135
    errors on both). All 8 Phase 5 controls re-certified as discriminating correctly, matching
    Phase 5's original certification exactly; 14 of ~22 validator scripts hardcode the original
    base-commit SHA in their own scope-check logic and needed SHA-adapted copies
    (`architecture_v2/R02/validators_adapted/`, same pattern as R05/R06/R09). Commit tagged
    `condition-c-r02-v1`. See `architecture_v2/R02/RESTRUCTURE_REPORT.md`.
  - **R08 (Signal-Android, Kotlin/Java, 371.9k LOC) also fully restructured and re-certified** —
    the largest scope-expansion in the study by cell count (9 → 94, 85 new cells, 775 files, up
    to 11 path components deep) and the first repo where the pre-disclosed infeasibility risk
    genuinely manifested and had to be worked through rather than assumed away. Per explicit user
    decision (full recursive expansion, matching R02/R05/R09 precedent), 14 parallel batch agents
    documented every new cell to full completeness; `goga lint .`: 0 errors across all 94 cells.
    A real Kotlin/Java import-graph analysis (4,487 files) found cycles across 4 distinct
    architectural patterns — an `AppDependencies` service-locator hub (the same shape as R02's
    `salt/loader`), two Compose navigation-graph hubs, and `libsignal-service/api`'s public
    entry-point classes — disclosed in `architecture_v2/R08/CYCLE_FIXES.md`. **Hard gate required
    real problem-solving**: `./gradlew assembleDebug` exhausted disk twice (once to <1%, once to
    200MB free, killing the Gradle daemon); resolved by cleaning ~3GB of stale scratch directories
    from already-tagged prior repos, narrowing to a single product flavor, and finally scoping to
    compile-only (skipping disk-heavy dexing/packaging not needed to prove a documentation-only
    restructuring didn't break compilation) — **BUILD SUCCESSFUL in 4m**, disk stable throughout.
    Full-module test compilation proved impractically slow (40+ min, still genuinely working, not
    hung) and was abandoned in favor of complete, real test runs on the two standalone library
    modules most directly covering the restructured cells: 634 (`lib:libsignal-service`) + 288
    (`core:util`) tests, 0 failures, byte-identical to the unmodified baseline. All 8 Phase 5
    controls re-certified as discriminating correctly, matching Phase 5's original certification
    exactly — including finding and fixing a real bug in the re-certification harness itself
    (`git apply` leaves new files untracked, breaking `git diff --diff-filter=A`-based AC checks
    until `git add -A` is run first — not a validator-script bug, a one-time harness fix). Commit
    tagged `condition-c-r08-v1`. See `architecture_v2/R08/RESTRUCTURE_REPORT.md`.
  - **R10 (Signal-iOS, Swift, 548.0k LOC) also fully restructured and re-certified — the largest
    repo in the study, and the tenth and final one, closing out the Condition C restructuring
    pass.** 10 → 52 cells (42 new, 212 files, discovered via the same recursive scan used for
    every prior repo — a much more modest expansion than R08's, applied directly without
    re-asking). `goga lint .`: 0 errors across 52 cells, after fixing 2 real pre-existing facade
    gaps in the Phase-8-authored `Interactions` cell (`TSMessage`/`TSInteraction` — the two most
    pervasively-referenced types in the whole forest, imported by name elsewhere but never
    declared there) and 1 cross-batch qualified-name mismatch. **A genuine methodological
    difference from every prior repo**: all 52 cells live inside one single Swift compilation
    target (unlike every prior repo's separate packages/modules/targets), so there is no
    `import`-statement graph to analyze — the closest honest proxy (unique-type-name source-text
    references) found 46 of 52 cells mutually reachable, driven by a handful of pervasive
    foundation types (`DBReadTransaction`/`DBWriteTransaction`, `DependenciesBridge`,
    `TSMessage`/`TSInteraction`) rather than pairs of cells importing each other's business logic
    — disclosed in `architecture_v2/R10/CYCLE_FIXES.md`. **Hard gate hit a second real
    feasibility problem**: `pod install` initially succeeded but left a third-party pod's prebuilt
    binary as an unresolved 133-byte Git LFS pointer (`git-lfs` wasn't installed in this
    environment) instead of the real 61MB archive; fixed by installing `git-lfs` and clearing the
    corrupted cache (a first fix attempt also accidentally let CocoaPods drift to a newer,
    incompatible major GRDB.swift version by deleting `Podfile.lock` — caught and corrected by
    restoring the pinned lock file before retrying). `xcodebuild -scheme SignalServiceKit build`:
    **BUILD SUCCEEDED**, disk stable throughout — direct proof the CODEMANIFEST-only restructuring
    (zero source files touched) didn't break compilation. A full test run hit a pre-existing,
    toolchain-version-sensitivity compile diagnostic in the unrelated, untouched `SignalUI` module
    (confirmed byte-identical on a fresh unmodified-commit clone — not a restructuring artifact);
    control re-certification instead used Phase 8's own pre-built, disk-aware 3-tier validator
    fallback (real `xcodebuild` attempt → `swiftc -parse` → static/behavioral check), which had
    already anticipated exactly this environment's constraints. All 8 Phase 5 controls
    re-certified as discriminating correctly, matching Phase 5's own documented calibration
    exactly (Task A's functional check is deliberately strict and discriminates; Tasks B/C/D's
    functional checks deliberately pass both controls by design — a "Dangerous Success" scenario
    where only the architecture checks discriminate, and all of them correctly do). Commit tagged
    `condition-c-r10-v1`. See `architecture_v2/R10/RESTRUCTURE_REPORT.md`.
  - **This closes Condition C's 10-repository restructuring pass** (R06, R03, R01, R07, R04, R05,
    R09, R02, R08, R10) — every repository in the study, including both R08 and R10 which
    `TREATMENT_DESIGN_EXPERIMENT_B.md` §4 flagged as carrying real infeasibility risk, is now
    fully restructured, lint-clean, hard-gated, and control-re-certified. In both flagged cases the
    risk materialized exactly as predicted (disk exhaustion; toolchain/environment friction) and
    was worked through with real, disclosed fixes rather than forced or silently worked around.
  - **A real data-loss incident occurred and was fully recovered, disclosed here rather than
    silently patched over.** R08 and R10's restructuring work was done in an independent `git
    clone` of their base repos (`git clone --local --no-hardlinks`) instead of a `git worktree
    add` — unlike every other repo in this study, which used worktrees and therefore
    automatically shared the base clone's object database. Because a clone's objects are NOT
    shared with its origin, R08/R10's `condition-c-rXX-v1` commits and tags existed only inside
    those two ephemeral `/tmp` clone directories — and were destroyed when those directories were
    deleted during a disk-space cleanup pass later in the same session, before the mistake was
    noticed. Recovery was possible because the 21 batch subagents' full JSONL transcripts (which
    record every `Write`/`Edit` tool call's complete arguments, including recursively-delegated
    sub-agents) survived independently of the deleted working directories: a script replayed each
    transcript's file-writing history in order to reconstruct all 85 (R08) + 42 (R10) new cells'
    real content, the 172-file R08 migration cell was recovered from its still-on-disk raw batch
    outputs (written to a separate, non-`/tmp` job-scratch directory per this session's own
    convention), and every subsequent manual lint-fix documented in each repo's own
    `RESTRUCTURE_REPORT.md`/`CYCLE_FIXES.md` was faithfully reapplied. Both reconstructions were
    independently re-verified from scratch: `goga lint .` → 0 errors on both (94/52 cells), and a
    real `xcodebuild`/`gradlew` compile-only build succeeded on both, confirmed via a fresh
    worktree checkout of the new tags. This time both were committed via `git worktree add` (not
    `git clone`), so their tags are correctly visible from the shared base clones
    (`benchmark-scratch/repos/R08`/`R10`) and cannot be lost the same way again. New commit SHAs:
    R08 `123d437318185c062ebdddb1842f379b29929d51`, R10 `e77aa44837da2d107b42553ab255250a0d71b424`
    (both still tagged `condition-c-rXX-v1`; superseding the original, now-nonexistent SHAs
    mentioned in each repo's `RESTRUCTURE_REPORT.md`, whose content otherwise still applies
    verbatim since this is a faithful reconstruction, not a redo).
  - **Condition C's own experiment (agents solving tasks A–D against the restructured commits)
    is now running**, per `TREATMENT_DESIGN_EXPERIMENT_B.md` §1 step 7: `experiment_plan_c.csv`
    (400 rows, seed 45) generated, `scripts/execute_run_c.py`/`run_batch_c.sh` added (checks out
    each repo's `condition-c-rXX-v1` tag directly as the worktree base — no overlay needed, since
    the treatment IS the base commit; no live Goga tooling exposure, matching primary Condition
    B's treatment intensity, not B'/B'''s tool-access axis; gracefully SKIPs — not ERRORs — any
    row whose repo's tag doesn't exist yet, so the same resumable batch script picked up R08/R10's
    rows automatically once their tags were restored, with no second plan file needed). Running in
    the background, in parallel with the still-in-progress Condition B'' batch, per explicit user
    request (2026-09-16) after confirming via `AskUserQuestion` given the earlier "wait for B''"
    instruction. Results land in `results/runs_experiment_c.csv` / `runs_experiment_c/`, never
    pooled with any other condition's results.
  - **Both C and B'' scaled from single-threaded to 2+2 moderate parallelism** (2026-09-16, per
    explicit user request), reusing the primary study's own proven repo-partitioned-worker
    pattern (`scripts/run_batch_for_repos.sh`, which gave a real ~4-5x throughput increase with
    3 workers on one condition — see the primary-study process notes below). New
    `scripts/run_batch_c_for_repos.sh`/`run_batch_b2_for_repos.sh` mirror it exactly: each worker
    only picks up run_numbers whose repository is in its own disjoint list, so no two workers
    ever `git worktree add` against the same base clone concurrently. Repo split (chosen to put
    the 4 heaviest/toolchain-riskiest repos — R07/R08 Android, R09/R10 Xcode — two per group
    rather than clustered in one): Group A = R01,R04,R05,R08,R09; Group B =
    R02,R03,R06,R07,R10. The original single-threaded loops were stopped (their in-flight runs
    completed naturally as orphaned children, not killed) and replaced with 2 workers per
    condition (4 concurrent runs total, up from 2) — scaled back from the historical 3+3 given
    two conditions now share the same disk-constrained machine simultaneously, unlike the
    original 3-worker run which had the whole machine to itself.
- A real, previously-undisclosed environmental-isolation gap in the ORIGINAL 800-run study was
  found and checked during this work: `goga connect claude` (run once in Phase 8) installs
  globally, not per-project, meaning Goga's skills/CLI were technically ambiently available in
  both original conditions (contradicting `TREATMENT_DESIGN.md`'s isolation intent). All 800
  `agent.log` files were checked — 0/400 Baseline runs mention "goga" at all; the 14/400
  Condition-B runs that do are consistent with reading the intended CODEMANIFEST treatment, not
  tool invocation. No evidence of actual contamination; logged as `PROTOCOL.md` Amendment 5.

## Primary study (frozen, complete)

Last updated: 2026-09-10

```
Phase 0 — Goga research:            COMPLETE  (GOGA_RESEARCH.md, TREATMENT_DESIGN.md)
Phase 1 — Environment:              COMPLETE  (experiment.yaml fully resolved: model, timeout, budget,
                                                permissions, seed; JDK 21 pinned; Android SDK, CocoaPods ready)
Phase 2 — Repository selection:     COMPLETE  (REPOSITORY_SELECTION.md, repos.yaml — 10/10)
Phase 3 — Task design:              COMPLETE  (tasks/R01-R10, 40 tasks + metadata + recon notes)
Phase 4 — Runnable architecture validators: COMPLETE (179 scripts across 40 tasks, ≥4 per task)
Phase 4.5 — Runnable functional validators: COMPLETE (40 scripts + 38 fixtures, unplanned phase — see notes;
                                                        found + fixed a real bug in R06 Task A's positive control)
Phase 5 — Positive/negative controls: COMPLETE (80 real diffs; 40/40 tasks CONFIRMED DISCRIMINATING)
Phase 6 — Pilot:                    COMPLETE  (4 real autonomous runs, R01-TA + R06-TA x2 reps, Baseline only;
                                                excluded from main 800-run sample; see pilot/PILOT_REPORT.md)
Phase 7 — Protocol freeze:          COMPLETE  (PROTOCOL.md + experiment.yaml frozen; git tag benchmark-v1;
                                                2 amendments logged post-freeze, see PROTOCOL.md)
Phase 8 — Goga architecture prep:   COMPLETE  (10/10 repos, 92 CODEMANIFEST files, 9,524 lines,
                                                all goga-lint-clean, ARCHITECTURE_CONTRACTS.md written)
Phase 9 — Randomization:            COMPLETE  (experiment_plan.csv, 800 rows, seed=42, immutable)
Phase 10 — Execution:               COMPLETE  (800/800 runs VALID; see Phase 10 process notes below —
                                                4 protocol amendments logged, incl. a full base-clone-corruption
                                                incident and recovery, and a moderate-parallelism speedup)
Phase 11 — Validation:              COMPLETE  (scripts/validate_results.py; 800/800 rows resolved, 0 problems;
                                                results/VALIDATION_REPORT.md, results/analysis_set.csv)
Phase 12 — Aggregation:              COMPLETE  (scripts/aggregate_results.py; results/cells.csv (80 rows),
                                                results/task_comparison.csv (40 paired rows);
                                                results/METRICS_COVERAGE.md discloses which planned metrics
                                                were/weren't captured)

Goga configurations prepared: 10/10

Repositories selected: 10/10
Repository candidates evaluated: 20 (across 2 independent recon passes, Python/JS-TS and Go/Kotlin/Swift)

Tasks designed: 40/40
Tasks validated: 40/40  (positive control passes functional+all architecture checks, negative control passes
                         functional but fails ≥1 architecture check — verified for every task, in most cases via
                         real test/build execution, not just static review)

Experimental cells prepared: 80/80

Runs completed: 800/800
Runs valid: 800/800
Runs invalid: 0 (all infrastructure failures along the way got a -RETRYn replacement; originals preserved)

Results aggregated: yes (results/cells.csv, results/task_comparison.csv)
Statistical analysis: done (Phase 13, results/PHASE13_STATISTICAL_ANALYSIS.md)
Final report: done (Phase 14, report/final_report.md)

Primary metric (Dangerous Success Rate, mean across 40 task-level cells):
  Baseline: 0.290   Goga: 0.275   Delta (Goga - Baseline): -0.015
  Cells where Goga < Baseline: 8/40, Goga > Baseline: 6/40, tied: 26/40
  95% bootstrap CI on delta: [-0.045, +0.013] (includes zero) -- Wilcoxon p=0.48, paired t p=0.34:
  no statistically significant difference on the primary metric itself.

  IMPORTANT -- this flat primary-metric result is not the whole story. Both components of
  Dangerous Success moved significantly in the SAME (negative) direction under Goga:
  functional_success_rate delta -0.038 (Wilcoxon p=0.037, GEE OR=0.86 p=0.011) and
  full_architecture_conformance_rate delta -0.058 (Wilcoxon p=0.031, GEE OR=0.75 p=0.048); ACR
  (continuous) delta -0.041 (Wilcoxon p=0.004). Because Dangerous Success = functional_success
  AND NOT full_architecture_conformance, a drop in functional success mechanically shrinks the
  pool of runs that could even qualify as "dangerous," while the architecture-conformance drop
  alone would push it up -- the two effects cancel in the composite metric. Full statistical
  write-up, multiple-comparisons caveat, and per-task-type breakdown in
  results/PHASE13_STATISTICAL_ANALYSIS.md.
```

## Documents produced so far

- [x] `GOGA_RESEARCH.md` — qarium/goga v1.2.2 (commit `f1257db59347651273ce94d4988e16d8fa1e7940`) researched from source; key finding: no bulk brownfield architecture ingestion exists in this version.
- [x] `TREATMENT_DESIGN.md` — Experiment B (full SDD workflow) rejected as primary design due to confounds; Experiment A (frozen CODEMANIFEST forest + static pointer file, no workflow/tooling change) adopted as the treatment; hypothesis narrowed accordingly.
- [x] `PROTOCOL.md` — DRAFT. Frozen only after Phases 3-6 complete (`benchmark-v1` tag).
- [x] `experiment.yaml` — DRAFT. Several fields marked TBD pending Phase 1 environment finalization (exact model pin, timeout, network policy, tool permissions, random seed).
- [x] `REPOSITORY_SELECTION.md` — criteria fixed 2026-08-25 before any candidate was evaluated; full 20-candidate pool and final 10 with reasoning and explicit limitations now documented.
- [x] `repos.yaml` — final 10 repositories (R01-R10), 2 per supported language (Python, TypeScript, Go, Kotlin, Swift).
- [x] `tasks/R01-R10/{task_A-D.md, metadata_A-D.yaml, RECON_NOTES.md}` — 40 tasks designed via 10 independent per-repository recon agents (GitHub API only, no full clones, respecting the disk constraint). Every extension point/architectural claim is grounded in cited real file paths/line numbers, not invented. All 40 metadata YAML files re-validated by the orchestrating session (schema completeness, ≥3 architecture_checks each, task_id consistency) after 4 files were found to have YAML syntax errors (unquoted `: ` inside plain scalars, one unquoted leading `@`) despite agent self-reports claiming validity — fixed by hand, documented here for transparency.
- [x] `tasks/R01-R10/validators/*.sh` (179 scripts) — Phase 4 runnable architecture-check implementations, one per `architecture_checks` entry per task.
- [x] `tasks/R01-R10/controls/*.diff` (80 diffs) + `tasks/R01-R10/CONTROL_RESULTS.md` (10 files) — Phase 5 positive/negative controls. **All 40/40 tasks confirmed discriminating**: positive control passes functional + all architecture checks, negative control (the "trap") passes functional but fails ≥1 architecture check. Several results include genuinely observed test failures (not just static grep evidence) proving the trap actually misbehaves — e.g. R04 Task D's trap measurably breaks undo, R06 Task B's trap triggers a real etcd server panic, R06 Task D's trap serves observably stale reads, R02 Task D's trap produces a real cross-test-pollution assertion failure, R08 Task D's trap is proven to return stale search results.
- [x] `pilot/PILOT_REPORT.md` + `pilot/raw/*.{json,diff}` — Phase 6 pilot. 4 real, autonomous `claude -p` runs (bypassPermissions, isolated git worktrees) against R01-TA and R06-TA (Baseline only — Goga artifacts don't exist yet per phase ordering). All infrastructure confirmed working: agent launch, session isolation, metrics capture (tokens/cost/turns/duration natively in JSON output), and Phase 4/5 validators scored real (not hand-authored) model output correctly, including one MANUAL REVIEW REQUIRED flag that was manually followed up and confirmed a genuine, reproducible test regression in one run. Pilot runs excluded from the 800-run sample.
- [x] `PROTOCOL.md` (FROZEN, `benchmark-v1` tag) + `experiment.yaml` (all TBDs resolved: model `claude-sonnet-5`, timeout 3600s, `--max-budget-usd 8`/run, `bypassPermissions`, random seed 42, JDK 21 pinned) — Phase 7.
- [x] `architecture/R01-R10/**/CODEMANIFEST` (92 files, 9,524 lines, all `goga lint`-clean) + per-repo `SCOPE.md`/`SETUP_COST.md`/`PLAUSIBILITY_CHECK.md` + shared `architecture/ARCHITECTURE_CONTRACTS.md` pointer template — Phase 8, the actual Goga-condition treatment artifact. See "Phase 8 process notes" below for the significant methodology finding this phase produced.
- [x] `experiment_plan.csv` — Phase 9. All 800 runs generated deterministically (seed=42): 400 Baseline / 400 Goga, exactly 10 repetitions per each of the 80 cells, blocked-randomized Baseline↔Goga order per pair, overall execution order also shuffled to avoid temporal confounds. Immutable from this point per `PROTOCOL.md` §13/§31.
- [x] `tasks/R01-R10/validators/*_functional.sh` (40 scripts) + fixtures (38 files) + `tasks/R01-R10/FUNCTIONAL_VALIDATORS.md` (10 files) — **Phase 4.5**, an unplanned but necessary phase discovered while preparing for execution: `functional_check_command` in the metadata was prose guidance, not a runnable script, unlike the architecture checks. Built standalone, implementation-agnostic functional validators for all 40 tasks (logged as `PROTOCOL.md` Amendment 2). Found and fixed a real end-to-end bug in R06 Task A's positive control in the process (see Amendment 2 and `tasks/R06/CONTROL_RESULTS.md`'s correction note).
- [x] `results/runs.csv` (826 raw rows, append-only) + `runs/<run_id>/*` (per-run raw artifacts) — **Phase 10**, the 800-run execution. See "Phase 10 process notes" below.
- [x] `results/analysis_set.csv` + `results/VALIDATION_REPORT.md` — **Phase 11**. 800/800 `experiment_plan.csv` rows resolved to exactly one usable VALID row each, 0 problems found (no duplicates, no cross-field mismatches, no out-of-range values, dangerous_success logic cross-checked against its own definition on every row).
- [x] `results/cells.csv` (80 rows) + `results/task_comparison.csv` (40 paired rows) + `results/METRICS_COVERAGE.md` — **Phase 12**. Per-cell aggregation (10 repetitions each) and the 40 Baseline-vs-Goga task-level pairings required by `PROTOCOL.md` §14, with Wilson-score 95% CIs on the binary rates (n=10/cell, too small for a naive normal approximation). `METRICS_COVERAGE.md` discloses which metrics from `experiment.yaml`'s full planned schema were actually captured vs. not (several detailed agent-activity/architecture-discovery-cost/stability sub-metrics were never instrumented in the executed harness — disclosed as a real scope limitation, not silently omitted).
- [x] `scripts/statistical_analysis.py` + `results/PHASE13_STATISTICAL_ANALYSIS.md` — **Phase 13**. Paired Wilcoxon signed-rank (zero_method='pratt', keeping the large tied fraction rather than discarding it) + exact sign test + paired t-test + percentile bootstrap 95% CI on all 40-cell deltas for the primary metric (Dangerous Success Rate) and every secondary rate/continuous metric; cluster-robust GEE logistic regression (binomial family, exchangeable working correlation, clustered by task-cell so the 10 repetitions per cell are never treated as independent) for each binary outcome, unadjusted and adjusted for repository + task_type; per-task-type descriptive breakdown. **Key finding, not just "no significant difference"**: the primary metric's flat delta (-0.015, CI includes zero) masks two individually-significant, same-direction drops under Goga — functional_success_rate (delta -0.038, Wilcoxon p=0.037, GEE OR=0.86 p=0.011) and full_architecture_conformance_rate (delta -0.058, Wilcoxon p=0.031, GEE OR=0.75 p=0.048) — which cancel inside the AND-based Dangerous Success definition rather than one dominating. Disclosed explicitly with a multiple-comparisons caveat (7 metrics tested, only 1 pre-registered) rather than presented as confirmed. All numbers independently cross-checked against `results/analysis_set.csv`'s raw pooled means and reproduced via a from-scratch scipy re-computation before being written up.
- [x] `report/final_report.md` — **Phase 14**. Full write-up: research question, design rationale, repos/tasks/validators/controls, protocol, primary results with Phase 13 statistics, extended study (B′/B″/C) both descriptively and via a new formal paired comparison against Baseline (`scripts/extended_study_analysis.py` → `results/PHASE13B_EXTENDED_STUDY_ANALYSIS.md`, same cell-paired Wilcoxon/GEE methodology as Phase 13), cost, threats to validity, limitations, conclusion, reproducibility index. Headline finding: the primary study's Dangerous Success Rate is flat (not significant) only because its two components (functional success down, architecture conformance down) cancel — both are individually significant; this same pattern, far more severe and statistically decisive, recurs in every extended condition (B″ especially: functional success roughly halves, GEE OR=0.34, p<0.0001). Also disclosed: `Research.md`, cited throughout `PROTOCOL.md`/`STATUS.md` as the source of the original RQ list and metrics schema, does not exist in this repository or its git history — never committed, content absorbed into `PROTOCOL.md`/`experiment.yaml` instead; the final report is structured from `PROTOCOL.md` directly and this gap is disclosed in the report's own preamble rather than silently worked around.

- [x] `report/final_report.md` §11.2 + `report/final_report.ru.md` §11.2 — folded in Condition D (interactive Goga pipeline, 4 R01 tasks) as a qualitative, non-pooled case series with a cross-task synthesis table, once all 4 tasks completed. Cost table updated to note Condition D's spend wasn't tracked by the automated cost harness (manual interactive session).
- [x] Condition D extended to R02 (salt) per explicit user request (2026-09-22): same 9-stage interactive pipeline, 4 tasks (A-D), one at a time. Every R02 task required at least one real correction found only via reading real source (undocumented event-bus dispatch convention in Task B; two missing required methods + cold-start gaps in Task C; wrong target file in Task D) and at least one more found only by the study's own black-box validators after formal acceptance (Task A's key-naming/shape; Task B's return-value fix; Task C's module rename plus a missed functional-test convention; Task D's full caching-mechanism rewrite from a bespoke TTL cache to Salt's real `__context__` per-run idiom — the single most severe post-acceptance finding in either repository, since an internally-self-consistent, formally ACCEPTED design still failed the external functional oracle outright). Full detail: `results/CONDITION_D_INTERACTIVE_PIPELINE.md`.
- [x] Condition D extended to R03 (nestjs/nest) and R04 (excalidraw) per explicit user request (2026-09-24): same 9-stage interactive pipeline, 4 tasks each (A-D), one at a time. R03-A was the first zero-correction run in this condition. R03-B and R03-D each found a real runtime-only defect (a Socket.IO write/close race condition; a NestJS global-enhancer DI-scope resolution bug) that no design-level trace could have found by reading alone — but, unlike every comparable R01/R02 finding, both were caught **before** formal acceptance, by actually executing the code as an ordinary part of finishing the task (a functional-fixture run in-session for B; the TDD `implement` stage's own integration test for D) — refining rather than contradicting the original finding: design-level tracing specifically never catches runtime-only defects, but *running* the code sometimes does, whenever the exercised scenario happens to hit the affected path. R04's four tasks needed no correction beyond design-level tracing, the TypeScript compiler, or the pipeline's own accept-stage review — including two genuine "trust the wrong existing discriminant" architectural traps caught by `code-design` in Task B (a fill/hit-testing flag mistaken for a closed-shape signal; a shared "polygon" type resolving text along with real enclosing shapes) and a real, previously-inaccurate CODEMANIFEST annotation fixed by tracing in Task D. Documentation/validator-evidence asymmetry across all 16 tasks is disclosed explicitly per task in the updated document rather than assumed uniform. Full detail, including an updated 16-task cross-task synthesis table: `results/CONDITION_D_INTERACTIVE_PIPELINE.md`.
- [x] `report/final_report.md` §11.2 + `report/final_report.ru.md` §11.2 — extended to fold in all 8 tasks across R01+R02 (updated summary table, cross-task synthesis, cost table, §14 limitations bullet). Not pooled with any other condition's estimates, consistent with the non-pooling rule applied throughout.
- [x] `report/final_report.md` §11.2 + `report/final_report.ru.md` §11.2 — extended again to fold in R03+R04 (2026-09-24): 16-row summary table, rewritten cross-task synthesis distinguishing design-level tracing from code-execution-based catches (R03-B/R03-D's pre-acceptance runtime-defect catches as the new nuance), cost table row (8→16 tasks), §14 limitations bullet updated. Not pooled with any other condition's estimates.
- [x] Condition D extended to R05 (VictoriaMetrics) per further explicit user request (2026-09-28): same 9-stage interactive pipeline, 4 tasks (A-D), using the same 9-cell static CODEMANIFEST overlay as R01-R04 (not R05's separate 55-cell Condition C restructuring — corrected after verification; see the note above). R05-A was a second zero-correction run. R05-B and R05-C each found real defects purely via `code-design`/`design-review`'s own source tracing before any code was written (wrong job-identity discriminant + wasteful check ordering in B; unprecedented hardcoded default + dangling unused fields in C). R05-D, drawn from the `architecture_trap` category, is this condition's first task where `brainstorm` itself avoided a named trap (unbounded raw state bolted onto a god-struct) before any design was drafted, purely by finding and modeling a real in-codebase precedent — then had every one of its remaining five stages each independently catch one further real, disclosed issue. R05-D also carries a disclosed methodological wrinkle: the orchestrating session inadvertently read the task's hidden answer key before starting, so all actual design/implementation was delegated to a fresh, uncontaminated subagent with every gate relayed to the human in both directions. Across all four R05 tasks, every real correction was caught somewhere inside the pipeline itself, with zero reliance on an external black-box oracle or post-acceptance catch. Full detail, including an updated 20-task cross-task synthesis table: `results/CONDITION_D_INTERACTIVE_PIPELINE.md`.
- [ ] `report/final_report.md` §11.2 + `report/final_report.ru.md` §11.2 — **not yet updated for R05, R06, or R07**. Both documents still describe the 16-task/4-repository (R01-R04) state. Folding in R05-R07's 12 tasks (updated summary table, cross-task synthesis, cost table row 16→28, §14 limitations bullet) is unstarted follow-up work, scoped but not done as part of this extension.
- [x] Condition D extended to R06 (etcd) and R07 (mihon) per further explicit user requests (2026-10-08): same 9-stage interactive pipeline, 4 tasks each (A-D). Disclosed protocol difference from R01-R05: neither repository's base commit had a pre-built CODEMANIFEST overlay — each task built its own forest live during its own `brainstorm`→`apply-architecture` stages, converging independently on the same real 10-cell spine for R06's A/B/C (11 for D) but varying genuinely by task for R07 (12-17 cells), since mihon's real architecture is large and multi-faceted enough that different features legitimately scope different slices of it. R06 reproduced R04/R05's cleanest pattern (every real correction, across all four tasks, caught somewhere inside the pipeline itself) and produced this condition's most severe self-caught defect: R06-D's `coding-plan` stage catching its own cache-before-authorization-check ordering bug before any external review, later proven by a dedicated test added at `accept-result` specifically because no prior test had exercised the fix with authorization enabled. R06-C sharpens the "design-level tracing catches self-consistency defects" finding: `architecture-review` overturned a cell's own documented self-suggestion (`apply`'s CODEMANIFEST plausibly suggested itself as the audit-logging home) once tracing proved it structurally can't see the traffic in question. R07-A/B/C reproduced the familiar pattern (two critical `interceptor.newAuth()` catches by `design-review` before any code existed in Task C; a JUnit silent-skip false-negative and a pre-existing test-infrastructure gap both found only by running the code, in Tasks A/B). R07-D is this condition's first task where the orchestrating human process itself introduced a defect — a delegated subagent hallucinated an "architecture hint" during Intake, caught only by direct re-reading of the real ticket plus a tool-transcript check ruling out contamination — disclosed as a hallucination incident distinct from R04-A's inadvertent-fixture-read incident. Once corrected, R07-D's own pipeline caught a `FilterList.equals`-always-`false` cache-key trap (independently re-derived from fresh tracing), a `design-review` catch of a contract bug its own test traces would have introduced, and a `plan-review` catch of real plan-vs-implementation scope drift. Full detail, including an updated 28-task cross-task synthesis table: `results/CONDITION_D_INTERACTIVE_PIPELINE.md`.

## Project status: complete through Phase 14 + Condition D (28/28 tasks across R01-R07; only 16/28 folded into `report/final_report.md` §11.2 so far — R05-R07 fold-in is open follow-up work)

Primary study (Condition A vs. B, 800/800 valid, frozen) + extended study (Condition B′ stopped by design at 91/400, B″ 400/400, C 400/400) + statistical analysis (Phase 13 + the extended-study addendum) + final report (Phase 14) are all done. Condition D (interactive Goga pipeline) is now 28/28 tasks across R01-R07, but only the first 16 (R01-R04) are folded into the final report §11.2 — R05-R07's fold-in is scoped (see the unchecked bullet above) but not yet done. 1,691 total automated runs, $5,097.33 total automated spend, plus 28 manual interactive-pipeline tasks (untracked cost). No phase remains open; the R05-R07→final-report fold-in is the one explicitly-scoped, not-yet-done extension. Other possible next steps (slide-deck extraction for the actual Podlodka AI Crew talk, the B′-specific formal test noted as unattempted in `report/final_report.md` §14, recovering the "derivable but not parsed" metrics from `results/METRICS_COVERAGE.md`, or extending Condition D to further repositories) remain new work, not a continuation of an existing phase, and should be scoped explicitly if/when requested.

## Phase 10 process notes (for reproducibility) — the longest and most infrastructure-heavy phase

- **Executed over ~11 days (2026-08-28 to 2026-09-10)** at a deliberately unhurried pace per explicit user instruction ("there's time, the talk is months away") — mostly single-threaded (~3-4 runs/hour), with a short moderate-parallelism period (3 concurrent repo-partitioned workers, ~18 runs/hour) near the end once the user upgraded their Claude subscription tier and asked for it.
- **Major incident, logged as `PROTOCOL.md` Amendment 4**: all 10 base git clones lived under `/tmp/benchmark-repos/` initially. macOS's periodic daily maintenance silently strips files untouched for ~3 days anywhere under `/tmp` — across the multi-day unattended run this gutted every base clone's `.git` internals (`HEAD`, `config`, `refs`, most of `objects`), while leaving the containing directories in place (misleadingly *looking* intact in a plain `ls`). This cascaded into ~650 spurious `INVALID` rows before being diagnosed (`git -C <clone> rev-parse HEAD` failing identically on all 10 clones, `uptime` ruling out a reboot as the cause). Fixed by relocating all base clones and scratch worktrees to a persistent path outside `/tmp` (`benchmark-scratch/` next to the project) and re-cloning all 10 at their exact pinned commits (`scripts/reclone_base_repos.sh`, shallow `git fetch --depth 1`) — original `INVALID` rows were kept, not deleted, and every affected run_number was re-run as a `-RETRYn` replacement.
- **A second real infrastructure failure mode, found by running it**: disk exhaustion mid-build (Xcode DerivedData, and separately Go's build cache, both independently regrew to 15-25GB) once caused a `claude -p` subprocess to hang in an uninterruptible I/O-wait state for **over 2 days straight** — its own 3600s timeout never fired because the process was blocked in the kernel, not actually running. `scripts/execute_run.py`'s `clean_xcode_caches()` (already present for the Xcode case) was extended to also run `go clean -cache`, and its disk-space floor was raised from 6GB to 10GB headroom once moderate parallelism made concurrent disk consumption a bigger risk.
- **Other recurring failure modes, all handled automatically by the harness rather than needing repeated manual intervention**: account session/usage rate limits (`is_error=True, total_cost_usd=0, api_error_status=429`) — auto-retried with a 300s backoff, up to 66 attempts; "connection closed mid-response" transport errors mid-run (sometimes after real cost was already incurred) — auto-retried up to 3 times with the worktree reset to clean state between attempts; stale `git worktree` registrations left behind by a killed process — self-healed via `git worktree prune` before every `git worktree add`.
- **Moderate parallelism** (`scripts/run_batch_for_repos.sh`, one process per disjoint subset of repositories so no two workers ever touch the same base clone's `.git` concurrently) was added late in the phase at the user's request, once their account's rate-limit ceiling was no longer the binding constraint. `results/runs.csv` writes are `flock`-serialized (`execute_run.py`) so concurrent workers' appends can't interleave/corrupt the file. Empirically this gave roughly a 4-5x throughput increase with 3 workers (not a clean 3x — some of the gain came from the rate-limit ceiling being gone, not parallelism alone), and was later scaled back to single-threaded, then briefly back to 3-threaded-rebalanced, purely based on the user's own live preference (laptop thermals, wanting to check in) rather than any technical constraint.
- **Final tally**: 800/800 `experiment_plan.csv` rows have exactly one VALID row; 0 rows required manual data correction (all replacement runs were genuine fresh independent attempts, not edits); total spend across the full 800-run sample was **$2,584.04** (`results/VALIDATION_REPORT.md`), mean $3.23/run, median $2.69/run.

## Phase 6 headline finding

Two independent pilot repetitions of the exact same task (R01-TA, freqtrade "reject conflicting capital-sizing config") produced two different architectural solutions to the same subtlety (validate the user's raw config vs. the schema-defaulted config) — one correct, one that empirically broke 4 existing tests (confirmed via a real `pytest` run). This is a live, small-scale preview of the "same task, same model, different architecture" instability the full 800-run study exists to measure — see `pilot/PILOT_REPORT.md` for the full writeup. Cost varied 3× across runs of the same task/repo ($0.73–$2.27), which should inform the budget line in `experiment.yaml` before Phase 10.

## Phase 4.5 process notes (unplanned phase, discovered while preparing for Phase 10)

- **Why this phase exists**: while preparing to actually execute the 800 runs, it became clear that `metadata_X.yaml`'s `functional_check_command` field (used throughout Phase 5) is prose guidance for a human/agent to interpret ("construct a conf dict with...", "manually run vmagent and confirm...") — not a runnable script, unlike the 179 Phase 4 architecture-check scripts. Without a real script, `functional_success` and the primary metric (Dangerous Success = functional_success AND NOT full_architecture_conformance) could not be computed automatically at 800-run scale. The user chose to build real functional validators before proceeding, mirroring Phase 4's rigor rather than falling back to an LLM judge or manual review.
- **Design constraint that matters most**: each of the 40 functional validators had to be **implementation-agnostic** — testing observable behavior through a stable, real public entry point, not internal helper names specific to the one Phase-5 reference implementation — since these scripts will grade many structurally different real AI-agent solutions during the actual 800 runs, not just the already-known controls.
- **A genuinely more rigorous measurement emerged**: for several tasks (R02 A/B/C, R05 A/B/C, and others), the new black-box functional tests correctly FAIL the negative control functionally, not only architecturally — Phase 5's original functional check often only re-ran the trap's own narrowly-scoped test file, which its author naturally wrote to pass. This narrows, for those specific tasks, the population of possible "Dangerous Success" outcomes (a trap that fails outright is not a dangerous success, just a failure) — a real, disclosed finding, not a defect.
- **A genuine defect was found and fixed**: R06 Task A's Phase-5-blessed positive control did not actually work end-to-end (`EtcdServer.UserAdd` hashes an empty password into a valid, non-empty hash before the store-layer emptiness check ever runs — a real, subtle bug that only a black-box gRPC-level test catches, not a direct-call unit test). Fixed in `server/etcdserver/v3_server.go`, re-verified clean against the new functional validator and all 5 existing architecture checks. Logged transparently as `PROTOCOL.md` Amendment 2 and as a dated correction appended to (not silently editing) `tasks/R06/CONTROL_RESULTS.md`.
- Of the 10 parallel per-repo agents, 6 hit at least one transport failure or the account's session-usage limit mid-task (the usage limit — "resets 2pm Europe/Moscow" — is a new failure mode not seen in earlier phases; unlike transport failures, resuming immediately did not help until enough time had passed). All were eventually resumed successfully with no lost work (partial files were always intact).
- R09 (firefox-ios) and R10 (Signal-iOS) both correctly used `MANUAL REVIEW REQUIRED` (never a fabricated PASS) for the Client-app-scoped tasks that remain genuinely unbuildable in this environment (missing Mozilla-internal `nimbus-fml.sh` tooling; Signal-iOS's disk/build-time cost) — consistent with the same honesty standard applied throughout Phase 5.

## Phase 8 process notes (for reproducibility) — includes a real methodology adaptation

- **Goga was installed twice.** First from PyPI by package name (`pipx install goga`), which the session's own safety classifier correctly blocked as an unverified-provenance supply-chain risk (a PyPI name match is self-declared, not proof of identity) before it was ever executed. Re-installed directly from the pinned GitHub tag (`pip install git+https://github.com/qarium/goga.git@v1.2.2`) instead — unambiguous provenance, same version. `goga connect claude` (which symlinks Goga's skills/commands into the real, shared `~/.claude/skills`/`~/.claude/commands` on this machine) was likewise held for, and got, explicit user confirmation before running, since it's a self-modification of the live agent environment, not a benchmark-scratch-space action.
- **Major finding, logged as `PROTOCOL.md` Amendment 1**: `goga-brainstorm` — the skill `TREATMENT_DESIGN.md` §4 originally assumed would be used to generate the architecture forest — turned out, once actually invoked, to be a strictly interactive, one-question-at-a-time human dialogue skill that explicitly instructs the agent *not* to read implementation source code. This makes it structurally incapable of autonomously documenting an existing codebase, a deeper and more concrete confirmation of the brownfield-ingestion gap already suspected in `GOGA_RESEARCH.md` §9. The adapted, logged method: author `docs/arch/<topic>.md` directly (grounded in real source reading, using the same `goga-cell`/`goga-cookbook`/`goga-lang-disp` DSL-rule skills), then run the real `goga-apply` mechanism against it — `goga-apply` never cared how its input plan was produced. The output artifact and its validation (`goga lint`, `goga contract`) are unaffected; only the input-authoring step changed, and this is disclosed in the frozen protocol rather than silently substituted.
- 10 parallel per-repository agents executed this adapted method. 7 of 10 hit at least one "connection closed mid-response" transport failure (the same pattern from Phases 3-5), consistently right as the agent was about to write a large chunk of CODEMANIFEST content; the empirically effective mitigation (write a skeleton via one `Write`, then append each cell via separate `Edit` calls) eliminated the failure for repos that adopted it from the start (R02, R03, R06, R07, R08, R10 completed cleanly once informed of this), while R01 (the first, not-yet-informed validation run) needed 3 attempts and R04 needed a full hand-off to the orchestrating session after 4 failures on the same step.
- **R04 (excalidraw) scope was reduced from a planned 10 cells to 5**, disclosed explicitly in its `SCOPE.md`: after repeated transport failures cost significant session time, coverage was prioritized to the deepest shared foundation (`common`/`fractional-indexing`/`math`/`element`) plus the one real extension-point cell (`actions`) most relevant to RQ7, rather than pushing for all 10 originally-scoped cells at proportionally higher cost. This is the only repository with below-target cell coverage; it is disclosed, not hidden, and the reduction was locked in before that repository's plausibility check (i.e., before task prompts were read), so it wasn't shaped by task content.
- **`goga contract` earned its keep**: R01, R05, R06, and R08's preparation agents each found and fixed genuine signature drift between their authored CODEMANIFEST and the real implementation (wrong parameter shapes, invented methods that don't exist, missing real parameters) — direct evidence the drift-check step is doing real verification work, not rubber-stamping. Multiple repos also surfaced and documented real tool-level limitations (e.g. `goga contract`'s `javascript` grammar cannot parse TypeScript, so R03/R04 got `implementation: null` for everything; Swift's extractor assumes `public`-only facades and returns nulls for internal-only app targets in R09) — logged as tooling gaps, not treated as content errors.
- Every one of the 10 `PLAUSIBILITY_CHECK.md` files was written only after its repository's CODEMANIFEST forest was fully authored, materialized, and lint-clean — task prompts were read last, per `TREATMENT_DESIGN.md` §4's ordering rule. Several genuine overlaps between a documented extension point and a Task C/D scenario were found and disclosed (never hidden or "fixed" after the fact) — judged, consistently across repos, to be the intended operation of documenting a real mechanism generically, not task-specific leakage.

## Phase 4/5 process notes (for reproducibility)

- Environment gaps identified after Phase 3 were resolved before Phase 5: installed OpenJDK 26 (Homebrew, keg-only, invoked via explicit `JAVA_HOME`), Android SDK cmdline-tools + platform 34/35 + build-tools 34.0.0/35.0.0 (licenses accepted non-interactively), and CocoaPods — enabling real builds/tests for all 5 languages instead of static-review-only fallbacks.
- **Toolchain finding worth carrying into Phase 1's final environment spec**: JDK 26 works for `mihonapp/mihon` but breaks `signalapp/Signal-Android`'s Robolectric unit tests (`Unsupported class file major version 70` — Robolectric's bundled ASM can't parse JDK 26 bytecode). The R08 agent self-diagnosed this and installed `openjdk@21` specifically for Signal-Android's Gradle invocations. **Action item**: pin JDK 21 (not 26) as the benchmark-wide Android JDK before Phase 6, and re-verify Mihon still builds under JDK 21 for consistency across the two Kotlin repositories.
- 10 parallel per-repository agents were launched for Phase 4+5 (clone at pinned commit, write validators, implement + test a real positive and real negative control per task, judge discrimination). 6 of 10 runs (R01, R04 ×2, R05, R06, R07 ×2, R09 ran clean) hit the same "connection closed mid-response" transport failure seen in Phase 3, always immediately before writing the final `CONTROL_RESULTS.md` summary (all validator scripts and control diffs were already safely written in every case). Resumption via `SendMessage` succeeded for R01/R05/R06/R09/R10; for R04 and R07, resumption itself failed a second time, so the orchestrating session completed those two directly — re-applying each of the 8 diffs against the clean pinned-commit clone and re-running every validator script live (in R04's case, live `vitest` runs; in R07's case, plus a real `./gradlew :domain:compileDebugKotlin` spot-check) rather than reconstructing results from memory.
- Some repo-level agents (R01, R03, R08) further delegated individual tasks to their own sub-agents running in isolated `git worktree`s; the orchestrating session did not duplicate that work but did spot-check disk cleanliness and final file counts across all 10 repos afterward.
- No task among the 40 required forcing or fudging a result. Multiple agents found and fixed real validator-script bugs (shell portability issues: macOS `awk`/`sed`/`grep` BRE-vs-GNU-regex differences; overly narrow or overly broad grep patterns) during development and documented the fixes rather than silently patching around them.
- Disk usage was monitored throughout (dropped as low as ~1GB free during concurrent Signal-Android/Signal-iOS work before recovering to ~30GB); no data was lost, though one Gradle transform-cache corruption in R08 was documented and worked around.

## Phase 3 process notes (for reproducibility)

- 10 repo-reconnaissance agents were launched in parallel (one per repository), each independently instructed not to use Goga, not to name discovered extension points in task prompts, and to ground every claim in code actually read via the GitHub API at the pinned commit.
- 4 of the 10 agent runs (R01, R07, R09) hit a transport-level "connection closed mid-response" error partway through (a session-infrastructure issue, unrelated to task content) and were resumed with a follow-up message pointing at exactly the missing deliverables; R01's final file (`RECON_NOTES.md`) failed twice on resume and was completed directly by the orchestrating session using the already-written, already-verified task/metadata files as source material.
- Two agents (R07/mihon, R09/firefox-ios) explicitly rejected the extension-point candidate suggested in their prompt after verifying it didn't fit (mihon's `Source`/`CatalogueSource` turned out to be an external-extension-APK mechanism, not in-repo; firefox-ios confirmed Redux has zero usage inside BrowserKit) and independently found a better-grounded alternative (`Tracker`/`BaseTracker`/`TrackerManager`; scoping Redux-dependent tasks to the Client app instead) — treated as a positive signal that the recon was genuine rather than confirmatory.

## Section 68 / Step 11 validation — does the design separate Quality/Stability from confounds, against the final 10 repositories?

Re-checked against the concrete `repos.yaml` set (not just in the abstract, as originally argued in `TREATMENT_DESIGN.md` §5):

- All 10 repositories are in languages Goga v1.2.2 fully or partially supports (9 full, 1 partial — R08's coexisting legacy Java portion has no drift-checking; scoped around in Phase 8). No repository forces a fallback to a different, undocumented treatment.
- The treatment (frozen CODEMANIFEST forest + one static pointer file, §2 of `TREATMENT_DESIGN.md`) requires no repository-specific exception — it applies uniformly across all 10, including the two "poor documentation" repositories (R01, R05) where it is expected to matter most, and the two "already well-documented" repositories (R02, R09) where it is expected to matter least (an informative contrast for RQ11).
- Nothing in the final repository set requires running Goga's multi-stage SDD pipeline, `goga build`, or any Docker-isolated pipeline execution as part of the 800 task-solving runs — Docker/pipeline machinery stays confined to the one-time, pre-freeze architecture-forest preparation in Phase 8, as designed.
- **QUALITY** (does the agent follow architecture) and **STABILITY** (does it repeat its own decision across 10 reps) remain answerable per repository and per task type, since condition assignment changes only static reference material, not the model, prompt, tool permissions, or session protocol.
- Residual, already-documented risk carried forward unchanged from `TREATMENT_DESIGN.md` §5: Condition B adds *information* (a correct architecture description) together with *format* (the CODEMANIFEST DSL) — this benchmark cannot separate "structured format helped" from "any correct architecture summary would have helped just as much." This remains an explicit scope limitation, not a flaw hidden from the final report.

Conclusion: the design, as instantiated against the real 10-repository sample, still supports the narrowed hypothesis in `TREATMENT_DESIGN.md` §3. No repository-specific compromise reopened the Experiment A/B confound.

## Next steps

1. ~~Phase 13 — statistical analysis~~ — **done**, see `results/PHASE13_STATISTICAL_ANALYSIS.md`.
2. ~~Phase 14 — final report~~ — **done**, see `report/final_report.md` (includes the extended-study formal statistical addendum, `results/PHASE13B_EXTENDED_STUDY_ANALYSIS.md`).

No phase remains open. See "Project status: complete through Phase 14" above for what any further work would be (new scope, not a continuation).

## Explicit reminder

All phases (0-14) are complete: the 800-run primary study (800/800 VALID, frozen), the extended study (B′ stopped by design at 91/400, B″ and C both 400/400), statistical analysis of both, and the final report. As with every phase before it, any further work is new scope and should be explicitly requested, not assumed.
