# Does Machine-Readable Architecture Help AI Coding Agents?

**A benchmark study of Claude Code against 10 large, real, pre-existing open-source codebases,
prepared for a Podlodka AI Crew 2026 conference talk.**

Status: primary study frozen and complete (Phases 0-13); this document is Phase 14. Extended
study (Experiment B: Conditions B′, B″, C) complete through execution and reported here
descriptively, per its own explicit non-pooling rule (`TREATMENT_DESIGN_EXPERIMENT_B.md` §3).

A note on this report's provenance: `PROTOCOL.md` and `STATUS.md` frequently cite a `Research.md`
document (e.g. "`Research.md` §35-45", "`Research.md` §53", "`Research.md` §65", "`Research.md`
§68") as the source of the original research questions, full metrics schema, and threats-to-
validity list. That file does not exist anywhere in this repository or its git history — its
content appears to have been fully absorbed into `PROTOCOL.md` (research questions, Section 1),
`experiment.yaml` (the metrics schema, per `results/METRICS_COVERAGE.md`'s own note), and the
preliminary threats-to-validity list reproduced in `PROTOCOL.md` §20, rather than ever existing
as a standalone committed artifact. This report is therefore structured from `PROTOCOL.md`
directly (the actually-frozen, actually-committed protocol) rather than from the uncommitted
`Research.md`, and this gap is disclosed here rather than silently papered over.

---

## 1. Research question

When an AI coding agent (Claude Code) is asked to modify a large, pre-existing codebase it has
never seen before, does giving it a **machine-readable architecture representation** — Goga's
`CODEMANIFEST` cell model — make it more likely to produce a change that is *both* functionally
correct *and* architecturally conformant, rather than a **Dangerous Success** (works, but violates
the codebase's real architectural boundaries in a way that will bite later)?

The original twelve research questions (`PROTOCOL.md` §1, RQ1-RQ12) are broader than this single
headline question — they also ask about run-to-run stability, architectural decision consistency,
extension-point usage, architecture discovery cost, and how any effect depends on task type,
repository size, and documentation quality. This report answers what the executed data can
actually support (primarily RQ1-RQ4, RQ9 descriptively; see `results/METRICS_COVERAGE.md` and
§10 below for which of the original wishlist metrics were never instrumented and why).

## 2. Why this design, not a simpler one

An earlier design (`TREATMENT_DESIGN.md`, considered and rejected as the *primary* design)
proposed giving the agent Goga's entire workflow — `brainstorm` → `apply` → `design` → `plan` →
`build`, its skills, its slash commands, its own validation pipeline. That confounds four things
at once (interaction protocol, prompt set, tool access, validation process) into a single "Goga
condition": any resulting effect would only support the weak claim *"the Goga workflow produced a
different result,"* never the precise claim *"machine-readable architecture caused the
improvement."*

The primary study instead isolates **one variable**: the presence of a frozen, machine-readable
`CODEMANIFEST` architecture description, added to the repository as ordinary files, with
*nothing else* different — same prompt (modulo one pointer-file mention), same tools, same
single-session protocol, same everything else. This is deliberately the narrowest, most
defensible causal claim the study can support:

> **H (primary):** When a large existing repository is annotated with a frozen, Goga-format
> (`CODEMANIFEST`) machine-readable architecture representation covering its main structural
> boundaries, does a Claude Code agent — working under an otherwise identical single-session
> protocol, prompt, and toolset — produce (a) more architecturally conformant and (b) more
> run-to-run-stable changes than the same agent working from the repository's existing
> documentation alone? (`TREATMENT_DESIGN.md` §3)

The full-workflow design was not discarded, only descoped to a separate, explicitly-confounded
follow-up (Experiment B, §9 below), run only after the primary study froze.

## 3. Repositories

Ten large, real, pre-existing open-source codebases, two per language across five languages,
selected before any task was designed (`REPOSITORY_SELECTION.md`, criteria fixed before any
candidate was evaluated):

| Repo | Project | Language | Production LOC |
|---|---|---|---|
| R01 | freqtrade | Python | 44.8k |
| R02 | salt | Python | 275.5k |
| R03 | nestjs (nest) | TypeScript | 34.7k |
| R04 | excalidraw | TypeScript | 106.5k |
| R05 | VictoriaMetrics | Go | 120.1k |
| R06 | etcd | Go | 62.3k |
| R07 | mihon | Kotlin | 77.4k |
| R08 | Signal-Android | Kotlin/Java | 371.9k |
| R09 | firefox-ios | Swift | 245.2k |
| R10 | Signal-iOS | Swift | 548.0k |

Two repositories (R01, R05) were deliberately chosen as poorly-documented, expected to benefit
most from an architecture description; two (R02, R09) as already well-documented, expected to
benefit least — an informative contrast, not a random sample.

## 4. Tasks, validators, and controls

**4 tasks per repository (40 total)**, each grounded in real, cited code at the pinned commit —
never invented:

- **Task A — Local Change**: a small, contained modification.
- **Task B — Cross-Module Feature**: a feature genuinely touching ≥3 architectural boundaries.
- **Task C — Existing Extension Point**: exercising a real, designed extensibility mechanism the
  codebase already has.
- **Task D — Architecture Trap**: a task solvable two ways — one that respects the codebase's
  real architectural boundaries, one that "works" but violates them (the trap).

Each task has one **functional validator** (does it work? — a standalone, implementation-agnostic
executable check exercising a stable public entry point, `tasks/R0X/validators/task_Y_functional.sh`,
40 total) and **≥3 architecture-conformance validators** (does it respect the boundaries? — 179
scripts total). Every one of the 40 tasks was confirmed discriminating (`tasks/R0X/CONTROL_RESULTS.md`)
against a real positive control (correct solution: passes functional + all architecture checks)
and a real negative control (the trap: passes functional, fails ≥1 architecture check) — 40/40
tasks, 80 real diffs, several confirmed via genuine test/build execution rather than static review
(e.g. R04 Task D's trap measurably breaks undo; R06 Task B's trap triggers a real etcd server
panic; R08 Task D's trap is proven to return stale search results).

One genuine defect was found and fixed during this phase: R06 Task A's original positive control
did not actually work end-to-end (`EtcdServer.UserAdd` bcrypt-hashes an empty password into a
valid, non-empty hash *before* the store-layer emptiness check ever runs — invisible to a direct
unit-level call, only caught by a real black-box gRPC-level test). Fixed in
`server/etcdserver/v3_server.go`, re-verified clean; documented as `PROTOCOL.md` Amendment 2 and
a dated correction in `tasks/R06/CONTROL_RESULTS.md`, not silently edited away.

## 5. Conditions (primary study)

- **Condition A (Baseline)**: the repository exactly as it exists — source, README, tests,
  comments. Nothing added.
- **Condition B (Goga)**: identical everything, *plus* a frozen forest of `CODEMANIFEST` files
  covering the codebase's architectural "spine" (92 files, 9,524 lines across the 10 repos) and
  one short pointer file explaining the format. No live `goga` CLI, no skills, no workflow change
  — purely a documentation artifact the agent can read like any other repository file.

Materializing this forest required a real, disclosed protocol amendment: `goga-brainstorm`, the
skill `TREATMENT_DESIGN.md` originally assumed would generate it, turned out (once actually
invoked) to be a strictly interactive, one-question-at-a-time human-dialogue skill that explicitly
instructs the agent not to read implementation source code — structurally incapable of
autonomously documenting an existing codebase. The adapted, logged method: author
`docs/arch/<topic>.md` directly (grounded in real source reading, using the same DSL-rule skills),
then run the real `goga-apply` mechanism against it exactly as designed (`PROTOCOL.md` Amendment
1). The output artifact and its validation (`goga lint`, `goga contract`) are unaffected; only the
input-authoring step changed. One repository (R04/excalidraw) has below-target cell coverage (5 of
a planned 10 cells) after repeated infrastructure transport failures, disclosed in its own
`SCOPE.md`, decided before any task prompt was read.

## 6. Protocol

- **Clean-room execution**: fresh git worktree per run, exact pinned commit, no conversational
  memory, no prior diffs, no accumulated notes between repetitions.
- **No manual rescue**: every run is a single non-interactive `claude -p <prompt>
  --permission-mode bypassPermissions --no-session-persistence` call with no channel for a human
  to inject a hint mid-run.
- **Timeout**: 3600s per run; **budget ceiling**: `--max-budget-usd 8` per run.
- **Randomization**: seed 42, Baseline↔Goga order blocked-randomized per pair, overall execution
  order shuffled to prevent temporal drift confounding condition.
- **Model**: `claude-sonnet-5`, pinned for the entire primary study.

## 7. Primary metric

**Dangerous Success** = `functional_success == true AND full_architecture_conformance == false`
(`PROTOCOL.md` §18) — reported as **Dangerous Success Rate** per condition. Lower is better.

## 8. Execution and data integrity

**800 runs** (10 repos × 4 tasks × 2 conditions × 10 repetitions), executed over ~11 days
(2026-08-28 to 2026-09-10). **800/800 valid** — every infrastructure failure along the way
received a `-RETRYn` replacement run under a new ID; original failed rows were kept, never
deleted (`PROTOCOL.md` §15). Total spend: **$2,584.04** (mean $3.23/run, median $2.69/run).

Two real infrastructure incidents occurred and are disclosed in full (`PROTOCOL.md` Amendment 4,
`STATUS.md` "Phase 10 process notes"), both fixed without discarding any data:

- **Base-clone corruption via macOS's periodic `/tmp` cleanup**: macOS silently deletes files
  untouched for ~3 days anywhere under `/tmp`; across the multi-day unattended run this stripped
  the `.git` internals out of all 10 base clones mid-batch, producing ~650 spurious `INVALID`
  rows before diagnosis. Fixed by relocating all base clones and scratch worktrees outside `/tmp`
  entirely; every affected run re-executed as a `-RETRYn` replacement.
- **Disk exhaustion causing a >2-day hung subprocess**: Xcode DerivedData and Go's build cache
  independently regrew to 15-25GB, once causing a `claude -p` subprocess to hang in
  uninterruptible I/O-wait — its own 3600s timeout never fired because the process was blocked in
  the kernel. Fixed by extending automatic cache-clearing to Go's build cache and raising the
  harness's disk-space floor from 6GB to 10GB.

A further, later-discovered environmental-isolation gap (`PROTOCOL.md` Amendment 5): `goga connect
claude` (run once in Phase 8 to prepare the treatment) installs its skills/CLI **globally**, not
per-project — meaning the `goga` binary and every `goga-*` skill were ambiently available in
*both* Condition A and Condition B for the entire primary study, contradicting the design's stated
isolation. A full grep of all 800 `agent.log` summaries for "goga" found 0/400 Baseline mentions
and 14/400 Condition-B mentions, every one of which is the agent discussing the vocabulary of the
CODEMANIFEST files it was deliberately given (the treatment itself), not evidence of any tool
actually being invoked — no `goga <subcommand>` command string appears in any of the 14. No
evidence this altered behavior was found; the data was not re-run; this remains a disclosed threat
to validity (§13 below), not a data-integrity failure.

Validation (`results/VALIDATION_REPORT.md`, Phase 11): 800/800 `experiment_plan.csv` rows resolved
to exactly one usable VALID row, 0 problems found (no duplicates, no cross-field mismatches, no
out-of-range values, `dangerous_success` logic cross-checked against its own definition on every
row).

## 9. Primary study results

### 9.1 Descriptive summary

| Metric | Baseline | Goga | Delta (Goga − Baseline) |
|---|---|---|---|
| Dangerous Success Rate | 0.293 | 0.283 | −0.010 |
| Functional Success Rate | 0.480 | 0.440 | −0.040 |
| Full Architecture Conformance Rate | 0.2975 | 0.240 | −0.058 |
| Architecture Conformance Rate (ACR, continuous) | 0.668 | 0.627 | −0.041 |
| Cost per run | $3.207 | $3.254 | +$0.047 |
| Duration per run | 489.2s | 508.2s | +19.0s |
| Agent turns per run | 56.7 | 58.4 | +1.7 |

(All rows computed at the 40-cell paired level — 10 repetitions aggregated into one rate/mean per
`repository × task × condition` — never pooled naively across the 800 raw runs; see
`results/cells.csv` / `results/task_comparison.csv`.)

**Correction (2026-09-22)**: the R01 Task A functional validator was found, via a user manually
reproducing one run by hand, to be systematically too narrow — it recognized only one of two
implementation styles the task itself explicitly allows, and (for a second, more specific reason)
couldn't validate implementations that correctly checked freqtrade's real `original_config` field
to avoid a schema-default false positive. Fixed and all 20 real R01-TA runs (Baseline + Goga)
re-verified by reconstructing each run's worktree from its preserved `git.diff` and re-running the
corrected validator; full details and the corrected per-run table are in
`tasks/R01/FUNCTIONAL_VALIDATORS.md`'s "Correction" section. The numbers in this report already
reflect the correction (R01-TA moved from a 0.0/0.0 tied cell to Baseline 0.4 / Goga 0.3 on
functional success, and Baseline 0.1 / Goga 0.3 on dangerous success) — this is the only cell,
of 40, corrected this way; the other 39 were not re-audited and no similar defect is confirmed or
assumed elsewhere.

### 9.2 Formal statistical analysis (Phase 13)

Full methodology, all test statistics, per-task-type breakdowns, and a multiple-comparisons
caveat are in `results/PHASE13_STATISTICAL_ANALYSIS.md`, reproducible via
`scripts/statistical_analysis.py`. Headline:

**On the primary, pre-registered metric (Dangerous Success Rate) alone, there is no statistically
significant difference between Baseline and Goga** at n=40 paired task-level cells: mean delta
−0.010, 95% bootstrap CI [−0.043, +0.020] (includes zero), Wilcoxon signed-rank p=0.69, paired
t-test p=0.54.

**This flat headline number is not the whole story, and should not be read on its own.** Both
components of Dangerous Success moved in the *same*, negative direction under Goga, each
individually statistically significant across multiple independent tests:

- **Functional Success Rate**: delta −0.040, Wilcoxon p=0.022, paired t p=0.012, cluster-robust
  GEE logistic regression OR=0.85 (unadjusted, p=0.007) / OR=0.82 (adjusted for repository +
  task_type, p=0.008).
- **Full Architecture Conformance Rate**: delta −0.058, Wilcoxon p=0.031, GEE OR=0.75
  (unadjusted, p=0.048).
- **Architecture Conformance Rate (continuous)**: delta −0.041, Wilcoxon p=0.004, paired t
  p=0.014 — the strongest and most consistent secondary signal.

Because `dangerous_success = functional_success AND NOT full_architecture_conformance`, a drop in
functional success mechanically shrinks the pool of runs that could even *qualify* as a dangerous
success (functional success is a necessary precondition), while the architecture-conformance drop
alone would, on its own, have pushed Dangerous Success Rate *up*. **The two effects pull the
composite metric in opposite directions and largely cancel.** The honest headline is not "Goga
made no difference" — it is that, on this sample, giving the agent a static, frozen architecture
description was associated with the agent doing measurably worse on both functional correctness
and architecture conformance individually, and the one composite metric that looked flat is flat
because of how its two ingredients happen to cancel, not because nothing changed.

A plausible (untested by this design) mechanism: reading ~9,500 lines of `CODEMANIFEST` content
plus a pointer file consumes agent turns and context budget that would otherwise go toward the
task itself, without necessarily improving the agent's actual comprehension of the codebase —
consistent with the (individually non-significant, but directionally consistent) increases in
mean duration (+19.0s) and turns (+1.7) per run under Goga.

**Multiple-comparisons caveat**: seven metrics were tested (one pre-registered primary, six
secondary/exploratory), each with several companion tests, with no formal correction (e.g.
Bonferroni/Holm/FDR) applied. The secondary-metric p-values should be read as *coherent
exploratory evidence* for a single mechanistically-explicable pattern (functional success down,
architecture conformance down, in the same direction across Wilcoxon, sign test, paired t-test,
and cluster-robust GEE), not as independently-confirmed hypothesis tests. Effect sizes are also
small in absolute terms (delta magnitude ~0.04-0.06), and n=40 paired cells gives this design
limited power to detect true effects of that magnitude — this is a genuine limitation (§13), not
a claim that no true effect exists in either direction.

### 9.3 Per-task-type pattern

| Task type | Baseline DSR | Goga DSR | Delta | Baseline FSR | Goga FSR | Delta |
|---|---|---|---|---|---|---|
| A — Local Change | 0.39 | 0.39 | 0.00 | 0.70 | 0.68 | −0.02 |
| B — Cross-Module Feature | 0.24 | 0.19 | −0.05 | 0.26 | 0.22 | −0.04 |
| C — Existing Extension Point | 0.33 | 0.34 | +0.01 | 0.44 | 0.42 | −0.02 |
| D — Architecture Trap | 0.21 | 0.21 | 0.00 | 0.52 | 0.44 | −0.08 |

(n=10 cells per row — too small for a standalone test to be trustworthy on its own; the functional-
success drop is directionally consistent across all four task types, most pronounced on
Architecture Trap tasks, where the negative control is specifically designed to *look* plausible.)

### 9.4 A pilot-phase preview of why this study exists

Two independent pilot repetitions of the exact same task (R01-TA, freqtrade "reject conflicting
capital-sizing config"), same model, same repository, produced two *different* architectural
solutions to the same subtlety — one correct, one that empirically broke 4 existing tests
(confirmed via a real `pytest` run). Cost varied 3× across runs of the same task/repo
($0.73-$2.27). This instability, at n=2, is exactly what the 800-run study exists to measure
systematically rather than anecdotally (`pilot/PILOT_REPORT.md`).

## 10. Metrics actually captured vs. originally planned

`experiment.yaml`'s full planned metrics schema is aspirational; the executed harness did not
implement all of it. Fully disclosed in `results/METRICS_COVERAGE.md` rather than silently
presenting `results/cells.csv` as complete. **Captured**: functional/architecture correctness
rates, ACR, tokens, `tool_calls_num_turns` (Claude Code's own turn count, a proxy not a raw
tool-invocation count), `files_changed`, `duration_ms`, per-cell stability statistics
(mean/median/SD/IQR/min/max). **Not captured** (raw artifacts preserved per run — `git.diff`,
`git.status`, `agent.log`, `changed_files.txt` — so derivable in a follow-up pass without
re-running anything, but not parsed here): existing-test-regression sweep, granular
architecture-discovery-cost timing (files/searches/tokens before first edit), dominant-strategy
share, module-Jaccard stability, extension-point usage rate (task type C specifically), separate
build/test/validation timing. This is a real scope gap relative to the original plan (§13).

## 11. Extended study — Experiment B (not pooled with the primary result)

After the primary study froze, three additional, more confounded conditions were added at
explicit request and run as a **separate study**, reusing the exact same 40 tasks, validators, and
controls (only the treatment differs), per `TREATMENT_DESIGN_EXPERIMENT_B.md`'s explicit
non-pooling rule (§3 of that document): these answer *different* questions than the primary A-vs-B
comparison and must never be merged into it.

| Condition | What it tests | n valid | Functional Success Rate | Full Architecture Conformance Rate | Dangerous Success Rate | Total cost |
|---|---|---|---|---|---|---|
| B′ — Goga Full Workflow | Does an agent voluntarily use live Goga tooling ("available if useful"), and does outcome change when it does? | 91/400 (stopped by design) | 0.473 | 0.297 | 0.253 | $283.96 |
| B″ — Goga Forced Workflow | Same tooling, explicit instruction to use it | 400/400 | 0.233 | 0.120 | 0.168 | $1,065.28 |
| C — Goga-Native Architecture | Does a codebase whose *actual* structure is Goga-cell-native (not just described) change outcomes? | 400/400 | 0.367 | 0.195 | 0.242 | $1,164.05 |

*(These figures are the pooled Functional/Full-Architecture-Conformance/Dangerous-Success rates
across each condition's own 400 (or 91) runs. The formal, cell-paired statistical test against
Baseline follows immediately below.)*

**B′ (voluntary tool use) was stopped, not discarded, at 91/400** once it became clear organic
engagement was very low: only 1 of the first 79 runs showed any sign of the agent actually
invoking Goga tooling in its final summary. This is itself a real, valid finding about voluntary
adoption rate under a neutral "available if useful" prompt — most agents, given the *option* to
consult architecture tooling mid-task, simply don't reach for it.

**B″ (forced tool use) shows a striking, and previously undisclosed-at-this-magnitude, negative
pattern**: functional success roughly *halves* relative to Baseline (0.233 vs. 0.480) and Full
Architecture Conformance drops to roughly 40% of Baseline (0.120 vs. 0.2975). This is the
strongest effect observed anywhere in this study, in either direction. One partial, disclosed,
non-exhaustive contributing cause was found and fixed mid-execution: a real git-hook interaction
specific to R03 (nestjs) — once `npm install`'s `husky` postinstall step writes `core.hooksPath`
into the *shared* base-clone git config (visible to every worktree of that clone), the harness's
own internal bookkeeping commit (applying the `.goga/config.yml` treatment overlay) began failing
commitlint's Conventional-Commits check, producing several spurious `INVALID` rows before
diagnosis; fixed by adding `--no-verify` to that specific internal harness commit (not to any
agent-authored commit) in `scripts/execute_run_b.py`/`execute_run_b2.py`/`execute_run.py`. This
fix only affects a handful of rows for one repository and does not explain the magnitude of the
effect across all 400 B″ runs — the dominant explanation is very likely that *forcing* an
`goga schema`/`goga lint`/skill-invocation workflow into the task consumes real agent turns/budget
on tooling calls unrelated to the task itself, compounding the same directional pattern already
seen (more weakly) in the primary study's Condition B.

**Condition C (real cell restructuring) sits between Baseline and B″**: functional success 0.367
(below Baseline's 0.480 but well above B″'s 0.233), architecture conformance 0.195 (below both
Baseline and B — again the same directional pattern, though less severe than forced-tool-use). All
10 repositories were fully, physically restructured into Goga's cell model before this condition's
own 400 runs began — every cell independently `goga lint`-clean, every real circular dependency
found and either fixed or explicitly disclosed (from zero, in etcd, to a single-target Swift
codebase where 46 of 52 cells were found mutually reachable, driven by a handful of pervasive
foundation types rather than tangled business logic — each case in a per-repository
`CYCLE_FIXES.md`, never silently forced into an artificial clean hierarchy), every restructured
commit passed the repository's own real build+test suite unchanged, and all 8 original
positive/negative controls re-certified as still discriminating correctly against the new commit.
This was the most labor-intensive of the three extended conditions by construction effort
(thousands of new declarations across Signal-Android and Signal-iOS alone) and included recovery
from a genuine data-loss incident: those two repositories' restructuring commits were initially
made in independent `git clone`s rather than `git worktree`s (unlike every other repository, whose
worktrees automatically share the base clone's object database), and were destroyed during a
disk-cleanup pass before the mistake was noticed. Full recovery was achieved by replaying the
authoring subagents' preserved tool-call transcripts (`Write`/`Edit` history) to reconstruct every
file, reapplying every subsequent manual fix from its own recorded history, and independently
re-verifying both reconstructions (lint-clean, real compile success) before committing correctly
(via `git worktree` this time) — no data was permanently lost, but this is disclosed here as a
genuine operational incident, not hidden.

### 11.1 Formal statistical comparison against Baseline

The descriptive gaps above are not noise. Using the identical cell-paired methodology as §9.2 (40
paired `repository × task` cells, 10 repetitions each, Wilcoxon signed-rank with `zero_method=
'pratt'`, paired t-test, exact sign test, percentile bootstrap 95% CI, and cluster-robust GEE
logistic regression at the run level), both B″ and C were tested against the primary study's own
Condition A (Baseline) cells (`scripts/extended_study_analysis.py` →
`results/PHASE13B_EXTENDED_STUDY_ANALYSIS.md`). Condition B′ is excluded from this formal test —
stopped at 91/400 with uneven, often-zero repetitions per cell, it cannot support a valid
10-repetition cell rate. **This is a separate test from the primary A-vs-B comparison, not a
pooling of data into it** (`TREATMENT_DESIGN_EXPERIMENT_B.md` §3): a significant result here shows
*that* something changed relative to no-Goga-at-all, not *which* ingredient of the (confounded)
extended condition caused it.

| Condition | Metric | Mean delta vs. Baseline | 95% bootstrap CI | Wilcoxon p | GEE OR (vs. Baseline) | GEE p |
|---|---|---|---|---|---|---|
| B″ | Functional Success Rate | −0.248 | [−0.338, −0.160] | **<0.0001** | 0.328 | **<0.0001** |
| B″ | Full Architecture Conformance Rate | −0.178 | [−0.273, −0.093] | **0.001** | 0.322 | **0.0001** |
| B″ | Dangerous Success Rate | −0.125 | [−0.200, −0.055] | **0.001** | 0.487 | **0.0004** |
| C | Functional Success Rate | −0.113 | [−0.175, −0.058] | **0.001** | 0.629 | **0.0001** |
| C | Full Architecture Conformance Rate | −0.103 | [−0.183, −0.035] | **0.010** | 0.572 | **0.004** |
| C | Dangerous Success Rate | −0.050 | [−0.103, +0.000] | 0.063 | 0.774 | 0.052 |

Unlike the primary study's own Condition B (§9.2), where only the secondary metrics reached
significance and the primary Dangerous Success Rate stayed flat, **B″'s Dangerous Success Rate
itself is significantly lower than Baseline** (Wilcoxon p=0.001, GEE OR=0.49, p=0.0004) — but for
the same mechanical reason flagged in §9.2, not because B″ is safer: functional success collapsed
so much more severely (OR=0.33) than architecture conformance alone would predict that fewer runs
ever reach the "functionally works" precondition required to be a dangerous success in the first
place. This is a lower Dangerous Success Rate achieved by the agent failing outright far more
often, not by it making safer architectural choices — the opposite of what the metric is meant to
detect as a good outcome, and a concrete illustration of why §9.2 insists the composite metric
must never be read without its two components. Condition C's Dangerous Success Rate delta
(−0.050) does not reach significance (Wilcoxon p=0.063, GEE p=0.052) — directionally the same
partial-cancellation pattern as the primary study's Condition B, just with a larger, more
significant drop in both components underneath it.

### 11.2 Condition D — Interactive Goga Development Pipeline (qualitative case series, not pooled)

A fourth, categorically different extended condition was added at explicit request: instead of
varying what the agent is *given* (Condition B's docs-only treatment, B′/B″'s live tooling, C's
restructured codebase) while holding the harness fixed at one non-interactive turn, Condition D
varies the **process** itself. Four R01 (freqtrade) tasks, then — at further explicit requests —
four R02 (salt) tasks, four R03 (nestjs/nest) tasks, and four R04 (excalidraw) tasks, were each
carried through Goga's real `development.yml` pipeline — `brainstorm → architecture-review →
apply-architecture → code-design → design-review → coding-plan → plan-review → commit-changes →
accept-result`, 9 stages, several with interactive WAIT gates — by invoking each Goga skill
directly, with a human confirming or redirecting at every gate, rather than a single unsupervised
agent turn. This is **not** a fifth arm of the quantitative comparison: n=1 per task (n=16 total
across 4 repositories), no repetitions, no statistical test, never pooled with any other
condition's rate estimates (`TREATMENT_DESIGN_EXPERIMENT_B.md` §3's non-pooling rule applies here
too). It answers a different question than the primary study can: *when a human stays in the loop
through Goga's full intended workflow — not just given the tooling, but actually walking every
review stage — does the pipeline's own internal checks catch the defects that matter, and what do
they miss?* R02 was chosen as the second repository specifically because it is one of this study's
two "already well-documented" repositories (§5), the contrast expected to benefit *least* from
architecture tooling. R03 and R04 extend the same question to two structurally different
TypeScript repositories — R03 (nestjs/nest, a mid-sized, dependency-injection-heavy framework) and
R04 (excalidraw, whose CODEMANIFEST forest covers only 5 of a planned 10 cells, §13) — testing
whether the pattern found on R01/R02 (Python) also holds in a different language ecosystem.

All sixteen tasks were scored against the exact same black-box validators used throughout this
study (validator-execution evidence is uneven across the R03/R04 tasks specifically, disclosed per
task in `results/CONDITION_D_INTERACTIVE_PIPELINE.md`) and each ultimately reached functional
success with full architecture conformance (`dangerous_success = False`), but the number of real,
substantive corrections needed along the way varied sharply:

| Repo | Task | Feature | Real corrections needed | What caught each one |
|---|---|---|---|---|
| R01 | A | Config-validation consistency check | 1: pre-existing CODEMANIFEST-vs-implementation drift | `code-design`'s own source trace |
| R01 | B | Cross-currency exposure cap | 1: wrong interpretation of an ambiguous task phrase ("underlying currency" resolved as quote currency; ground truth used base currency) | External black-box functional oracle, **only found post-acceptance** |
| R01 | C | Consecutive-loss-streak protection | 2: a config-shape conflict (brainstorm approved independent per-pair/bot-wide thresholds; the real base class only supports one shared pair) + a self-inflicted test-isolation bug | `code-design`'s source trace; a full-regression test run |
| R01 | D | Short-lived price-fetch caching | 3: a misconfigured pre-existing cache (300s TTL, not "a few seconds"); a regression once that cache was wired into the real call sites (broke trailing-stop-loss, which needs always-fresh prices); and, after both of those were fixed and accepted, discovery that both rounds had targeted the wrong method entirely (`Exchange.get_rate` instead of the real `Exchange.fetch_ticker`/`DataProvider.ticker()` entry point the task's own scoring fixture exercises) | Source trace; full-regression test run; external black-box oracle, **again only found post-acceptance** |
| R02 | A | Low-usage disk alert threshold | 1: reference implementation's key names/shape (`low`/`high`, no `alert_type` marker) had no in-codebase signal pointing to it | External black-box functional oracle, **only found post-acceptance** |
| R02 | B | Live beacon-execution status query | 1 (undocumented event-bus dispatch convention, found before acceptance) + 3 gaps closed by `accept-result`'s own review + 1 return-shape fix | `code-design`'s source trace; `accept-result`'s manifest/usage/test review; external oracle, **post-acceptance** |
| R02 | C | SQLite-backed cache option | 2 missing required methods + 2 cold-start gaps + 1 config-naming fix, all found before acceptance; 1 module rename + 1 missing real functional-test convention, found after | `code-design`'s source trace; `design-review`/`plan-review`; external oracle (twice), **post-acceptance** |
| R02 | D | Per-run disk-usage caching | 1 — but a wrong **mechanism**, not a wrong detail: a bespoke TTL-based cache instead of Salt's real, already-established `__context__` per-run caching idiom, used identically elsewhere in the same cell | External black-box functional oracle, **only found post-acceptance**, after a fully-reviewed design had already been **ACCEPTED** |
| R03 | A | HTTP 429 exception | 0 — zero-defect run | N/A |
| R03 | B | Graceful-shutdown WebSocket notice | 5 code-design corrections + 1 design-review API-shape finding + 1 runtime write/close race condition + 1 pre-existing test-isolation bug | `code-design`'s source trace; `design-review`'s re-trace; the study's own functional validator, **run before formal acceptance** |
| R03 | C | Consecutive-failure guard | 1: a DI circular-dependency workaround | `design-review`/`plan-review`'s traceability checks |
| R03 | D | Request-correlation-id header | 1: a runtime-only NestJS global-enhancer DI-scope resolution bug, invisible to any static read | A real e2e integration test written during TDD `implement`, **before formal acceptance** |
| R04 | A | Filesystem-safe drawing-name sanitization | 1 real UI bug (input resync) + 1 typecheck error | `code-design`'s source trace; the TypeScript compiler |
| R04 | B | Live shape-area readout | 2 architectural corrections (two independent "trust the wrong existing discriminant" traps) + 1 accept-stage manifest fix | `code-design`'s source trace; `accept-result`'s own manifest review |
| R04 | C | Toggle caption visibility | 1 second guard point found by tracing + 1 self-caught regression + 1 test-harness gap + 1 accept-stage coverage gap | `code-design`'s source trace; careful re-reading before shipping; `accept-result`'s own test assessment |
| R04 | D | Snap selection to grid | 1 CODEMANIFEST defect found by tracing + 1 deliberate scope exclusion + 2 typecheck errors + 1 test bug | `code-design`'s source trace; the TypeScript compiler; debugging |

R01 Task D and R02 Task D remain the two most informative results within their pair, and they
reinforce the same finding from two different angles. R01-D's three corrections were each caught
by a *different* verification mechanism, and each would have missed at least one of the other two
defects: reading source code found the misconfigured TTL but gave no signal about which call
sites depended on always-fresh prices; running the existing test suite found the refresh-bypass
regression but had no way to know an entirely different, uncached method was the one the task's
own ground truth actually cared about; the external black-box functional oracle found the
wrong-layer problem but only after — not instead of — the first two rounds of real,
source-grounded work. R02-D goes one step further: its single defect was not a wrong parameter or
a missed call site but a wrong **choice of mechanism from scratch**, and the correct mechanism
(`__context__`) was not a hidden implementation detail but an idiom already used, unmodified, by
two other real files in the exact same cell — yet nothing in `code-design`'s per-function
source-tracing discipline (nor the reuse check that did correctly rule out one alternative,
`salt.utils.decorators.memoize`) prompted a codebase-wide search for "does a mechanism like this
already exist." The design passed every internal review stage, was formally **ACCEPTED**, and only
failed once tested against genuinely independent black-box behavior.

R03-B and R03-D add a genuinely new nuance, best stated precisely rather than folded into the same
bucket as R01/R02's post-acceptance catches. Both found *runtime-only* defects (a Socket.IO
write/close race condition; a NestJS global-enhancer DI-scope resolution bug identical in kind to
`packages/core/scanner.ts`'s real, narrow `getClassScope()` behavior for globally-registered
enhancers) that no amount of reading source could have found — but, unlike every comparable
R01/R02 finding, both were caught **before** formal acceptance, simply by executing the code under
realistic conditions as an ordinary part of finishing the task rather than as a separate audit
step. The correct refinement of the original finding is therefore not "internal review never
catches runtime defects" but that **design-level tracing specifically** (brainstorm/code-design/
design-review reading source without executing it) never does, while *running* the code — whether
via the task's own TDD tests, a full regression suite, or the external black-box oracle — sometimes
does, and whether that happens before or after formal acceptance depends on whether the specific
scenario exercised happens to hit the affected path, which following the pipeline correctly does
not by itself guarantee. R04's four tasks, by contrast, needed no correction beyond design-level
tracing, the compiler, or the pipeline's own accept-stage review for any task — including two
genuine "trust the wrong existing discriminant" architectural traps in Task B (a fill/hit-testing
flag mistaken for a closed-shape-area signal; a shared "polygon" return type silently including
`text` elements alongside real enclosing shapes) that `code-design`'s source trace caught cleanly
before implementation began.

The pattern that emerges across all sixteen tasks, on four structurally different repositories
(one poorly-documented, one already well-documented, two TypeScript repositories of very different
scale and convention), is the central, disclosed limitation of this condition as a methodology:
Goga's own **design-level** pipeline stages (`code-design`'s source tracing, `design-review`'s
re-trace, `plan-review`'s traceability checks, `accept-result`'s manifest/usage/test assessment)
reliably catch **internal self-consistency** defects — contract-vs-implementation drift, missing
test coverage, plan-vs-design traceability gaps, undocumented dispatch conventions, "trust the
wrong existing discriminant" traps — once the specific file is actually read, because that is what
they are built to check. They structurally **cannot** catch an agent's divergence from an
external, unseen ground truth by reading alone: a specific resolution of ambiguous task language
(R01-B), an arbitrary naming/shape choice with no in-codebase signal (R02-A), or the choice of
implementation mechanism itself when a correct, established idiom for the same problem already
exists elsewhere in the codebase (R02-D) — because `brainstorm` deliberately never reads
task-specific validator code or reference solutions, by design (§11's non-interactive harness
shares this same blind spot, just with no human present to eventually discover it via a black-box
re-check, or — per R03-B/R03-D — via the pipeline's own TDD test execution). Across this 16-task
sample, roughly a third to a half of all real correction-events per repository (R01: 2 of 6; R02:
3 of 5; R03: 2 of 3, both caught pre-acceptance by execution rather than a post-acceptance audit;
R04: 0 of 4) needed something beyond a purely design-level trace to catch — and this held
consistently across a poorly-documented repository (R01), a large well-documented one (R02), and
two differently-scaled TypeScript repositories (R03, R04), suggesting the limitation is structural
to design-level review's own scope, not a symptom of any one repository's documentation quality or
language. A human-in-the-loop Goga workflow is only as good as the verification signals actually
exercised at each stage — design-level tracing catches contract-consistency defects reliably;
catching runtime-only defects requires the code to actually run under a realistic scenario, by
whatever mechanism happens to exercise the affected path, and being in the loop only helps if that
execution happens before the work is declared done, not automatically. Full detail for all sixteen
tasks, including the exact commits, real test regressions found and their root causes, a
prompt-injection-pattern disclosure encountered (and correctly disregarded) mid-session on R01,
and an explicit disclosure of one inadvertent read of a black-box fixture during R04-A's
`code-design` stage: `results/CONDITION_D_INTERACTIVE_PIPELINE.md`.

## 12. Cost

| Study | Runs | Total cost |
|---|---|---|
| Primary (Condition A + B) | 800 | $2,584.04 |
| Extended B′ | 91 | $283.96 |
| Extended B″ | 400 | $1,065.28 |
| Extended C | 400 | $1,164.05 |
| **Total (automated runs)** | **1,691** | **$5,097.33** |
| Extended D (16 tasks across 4 repos, interactive session, no automated cost harness) | 16 | not tracked |

## 13. Threats to validity

Carried forward from `PROTOCOL.md` §20's preliminary list, confirmed or elaborated against what
was actually found during execution:

- **Single model, single agent harness**: all 1,691 runs used `claude-sonnet-5` via Claude Code's
  `-p` non-interactive mode. No claim here generalizes to other models or agent harnesses.
- **10 repositories, 4 tasks each**: a real but bounded sample; task-selection subjectivity (even
  with the recon-then-freeze discipline used here) and validator quality/coverage limits what any
  single task's pass/fail result can prove about the underlying codebase.
- **Goga-representation quality**: the CODEMANIFEST forest was authored by an AI agent (following
  Goga's own DSL rules and `goga lint`/`goga contract` validation), not a human architect; a
  differently-authored or higher-fidelity representation might show a different effect.
- **Confound the design cannot separate**: Condition B adds *information* (a correct architecture
  description) together with *format* (the CODEMANIFEST DSL) simultaneously — this study cannot
  distinguish "the structured format specifically helped/hurt" from "any correct architecture
  summary, in any format, would have had the same effect." This is an explicit, accepted scope
  limitation of the primary design, not an oversight (`TREATMENT_DESIGN.md` §5).
- **LLM nondeterminism / possible model drift**: repeated runs of the identical task/condition
  produced materially different outcomes (§9.4); the 10-repetition design exists specifically to
  characterize this, not eliminate it, but any drift in the underlying model across the ~11-day
  execution window is a residual, unmeasured confound.
- **Cross-language / OSS-vs-proprietary generalizability**: five languages, ten OSS repositories.
  Results may not generalize to other languages or to closed-source codebases with different
  conventions, review culture, or CI rigor.
- **Ambient Goga tooling exposure during the primary study** (§8, `PROTOCOL.md` Amendment 5): the
  `goga` CLI and skills were technically available machine-wide in both Condition A and B for the
  entire 800-run execution window, contradicting the design's stated isolation. No evidence of
  actual use was found in any of the 800 `agent.log` transcripts, but the *theoretical* gap is
  real and undetectable from this data alone with full certainty.
- **Metrics scope gap** (§10, `results/METRICS_COVERAGE.md`): several planned secondary metrics
  (dominant strategy share, module-Jaccard stability, extension-point usage rate,
  architecture-discovery-cost sub-timing) were never instrumented in the executed harness, limiting
  which of the original RQ1-RQ12 this report can answer with data rather than plausible narrative.
- **Extended-study (B′/B″/C) confounds are deliberate and severe, not accidental**: as stated in
  §11 and `TREATMENT_DESIGN_EXPERIMENT_B.md` §3, these conditions mix format, tooling, workflow,
  and (for C) actual structural change, and their results must not be read as isolating any single
  cause — they show *that* something changed, not precisely *why*.
- **Multiple comparisons** (§9.2): the significant secondary-metric findings are exploratory, not
  independently pre-registered, and no formal correction was applied.
- **Statistical power**: n=40 paired cells (primary) / n=10 per task-type subgroup gives this
  design limited power to detect true effects smaller than roughly the observed magnitudes
  (delta ~0.02-0.06 on rate metrics); a true small effect in either direction could exist
  undetected.
- **One repository below target scope**: R04 (excalidraw)'s CODEMANIFEST forest covers 5 of a
  planned 10 cells (§5), disclosed and locked in before task content was read, but still a real
  reduction in treatment completeness for that one repository specifically.

## 14. Limitations and future work

- A rigorous paired statistical comparison of B′ specifically against the primary study's
  Condition A cells remains undone: B′'s uneven, often-zero per-cell repetition count (stopped at
  91/400) blocks the same 10-repetition cell-rate methodology used for B″ and C in §11.1. A
  cell-weighted or repetition-count-aware variant (e.g. inverse-variance weighting, or restricting
  to the subset of cells that happen to have ≥5 repetitions) could still yield a valid, if less
  powered, formal test; not attempted here.
- Recover the "derivable but not parsed" metrics from `results/METRICS_COVERAGE.md` (existing-test
  regressions, architecture-discovery-cost sub-timing, module-Jaccard stability, dominant-strategy
  share, extension-point usage rate) from the raw per-run artifacts already preserved under
  `runs/<run_id>/` and `runs_experiment_{b,b2,c}/<run_id>/` — no re-execution needed, only
  additional parsing.
- Investigate the B″ functional-success collapse (§11) more directly than the one disclosed,
  partial R03-specific cause found so far — e.g. by sampling `agent.log` transcripts to
  characterize how much of each run's turn/token budget went to Goga tool calls versus the task
  itself, and whether budget/turn exhaustion (not task difficulty) is the proximate cause.
- A replication with a different model or agent harness would directly test the single-model
  threat to validity in §13.
- A version of Condition B using a non-Goga-formatted architecture summary (plain prose, or a
  different structured format) would help separate "structured format" from "any correct
  architecture information," the confound explicitly left open in §13.
- Condition D (§11.2) now covers 16 tasks on four repositories (R01, R02, R03, R04) — one
  poorly-documented, one already well-documented, two TypeScript repositories of different scale —
  and the central pattern (real defects that design-level tracing structurally cannot catch)
  held on all four, including R02-D's more severe variant (a wrong implementation *mechanism*
  surviving full internal review and formal acceptance) and, on R03, a more encouraging refinement:
  two runtime-only defects (R03-B, R03-D) were caught *before* formal acceptance because the
  specific test scenario exercised during implementation happened to hit the affected code path —
  showing the pipeline's own TDD discipline, not just an external post-acceptance audit, can catch
  this class of defect when the right scenario gets exercised, though nothing about following the
  pipeline correctly guarantees that it will. R04 needed no correction beyond design-level tracing
  or the compiler for any of its four tasks, the first repository in this condition where that held
  uniformly. A fifth repository in a still-different language (Go, Kotlin, or Swift) would further
  test whether "an established idiom already exists elsewhere in the codebase" (R02-D) recurs as a
  general failure mode or was specific to Python's `__context__`/dunder convention style.

## 15. Conclusion

On this benchmark's primary, narrowly-scoped comparison — a frozen, Goga-format `CODEMANIFEST`
architecture description added to an otherwise-unchanged single-session agent protocol — there is
**no statistically significant change in Dangerous Success Rate**, the headline metric this study
set out to test (n=40 paired task-level cells, 800 runs). Read on its own, that would suggest
static architecture documentation is, at best, a wash.

That reading would be incomplete. The metric's two components each moved in the same negative
direction, both individually statistically significant: functional correctness dropped, and
architecture conformance *also* dropped, under Goga — the composite metric only looks flat because
those two effects happen to cancel inside its AND-based definition. And the extended,
more-confounded conditions show the same directional pattern getting *worse*, not better, and far
more statistically decisive, as more Goga machinery is added: voluntary tool use is barely adopted
at all (B′); explicitly forced tool use (B″) is associated with the single largest negative effect
measured anywhere in this study — functional success roughly halved (GEE OR=0.33, p<0.0001) and,
unlike the primary study, even the composite Dangerous Success Rate itself drops significantly
(p=0.001), though for the wrong reason (more outright failures, not safer architecture, §11.1); and
even a genuinely, physically cell-native-restructured codebase (C) shows significantly lower
functional success (p=0.001) and architecture conformance (p=0.010) than an untouched baseline.

None of this licenses a claim that *no* structured-architecture representation could ever help an
AI coding agent — the confounds disclosed in §13 (representation quality, format-vs-information,
single model, limited statistical power) are real and specifically block that broader claim. What
this benchmark *does* support, across four independent conditions and 1,691 total runs, is a
consistent, disclosed, and somewhat counter-intuitive pattern: on this sample, every way this
study gave the agent more Goga — from a passive document, to optional live tooling, to mandatory
live tooling, to an actually-restructured codebase — was associated with the agent doing as well
or worse on the tasks it was asked to do, never measurably better. That is the honest headline for
the talk, not "no significant difference," and not "Goga helps."

## 16. Reproducibility

Every number in this report traces to a committed, re-runnable artifact:

- `results/analysis_set.csv`, `results/cells.csv`, `results/task_comparison.csv` — primary study,
  Phases 11-12.
- `results/PHASE13_STATISTICAL_ANALYSIS.md` + `scripts/statistical_analysis.py` — Phase 13,
  fully reproducible (fixed seed, documented in the script's own header).
- `results/runs_experiment_b.csv`, `results/runs_experiment_b2.csv`, `results/runs_experiment_c.csv`
  — extended study raw results.
- `results/PHASE13B_EXTENDED_STUDY_ANALYSIS.md` + `scripts/extended_study_analysis.py` — §11.1's
  formal B″/C-vs-Baseline comparison, same fixed-seed reproducibility guarantee as Phase 13.
- `results/VALIDATION_REPORT.md`, `results/METRICS_COVERAGE.md` — data-quality and scope
  disclosures.
- `PROTOCOL.md` (frozen, `benchmark-v1` tag, with 5 logged amendments) and
  `TREATMENT_DESIGN.md` / `TREATMENT_DESIGN_EXPERIMENT_B.md` — full design rationale.
- `STATUS.md` — the living phase-by-phase log this report is distilled from, including every
  incident narrated in §8 and §11 in full operational detail.
- `tasks/R01/FUNCTIONAL_VALIDATORS.md`'s "Correction" section (2026-09-22) — the R01 Task A
  functional-validator fix disclosed in §9.1, with the full per-run before/after table.
  `results/pre_r01ta_correction_backup/` preserves the pre-correction `analysis_set.csv`,
  `cells.csv`, `task_comparison.csv`, and both Phase 13 statistical reports exactly as they
  stood before this correction, for direct diffing.

No run's raw data was ever overwritten or deleted; every replacement run exists alongside the
original it replaced (`PROTOCOL.md` §15). The one correction applied after initial publication
(R01 Task A's functional validator, above) followed the same rule: raw per-run artifacts under
`runs/R01-TA-*/` are untouched; only the derived aggregate files were recomputed, with the
original pre-correction versions preserved for comparison rather than deleted.
