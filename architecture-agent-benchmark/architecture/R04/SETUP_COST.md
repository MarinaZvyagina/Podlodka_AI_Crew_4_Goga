# SETUP_COST.md — R04 (excalidraw/excalidraw)

## initial_generation_time

The original preparation agent spent substantial wall-clock time (multiple work sessions between roughly 16:18 and 19:00 on 2026-08-26, per file mtimes) authoring cells 1-4 (`common`, `fractional-indexing`, `math`, `element`) at 705 lines, but was cut off by a repeated transport-layer failure ("connection closed mid-response") four times in a row while attempting to author the remaining 5 originally-planned cells, always at the exact same step (about to write more plan content). After the fourth failure, the orchestrating session took over directly: added a 5th cell (`packages/excalidraw/actions`, ~100 lines, informed by direct reading of `packages/excalidraw/actions/types.ts`, `register.ts`, and `manager.tsx`), revised the Topic/Implementation Order/Dependency Map/Verification Checklist sections to consistently reflect a 5-cell scope (see `SCOPE.md` for the disclosed reduction), materialized all 5 CODEMANIFEST files by hand, ran `goga lint`, and fixed errors to a clean pass. This hand-off/completion phase took approximately 25 minutes of orchestrating-session wall-clock time.

## manual_correction_time / number_of_manual_corrections

**2 lint rounds** during the orchestrating session's completion phase:
- Round 1 (105 errors): 92 `annotation_links_exists` (invalid backtick cross-references — prose mentions of property names, constants, code snippets, and cross-cell method references that aren't valid DSL link targets; fixed via a scripted pass stripping backticks from exactly the flagged strings, same technique used successfully on R01/R02/R03/R06/R07/R08), 8 `signature_is_valid` (method signatures containing inline TypeScript arrow-function-type parameters like `(node: T) => number`, which the DSL signature parser cannot handle — fixed by replacing the inline function type with a plain `Function` type name), 3 `import_type_exists` (`Emitter`, `GlobalPoint`, `LocalPoint` referenced via `Imports` but not declared as their own top-level entities in the source cell — fixed by renaming `Emitter<T>()` to `Emitter()` so the import name-matching succeeds, and by adding explicit `GlobalPoint()`/`LocalPoint()` entity declarations to `packages/math/src`), 2 `import_is_used` (an unused `validateOrderKey` import removed from `packages/element/src`; `ExcalidrawElement` given an explicit backtick reference in `packages/excalidraw/actions`'s header Annotations, since a signature-only usage did not satisfy the check).
- Round 2 (3 errors): 2 more invalid backticks (`` `flush()` ``/`` `cancel()` `` — method-call-shaped text, not a valid link target) and 1 (`` `perform` `` used as a bare word in a HeaderNode annotation, also invalid) — all fixed by stripping backticks.
- Round 3: `goga lint` reported `cells: 5 errors: 0`.

## artifact_size

5 CODEMANIFEST files, 682 total lines (`common/src`: 142, `fractional-indexing/src`: 67, `math/src`: 121, `element/src`: 251, `excalidraw/actions`: 101). No separate `.usages/` files — all practices used the DSL's inline form.

## contract_drift_findings

`goga contract packages/common/src --lang javascript` returned `"implementation": null` for every documented method/property (e.g. `BinaryHeap`, `Emitter`). This matches a tool limitation independently discovered by the R03 (nestjs/nest) preparation session: Goga v1.2.2's `goga contract` has no `typescript` language option, and the `javascript` tree-sitter grammar it falls back to cannot reliably parse TypeScript class/interface syntax. This is a documented tooling gap, not a signal of content drift — all signatures in this forest were verified by direct reading of the real `.ts`/`.tsx` source files during authoring (see the cited `location:` file paths in each CODEMANIFEST), not inferred or guessed.

## maintenance_steps

N/A — one-time freeze, not yet exercised. If Excalidraw's real code changes after this freeze, this CODEMANIFEST forest is not automatically kept in sync (per `TREATMENT_DESIGN.md`, the forest is frozen before Phase 9 randomization and reused unchanged across all repetitions of all 4 tasks).
