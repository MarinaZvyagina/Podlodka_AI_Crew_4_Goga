# SCOPE.md — R04 (excalidraw/excalidraw)

## Cells covered (5)

| Cell | Why covered |
|---|---|
| `packages/common/src` | No `Imports` (leaf); the single most widely depended-upon cell in the monorepo (event emitter, branded-type helper, color/keys/random/env utilities used by nearly every other package). Verified via real imports across `packages/element`, `packages/math`, `packages/excalidraw`. |
| `packages/fractional-indexing/src` | No `Imports` (leaf); a fully self-contained, dependency-free ordering-key algorithm that `packages/element/src` builds its canvas element ordering on top of. |
| `packages/math/src` | Depends only on `packages/common/src`; the pure 2D geometry layer (points, vectors, lines, curves, rectangles) shared by the scene/element system. |
| `packages/element/src` | Depends on `common`/`math`/`fractional-indexing`; the element & scene data model (`ExcalidrawElement`, `Scene`, mutation/duplication/binding/grouping/resizing) — the second most widely depended-upon cell in the monorepo. |
| `packages/excalidraw/actions` | Depends on `packages/element/src`; the action-registry extension point (`register`, `Action`, `ActionManager`) — the one designed-for-extension mechanism most directly relevant to this benchmark's "Existing Extension Point" task category (RQ7). |

## Scope reduction — disclosed, not hidden

An earlier draft of the architecture plan for this repository also scoped `packages/excalidraw` (root: `types.ts`/`appState.ts`/`history.ts`/etc.), `packages/excalidraw/scene`, `packages/excalidraw/data`, `packages/utils/src`, and `excalidraw-app` — 10 cells total, matching the original Implementation Order in `docs/arch/architecture-overview.md`'s draft history. During materialization, this was reduced to the 5 cells above to keep this one-time preparation session's cost/time bounded (this session hit repeated transport-layer failures during authoring — see `SETUP_COST.md` — and finishing all 10 cells to the same standard of real-source-grounding as the first 4 would have cost substantially more time).

**Why these 5 and not a different 5:** `common`/`fractional-indexing`/`math`/`element` are the deepest, most load-bearing shared foundation — every other package in the monorepo depends on them, directly or transitively. `packages/excalidraw/actions` was added as the 5th cell specifically because it is the one real, pre-existing extension-point mechanism in this repository (confirmed in Phase 3 reconnaissance, `tasks/R04/RECON_NOTES.md`), and covering it is directly relevant to testing RQ7 (does the Goga treatment change existing-extension-point usage rates) for Task C. The cut cells (`excalidraw` root, `scene`, `data`, `utils`, `excalidraw-app`) are real and load-bearing too, but were judged lower-priority for this benchmark's specific research questions than ensuring the extension point was covered.

This reduction was made and finalized **before** the plausibility check in `PLAUSIBILITY_CHECK.md` (i.e., before task prompts were read), so it was not tuned to any task's content — only to session cost constraints and the pre-registered priority (RQ7/extension points) stated in `TREATMENT_DESIGN.md`.
