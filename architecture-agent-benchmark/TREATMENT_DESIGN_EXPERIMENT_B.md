# TREATMENT_DESIGN_EXPERIMENT_B.md

## Why this document exists

`TREATMENT_DESIGN.md` (Phase 0) deliberately rejected "Experiment B" (the full Goga SDD
workflow, and — a fortiori — a fully cell-restructured codebase) as the *primary* 800-run
design, because it confounds workflow/tooling/format into one variable and cannot support the
narrow causal claim "machine-readable architecture caused the improvement." That decision
stands unchanged for the original 800-run sample (`results/`).

The user has now explicitly asked for Experiment B to be run anyway, as an **additional,
separately-reported study** — not pooled with the original 800 runs — to get a more complete
picture: "as-is" vs "static architecture docs" (already done) vs "live Goga workflow" vs "fully
Goga-native codebase." This document defines that additional study precisely, following the
same rigor rules as `PROTOCOL.md` (clean-room execution, no manual rescue, raw data preserved,
disclosed limitations) so its results are as trustworthy as the original sample, while being
explicit that **this is a different, more confounded experiment whose findings must never be
silently merged with the primary Dangerous-Success-Rate result.**

Research basis: fresh research against `qarium/goga` branch `1.3.x` (commit `9fdb39b19...`,
2026-09-12), which is spec-identical to the originally-pinned `v1.2.2` for everything relevant
here (`docs/cell/codemanifest.md` and `docs/cell/usages.md` are byte-for-byte unchanged between
the two; only new internal-maintainer AST docs were added). Findings below cite exact file paths
in that repository.

## 1. Two new conditions, not one

The user's "пункт 2" and "пункт 3" are genuinely different treatments and are kept as two
separate conditions rather than folded together:

### Condition B′ — Goga Full Workflow (live tool use during task-solving)

Same repository, same pinned commit, same task prompt, same model, same timeout/budget as
Condition A/B, **plus**:
- The repository already carries the frozen `CODEMANIFEST` forest from Condition B (Phase 8) —
  B′ is a superset of B, not a replacement for it, so the comparison ladder A → B → B′ is
  monotonic in "how much Goga is present."
- `goga connect claude` is run in that worktree before the agent starts, making the full Goga
  CLI (`goga schema/lint/build/contract/...`) and all `goga-*` skills available.
- The task prompt gets one added sentence, identical in wording across all 40 tasks: *"This
  repository has Goga tooling and skills available (already connected) if you find them useful
  for this task."* The agent is not instructed to use them — whether it chooses to invoke
  `brainstorm`/`apply`/`design`/`plan`/`build` at all, and how far through that pipeline it gets
  within the same 3600s/$8 budget, is itself part of what's measured (a realistic "developer who
  has the tool installed" scenario, not a forced workflow).
- Everything else (clean-room worktree, no manual rescue, timeout, budget) is identical to
  Condition A/B per `PROTOCOL.md` §9-§12.

This is squarely what `TREATMENT_DESIGN.md` §6 called "a legitimate, separate research
question" and explicitly scoped out of the primary study.

### Condition C — Goga-Native Architecture (real cell restructuring)

Per the 1.3.x research (see chat record for full citations — `docs/cell/index.md`,
`docs/cell/codemanifest.md`, `goga/assets/skills/goga-brainstorm-cell-distribution/SKILL.md`,
`docs/workflow/{brainstorm,apply,change}.md`): Goga has **no bulk/brownfield migration tool**.
`brainstorm→apply` is a one-subtask-at-a-time pipeline with mandatory human `WAIT`/`STOP` gates
at nearly every phase; `apply` writes only `CODEMANIFEST`/`.usages/`, never source code; actual
code motion happens only via a generic coding agent inside `design→plan→build`. Two hard
constraints bite at scale: cells cannot have subdirectories (`location` must sit beside
CODEMANIFEST), and cells cannot have cyclic `Imports` — real, already-existing repositories very
likely have coupling that violates this and must be manually untangled first.

**Scope decision (bounds an otherwise unbounded task):** Condition C restructures exactly the
same architectural "spine" already identified and scoped in Phase 8 (`architecture/<repo_id>/
SCOPE.md` — the same ~92 cells/9,524 lines of CODEMANIFEST across all 10 repos), not the entire
repository. This is a deliberate parallel to how Condition B's static docs were scoped, so B and
C differ only in *treatment intensity over the same architectural surface* (described vs.
actually restructured), not in *scope*. Code outside that spine is left untouched in both
conditions, and this boundary is disclosed identically to both.

**Process per spine component, using Goga's real, unmodified pipeline (not an invented
shortcut):**
1. `goga brainstorm`, run against the real pinned-commit clone, scoped to that one spine
   component (mirrors "one subtask at a time" as the pipeline requires) — Intake → Context →
   Primary Analysis → Type Map → Type Detailing → Cell Distribution → Contracts → Cell Assembly
   → Plan Assembly → Plan Verification, with the orchestrating session (this Claude Code
   session) acting as the human approver at every `WAIT`/`STOP` gate, grounded in the real
   existing code (not invented from scratch, since the code already exists) — this differs from
   ordinary greenfield brainstorming only in that "what should this cell do" is answered by
   reading the existing implementation rather than proposing a new one.
2. Any pre-existing circular dependency the Cell Distribution phase's cycle check surfaces is
   resolved by the minimal real refactor needed to break the cycle (e.g. extracting a shared
   interface/lower cell) — logged per-repo in a new `architecture_v2/<repo_id>/CYCLE_FIXES.md`,
   since this is real, disclosed architectural surgery, not free of behavior-preserving risk.
3. `goga apply` materializes the approved plan's `CODEMANIFEST`/`.usages/` skeletons on disk.
4. `design → plan → build` (or, where `build`'s containerized generic-agent loop proves
   impractical for a given language/toolchain, a direct careful implementation pass by this
   session against the same approved plan — disclosed per repo if used) physically moves/rewrites
   the existing source into the new flat per-cell layout and updates the facade
   (`__init__.py`/equivalent) per `goga-cell-<language>` rules.
5. **Hard gate before freezing the new commit**: the repository's own existing build and test
   suite (the same `build_command`/`test_command` from `repos.yaml`) must still pass after
   restructuring. If it cannot be made to pass within a reasonable, disclosed effort, that
   repository's Condition C arm is marked **excluded, with reasons**, in
   `architecture_v2/<repo_id>/RESTRUCTURE_REPORT.md` rather than silently forced through — this
   is the single most likely source of a partial-coverage outcome for this experiment, is
   anticipated in advance, and is not a failure of the study, just a real, disclosed constraint
   of applying Goga's cell model to a large pre-existing codebase.
6. **Validator re-certification** (mirrors Phase 5's rigor): once a repo's restructured commit
   is frozen, re-run that repo's existing positive/negative controls
   (`tasks/R0X/controls/*.diff`) against the new commit. Any architecture validator
   (`task_Y_AC*.sh`) that hardcodes a now-stale file path is fixed and the fix is logged (same
   "amendment" discipline as `PROTOCOL.md`), since functional validators should mostly be
   unaffected (Phase 4.5 design goal was implementation-agnostic checks against stable public
   entry points) but architecture validators frequently do check specific file locations.
7. The restructured commit is frozen (git-tagged per repo) and used as Condition C's base commit
   in a new `experiment_plan_b.csv`, generated the same way as the original (fixed seed,
   documented) — never mixed into the original `experiment_plan.csv`.

## 2. What is NOT changed from the original protocol

- Model, timeout (3600s), per-run budget ($8), `--permission-mode bypassPermissions
  --no-session-persistence`, clean-room worktree-per-run, no manual rescue, raw-artifact
  preservation, replacement-run-on-infrastructure-failure (`-RETRYn`, original never deleted) —
  all identical to `PROTOCOL.md` §9-§16.
- Same 4 tasks per repository, same wording, same ground truth intent — Condition C's tasks are
  the *same* task prompts, now solved against a different (restructured) starting commit. (One
  disclosed nuance: a task prompt written against the original file layout may reference behavior
  near a spine component that has moved — task prompts describe *behavior*, not file paths, per
  the original Phase 3 design rule, so this is not expected to require rewriting the 40 task
  prompts themselves, but is explicitly re-checked per repository during Condition C prep.)
- Repetitions: kept at **10 per cell**, matching the original design, for the same
  variance/stability reasoning in `PROTOCOL.md` §13 — no shortcut to fewer reps.
- Baseline (Condition A) is **not re-run**: the existing 400 Condition-A rows in
  `results/runs.csv` are reused as the comparison group for both B′ and C. This is a disclosed
  design choice, not an oversight — re-running Baseline would cost another ~$1,300 for no new
  information, since Condition A is untouched by any of this. The one threat this introduces
  (temporal drift / possible model behavior drift between the original Baseline runs, executed
  2026-08-28 to 2026-09-10, and B′/C runs executed later) is logged explicitly in the eventual
  report's threats-to-validity section rather than ignored.

## 3. Reporting boundary (repeating `TREATMENT_DESIGN.md` §6's rule, now that it applies)

Results from B′ and C answer *different* questions than the primary study and must be reported
as such, never pooled into the primary Dangerous-Success-Rate comparison:
- Primary study (A vs B): "does a frozen, machine-readable architecture *description* change
  outcomes, with everything else held constant?"
- B′: "does an agent, given access to Goga's live tooling/workflow, choose to use it, and does
  outcome change when it does?" — confounds workflow+tooling+format, exactly as
  `TREATMENT_DESIGN.md` §1 originally flagged; that confound is now accepted deliberately, not
  discovered by accident.
- C: "does a codebase whose architecture is *actually* Goga-cell-native (not just described)
  change outcomes?" — confounds format+actual structure+(likely) the disruption/benefit of the
  restructuring itself; also cannot separate "cells specifically helped" from "*any* clean,
  well-decomposed module boundary would have helped equally."

## 4. Scale and cost estimate (for explicit sign-off before starting restructuring)

- **B′ execution**: 40 tasks × 10 reps = 400 new runs. Expected cost similar to or somewhat
  above the original per-run average ($3.23 mean, $2.69 median) since agents that engage Goga's
  multi-stage pipeline mid-task will likely use more turns/tokens before writing any code —
  rough estimate **$1,500-$3,500** total, plus the same multi-day wall-clock reality as the
  original 800 runs (rate limits, transport errors, disk exhaustion all apply identically).
- **C restructuring** (one-time cost per repo, before any of C's 400 runs): running
  `brainstorm→apply→design→plan→build` once per spine component (~92 components across 10
  repos, per Phase 8's existing scope) is a materially larger, harder-to-bound cost than
  anything done so far in this project — each component needs several agent turns across a
  10-phase pipeline with human-gate round-trips, plus cycle-untangling work of unpredictable
  size, plus the hard build/test gate potentially requiring multiple fix-and-retry passes.
  Rough order of magnitude: **$4,000-$15,000+** in agent cost alone across all 10 repos, spread
  over what is realistically **several weeks**, with a real (not hypothetical) chance that 1-3
  of the largest/most-coupled repositories (candidates: Signal-Android 371.9k LOC, Signal-iOS
  548.0k LOC, salt 275.5k LOC) cannot be cleanly restructured within reasonable effort and end up
  excluded per §1 step 5's disclosed-exclusion rule rather than forced through.
- **C execution** (after restructuring): another 400 runs, similar cost profile to B′, **roughly
  $1,500-$3,500**.
- **Combined rough total for both new conditions: ~$7,000-$22,000 in API cost**, on top of the
  original $2,584 already spent, plus a multi-week timeline dominated by the C restructuring
  step. This is an order-of-magnitude jump from the original study's cost and is the reason this
  document stops here for explicit confirmation rather than proceeding straight into
  restructuring, mirroring the same checkpoint discipline used before the original 800-run batch
  was started.
