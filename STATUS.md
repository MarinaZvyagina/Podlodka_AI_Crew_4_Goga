# STATUS.md

Last updated: 2026-08-25

```
Phase 0 — Goga research:            COMPLETE  (GOGA_RESEARCH.md, TREATMENT_DESIGN.md)
Phase 1 — Environment:              PARTIAL   (experiment.yaml drafted; model pin/timeout/network policy still TBD;
                                                build toolchain now proven: JDK 26 + Android SDK cmdline-tools +
                                                CocoaPods installed and validated against real builds)
Phase 2 — Repository selection:     COMPLETE  (REPOSITORY_SELECTION.md, repos.yaml — 10/10)
Phase 3 — Task design:              COMPLETE  (tasks/R01-R10, 40 tasks + metadata + recon notes)
Phase 4 — Runnable validators:      COMPLETE  (179 validator scripts across 40 tasks, ≥4 per task)
Phase 5 — Positive/negative controls: COMPLETE (80 real diffs; 40/40 tasks CONFIRMED DISCRIMINATING)
Phase 6 — Pilot:                    COMPLETE  (4 real autonomous runs, R01-TA + R06-TA x2 reps, Baseline only;
                                                excluded from main 800-run sample; see pilot/PILOT_REPORT.md)
Phase 7 — Protocol freeze:          COMPLETE  (PROTOCOL.md + experiment.yaml frozen; git tag benchmark-v1)
Phase 8 — Goga architecture prep:   COMPLETE  (10/10 repos, 92 CODEMANIFEST files, 9,524 lines,
                                                all goga-lint-clean, ARCHITECTURE_CONTRACTS.md written)

Goga configurations prepared: 10/10

Repositories selected: 10/10
Repository candidates evaluated: 20 (across 2 independent recon passes, Python/JS-TS and Go/Kotlin/Swift)

Tasks designed: 40/40
Tasks validated: 40/40  (positive control passes functional+all architecture checks, negative control passes
                         functional but fails ≥1 architecture check — verified for every task, in most cases via
                         real test/build execution, not just static review)

Experimental cells prepared: 0/80

Runs completed: 0/800
Runs valid: 0/800
Runs invalid: 0

Results aggregated: no
Statistical analysis: no
Final report: no
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
- [ ] Phase 9+ (randomization, execution, analysis, report) — not started.

## Phase 6 headline finding

Two independent pilot repetitions of the exact same task (R01-TA, freqtrade "reject conflicting capital-sizing config") produced two different architectural solutions to the same subtlety (validate the user's raw config vs. the schema-defaulted config) — one correct, one that empirically broke 4 existing tests (confirmed via a real `pytest` run). This is a live, small-scale preview of the "same task, same model, different architecture" instability the full 800-run study exists to measure — see `pilot/PILOT_REPORT.md` for the full writeup. Cost varied 3× across runs of the same task/repo ($0.73–$2.27), which should inform the budget line in `experiment.yaml` before Phase 10.

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

## Next steps (require explicit go-ahead — see reminder below)

1. Phase 9 — randomization: generate the immutable `experiment_plan.csv` for all 800 runs with the fixed random seed (42) already recorded in `experiment.yaml`, using blocked randomization of Baseline↔Goga execution order per `PROTOCOL.md` §13.
2. Phase 10 — execution: the actual 800 runs, applying each repository's frozen `architecture/R0X/**/CODEMANIFEST` forest + the shared `ARCHITECTURE_CONTRACTS.md` pointer into a fresh clone/worktree for every Condition-B run (Condition A gets neither). Given the pilot's observed cost range ($0.73-$2.27 per single-task Baseline run) and that the real 40 tasks include the more complex B/C/D categories, budget meaningfully above the pilot's numbers before starting — this is the single most expensive and time-consuming remaining phase by a wide margin.
3. Phase 11-14 — validation, aggregation, statistical analysis, and the final report, per `PROTOCOL.md` §14/§19.

## Explicit reminder

Per `Research.md` §68: **do not start the 800-run benchmark without explicit request.** Phases 0-8 are now complete: repositories selected, 40 tasks designed and validated with real positive/negative controls, a real 4-run pilot confirmed the execution infrastructure end-to-end, the protocol is frozen (`benchmark-v1`), and all 10 repositories have a real, `goga lint`-clean, drift-checked CODEMANIFEST forest ready to serve as the Goga condition. Only Phase 9 (randomization — cheap, mechanical) and Phase 10 (the actual 800 runs — the single largest remaining time/cost commitment in this project) remain before analysis and the final report. Phase 10 should only proceed once the user has explicitly approved starting the main run at its budgeted cost.
