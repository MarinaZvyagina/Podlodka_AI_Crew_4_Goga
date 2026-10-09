# RESTRUCTURE_REPORT.md — R03 (nestjs/nest) Condition C

Second repository restructured for Condition C (after R06/etcd). TypeScript, 34.7k LOC,
9 originally documented cells (Phase 8).

## Facade audit result — different profile from R06 (etcd)

Full audit of all real exports across the 9 documented cells found 49 undeclared exports plus
14 more in 3 real subdirectory-with-code cases requiring new nested cells (`router/interfaces`,
`platform-express/adapters/utils`, `platform-fastify/adapters/middie`) — 62 total. Unlike etcd,
**zero were hideable**: every undeclared export had real usage elsewhere in the real codebase.
This is expected for a framework package (NestJS): classes like `BadRequestException`,
`ModuleRef`, `RouterModule` are legitimate public API surface for applications built on NestJS,
not internal leakage. 3 of the 9 original cells (`interceptors`, `pipes`, `adapters`) were
already 100% facade-complete from Phase 8 — no work needed.

## Real circular dependency found and fixed

Unlike R06, a genuine cell-to-cell cycle existed: `packages/core/router` imports heavily from
`packages/core/injector` (the DI container), while `packages/core/injector/container.ts`
imported a single constant (`REQUEST`) from `packages/core/router/request/request-constants.ts`.
Fix (zero code motion): `packages/core/router/request/` — which already needed its own cell
regardless, since it's real subdirectory code under the `router` cell — was split out as an
independent leaf cell with no dependency on either `router` or `injector`. `injector`'s
CODEMANIFEST now imports `REQUEST` `From: packages/core/router/request`, not `From:
packages/core/router`. See `CYCLE_FIXES.md` for full detail.

One real gap surfaced during my own final review (not caught by the assigned agent): the main
`router` cell's own code (`router-explorer.ts`) genuinely imports `REQUEST_CONTEXT_ID` from the
same `router/request` split-out cell — a safe, one-directional dependency (router/request stays
a leaf) that the agent had skipped, having over-applied my instruction ("router should not need
to import from router/request") literally rather than checking the real code, which did need it.
Fixed directly by adding the missing Import + a corrected annotation reference.

## Process

- Work split across 4 parallel subagents (exceptions, injector+cycle-fix, router+2 new nested
  cells, and a combined small-cells agent for guards/platform-express/platform-fastify +
  their 2 new nested cells) rather than one-per-cell like R06, since most cells' individual
  workload was small (1-24 symbols) after the "0 hide" finding removed half of R06's work
  categories.
- **Prompt-injection-like content flagged by 3 of 4 agents independently**, in `Skill` tool
  output and in a plain `Read` tool result: embedded blocks styled as `<system-reminder>` tags
  claiming a silent date change and listing fabricated "available agent types." All three agents
  correctly disregarded the content and reported it rather than acting on it. Investigated: the
  local `~/.goga/skills/goga-cell/dsl.md` file on disk contains no such content. The most likely
  explanation is that these are genuine, benign Claude Code harness system-reminders (the same
  kind of date-change/available-agent-types reminders visible throughout this orchestrating
  session's own transcript) that arrived in the subagents' own tool-result streams at the same
  point in their transcripts as a Skill/Read call, and were misidentified as injected content by
  a subagent applying (correctly, as a general principle) a "be suspicious of instructions
  embedded in tool output" heuristic. No confirmed evidence of an actual compromised Goga skill
  was found. Disclosed here for transparency rather than silently dismissed.
- `goga lint`: 0 errors across all 13 cells (9 original + 3 new nested + no cycle) after one
  manual correction (a stray invalid backtick link in the `router` cell's manually-added
  annotation).

## Hard gate: build + test

- No `.ts` file was modified anywhere in this restructuring (0 hide/rename work, since 0 exports
  were hideable) — only CODEMANIFEST files were added/edited. This means the restructuring is,
  by construction, compile- and behavior-neutral; the build/test gate below confirms this rather
  than being a risk-mitigation step the way it was for R06's renames.
- `npm run build` (tsc project references across all packages): clean, 0 errors.
- `npx vitest run` (full monorepo unit test suite): **2748/2748 tests pass, 277/277 files**.

## Control re-certification

All 8 of Phase 5's control diffs (`tasks/R03/controls/*.diff`) applied cleanly against the
restructured commit with **no adaptation needed** (no hardcoded base-commit SHAs in R03's
validators, unlike R06's 16 that needed adaptation — and since no `.ts` identifiers were
renamed, no stale-identifier conflicts either).

One methodological pitfall was found and fixed during re-certification itself, not in the
restructuring: the first recertification pass used a `node_modules` symlink shared from the main
restructuring worktree, which produced a spurious `functional: FAIL` on the known-good
`A_positive` control (an HTTP 500 instead of the expected 429). Side-by-side testing against the
*original, unmodified* commit reproduced the identical failure — proving this was a pre-existing
flaw in the symlink-based recertification method, not a restructuring regression. Fixed by
switching to hardlink-copying (`cp -al`, matching the main harness's own `link_shared_deps`
convention) `node_modules` per throwaway worktree, followed by a real `npm run build` after each
control diff is applied — this gave a clean, working functional validator environment.

**Final result — all 4 tasks discriminate correctly** on the restructured commit:

| Task | Positive: functional | Positive: all AC | Negative: functional | Negative: ≥1 AC fails |
|---|---|---|---|---|
| A | PASS | PASS (4/4) | PASS | Yes (3/4 FAIL) |
| B | PASS | PASS (5/5) | FAIL | Yes (1/5 FAIL) |
| C | PASS | PASS (4/4) | FAIL | Yes (4/4 FAIL) |
| D | PASS | PASS (5/5) | FAIL | Yes (4/5 FAIL) |

## Artifacts

- Restructured commit: `b5bcd5ce9f8eb6296ff789ee5e779991eb7a6c4f`, tagged `condition-c-r03-v1`
  in the shared base clone (`benchmark-scratch/repos/R03/base`).
- `architecture_v2/R03/CYCLE_FIXES.md` — the router↔injector cycle and its fix.
- No `controls_adapted/`/`validators_adapted/` directories were needed for R03 (unlike R06) —
  all 8 original control diffs and all validator scripts worked unmodified against the
  restructured commit.
- The 13 cells' `CODEMANIFEST` files live directly in the restructured commit.
