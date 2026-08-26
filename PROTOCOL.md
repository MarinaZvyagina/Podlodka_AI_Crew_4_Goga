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

(none yet — this section is appended to, never edited in place, for any change made after the `benchmark-v1` freeze)
