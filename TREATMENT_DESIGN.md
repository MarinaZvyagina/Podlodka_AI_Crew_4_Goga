# TREATMENT_DESIGN.md

## Question this document answers

> Какую именно гипотезу позволяет проверить выбранная конфигурация?

## 1. The confound problem, restated with real Goga mechanics

`GOGA_RESEARCH.md` establishes what running "the full Goga workflow" on a benchmark task would actually entail:

- a different **interaction protocol** (multi-stage pipeline with optional human review gates: `define → discover → propose → brainstorm → apply → design → plan → build → accept`, vs. Baseline's single autonomous session);
- a different **prompt set** (11 slash commands + skill-specific prompts per stage, vs. one task prompt);
- different **tools available** (`goga schema`, `goga lint`, `goga contract`, `goga pipeline`, plus 72 Skill directories, vs. Baseline's plain Claude Code);
- a different **artifact trail** (PRDs, ADRs, design docs, plans — all consumed/produced mid-task), which changes how much the agent "thinks out loud" before touching code;
- a different **validation process** (ralph-loop: contract tests → implementation → interface verification → logic tests → lint → review, baked into `goga build`, vs. Baseline running the repository's own test suite once at the end).

Running this full pipeline as "the Goga condition" is exactly **Experiment B** from the brief: it would let us say only *"the Goga-based workflow produced a different result,"* never *"machine-readable architecture caused the improvement."* Given the study's explicit priority (reproducibility and a defensible causal claim over an impressive-looking result), Experiment B is rejected as the primary design.

## 2. Chosen design: Experiment A, tightly scoped

**Primary treatment variable: presence of a pre-built, frozen, machine-readable architecture representation in Goga's `CODEMANIFEST` format, available to the agent as ordinary repository files — with no other change to prompt, workflow, tools, or interaction protocol.**

Concretely, the two conditions for the actual 800 task-solving runs are:

### Condition A — Baseline
Agent works in the repository exactly as it exists (source, README, CONTRIBUTING, ADRs, AGENTS.md/CLAUDE.md, tests, comments — see `PROTOCOL.md` §9). Plain Claude Code. One task prompt. One autonomous session.

### Condition B — Goga (architecture-representation only)
Identical repository, identical task prompt, identical model, identical Claude Code version, identical permissions, identical single-session protocol, **plus**:

1. A frozen forest of `CODEMANIFEST` files (Goga's DSL, §2 of `GOGA_RESEARCH.md`) checked into the repository, covering the architectural "spine" of the codebase (see §4 below for scope rule).
2. One short, neutral pointer file (`ARCHITECTURE_CONTRACTS.md` at repo root, ≤ 300 words, identical template across all 10 repositories) stating that machine-readable architecture contracts exist as `CODEMANIFEST` files per directory, briefly explaining the section format (Imports/Usages/Annotations header, Entity/Routine/Embedded body), so the agent does not have to reverse-engineer an unfamiliar file format from nothing. This mirrors how a real team would document a convention in a README — it is data, not a workflow instruction.

**Explicitly not included in Condition B for the 800 runs:**
- no `goga` CLI installed or invocable (no `goga schema`, `goga lint`, `goga contract`, `goga pipeline`, `goga build`);
- no Goga Skills or slash commands connected to Claude Code (`goga connect` is *not* run for the benchmark sessions);
- no multi-stage SDD workflow, no review gates, no separate define/brainstorm/apply/design/plan/build sessions;
- no Goga-specific system prompt changes.

This keeps the two conditions identical on every axis in `PROTOCOL.md` §9 (repository commit, task prompt, model, model version, Claude Code version, system prompt, tool permissions, timeout, machine, dependency state, network policy, working-directory structure, test environment) **except** the presence of the CODEMANIFEST file set + one static pointer doc.

## 3. Narrowed research hypothesis

The original broad hypothesis ("does structured architecture representation help AI coding agents make more architecturally correct and stable decisions") is **narrowed** to:

> **H (primary):** When a large existing repository is annotated with a frozen, Goga-format (`CODEMANIFEST`) machine-readable architecture representation covering its main structural boundaries, does a Claude Code agent — working under an otherwise identical single-session protocol, prompt, and toolset — produce (a) more architecturally conformant and (b) more run-to-run-stable changes than the same agent working from the repository's existing documentation alone?

This hypothesis is about **the presence of a specific structured-architecture artifact format**, not about Goga-the-workflow, not about Goga-the-CLI, and not about Goga's skills/pipelines/validation machinery. Any results from this benchmark license claims of the form *"a CODEMANIFEST-style architecture doc-set changed X"* — they do **not** license claims of the form *"the Goga SDD workflow improves AI coding"* or *"Goga's build/review pipeline catches more bugs."* Those would require a separate Experiment-B-style study, explicitly out of scope here (see §6).

## 4. Building the frozen CODEMANIFEST forest without task leakage

Per `PROTOCOL.md`/original brief §15, ordering is fixed: **repository selection → reconnaissance → task design → ground truth → validators → protocol freeze → (only then) Goga architecture preparation.** Consequently, whoever builds the CODEMANIFEST forest already knows the 4 frozen tasks per repository, which creates a cherry-picking risk: it would be trivial to author suspiciously on-the-nose contracts that hand the agent the exact answer to Task D's Architecture Trap. To prevent this:

- **Scope rule, fixed in advance:** CODEMANIFEST coverage targets the repository's top-level architectural "spine" — every directory at depth ≤ 3 from the relevant source root that constitutes a named component in the project's own documentation/module layout (e.g. controllers/handlers, services/use-cases, domain/model, storage/repository, config, plugin/extension registries, public API surface). This scope is decided from the repository's *own* module structure and existing docs, not from the task list, and is documented per-repository in `architecture/<repo_id>/SCOPE.md` before task-specific content is considered.
- **No task-keyed content:** contract descriptions and annotations are written to describe what a component *does* and *how it fits into the dependency graph*, using the vocabulary of the codebase itself — never phrased around a benchmark task ("add caching here" is forbidden phrasing; "this cell is the read path for search queries" is acceptable).
- **Single build pass, then freeze:** the forest is generated once (via Goga's own `brainstorm` → `apply` cycle, run manually against the real repository by the researcher, using `goga connect claude` in a *separate* preparation session — never during a benchmark run), reviewed for `goga lint` validity and spot-checked with `goga contract` for drift against the real implementation, then frozen (git-committed) before Phase 9 randomization. Any manual correction after generation is logged (`architecture/<repo_id>/CORRECTIONS.md` — count, reason, diff) as part of Goga setup cost (§45 of the original brief).
- **Same artifact for all 4 tasks:** exactly as required by the brief — Task A/B/C/D against one repository all see the same frozen forest; nothing is added or adjusted per task type.
- **Independent plausibility check:** before freeze, a reviewer who has *not* seen the task list confirms the CODEMANIFEST forest reads as a generic architecture description a maintainer might write, not a task-specific hint sheet.

## 5. Does this design actually separate the Quality and Stability questions from confounds?

Yes, with one explicitly named residual risk:

- **Quality (RQ3, RQ4):** since prompt/tools/protocol are held constant, any difference in Architecture Conformance Rate or Dangerous Success Rate between conditions is attributable to the presence of the architecture doc-set (content availability), not to a different agentic workflow.
- **Stability (RQ5, RQ6):** since interaction protocol is single-session/autonomous in both conditions (no branching human-review gates that could themselves inject variance or reduce it), any change in run-to-run variance is attributable to whether the agent had a stable, structured reference to converge on, not to a different number of decision checkpoints.
- **Residual risk — content, not just format:** Condition B necessarily adds *information* (a description of the real architecture) as well as *format* (the CODEMANIFEST DSL). We cannot cleanly separate "the agent did better because the format is machine-readable/structured" from "the agent did better because it was simply given a correct architecture summary, in *any* format." This benchmark measures the combined effect of **Goga's specific structured representation**, not structure-vs-prose in the abstract. This is stated explicitly here so it is not misrepresented later in `report/final_report.md`.
- **Residual risk — pointer file wording:** the `ARCHITECTURE_CONTRACTS.md` pointer is new text present only in Condition B. It is kept minimal and purely descriptive (no task guidance, no "look here for hints") to avoid smuggling in a second, unlabeled treatment variable.

## 6. Experiment B — explicitly descoped, not discarded

The full Goga SDD pipeline (Experiment B) remains a legitimate, separate research question — "does adopting the full Goga process, not just its architecture format, change outcomes?" — but it is **not** run as part of the 800-run primary benchmark, because it would reintroduce every confound listed in §1. If pursued later, it must be a distinct study with its own treatment design document, explicitly not pooled with this benchmark's results.

## 7. What "Goga" means for the rest of this benchmark

Everywhere `PROTOCOL.md`, `repos.yaml`, `experiment_plan.csv`, and `results/*.csv` refer to "Goga condition," it means precisely: *Condition B as defined in §2 of this document* — a frozen CODEMANIFEST architecture forest plus one static pointer file, nothing else. This scoping note must be repeated in `report/final_report.md` §3 verbatim to prevent readers (or the HighLoad++ audience) from generalizing findings to "Goga the product" or "Goga the workflow."
