# Experiment Summary — Does Machine-Readable Architecture Help AI Coding Agents?

*A benchmark study prepared for a Podlodka AI Crew 2026 conference talk. This document is a
narrative overview of the whole study, written after the primary study froze and while the
extended study is still running. For full operational detail, see `STATUS.md` (the living
log this summary is distilled from), `PROTOCOL.md`, `TREATMENT_DESIGN.md`, and
`TREATMENT_DESIGN_EXPERIMENT_B.md`.*

## 1. The question

When an AI coding agent (Claude Code) is asked to modify a large, pre-existing codebase it has
never seen before, does giving it a **machine-readable architecture representation** — Goga's
`CODEMANIFEST` cell model — make it more likely to produce a change that is *both* functionally
correct *and* architecturally conformant, rather than a "Dangerous Success" (works, but violates
the codebase's real architectural boundaries in a way that will bite later)?

And a follow-up, more confounded but practically important question: if a codebase is not just
*described* by such a representation but actually *restructured* into it — or if the agent is
actively encouraged or forced to use Goga's live tooling — does that change the picture further?

## 2. Why this design, not a simpler one

An earlier design (`TREATMENT_DESIGN.md`, rejected) considered giving the agent Goga's entire
workflow — brainstorm → apply → design → plan → build, its skills, its slash commands, its own
validation pipeline. That was rejected as the *primary* design because it confounds four things
at once (interaction protocol, prompt set, tool access, validation process) into a single
"Goga condition" — any result would only support the weak claim *"the Goga workflow produced a
different result,"* never the precise claim *"machine-readable architecture caused the
improvement."*

The primary study instead isolates **one variable**: the presence of a frozen, machine-readable
`CODEMANIFEST` architecture description, added to the repository as ordinary files, with
*nothing else* different — same prompt, same tools, same single-session protocol, same
everything else. This is deliberately the narrowest, most defensible causal claim the study can
support.

## 3. The primary study — Condition A vs. Condition B (frozen, complete)

**10 repositories**, one large, real, pre-existing open-source codebase per language, two per
language across 5 languages:

| Repo | Language | Production LOC |
|---|---|---|
| R01 freqtrade | Python | 44.8k |
| R02 salt | Python | 275.5k |
| R03 nestjs | TypeScript | 34.7k |
| R04 excalidraw | TypeScript | 106.5k |
| R05 VictoriaMetrics | Go | 120.1k |
| R06 etcd | Go | 62.3k |
| R07 mihon | Kotlin | 77.4k |
| R08 Signal-Android | Kotlin/Java | 371.9k |
| R09 firefox-ios | Swift | 245.2k |
| R10 Signal-iOS | Swift | 548.0k |

**4 tasks per repository** (40 total), each grounded in real, cited code — never invented:
- **Task A — Local Change**: a small, contained modification.
- **Task B — Cross-Module Feature**: a feature genuinely touching ≥3 architectural boundaries.
- **Task C — Existing Extension Point**: exercising a real, designed extensibility mechanism the
  codebase already has.
- **Task D — Architecture Trap**: a task solvable two ways — one that respects the codebase's
  real architectural boundaries, one that "works" but violates them (the trap).

Each task has a **functional validator** (does it work?) and **≥3 architecture-conformance
validators** (does it respect the boundaries?), each independently confirmed to discriminate a
real positive control (correct solution) from a real negative control (the trap) — 40/40 tasks
confirmed, 80 real diffs.

- **Condition A (Baseline)**: the repository exactly as it exists — source, README, tests,
  comments. Nothing added.
- **Condition B (Goga)**: identical everything, *plus* a frozen forest of `CODEMANIFEST` files
  covering the codebase's architectural "spine" (92 files, 9,524 lines across the 10 repos) and
  one short pointer file explaining the format. No live `goga` CLI, no skills, no workflow change
  — purely a documentation artifact the agent can read like any other repository file.

**800 runs** (10 repos × 4 tasks × 2 conditions × 10 repetitions), executed over ~11 days
(2026-08-28 to 2026-09-10), 800/800 valid (every infrastructure failure along the way got a
replacement run; originals preserved, never deleted). Total spend: **$2,584.04**.

**Headline result (descriptive; formal significance testing is Phase 13, not yet run):**

```
Primary metric — Dangerous Success Rate (mean across 40 task-level cells):
  Baseline: 0.290    Goga: 0.275    Delta: -0.015
  Cells where Goga < Baseline: 8/40   Goga > Baseline: 6/40   Tied: 26/40
```

A smaller preview of *why* this matters showed up as early as the pilot phase: two identical
repetitions of the same task, same model, same repository produced two *different* architectural
solutions — one correct, one that broke 4 existing tests. The 800-run study exists to measure
that run-to-run instability systematically, not just anecdotally.

## 4. The extended study — Experiment B (in progress)

After the primary study froze, three additional, more confounded conditions were added at
explicit request, run as a **separate study, never pooled with the primary 800-run result**:

- **Condition B′ — Goga Full Workflow (optional tool use).** Same as Condition B, plus the live
  `goga` CLI and skills connected, with a neutral *"available if useful"* prompt sentence — the
  agent isn't told to use them. Stopped at 91/400 once it became clear organic engagement was
  very low (only 1 run in the first 79 showed any sign of actually invoking Goga tooling) — kept
  as a real, valid finding about voluntary-adoption rate, not discarded.
- **Condition B″ — Goga Forced Workflow (explicit instruction).** Same as B′, but the prompt
  explicitly instructs the agent to use `goga schema`/`goga lint`/relevant skills as part of its
  process. A genuinely separate condition (not a mutation of B′ mid-batch, which would have mixed
  two treatments under one label). **In progress: 220/400 valid so far.**
- **Condition C — Goga-Native Architecture (real restructuring).** Not just documented — the
  repository's actual `CODEMANIFEST` cell boundaries are made real: every cell independently
  `goga lint`-clean, every real circular dependency found and either fixed or explicitly
  disclosed, every restructured commit passed the repository's own build+test suite unchanged,
  and all 8 original positive/negative controls re-certified as still discriminating correctly
  against the new commit. **All 10 repositories fully restructured** — the largest of the three
  extended conditions by construction effort (thousands of new declarations across the two
  biggest repos, Signal-Android and Signal-iOS, whose restructuring alone required real,
  disclosed engineering work: resolving 11-to-46-cell strongly-connected dependency components,
  working through real disk-space and toolchain limits during the build/test hard-gate, and — in
  one case — recovering from a genuine data-loss incident, below). Condition C's own experiment
  (agents solving the same 40 tasks against the *restructured* commits) is now running:
  **108/400 valid so far.**

All three extended conditions reuse the exact same 40 tasks, validators, and controls as the
primary study — only the treatment (what the agent sees/has access to) differs.

## 5. Notable methodological moments (disclosed, not hidden)

This study's standing discipline is to disclose real problems and how they were resolved, rather
than silently smoothing them over — a few worth naming:

- **A real data-loss incident, fully recovered.** Two repositories' restructuring work
  (Signal-Android, Signal-iOS) was initially done in an independent `git clone` rather than a
  `git worktree` — unlike every other repo, whose worktrees automatically shared the base
  clone's object database. The clones' commits/tags were destroyed during a disk-cleanup pass
  before the mistake was noticed. Recovery was possible because the authoring subagents' full
  tool-call transcripts survived independently of the deleted directories: their `Write`/`Edit`
  history was replayed to reconstruct every file, all subsequent manual fixes were reapplied from
  their own written records, and both reconstructions were independently re-verified (lint-clean,
  real compile success) before being committed correctly this time.
- **A base-clone corruption incident during the primary 800-run execution**, caused by macOS
  silently deleting files untouched for ~3 days anywhere under `/tmp` — diagnosed, all 10 base
  clones relocated to a path outside `/tmp`'s cleanup policy, ~650 affected rows replaced.
- **Real circular dependencies found and resolved** across the restructured repositories — from
  zero (etcd) to a single-module Swift codebase where 46 of 52 cells were found mutually
  reachable, driven by a handful of pervasive foundation types rather than tangled business
  logic — each case disclosed in a per-repository `CYCLE_FIXES.md`, never silently forced into an
  artificial clean hierarchy.
- **Moderate parallelism** (multiple workers, each pinned to a disjoint subset of repositories so
  no two ever touch the same base clone concurrently) was used opportunistically in both the
  primary and extended studies to speed up unattended execution, and scaled back to single-
  threaded whenever the operator needed the machine's resources for other work — a live,
  practical trade-off, not a fixed protocol requirement.

## 6. Where things stand right now

- Primary study (Condition A vs. B): **frozen, complete**, descriptive result above; formal
  statistical analysis and the final report are the next steps.
- Condition B′: stopped by design at 91/400 (a complete, valid finding in itself).
- Condition B″: running, 220/400.
- Condition C: all 10 repositories restructured and re-certified; its own 400-run experiment
  running, 108/400.

None of the extended-study numbers are final — check `STATUS.md` for the live count.
