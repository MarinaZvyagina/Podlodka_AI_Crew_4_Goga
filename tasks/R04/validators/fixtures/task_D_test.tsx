// Functional validator fixture for R04 Task D (one-click "snap selection to
// grid").
//
// Implementation-agnostic by design: it drives the feature exclusively
// through the pre-existing, stable public entry points `actionManager.
// executeAction()` and `createUndoAction(h.history)` -- the same dispatch
// path every other action in the app (and every other action's test file,
// e.g. actionAlign.tsx's tests) goes through -- rather than any internal
// helper the candidate might introduce. The one candidate-defined symbol it
// needs, `actionSnapSelectionToGrid`, is expected to be exported from the
// actions barrel (`packages/excalidraw/actions/index.ts`) under this literal
// name -- the natural name for this feature, following this codebase's own
// verb+noun action-naming convention (actionAlign*, actionToggle*, ...).
//
// This merges two originally-separate observations into one fixture:
//   1) "does it look snapped" -- x/y/width/height end up on the grid, only
//      for the intended targets (ticket's core functional requirement).
//   2) "does undo/version-bumping actually work" -- a single undo fully
//      reverts the snap, and version/versionNonce are bumped on every
//      snapped element. This is the *architecture-sensitive* half: a
//      direct-property-mutation implementation can satisfy (1) while
//      silently failing (2), because the mutation never goes through
//      `mutateElement`/`captureUpdate: IMMEDIATELY` and therefore never
//      reaches the undo/redo stack. The ticket itself states "Undo ...
//      must revert the snap in a single step, exactly like every other
//      edit in the app," so this is a first-class functional requirement,
//      not just an architecture nicety.
import React from "react";

import { Excalidraw } from "../index";
import { actionSnapSelectionToGrid } from "../actions";
import { createUndoAction } from "../actions/actionHistory";
import { API } from "../tests/helpers/api";
import { act, render } from "../tests/test-utils";

const { h } = window;

const GRID_SIZE = 20;

describe("snap selection to grid", () => {
  beforeEach(async () => {
    await render(<Excalidraw handleKeyboardGlobally={true} />);
    API.setElements([]);
    act(() => {
      h.setState({ gridSize: GRID_SIZE });
    });
  });

  it("snaps only the selected shapes independently, leaving unselected shapes untouched", () => {
    const a = API.createElement({
      type: "rectangle",
      x: 13,
      y: 27,
      width: 53,
      height: 41,
    });
    const b = API.createElement({
      type: "rectangle",
      x: 101,
      y: 5,
      width: 33,
      height: 22,
    });
    const untouched = API.createElement({
      type: "rectangle",
      x: 7,
      y: 7,
      width: 17,
      height: 17,
    });
    API.setElements([a, b, untouched]);
    API.setSelectedElements([a, b]);

    act(() => {
      h.app.actionManager.executeAction(actionSnapSelectionToGrid);
    });

    const snappedA = h.elements.find((el) => el.id === a.id)!;
    const snappedB = h.elements.find((el) => el.id === b.id)!;
    const stillUntouched = h.elements.find((el) => el.id === untouched.id)!;

    for (const el of [snappedA, snappedB]) {
      expect(el.x % GRID_SIZE).toBe(0);
      expect(el.y % GRID_SIZE).toBe(0);
      expect(el.width % GRID_SIZE).toBe(0);
      expect(el.height % GRID_SIZE).toBe(0);
    }

    // matches manual drag-snap rounding: nearest multiple of grid size
    expect(snappedA.x).toBe(20);
    expect(snappedA.y).toBe(20);
    expect(snappedA.width).toBe(60);
    expect(snappedA.height).toBe(40);

    // unselected shape is untouched
    expect(stillUntouched.x).toBe(7);
    expect(stillUntouched.y).toBe(7);
    expect(stillUntouched.width).toBe(17);
    expect(stillUntouched.height).toBe(17);
  });

  it("applies to every shape on the canvas when nothing is selected", () => {
    const a = API.createElement({
      type: "rectangle",
      x: 13,
      y: 27,
      width: 53,
      height: 41,
    });
    const b = API.createElement({
      type: "ellipse",
      x: 101,
      y: 5,
      width: 33,
      height: 22,
    });
    API.setElements([a, b]);
    API.setSelectedElements([]);

    act(() => {
      h.app.actionManager.executeAction(actionSnapSelectionToGrid);
    });

    for (const el of h.elements) {
      expect(el.x % GRID_SIZE).toBe(0);
      expect(el.y % GRID_SIZE).toBe(0);
      expect(el.width % GRID_SIZE).toBe(0);
      expect(el.height % GRID_SIZE).toBe(0);
    }
  });

  it("bumps version/versionNonce on every snapped element (mutateElement, not direct assignment)", () => {
    const a = API.createElement({
      type: "rectangle",
      x: 13,
      y: 27,
      width: 53,
      height: 41,
    });
    API.setElements([a]);
    API.setSelectedElements([a]);

    const versionBefore = a.version;
    const versionNonceBefore = a.versionNonce;

    act(() => {
      h.app.actionManager.executeAction(actionSnapSelectionToGrid);
    });

    const snapped = h.elements.find((el) => el.id === a.id)!;
    expect(snapped.version).toBeGreaterThan(versionBefore);
    expect(snapped.versionNonce).not.toBe(versionNonceBefore);
  });

  it("a single undo fully reverts the snap in one step", async () => {
    // seed elements via initialData (rather than API.setElements after
    // mount) so the store has a committed "before" snapshot to diff
    // against, matching the pattern used by history.test.tsx.
    const a = API.createElement({
      type: "rectangle",
      x: 13,
      y: 27,
      width: 53,
      height: 41,
    });
    const b = API.createElement({
      type: "rectangle",
      x: 101,
      y: 5,
      width: 33,
      height: 22,
    });

    await render(
      <Excalidraw
        handleKeyboardGlobally={true}
        initialData={{ elements: [a, b], appState: { gridSize: GRID_SIZE } }}
      />,
    );

    const preSnap = {
      a: { x: a.x, y: a.y, width: a.width, height: a.height },
      b: { x: b.x, y: b.y, width: b.width, height: b.height },
    };

    API.setSelectedElements([
      h.elements.find((el) => el.id === a.id)!,
      h.elements.find((el) => el.id === b.id)!,
    ]);

    act(() => {
      h.app.actionManager.executeAction(actionSnapSelectionToGrid);
    });

    // sanity: something actually changed
    const snappedA = h.elements.find((el) => el.id === a.id)!;
    expect(snappedA.x).not.toBe(preSnap.a.x);

    const undoAction = createUndoAction(h.history);
    act(() => {
      API.executeAction(undoAction);
    });

    const revertedA = h.elements.find((el) => el.id === a.id)!;
    const revertedB = h.elements.find((el) => el.id === b.id)!;

    expect(revertedA.x).toBe(preSnap.a.x);
    expect(revertedA.y).toBe(preSnap.a.y);
    expect(revertedA.width).toBe(preSnap.a.width);
    expect(revertedA.height).toBe(preSnap.a.height);

    expect(revertedB.x).toBe(preSnap.b.x);
    expect(revertedB.y).toBe(preSnap.b.y);
    expect(revertedB.width).toBe(preSnap.b.width);
    expect(revertedB.height).toBe(preSnap.b.height);
  });
});
