# PLAUSIBILITY_CHECK.md — R04 (excalidraw/excalidraw)

## When this check was performed

`tasks/R04/task_A.md` through `task_D.md` were read for the first time by the orchestrating session **after** the 5-cell forest was authored, materialized, linted to zero errors, and `SCOPE.md`/`SETUP_COST.md` were already written and frozen. No CODEMANIFEST content was revised as a result of this check.

## The four task prompts (summarized)

- **Task A**: sanitize a drawing's name so it's always a valid, safe file name on save/export.
- **Task B**: add a live shape-area readout to the stats panel, correct for rotated/non-rectangular/closed shapes.
- **Task C**: a single on/off switch to hide/show all shape captions instantly and non-destructively.
- **Task D**: one-click "snap selected shapes to grid," with correct single-step undo and collaboration sync.

## Term-level check

Grepped all 5 CODEMANIFEST files for task-specific vocabulary: "filename", "sanitiz", "area", "polygon", "caption", "snap", "grid". None appear. No annotation reads like "add caching here" or "implement snap-to-grid" — every annotation describes what a real, already-existing class/function does today (`Emitter`, `BinaryHeap`, `pointFrom`, `ExcalidrawElement`, `mutateElement`, `register`, `ActionManager`), consistent with `TREATMENT_DESIGN.md` §4's required phrasing style.

## Where overlap exists, and why it's expected rather than leakage

- **Task A ↔ forest: no overlap.** Task A's relevant real code (`packages/excalidraw/components/ProjectName.tsx`, `data/filename.ts`, `data/filesystem.ts`, per `tasks/R04/RECON_NOTES.md`) lives entirely in the `packages/excalidraw` root cell, which is **out of scope** for this 5-cell forest (see `SCOPE.md`'s disclosed reduction). An agent in the Goga condition gets no more help on this task than an agent in Baseline.
- **Task B ↔ forest: weak, generic overlap only.** `packages/math/src`'s CODEMANIFEST documents general geometry primitives (`pointDistance`, `curveLength`, `rectangleIntersectRectangle`, branded `GlobalPoint`/`LocalPoint` types) but does **not** document any area-computation function — `polygonArea`/`getElementShape` (the real functions Task B's positive control uses, per `tasks/R04/RECON_NOTES.md`) are not covered by this forest at all. An agent gets confirmation that a geometry layer exists and how it's typed, not a pointer to an area function.
- **Task C ↔ `packages/excalidraw/actions`: the closest overlap, and an intended one.** Task C ("hide all shape captions, single on/off switch, reachable from menu+shortcut, non-destructive") is a near-textbook new `Action` registered via `register()`, exactly matching this cell's documented extension point. The CODEMANIFEST never mentions captions, hiding, or any wording from the task — it describes the *mechanism* (`Action`, `register`, `ActionManager.executeAction`) using only real, pre-existing names. This is Task C's category by design ("Existing Extension Point... prompt does not name it — agent must discover it or fail to"), and `packages/excalidraw/actions` was deliberately prioritized as the 5th cell specifically because it is this repository's real, verified extension point (see `SCOPE.md`) — documenting it generically is the mechanism the Goga condition is meant to test, not an accidental giveaway.
- **Task D ↔ `packages/element/src`: a real, load-bearing overlap, also expected.** Task D's core requirement (single-step undo, correct sync to collaborators) maps directly onto this cell's documented `Store` entity ("captures observed element/app-state changes and emits them as increments consumed by... undo/redo `History`") and the `mutateElement` routine's documented constraint ("does not itself trigger a UI update — use `Scene.mutateElement` when a re-render is needed" / prefer this over direct field assignment). This is exactly the architectural fact Task D is designed to test whether an agent discovers and respects (per `tasks/R04/RECON_NOTES.md`'s trap: direct `element.x = ...` mutation bypasses undo capture). The forest states this as a general constraint on how any code should update elements — it does not mention grids, snapping, or Task D's scenario at all.

## Outcome

No revision was made to the architecture forest as a result of this check. Two of the four tasks (C and D) have genuine, real overlap with documented cells — both judged to be the intended operation of documenting real, load-bearing mechanisms (an extension point and a mutation/undo invariant) rather than task-specific hint content, consistent with the same reasoning applied in R01's, R02's, and R06's plausibility checks. Task A has zero overlap (out-of-scope cell) and Task B has only generic, non-specific overlap — a legitimate, uneven distribution of expected treatment effect across task types (relevant to RQ9), not evidence of cherry-picking.
