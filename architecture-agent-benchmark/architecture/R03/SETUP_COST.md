# SETUP_COST.md — R03 (nestjs/nest)

## initial_generation_time

Active tool-call work spanned one continuous session on 2026-08-26 covering: reading
`TREATMENT_DESIGN.md`/`PROTOCOL.md` (including Amendment 1), verifying the pinned-commit clone
at `/tmp/benchmark-repos/R03/base`, running `goga init` (language: javascript), reading the
`goga-cell`/`goga-cookbook`/`goga-lang-disp`/`goga-cell-javascript` DSL skills directly (the
Skill tool did not surface the goga-* skills in this session, consistent with the note in
Amendment 1), a source-reading pass over `packages/core/injector`, `packages/core/adapters`,
`packages/core/router`, `packages/core/guards`, `packages/core/pipes`,
`packages/core/interceptors`, `packages/common/exceptions`, `packages/platform-express/adapters`,
and `packages/platform-fastify/adapters` (roughly 20 file reads, several of them large — e.g.
`injector.ts` at 1,306 lines, `fastify-adapter.ts` at 800+ lines), authoring the ~970-line
`docs/arch/architecture-overview.md` plan (9 cells) incrementally — one `Write` for the skeleton,
then one `Edit` per cell or pair of cells — materializing it by hand to 9 CODEMANIFEST files
(the `goga-apply`/`goga:apply` Skill invocation was attempted first and did not resolve, so
materialization followed `goga-apply`'s and `goga-cells-by-brainstorm`'s `SKILL.md` procedure
manually, per Amendment 1's documented fallback), 1 round of `goga lint` correction, and `goga
contract` drift spot-checks on 3 cells. Total wall-clock time for this phase: approximately
1.5–2 hours of continuous tool-call activity.

## manual_correction_time

Concentrated in one focused pass immediately after the first `goga lint` run: a scripted Python
pass stripped invalid backtick cross-references (method names, external/unimported interface
names, decorator literals, directory-path mentions, nested object-field names) across all 9
CODEMANIFEST files, followed by 8 targeted `Edit` calls fixing the remaining context-specific
lint errors (2 unused imports removed, 6 method-scoped invalid backtick references rephrased in
prose). This took a few minutes within the session; not separately clocked.

## number_of_manual_corrections

- **Lint correction rounds: 1** (`goga lint` was run 2 times total):
  1. Initial `goga lint` on the freshly materialized forest: **12 errors** across 5 of the 9
     cells — two rule types: `annotation_links_exists` (10 — invalid backtick references to a
     method-signature-scoped parameter name used outside that method's own annotation, e.g.
     `` `token` `` referenced inside `addModule`'s annotation when `token` is not one of
     `addModule`'s own parameters, or `` `container` `` referenced inside `RoutesResolver.resolve`'s
     method annotation when `container` is only a parameter of the enclosing entity's
     constructor, plus two literal npm-package-name mentions `` `@nestjs/platform-express` `` /
     `` `@nestjs/platform-fastify` `` that don't resolve to anything in-document) and
     `import_is_used` (2 — `Module` and `HttpException` were imported into `packages/core/router`
     but never referenced by a resolvable backtick anywhere in that cell's body).
  2. All 12 fixed: the two unused imports were removed from `Imports.Types`; the ten invalid
     backtick references were rephrased in plain prose (no code, no lost meaning — e.g. "looked
     up in `module`'s injectables" → "looked up in the current module's injectables"). Re-lint:
     **0 errors**.
  A related, non-error cleanup pass (done proactively before the first lint run, based on
  Amendment 1's explicit warning that "backtick references... for arbitrary method names... produce
  lint errors") removed roughly 70 additional backtick-wrapped method names, external interface
  names (`CanActivate`, `PipeTransform`, `NestInterceptor` — real NestJS interfaces, but not
  imported into any of these 9 cells, so not valid link targets per the DSL), decorator literals
  (`@Global()`, `@UseGuards()`, etc.), and directory-path mentions (`` `core/router` ``) before
  that first lint run — this preemptive pass is why the first (and only) lint run already came
  back with just 12 errors rather than the ~200+ seen in the R01 validation run.
- **Contract-drift corrections: 0.** `goga contract` was run against 3 cells
  (`packages/core/injector`, `packages/core/adapters`, `packages/core/router`) but returned
  `"implementation": null` for every single signature, property, and method across all 3 cells
  (confirmed: 38/38 fields null for `packages/core/injector` alone). Root cause: this repository
  is TypeScript, and `goga contract` has no `typescript` language option (`goga contract --lang
  typescript` errors with `unsupported language: typescript`; the only options are `python`,
  `golang`, `kotlin`, `swift`, `javascript`). Under `--lang javascript` (this project's configured
  language, per the assignment's own instruction that Goga's JS tree-sitter grammar family covers
  JS/TS), the extractor could not parse any of the real `.ts` source files' TypeScript-specific
  syntax (interface bodies, generics, access modifiers, `abstract`, decorators) into an
  implementation signature, so it silently returned `null` rather than a mismatch. This is a
  genuine tool-capability gap for this repository, not evidence that the CODEMANIFEST content is
  wrong — every signature in the forest was instead verified manually against the real source
  during authoring (each cell's table entry above cites the exact file read). No corrections were
  made based on `goga contract`'s output because it produced no comparable signal.

## artifact_size

- **9 CODEMANIFEST files** (one per documented cell)
- **825 total lines** (`wc -l` across all 9 files in the deliverable directory)
- Cell sizes range from 62 lines (`packages/platform-fastify/adapters`) to 214 lines
  (`packages/core/injector`)
- **56 KB** total (`du -sh` on the deliverable `packages/` tree)
- No `.usages/` files were created — the one practice worth naming (`di_resolution`, describing
  the injector's module-graph traversal algorithm) was short and specific to one cell, so it was
  declared inline in `packages/core/injector/CODEMANIFEST`'s `Usages` section per
  `goga-cookbook`'s inline-vs-file guidance, rather than split into a separate `.goga/usages/` or
  `.usages/` file.

## contract_drift_findings

See "Contract-drift corrections: 0" above. `goga contract` could not produce a usable
implementation-side signal for this TypeScript repository under any supported `--lang` value, so
there is no drift finding to report beyond the tooling-gap itself. Manual verification (direct
source reading of `container.ts`, `module.ts`, `injector.ts`, `instance-wrapper.ts`,
`instance-loader.ts`, `http.exception.ts` and 4 concrete exception subclasses, `http-adapter.ts`,
`express-adapter.ts`, `fastify-adapter.ts`, `guards-consumer.ts`, `guards-context-creator.ts`,
`pipes-consumer.ts`, `pipes-context-creator.ts`, `params-token-factory.ts`,
`interceptors-consumer.ts`, `interceptors-context-creator.ts`, `routes-resolver.ts`,
`router-explorer.ts`, `router-execution-context.ts`) was the substitute verification method for
this repository, performed during authoring rather than as a separate post-hoc pass.

## maintenance_steps

N/A — one-time freeze, not yet exercised. Per `PROTOCOL.md` §6, this CODEMANIFEST forest is
frozen as-is for the duration of `benchmark-v1` and is not regenerated if `nestjs/nest` or Goga
change mid-benchmark.
