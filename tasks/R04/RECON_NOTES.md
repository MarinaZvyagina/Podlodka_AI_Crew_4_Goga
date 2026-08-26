# R04 (excalidraw/excalidraw) — Task Design Recon Notes

Pinned commit: `e160ff7ba0641fba729c528482de5277ffb19c58`

Method: no full clone was performed. All evidence below was gathered via
`gh api repos/excalidraw/excalidraw/git/trees/<sha>?recursive=1` for the file tree, and
`curl -s https://raw.githubusercontent.com/excalidraw/excalidraw/<sha>/<path>` /
`gh api .../contents/<path>` for individual file contents, pinned to the exact commit
SHA above. No local clone was created, so there is nothing to `rm -rf`. Disk headroom
was in fact ~27GB free (`df -h /`), well above the stated 1.5GB clone threshold, but a
clone was avoided anyway since the API approach was sufficient and faster for this
recon.

Files fetched and inspected (raw content read via Read tool, cached under /tmp, not
part of the repo):
- `CLAUDE.md` (root)
- `packages/excalidraw/actions/manager.tsx`, `register.ts`, `types.ts`, `index.ts`
- `packages/excalidraw/actions/actionToggleGridMode.tsx`,
  `actionToggleObjectsSnapMode.tsx` (toggle-action template)
- `packages/excalidraw/actions/actionExport.tsx` (actionChangeProjectName)
- `packages/excalidraw/components/ProjectName.tsx`
- `packages/excalidraw/components/CommandPalette/CommandPalette.tsx`
- `packages/excalidraw/actions/shortcuts.ts`
- `packages/excalidraw/data/filesystem.ts`, `data/json.ts`
- `packages/excalidraw/components/Stats/index.tsx`, `Stats/Dimension.tsx`
- `packages/element/src/shape.ts` (getElementShape, ShapeCache), `types.ts`,
  `mutateElement.ts`, `align.ts`, `dragElements.ts`, `store.ts`, `Scene.ts`
- `packages/math/src/polygon.ts`, `math/src/index.ts`
- `packages/utils/src/shape.ts` (GeometricShape/Ellipse types)
- `packages/excalidraw/types.ts`, `appState.ts`, `index.tsx` (public entry point)
- `packages/excalidraw/components/App.tsx` (grep only, 13,949 lines — targeted greps
  for `scene.mutateElement`, `store.scheduleAction`, `store.commit`, `getName`)
- `packages/{math,element,utils,common,excalidraw}/package.json` (dependency direction)

## Task A — Local Change: filename sanitization

Evidence:
- `packages/excalidraw/components/ProjectName.tsx` is a plain controlled `<input>` with
  no validation whatsoever — `onChange`/`onBlur` pass the raw string straight to
  `props.onChange`.
- `packages/excalidraw/actions/actionExport.tsx`'s `actionChangeProjectName` (register()'d
  action) takes that raw string and puts it directly into `appState.name` with zero
  sanitization.
- `packages/excalidraw/data/filesystem.ts`'s `fileSave()` builds
  `` fileName: `${opts.name}.${opts.extension}` `` directly from that string — no escaping,
  no reserved-character stripping, no empty-string handling.
- `packages/excalidraw/data/json.ts`'s `saveAsJSON()` passes `filename` straight into
  `fileSave()`.
- Confirmed via `App.tsx` (`getName()`, line ~6092) that there IS an existing fallback for
  *empty* app state (`state.name || props.name || "untitled-<date>"`), but this only
  covers `appState.name` being falsy — it does nothing for a non-empty string containing
  filesystem-illegal characters, which is the actual gap.
- This entire flow lives inside `packages/excalidraw` only; nothing in `excalidraw-app`,
  `packages/element`, or `packages/math` is involved. Confirmed genuinely single-layer
  → appropriate scope for Task A ("should NOT require touching multiple architectural
  layers").

## Task B — Cross-module Feature: shape area readout

Evidence of the real, already-existing cross-package geometry chain this feature would
naturally have to touch:
- `packages/excalidraw/components/Stats/index.tsx` (the live per-selection stats panel)
  **already imports directly from `@excalidraw/element` and `@excalidraw/math`**
  (`clamp`, `round` from math; `getUncroppedWidthAndHeight`, `resizeSingleElement`,
  etc. from element) — i.e. this exact UI surface is already an established
  cross-package consumer, not something that should get new geometry logic
  reimplemented inline.
- `packages/math/src/polygon.ts` already defines `polygonSignedArea` /
  `polygonArea` — a general shoelace-formula polygon-area function, exported from the
  package's public `index.ts`.
- `packages/element/src/shape.ts` already defines `getElementShape(element,
  elementsMap): GeometricShape<Point>`, a per-element-type dispatcher (rectangle/diamond
  → `getPolygonShape`; ellipse → `getEllipseShape`; line/arrow/freedraw → curve/closed-curve
  shapes) used today for hit-testing/collision — i.e. the "what shape is this element,
  geometrically" problem is already solved once, generically, in the element layer.
- `GeometricShape`, `Ellipse`, `Polygon` types live in `packages/utils/src/shape.ts`
  (imported by `packages/element/src/shape.ts` via `@excalidraw/utils/shape`) — a
  fourth package in the chain.
- `packages/element/src/types.ts` line 346 confirms `ExcalidrawLineElement.polygon:
  boolean` — closed/polygon-mode lines are a first-class, real, existing element concept,
  which is why "closed hand-drawn/multi-point shapes" in the task prompt is grounded and
  not invented.
- Verified dependency direction via each package's `package.json`: `common` (no
  internal deps) ← `math` (deps on common) ← `element` (deps on common, math,
  fractional-indexing) ← `excalidraw` (deps on common, element, math, ...). `utils` sits
  parallel (deps on laser-pointer, roughjs, etc., no declared dep on element/math
  despite importing them via workspace resolution — noted as a pre-existing repo
  quirk, not something the task should touch). This grounds the "forbidden
  dependencies: math/element must not depend on excalidraw" constraint.

This is a genuine 3-4 boundary crossing (excalidraw UI → element → utils → math), not
invented — the task only needed to ask for something the panel doesn't yet show (area),
using shapes that expose the real gap between "bounding box formula" and "actual
enclosed-region math" (closed lines / freedraw / rotated shapes).

## Task C — Existing Extension Point: action registry

Extension point verified by direct code reading (mechanism name/files intentionally
**not** mentioned anywhere in `task_C.md`):

- `packages/excalidraw/actions/register.ts`: `register(action)` appends to a shared
  module-level `actions: readonly Action[]` array.
- `packages/excalidraw/actions/types.ts`: `Action` interface — `name` (from a closed
  `ActionName` union), `label`, `icon`, `perform`, `keyTest`, `checked`, `predicate`,
  `trackEvent`, `viewMode`, `navigation`, optional `PanelComponent`.
- `packages/excalidraw/actions/manager.tsx`: `ActionManager` class —
  `registerAction`/`registerAll` populate `this.actions: Record<ActionName, Action>`;
  `handleKeyDown` iterates `this.actions`, filters by `canvasActions` gating and
  `action.keyTest(event, appState, elements, app)`, and on a unique match calls
  `action.perform(...)` and threads the result through `this.updater`; `executeAction`
  is the non-keyboard (UI/API/command-palette) dispatch path; `isActionEnabled` reads
  `action.predicate`; `renderAction` renders `action.PanelComponent`.
- Three real, structurally-identical toggle actions confirm this is the established
  pattern for exactly this class of feature (a drawing-wide boolean on/off switch with a
  keyboard shortcut and a checked state): `actionToggleGridMode.tsx` (Ctrl/Cmd+'),
  `actionToggleObjectsSnapMode.tsx` (Alt+S), and `actionToggleZenMode.tsx` (Alt+Z,
  confirmed present at `packages/excalidraw/actions/actionToggleZenMode.tsx` in the
  file tree). Each: `register({ name, icon, label, viewMode, trackEvent, perform(...)
  { return { appState: {...}, captureUpdate }; }, checked, predicate, keyTest })`.
- `packages/excalidraw/actions/shortcuts.ts` shows these three toggles are also listed
  in the keyboard-shortcut-help surface (`ShortcutName` union + a `shortcuts` map), and
  `packages/excalidraw/components/CommandPalette/CommandPalette.tsx` shows registered
  actions (including `gridMode`, `objectsSnapMode`, `zenMode`) are explicitly pulled
  into the command-palette item list via `actionManager.actions.<name>`.
- `packages/excalidraw/types.ts` confirms the naming convention for this class of state:
  `zenModeEnabled: boolean`, `gridModeEnabled: boolean`, `objectsSnapModeEnabled:
  boolean`, `viewModeEnabled: boolean` all live directly on `AppState`.

Naming leak check for `task_C.md`: re-read the final prompt text — it contains no
occurrence of "action", "register", "ActionManager", "extension point", "plugin",
"handler", or any file/class name from the above. It only describes user-facing
behavior (a switch reachable from "the same places... other drawing-wide display
toggles" and "keyboard shortcut", "shows its current on/off state the way similar
switches do elsewhere") — enough for an agent that explores the codebase to discover
gridMode/zenMode/objectsSnapMode as a natural template, without being told the
mechanism exists.

Feature-collision check: confirmed no existing appState field or action already hides
bound text captions (grepped `types.ts` for `ModeEnabled` fields and `actions/index.ts`
for anything caption/label/text-visibility related — none found), so this is a genuinely
net-new, non-duplicate feature request.

## Task D — Architecture Trap: one-shot "snap selection to grid"

Evidence for the "correct" path:
- `packages/excalidraw/actions/actionAlign.tsx` (`alignSelectedElements`) →
  `packages/element/src/align.ts`'s `alignElements()` → confirmed (grep) it calls
  `scene.mutateElement(element, {...})` for each moved element — the established
  pattern for "action bulk-updates several elements' geometry."
  `actionAlignHorizontallyCentered` (and siblings) return `{ appState, elements:
  alignSelectedElements(...), captureUpdate: CaptureUpdateAction.IMMEDIATELY }`.
- `packages/element/src/mutateElement.ts`: `mutateElement()` bumps `element.version`,
  `element.versionNonce`, `element.updated`, and — critically — its own doc comment
  says in-place mutation "won't trigger the component to update, so if you need to
  trigger component update, use `scene.mutateElement` or
  `ExcalidrawImperativeAPI.mutateElement` instead." This is direct, in-repo evidence
  that a naive "just assign the properties and force a re-render" approach is a
  known-wrong pattern the codebase explicitly warns against.
- `packages/element/src/store.ts`: `CaptureUpdateAction.IMMEDIATELY` doc comment states
  verbatim: "Immediately undoable... These updates will _immediately_ make it to the
  local undo/redo stacks," versus `NEVER`: "these updates will _never_ make it to the
  local undo/redo stacks." This is exactly the mechanism whose bypass Task D's trap
  hinges on.
- `App.tsx` line 3025: `this.store.scheduleAction(actionResult.captureUpdate)` is the
  single place an action's returned `captureUpdate` value feeds into history capture —
  confirming a `perform()` that doesn't return `elements`/`captureUpdate` through the
  normal action-result path never reaches the history/undo system, no matter how the
  screen is made to re-render.
- `App.tsx` contains 20+ call sites of `this.scene.mutateElement(...)` for in-editor
  interactions outside of `actions/` too (drag, resize, frame membership, crop, etc.),
  confirming `scene.mutateElement` (not raw property assignment) is the codebase-wide
  convention for "the user did something that changes element geometry," not an
  action-specific quirk.
- `ShapeCache` (`packages/element/src/shape.ts`) is a `WeakMap<ExcalidrawElement, ...>`
  keyed by object identity; `mutateElement` explicitly calls `ShapeCache.delete(element)`
  when `width`/`height`/`points`/`fileId` change. A trap implementation that mutates
  width/height in place without going through `mutateElement` would leave a stale
  cached rough-shape — a secondary, real (if harder to assert in a quick test)
  consequence, mentioned in the metadata's architectural_constraints as supporting
  evidence but not used as a primary check since it's harder to assert deterministically
  than undo/version/captureUpdate.
- No existing "snap already-placed shapes to grid in one action" command was found:
  grid snapping today only fires live during drag (`packages/element/src/
  dragElements.ts` imports and calls `getGridPoint` from `@excalidraw/common`). This
  confirms the feature is a genuine gap, not a duplicate of existing functionality.

## Confirmation: no extension-point / internal-name leakage across all 4 prompts

Re-read `task_A.md`, `task_B.md`, `task_C.md`, `task_D.md` after drafting. None of them
mention: `Action`, `register`, `ActionManager`, `mutateElement`, `scene`, `CaptureUpdateAction`,
`GeometricShape`, `polygonArea`, `getElementShape`, `AppState`, `ShapeCache`,
class/file/module names, or any package path. All four read as ordinary user-facing
bug reports / feature requests, matching the "good" example style in Research.md §22
(behavior description only, no `PaymentRepository`-style internal naming).

## Task category sanity check

- **A (local_change)**: confined to `packages/excalidraw` UI/data glue only (component +
  one action + one data-layer save function); does not require understanding
  element/math geometry or the app/library boundary.
- **B (cross_module_feature)**: genuinely requires touching (at minimum) the
  `packages/excalidraw` UI layer and `packages/element`'s shape dispatch, and very
  plausibly `packages/math`'s polygon area function and `packages/utils`'s
  `GeometricShape` types too — 3-4 real boundaries, verified via actual imports in the
  pinned commit, not hypothesized.
- **C (existing_extension_point)**: mechanism (`register`/`ActionManager`) verified by
  reading its implementation and three real analogous features; task prompt withholds
  all internal naming; a plausible parallel-mechanism failure mode (bespoke
  `useState` + a second `keydown` listener) is identified and encoded as the negative
  control.
- **D (architecture_trap)**: "easy" implementation (direct property mutation + forced
  re-render) is real, compiles, and would visually "work" for a shallow functional
  check; "correct" implementation (`scene.mutateElement` + `captureUpdate:
  IMMEDIATELY`) is the codebase's own established, documented convention, not an
  invented rule. Undo-after-action is used as the primary, cheaply automatable
  functional/architecture-discriminating check (AC1), which is both realistic to
  write and hard to satisfy by accident if the trap path is taken.
