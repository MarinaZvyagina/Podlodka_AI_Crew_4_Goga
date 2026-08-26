# GOGA_RESEARCH.md

## Purpose of this document

This document is Phase 0 of the benchmark ("architecture-agent-benchmark"). It records what `qarium/goga` actually is and does, based on direct inspection of the repository (source of truth), not on the description of Goga contained in the original research prompt. It is the basis for `TREATMENT_DESIGN.md`.

## 0. Provenance

| Field | Value |
|---|---|
| Repository | `qarium/goga` (GitHub) |
| License | BSD-3-Clause |
| Default branch | `1.2.x` |
| Pinned tag used for this research | **`v1.2.2`** |
| Pinned commit SHA | `f1257db59347651273ce94d4988e16d8fa1e7940` |
| Commit date | 2026-08-24 13:08:21 +0300 |
| Research conducted | 2026-08-25 |
| GitHub issues at research time | 0 open, 0 closed |
| Repo created | 2026-04-09 (young project, ~4.5 months old) |

All commands, artifacts, and claims below are anchored to **this exact tag**. If Goga is updated during the benchmark, the version in use must be re-frozen and any drift documented (see `experiment.yaml` and Section 10 of the protocol on model/tooling drift).

## 1. What Goga is

Goga is a CLI-based **"AI-SDLC" platform**: it turns software development process into versioned, declarative **pipelines**, lets an already-installed coding-agent CLI (Claude Code, Codex, Cursor, OpenCode, or Qwen) be assigned to run each pipeline stage, and extends itself via pluggable `goga_tool_*` packages. It ships a reference **Specification-Driven Development (SDD)** cycle built around a contract file format called **CODEMANIFEST**.

Stated problems it targets (`docs/index.md`): contract/code drift, undocumented architecture, knowledge lost in chat transcripts, and unstandardized agent autonomy. It is not a code-generation model or a replacement for Claude Code — it is a **process/context layer on top of an existing coding-agent CLI**, distributed as Claude Code Skills + slash commands + a Docker-isolated pipeline runner.

Advertised supported project languages (README/docs badges): Python, Go, Kotlin, Swift, JavaScript (+ an inconsistent partial C++ skill, see §5).
Advertised supported agent CLIs: Claude Code, Codex, Cursor, OpenCode, Qwen — **Claude Code is one of five equally-supported harnesses, not a privileged one.**

## 2. CODEMANIFEST

CODEMANIFEST is a **YAML-based DSL**, one file per "cell" (a directory that encapsulates one responsibility domain), with three `---`-separated sections:

- **Header** — `Imports` (types/usages from other cells), `Usages` (named practice docs), `Annotations` (free-text global directives injected into every cell).
- **Body** — Entity types (stateful objects: services, configs, data models — properties + methods), Routine types (stateless operations), Embedded types (`->ExternalType` re-exports).
- **Footer** — `Author`, `CreatedAt`, `Description`.

It captures: module/cell boundaries, per-cell public contracts (types, method signatures, properties), inter-cell dependency edges (via `Imports`), and free-text architectural conventions (via `Usages`/`Annotations`). It does **not** capture full implementation logic — only the declared interface layer.

**Critical fact — how it is populated:** CODEMANIFEST content is written by the **AI agent** during the `apply` SDD stage, driven by a human/agent-authored architecture plan (`docs/arch/<topic>.md`). It is not statically reverse-engineered from existing code by a scanner. A separate, unrelated mechanism, `goga contract`, tree-sitter-extracts the actual implementation's real signatures and diffs them against an existing CODEMANIFEST for drift detection — but this only checks cells that already have a CODEMANIFEST; it does not create new ones.

Validation pipeline: Factory (YAML → AST) → Visitor (21 document-level rules) → Analyzer (3 tree-level rules incl. cyclic-dependency detection), run via `goga lint`.

## 3. How Goga represents architecture/contracts

Architecture is represented as a **forest of CODEMANIFEST files**, one per cell, each declaring its own public contract and its `Imports` from other cells. `goga schema` walks this forest and emits a hierarchical JSON tree (cell path, description, types, usages, dependencies, children) — this is the read/visualization surface (`goga schema | goga tool viewer` opens an interactive dependency graph). There is no separate central "architecture.yaml" — the architecture *is* the union of per-cell CODEMANIFEST files plus `.goga/config.yml` (project-level Docker/agent/env config) and `.goga/usages/*.md` (cross-cutting conventions).

## 4. SDD workflow (stages, artifacts)

Two workrounds, gated by optional human/agent review at each step:

**Refinement** (what/why): `define → discover → propose → review(task)` → produces `docs/defines/<topic>.md`, `docs/proposals/<topic>.md`, `docs/tasks/<topic>.md`.

**Development** (how): `brainstorm → apply → design → plan → build → change → accept`
- `brainstorm`: task → architecture plan (`docs/arch/<topic>.md`)
- `apply`: architecture plan → **writes CODEMANIFEST + `.usages/` files on disk** (no implementation code)
- `design`: CODEMANIFEST → detailed design doc (`docs/design/<topic>.md`)
- `plan`: design doc → ralph-loop execution plan (`docs/plans/<topic>.md`)
- `build` (`goga build`): Docker-isolated "ralph-loop" — declaration → contract tests → implementation → interface verification → logic tests → lint → review → approval; **CODEMANIFEST is read-only during build**
- `change`: short-path bugfix loop
- `accept`: final acceptance/coverage audit

## 5. What data the coding agent receives

Purely filesystem-based (no MCP server exists in this version — confirmed absent from source and dependencies). `goga connect claude` symlinks:

- **72 Skill directories** into `~/.claude/skills/goga-*` (native Claude Code Skills: `goga-cell` [+ a live-downloaded DSL spec `dsl.md`], `goga-cookbook`, `goga-lang-disp`, `goga-brainstorm*`, `goga-apply`, `goga-design*`, `goga-plan*`, `goga-review*`, `goga-accept*`, `goga-change*`, `goga-define*`, `goga-discover`, `goga-propose`, and per-language `goga-cell-{python,go,javascript,kotlin,swift,cpp}`).
- **11 slash commands** into `~/.claude/commands/goga` (`/goga:brainstorm`, `/goga:apply`, `/goga:design`, `/goga:plan`, `/goga:build`... etc. — Claude Code is one of only 3 harnesses, alongside OpenCode and Qwen, that gets slash-command registration; Codex and Cursor do not).
- Project-tree artifacts: `docs/defines|proposals|tasks|arch|design|plans/*.md`, per-cell `CODEMANIFEST` + `.usages/*.md`, `.goga/config.yml`, `.goga/usages/conventions.md`.
- Read-only structural context via `goga schema` (JSON) and `goga lint` output, explicitly referenced by skills such as `goga-define-project`/`goga-discover` ("read `goga schema` output and existing CODEMANIFEST/usage files to understand the existing product").

## 6. Commands relevant to the experiment

| Command | What it does |
|---|---|
| `goga init` | Interactive wizard; writes `.goga/config.yml` (+ optional Dockerfile / conventions). **Does not scan source code.** |
| `goga connect claude` | Symlinks skills/commands into `~/.claude/`. |
| `goga schema [CELLS]` | Emits JSON tree of existing CODEMANIFEST forest (read-only; nothing to show until cells exist). |
| `goga lint` | Validates existing CODEMANIFEST files. |
| `goga contract [CELLS] [--lang L]` | Tree-sitter diff of CODEMANIFEST vs actual implementation (drift check, Python/Go/Kotlin/Swift/JS only). |
| `goga pipeline <name> [-s stage]` | Runs a named pipeline (e.g. `development`) inside Docker. |
| `goga build` | Runs the ralph-loop implementation stage. |
| `/goga:brainstorm`, `/goga:apply`, `/goga:design`, `/goga:plan` (skills) | Agent-driven artifact production described in §4. |

**There is no `goga import` / `goga adopt` / `goga scan-existing-repo` command in v1.2.2.**

## 7. Additional skills/prompts/tools beyond base Claude Code

Built-in tools registered on connect: `viewer` (CODEMANIFEST dependency-graph browser), `mkdocs` (docs generation from CODEMANIFEST), `scriba` (writer/prompt-review tool). Third-party `goga_tool_*` packages can add more skills/pipelines but none are installed by default. No Claude Code hooks (`settings.json`-style) are used — pipeline stage control (`communication`/`approve`/`manual`) is Goga's own orchestration layer, external to Claude Code.

## 8. Supported languages (v1.2.2)

**Contract extraction / drift detection** (`goga contract`, tree-sitter): **Python, Go, Kotlin, Swift, JavaScript** — exactly 5 languages, matching `goga init`'s language wizard.

**CODEMANIFEST-authoring skill only** (no extraction/drift support): adds **C++** (`goga-cell-cpp`) — inconsistent, not selectable during `goga init`, no `goga/contract/cpp` module. Treated as an internal inconsistency, not a usable 6th language.

**Benchmark implication:** repositories must be in Python, Go, Kotlin, Swift, or JavaScript/TypeScript to receive full Goga tooling support (contract drift-checking + language wizard). TypeScript is not separately listed but the JavaScript tree-sitter grammar family commonly covers close variants — this must be verified per-repository, not assumed.

## 9. Applicability to existing ("brownfield") repositories — key finding

**Goga does not require a greenfield project, but it also has no one-shot brownfield ingestion.** `goga init` in an existing repo only creates `.goga/` config files — it never parses or maps existing source. The `apply` stage does have brownfield-aware logic (`docs/workflow/apply.md`, Phase 2: "Classify cells: mark each as **new** or **modification**; for modification, read current CODEMANIFEST to compute diff"), but this operates **cell-by-cell, scoped to whatever task is currently being worked** — there is no bulk command to backfill CODEMANIFEST coverage across an entire pre-existing large codebase in one operation.

Practical consequence: applying Goga to a large existing repository means the *first* task's `brainstorm`/`apply` stages will produce CODEMANIFEST files only for the cells that task happens to touch. A repository-wide architecture representation, if desired, must be built up either (a) by running the `apply`/`brainstorm` cycle repeatedly across many manually-scoped "describe this cell" tasks before the benchmark tasks begin, or (b) accepted as partial/incremental coverage. This is not documented as a known limitation anywhere in Goga's docs or issue tracker (0 issues exist) — it was established by direct reading of the entire `goga/onboarding` module and CLI surface.

## 10. Limitations discovered

1. **No bulk brownfield architecture generation** (§9) — the single most important limitation for this benchmark, since all candidate repositories are large pre-existing codebases.
2. **No MCP server / no structured tool-call interface** — everything is filesystem convention (skills + markdown/YAML files), meaning the "treatment" is fundamentally a set of *context files and workflow prompts*, not a programmatic API the agent calls.
3. C++ skill/extraction mismatch (§8) — cosmetic but signals the project is young/still stabilizing.
4. `goga build`/`goga pipeline` require Docker with host/image version parity (major.minor) unless `GOGA_SKIP_VERSION_CHECK=1` — an operational constraint for a reproducible benchmark harness.
5. Copier-based `goga init <template>` scaffolding requires an interactive TTY and fails in CI/piped environments — irrelevant to brownfield `goga init` (no template), but relevant if any automation wraps the CLI non-interactively.
6. Zero GitHub issues / very young project (created 2026-04-09) — no community track record of brownfield use at scale to draw on; this benchmark would be among the first evaluations of the tool at this scale.
7. Full pipeline execution (`goga pipeline development`) is a multi-stage, multi-artifact, human-reviewable workflow (define → discover → propose → brainstorm → apply → design → plan → build → accept) that is far broader than "give the agent an architecture doc" — see `TREATMENT_DESIGN.md` for why this matters for isolating the experimental variable.

## Sources

Primary: `README.md`, `docs/index.md`, `docs/getting-started.md`, `docs/architecture/index.md`, `docs/cell/index.md`, `docs/workflow/index.md`, `docs/workflow/apply.md`, `docs/pipelines/shipped.md`, `docs/cli/{index,init,connect,schema,lint,contract}.md`, `docs/languages/index.md`, `goga/CODEMANIFEST`, `goga/cli.py`, `goga/onboarding/{logic,questionnaire}.py`, `goga/connect/connect.py`, `goga/contract/{python,golang,kotlin,swift,javascript}/`, `goga/assets/skills/*`, `goga/assets/commands/*`, `goga/assets/pipelines/*.yml`, `pyproject.toml`. All read directly from a local clone pinned to tag `v1.2.2` (commit `f1257db59347651273ce94d4988e16d8fa1e7940`) on 2026-08-25.
