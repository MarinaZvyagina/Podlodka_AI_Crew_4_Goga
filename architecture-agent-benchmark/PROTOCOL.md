# PROTOCOL.md

Status: **FROZEN — `benchmark-v1`.** Repositories (Phase 2), tasks (Phase 3), validators (Phase 4), positive/negative controls (Phase 5), the infrastructure pilot (Phase 6), and the environment specification in `experiment.yaml` (Phase 1) are all complete and locked as of this freeze. Any change after this point must be logged in the "Protocol amendments" section at the end of this file, never by silent edit.

## 1. Research questions (RQ1–RQ12)

See `Research.md` §53 for the full list. Restated briefly:

1. How often does an AI agent violate the architecture of an existing repository?
2. How often does this happen alongside full functional success (Dangerous Success)?
3. Does the Goga treatment (as scoped in `TREATMENT_DESIGN.md`) change Architecture Conformance Rate?
4. Does it change Dangerous Success Rate?
5. Does it change run-to-run variance?
6. Does it change architectural decision stability (dominant strategy share)?
7. Does it change existing-extension-point usage rate?
8. Does it change Architecture Discovery Cost?
9. How does the effect depend on task type (Local / Cross-module / Extension Point / Architecture Trap)?
10. How does the effect depend on repository size/modularity?
11. How does the effect depend on documentation quality?
12. What is the token/time/setup cost of the Goga treatment?

## 2. Hypothesis

Primary hypothesis and its explicit scoping/narrowing are defined in `TREATMENT_DESIGN.md`. This protocol tests **that** narrowed hypothesis (H), not the broad, unscoped version in the original brief.

## 3. Experimental design overview

```
10 repositories × 4 tasks × 2 conditions × 10 repetitions = 800 agent runs
```

Nested structure (see `Research.md` §6-7):

```
Repository → Task → Condition → Repetition
```

Primary unit of comparison: **40 unique tasks** (10 Baseline obs vs 10 Goga obs each). Repetitions estimate success probability, variance, and stability — they are **not** treated as 800 independent observations (no pseudoreplication; see `PROTOCOL.md` §14 statistical analysis plan).

## 4. Conditions

Defined precisely in `TREATMENT_DESIGN.md` §2. Summary:

- **Baseline** — repository as-is (source, README, CONTRIBUTING, ADRs, AGENTS.md/CLAUDE.md, comments, tests, module docs). Nothing removed.
- **Goga** — identical repository + a frozen `CODEMANIFEST` architecture forest + one static pointer file (`ARCHITECTURE_CONTRACTS.md`). No Goga CLI, skills, slash commands, or multi-stage workflow during the benchmark session itself.

## 5. What is held constant between conditions

```
repository commit
task prompt
model / model version
Claude Code version
system prompt
tool permissions
timeout
machine / execution environment
dependency state
network policy
working-directory structure
test environment
interaction protocol (single autonomous session, no human-in-the-loop rescue)
```

Filled in concretely for the frozen run in `experiment.yaml` once Phase 1 (environment) completes.

## 6. Model / tooling drift policy

For every run, record: `requested_model`, `actual_model`, `model_identifier`, `claude_code_version`, `timestamp`. Prefer a pinned model version over a floating alias. If the actual model changes mid-benchmark:

1. record the change explicitly in `results/runs.csv` (do not silently continue);
2. do not merge pre- and post-drift runs into one analysis without flagging;
3. assess impact (e.g., compare a small set of re-run cells);
4. if material, split into separate experimental batches and report both.

Same policy applies to the Goga version pinned in `GOGA_RESEARCH.md` (`v1.2.2` / `f1257db59347651273ce94d4988e16d8fa1e7940`) — if Goga is upgraded mid-benchmark, the CODEMANIFEST forests already frozen are **not** regenerated; this is recorded as a limitation, not silently absorbed.

## 7. Repository selection

Criteria fixed before selection; see `REPOSITORY_SELECTION.md` and `repos.yaml`. Selection happens before task design (see §9 ordering) and without reference to Goga's ease of use on any candidate.

## 8. Task design (4 per repository)

- **Task A — Local Change**: bounded, single-component change.
- **Task B — Cross-module Feature**: crosses ≥2 (preferably ≥3) architectural boundaries.
- **Task C — Existing Extension Point**: repository already has a designed extension mechanism (interface/plugin/provider/registry/factory/strategy/adapter/middleware/handler-registration); prompt does not name it — agent must discover it or fail to.
- **Task D — Architecture Trap**: has an easy solution that compiles/passes functional tests but violates architecture, and a correct solution requiring understanding of existing boundaries.

Task prompts are written as realistic engineering requests; they never name internal classes/modules/patterns (see `Research.md` §22 good/bad examples).

## 9. Fixed ordering (bias control)

```
repository selection
→ repository reconnaissance
→ task design
→ ground truth (metadata.yaml)
→ validators (functional + architecture, ≥3 checks each, prefer 4-8)
→ positive control (correct impl passes both)
→ negative control (functional pass, architecture fail — proves validators discriminate)
→ protocol freeze (benchmark-v1 tag)
→ Goga architecture-forest preparation (per TREATMENT_DESIGN.md §4)
→ randomization / experiment_plan.csv
→ execution
```

Goga output is never used to search for "convenient" tasks — tasks are frozen before any Goga artifact exists for that repository.

## 10. Clean-room execution

Before every run: restore the exact commit, create a fresh worktree/container, clear any task-specific agent state, verify `git status` is clean, start a brand-new agent session. No conversational memory, no prior diffs, no prior Goga output generated *during* task-solving, no manual hints, no accumulated notes survive between repetitions.

## 11. No manual rescue

Once a run starts: no hints, no architecture explanations, no file pointers, no code fixes, no inconsistent answers to clarification questions. Enforced mechanically, not by discipline alone: every run is launched via `claude -p <prompt> --permission-mode bypassPermissions --no-session-persistence` (see `experiment.yaml` `environment.tool_permissions`) — a single non-interactive call that runs to completion or timeout with no channel for a human to inject a hint mid-run. Confirmed working in the Phase 6 pilot (4/4 runs completed autonomously, no intervention). If the agent asks a clarifying question in its final text output, this is recorded as agent behavior (potentially a functional_success=false signal, since nothing answers it) rather than responded to.

## 12. Timeout

Fixed at **3600 seconds (60 minutes)** per run, recorded in `experiment.yaml` `environment.timeout_seconds`, identical across both conditions and all task types. Chosen with margin above the Phase 6 pilot's observed 280-670s for the simplest task type (Local Change), anticipating longer runs for Cross-module/Extension-Point/Architecture-Trap tasks. On exceeding it: `status = TIMEOUT`; the run is not manually continued or nudged. A per-run cost ceiling is enforced identically via `--max-budget-usd 8` (`experiment.yaml`), separate from the time-based timeout.

## 13. Repetition schedule / randomization

Blocked randomization: for each `repository × task × repetition`, the Baseline↔Goga execution order is randomized (not run as "10 Baseline then 10 Goga") using a fixed random seed (recorded in `experiment.yaml`), to prevent temporal drift from being confounded with condition. Full 800-row plan generated once in `experiment_plan.csv` before execution and never edited afterward (replacement rows get new run IDs; see §15).

## 14. Statistical analysis plan

- Do not treat 800 runs as independent. Respect the `repository → task → condition → repetition` hierarchy.
- Primary analysis: aggregate 10 repetitions within each (task, condition) cell → 40 paired task-level comparisons (Baseline vs Goga).
- Secondary: hierarchical / mixed-effects modelling with repository and task as random effects, for anyone who wants to model repetition-level variance directly.
- Binary outcomes (functional success, full architecture conformance, dangerous success): account for repeated observations per cell (e.g. cluster-robust or exact binomial per cell, not naive pooled proportions across all 800 rows).
- Continuous metrics (ACR, tokens, time, discovery cost): report mean, median, SD, IQR — not mean alone.
- Report confidence intervals and effect sizes; do not rely on p-values as the sole argument.
- All aggregation methods actually used are documented in `results/` and `report/final_report.md` — not left implicit.

## 15. Invalid runs

If infrastructure fails: `status = INVALID`, `reason = ...`, raw data preserved, a replacement run is created under a **new** run ID. Failed runs are never deleted from history.

## 16. What is stored per run

```
prompt.txt, agent.log, stdout.log, stderr.log
git.diff, git.status, changed_files.txt
metrics.json, functional_results.json, architecture_results.json
environment.json, result.md
```
Raw results are never overwritten.

## 17. Metrics collected

See `Research.md` §35-45 for the full list (correctness, agent activity, change size, timing, Architecture Discovery Cost, reproducibility/stability metrics, Architectural Decision Stability, Dominant Strategy Share, module-set Jaccard stability, dependency-delta stability, cost of stability, Goga setup cost). Reproduced verbatim into `experiment.yaml`'s `metrics` section so the schema is machine-checkable.

## 18. Primary metric

**Dangerous Success** = `functional_success == true AND full_architecture_conformance == false`. Reported as **Dangerous Success Rate** per condition, per task type, per repository, per complexity group.

## 19. Phases

Phase 0 (Goga research) → 1 (environment) → 2 (repository selection) → 3 (task design) → 4 (validators) → 5 (controls) → 6 (pilot, excluded from main sample) → 7 (protocol freeze) → 8 (Goga architecture preparation) → 9 (randomization) → 10 (execution) → 11 (validation) → 12 (aggregation) → 13 (analysis) → 14 (report). Tracked in `STATUS.md`.

## 20. Threats to validity

Tracked in full in `report/final_report.md` §18 once written; preliminary list carried over from `Research.md` §65: single model, single agent harness, 10 repositories, 4 tasks/repo, task-selection subjectivity, validator quality, Goga-representation quality, possible model drift, LLM nondeterminism, cross-language differences, OSS-vs-proprietary generalizability, caching/tooling effects, missing token/tool metrics in some environments, possible persistent-state contamination.

## Protocol amendments

### Amendment 1 (Phase 8, post-freeze) — Goga architecture-forest generation mechanism

**What was planned:** `TREATMENT_DESIGN.md` §4 stated the CODEMANIFEST forest would be "generated once via Goga's own `brainstorm` → `apply` cycle."

**What was found on actually invoking the connected skills:** `goga-brainstorm`'s own `SKILL.md` (installed via `goga connect claude`) specifies a strictly interactive, human-in-the-loop dialogue protocol — "Ask one question per message... wait for selection, then ask the next. Never group questions" — and an explicit design rule: "Do not read implementation source code. Design is conducted at the level of CODEMANIFEST, project schema, and practices." This makes `goga-brainstorm`, as actually implemented in v1.2.2, structurally unable to autonomously produce a source-grounded description of an existing large codebase — it is built for collaboratively designing NEW cells for a proposed feature with a human in the loop, not for retroactively documenting real, existing architecture. This is a deeper, more concrete confirmation of the brownfield-ingestion gap already flagged in `GOGA_RESEARCH.md` §9.

By contrast, `goga-apply`'s `SKILL.md` (via its `goga-cells-by-brainstorm` sub-skill) reads `docs/arch/<topic>.md` and materializes whatever CODEMANIFEST/`.usages/` content that file already contains — it does not care how that file was produced, and does no design work of its own (per `goga-brainstorm-plan-assembly`'s own spec, `docs/arch/<topic>.md` is expected to already contain the complete, syntactically-correct CODEMANIFEST DSL content per cell before `apply` ever runs).

**Adapted mechanism (this amendment):** `docs/arch/<topic>.md` for each repository is authored directly — grounded in real source-code reading of that repository's top-level architectural spine (per `TREATMENT_DESIGN.md` §4's scope rule), following the exact DSL rules from the connected `goga-cell`/`goga-cookbook`/`goga-lang-disp` skills — instead of being extracted through `goga-brainstorm`'s interactive dialogue. `goga-apply` is then run exactly as designed, against this directly-authored plan, to materialize the real CODEMANIFEST forest via Goga's own tooling.

**What this does and does not change:** The OUTPUT contract from `TREATMENT_DESIGN.md` §2 is unchanged — a frozen, Goga-format CODEMANIFEST forest, materialized by Goga's own `apply` mechanism, validated by `goga lint`, scoped to the architectural spine and not to any specific benchmark task. Only the *input-authoring* step changes: from an (infeasible, as it turns out) interactive brainstorm dialogue to direct, source-grounded authorship of the plan document that `apply` was always going to consume verbatim regardless of its origin. This is logged here, rather than silently substituted, per this document's own freeze rule.

### Amendment 2 (Phase 4.5, post-freeze) — real, standalone functional validators added

**What was found:** while preparing for Phase 10 execution, it became clear that `metadata_X.yaml`'s `functional_check_command` field — used throughout Phase 5 to verify positive/negative controls — is largely prose guidance for a human/agent to interpret, not a uniformly executable script, unlike the 179 `architecture_checks` scripts built in Phase 4. This meant `functional_success` (and therefore the primary metric, Dangerous Success) could not yet be computed automatically for arbitrary real agent output at the scale of 800 runs.

**Action taken:** Phase 4.5 built one standalone, executable functional validator per task (`tasks/R0X/validators/task_Y_functional.sh`, 40 total, plus fixture test files), mirroring Phase 4's architecture-validator rigor. Each is designed to be **implementation-agnostic**: it exercises the feature through a stable, real public entry point (an existing exported function/class/API any correct solution must go through), not internal helper names specific to one candidate's code structure — because these scripts will later score many structurally different real AI-agent solutions to the same task, not just the Phase 5 reference implementations. Each was verified against both the existing positive and negative control diffs.

**Notable outcome — several validators turned out stricter than Phase 5's narrower checks**: for multiple tasks (e.g. R02 Tasks A/B/C, R05 Tasks A/B/C), the new black-box functional test correctly FAILs the negative control functionally, not just architecturally — because Phase 5's original functional check often only re-ran the trap's own narrowly-scoped test file, which the trap author naturally wrote to pass. A true black-box test against the task's real functional requirements is a strictly fairer, more rigorous measurement; this narrows the population of tasks where a "Dangerous Success" (functional pass + architecture fail) is possible, which is a legitimate empirical finding, not a defect introduced by this phase.

**A genuine defect was also found and fixed**: R06 Task A's positive control (etcd empty-password rejection) turned out not to work end-to-end — see the correction note in `tasks/R06/CONTROL_RESULTS.md`. `EtcdServer.UserAdd` unconditionally bcrypt-hashes the password before the store-layer emptiness check ever runs, so a real client's empty password was silently accepted despite Phase 5's unit tests (which called the store layer directly, bypassing the bug) reporting success. Fixed by adding the check in `server/etcdserver/v3_server.go` before hashing; re-verified clean against both the new functional validator and all 5 existing architecture checks; `controls/task_A_positive.diff` updated in place (not silently — the original CONTROL_RESULTS.md text is preserved with a dated correction appended, not edited away).

**Operational notes from the R01 (freqtrade) validation run**, carried forward to the remaining 9 repositories:
- In at least one subagent session, the Skill tool / `/goga:apply` slash command did not reliably auto-invoke despite `goga connect claude` having run; the fallback is to read `goga-apply`'s and `goga-cells-by-brainstorm`'s `SKILL.md` files directly and follow their materialization procedure by hand (parse `docs/arch/<topic>.md`, write each cell's `CODEMANIFEST` to its real path). This is acceptable because `goga lint` and `goga contract` — not the invocation mechanism — are what actually validate the output is genuine, schema-valid Goga content.
- CODEMANIFEST `Imports.From` paths resolve relative to the project/repo root, not relative to the importing cell's own directory — a real source of avoidable `goga lint` failures if assumed otherwise.
- Backtick cross-references in DSL prose (`` `Name` ``) are only valid for real link targets (imported or declared type names) — using them for arbitrary method names, CLI flags, or wildcards produces lint errors.
- Writing the full multi-cell plan document as one enormous single `Write` call correlated with repeated "connection closed mid-response" transport failures (3 consecutive occurrences on the same step for R01). The working mitigation: write the plan's skeleton (Topic/Implementation Order/Dependency Map/Verification Checklist) in one `Write`, then append each cell's CODEMANIFEST content via separate `Edit` calls, one cell at a time.

### Amendment 3 (Phase 10, first real execution tests) — harness fixes found by actually running it

Before scaling to the full 800 runs, the execution harness (`scripts/execute_run.py`) was tested against one real, live `claude -p` run (`R03-TC-G-07`). This surfaced four real bugs, all fixed and re-verified before proceeding:

1. **27 validator scripts (mostly R03, a few R09) checked `[ -d "$REPO/.git" ]` to confirm they were pointed at a git repository.** This is true for a normal clone but false for a `git worktree` — there, `.git` is a *file* containing a `gitdir:` pointer, not a directory. Every one of these scripts silently FAILed on every worktree-based run. Fixed by switching to `git -C "$REPO" rev-parse --is-inside-work-tree`, matching the convention most other validator scripts already used.
2. **The harness's own `git diff` (no flags) only captures changes to already-tracked files** — it misses new untracked files entirely, which is the norm, not the exception, for real coding tasks (e.g. a whole new demo directory). Fixed by staging everything (`git add -A`) before diffing (`git diff --cached`), and — since the Goga condition's CODEMANIFEST overlay is now committed as its own throwaway commit immediately after `git worktree add` and before the agent ever runs — this diff naturally isolates the agent's own contribution from the treatment artifacts, with no extra filtering needed.
3. **The harness's PASS/FAIL parser used `output.startswith("PASS")`.** Validator scripts print diagnostic output before their final verdict line, and that diagnostic output routinely contains the substring "PASS" in context (e.g. quoting a found class name) before the real verdict ever appears — silently misclassifying real PASSes as FAILs. Fixed by scanning from the *last* line of output for the actual verdict marker.
4. **Git worktrees do not share `node_modules`/`.venv`/`Pods`** (only `.git` objects/refs are shared) — every fresh worktree started with none of these installed, breaking any test/build step. Re-installing per run (800 times) is both far too slow and, for large repos, disk-prohibitive on this machine. Fixed by hard-link-copying (`cp -al`) any such directory already present in the shared base clone into each fresh worktree — near-zero extra disk cost, since `cp -al` shares the underlying file data via hardlinks rather than duplicating it, and safely diverges per-worktree the moment either side replaces (rather than in-place-truncates) a file, which is how package managers normally update files.

Also found and disclosed (not fixed further, judged not worth deeper investment): R03 Task C's functional-check discovery script initially only recognized `integration/*/src/` as a valid location for a new demo app; broadened to also accept `sample/*/src/` (both are genuine, real conventions in the actual nestjs/nest repository). A remaining, narrower discovery heuristic (detecting a specific protected/unprotected `@Get`-route pairing) did not fire for this particular real agent solution's exact structure — documented as a residual implementation-agnosticism gap in `tasks/R03/FUNCTIONAL_VALIDATORS.md` rather than chased indefinitely; any run hitting it is visible as `functional_success=False` with full diagnostic output preserved for manual review, not a silently wrong verdict.

### Amendment 4 (Phase 10, mid-batch, ~325/800 runs attempted) — base clones destroyed by macOS's periodic `/tmp` cleanup, relocated

The 10 base clones (`BASE_CLONES` in `scripts/execute_run.py`) originally lived under `/tmp/benchmark-repos/`. The full unattended batch run spans multiple days; macOS's periodic daily maintenance job silently deletes any file under `/tmp` that has gone untouched for roughly 3 days, regardless of the containing directory's own activity. Partway through the batch this stripped the *regular files* out of all 10 `.git` directories — `HEAD`, `config`, `packed-refs`, `index`, and (for files that had not been re-read/rewritten since the initial clone) most of `.git/objects` itself — while leaving the now-empty subdirectory skeleton (`objects/`, `refs/`, `hooks/`, `info/`, `logs/`) in place, which is why the corruption surfaced as `fatal: not a git repository` rather than a missing directory. Working-tree source files mostly survived, because validators/build steps kept re-touching their mtimes; the git object database mostly did not, because git rarely rewrites an existing object file. This is a genuine infrastructure failure, not a logic bug in the harness: `git worktree add` against a base clone in this state fails immediately (`exit 128`), so every run scheduled against an affected repository after the corruption point recorded a spurious `INVALID` row. Diagnosed by checking `git -C <base_clone> rev-parse HEAD` directly against all 10 base clones: all 10 had lost their `.git` internals (confirmed via `uptime`, no reboot occurred — this was the periodic-cleanup mechanism, not a restart clearing `/tmp`).

**Fix:** relocated `SCRATCH_ROOT` and all `BASE_CLONES` entries from `/tmp/benchmark-repos` / `/tmp/benchmark-runs` to a new persistent location outside `/tmp` entirely (`<repo-parent>/benchmark-scratch/{repos,runs}/`), which is not subject to this cleanup policy. All 10 base clones were re-created from scratch via `scripts/reclone_base_repos.sh` (shallow `git fetch --depth 1 origin <pinned_commit>`, one commit's tree only, no history — verified against the exact commit SHAs in `repos.yaml`/`COMMITS`), and per-repo dependency directories (`.venv` for R01/R02, `node_modules` for R03/R04, `Pods` for R10) were reinstalled from the repository's own documented `build_command` before resuming execution. Every `run_number` whose only recorded row is this kind of `INVALID` (git-worktree-add failure against a corrupted base clone) is being re-run as a `-RETRYn` replacement per the existing PROTOCOL.md §15 mechanism — the original `INVALID` rows are kept in `results/runs.csv`, not deleted, consistent with the project's own "never silently discard a record" rule.

### Amendment 5 (post-Phase-12, while designing Experiment B/C) — Goga skills/CLI were globally, not per-worktree, connected on the execution machine for the entire 800-run study

While researching how to build a new "live Goga workflow" condition (`TREATMENT_DESIGN_EXPERIMENT_B.md`), it was discovered that `goga connect claude` (run once, in Phase 8, on 2026-08-26, to prepare the CODEMANIFEST forest) installs **globally, machine-wide** — Goga's own documentation (`goga/connect/.usages/connect-usage.md` in the `qarium/goga` package) confirms `~/.goga/` is "the single source of truth" and `connect()` symlinks its skills/commands into the real, shared `~/.claude/skills`/`~/.claude/commands` — not into any per-project or per-worktree location. These symlinks were still present and dated 2026-08-26 when discovered. Separately, `scripts/execute_run.py`'s `build_env()` unconditionally prepends `~/.local/bin` (where `pipx` installed the `goga` executable) to every run's `PATH`, for both conditions. Together, this means the `goga` CLI binary and every `goga-*` Skill's presence in the agent's available-skills list were **not actually condition-specific** during the entire 800-run study (2026-08-28 to 2026-09-10) — they were ambiently available in **both** Condition A (Baseline) and Condition B, contradicting `TREATMENT_DESIGN.md` §2's explicit "Explicitly not included in Condition B" list (which itself only discussed Condition B, and implicitly assumed Baseline had no Goga exposure at all as the unstated default).

**Severity check performed:** `.goga/config.yml` is mandatory for every `goga` CLI subcommand (`load_project_config()` raises `FileNotFoundError` if it's absent — confirmed by reading `goga/config/project/.usages/*.md`), and no worktree in either Condition A or Condition B ever had this file, so any actual `goga <command>` invocation would fail immediately with a clear, harmless error — it could not have produced a working tool. To check for *any* observable trace of this ambient availability actually influencing agent behavior, every one of the 800 `runs/<run_id>/agent.log` files (the final JSON summary from `claude -p --output-format json` — the full turn-by-turn tool-use transcript was never separately preserved, so this check is a lower bound, not exhaustive) was grepped case-insensitively for "goga":
- **0 of 400 Baseline (`-B-`) runs** contain the word "goga" anywhere in their final summary text.
- **14 of 400 Condition-B (`-G-`) runs** contain it — inspected individually, every occurrence is either the agent quoting/discussing the vocabulary of the CODEMANIFEST/`ARCHITECTURE_CONTRACTS.md` files it was deliberately given as the treatment (e.g. `"usages": []` from a cell's contract, `.goga/config.yml` being *absent*), or the agent narrating awareness of a named Goga pipeline concept (`goga-change`, `goga-change-tracer`) in its own planning prose — consistent with the model's general training-data knowledge of the real, public `qarium/goga` project surfacing in reasoning text, not with any local skill/CLI actually being invoked. No `bash`/tool-use command string matching `goga <subcommand>` was found in any of the 14 files.

**Conclusion:** no evidence of the ambient global Goga installation having actually altered any of the 800 runs' behavior was found in the available data; the original `results/` outputs are not corrected or re-run. This is nonetheless logged as a genuine, previously-undisclosed environmental-isolation gap relative to `TREATMENT_DESIGN.md`'s stated design — a threat to validity, not a data integrity failure — and is carried into the final report's threats-to-validity section. **Fix, applied going forward for the new Experiment B/C harness (`scripts/execute_run_b.py`)**: Claude Code has no per-project skill directory — skills always load from the single, global `~/.claude/skills` — so the only two real, verifiable levers are (a) `PATH` (controls whether the `goga` binary itself resolves to anything) and (b) the `claude -p ... --disable-slash-commands` flag (disables all skills outright for that invocation, confirmed via `claude --help`). `build_env()` no longer unconditionally adds `~/.local/bin` to `PATH` for every condition; it is added only for the new condition that deliberately requires live Goga tooling (Condition B′). Should Baseline or the original static-docs Condition B ever need to be re-run in the future (they are not being re-run now — see `TREATMENT_DESIGN_EXPERIMENT_B.md` §2), `--disable-slash-commands` should be added to their invocation for a hard guarantee, closing even the theoretical gap this amendment describes.
