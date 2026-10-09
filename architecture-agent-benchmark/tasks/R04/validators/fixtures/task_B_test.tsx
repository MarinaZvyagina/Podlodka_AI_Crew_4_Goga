// Functional validator fixture for R04 Task B (live shape-area readout in
// the Stats panel).
//
// Implementation-agnostic by design: it drives the feature the way a user
// would (right-click canvas -> "Stats" -> select a shape) and reads the
// resulting value out of the DOM. It does not import any new
// symbol/module the candidate might introduce (e.g. a hypothetical
// `getElementArea` helper) -- only the pre-existing public `Excalidraw`
// component and test helpers.
//
// Value lookup is two-tiered:
//   1) the repo's existing testid convention for Stats rows (see
//      `stats-element-type` in Stats/index.tsx) -- `stats-area` is the
//      natural name under that convention.
//   2) a generic fallback that scans every `.exc-stats__row` (the existing,
//      pre-existing StatsRow wrapper class -- not introduced by this
//      feature) for a two-column row whose first cell reads "Area"
//      (case-insensitive), so a correct implementation that reuses
//      StatsRow but skips the "stats-area" testid is still recognized.
//
// NOTE: per this task's own control results, the *functional* behavior
// (correct area numbers) is expected to PASS for both the positive control
// and the architecturally-trapped negative control (the negative's ad hoc
// formulas happen to be numerically correct for these test shapes) --
// distinguishing them is the job of the architecture check (AC2: no inline
// geometry formulas), not this functional validator.
import { degreesToRadians, pointFrom } from "@excalidraw/math";
import { fireEvent, queryByTestId } from "@testing-library/react";
import React from "react";

import type { Degrees } from "@excalidraw/math";
import type { LocalPoint } from "@excalidraw/math";
import type { ExcalidrawElement } from "@excalidraw/element/types";

import { Excalidraw } from "../..";
import { API } from "../../tests/helpers/api";
import { GlobalTestState, render } from "../../tests/test-utils";
import { UI } from "../../tests/helpers/ui";

const { h } = window;

const openStatsPanel = () => {
  // the "stats" toggle only appears in the *canvas* context menu (nothing
  // selected), not the per-element one, so open it before selecting anything.
  fireEvent.contextMenu(GlobalTestState.interactiveCanvas, {
    button: 2,
    clientX: 1,
    clientY: 1,
  });
  const contextMenu = UI.queryContextMenu();
  fireEvent.click(queryByTestId(contextMenu!, "stats")!);
};

const selectAndReadElementStats = (element: ExcalidrawElement) => {
  API.setElements([element]);
  API.setSelectedElements([element]);

  const stats = UI.queryStats();
  const elementStats = stats?.querySelector("#elementStats");
  return elementStats;
};

const readAreaValue = (elementStats: Element | null | undefined) => {
  if (!elementStats) {
    return null;
  }

  // primary: existing repo testid convention (see "stats-element-type")
  const row = queryByTestId(elementStats as HTMLElement, "stats-area");
  if (row) {
    const valueDiv = row.querySelectorAll("div")[1];
    return valueDiv ? Number(valueDiv.textContent) : null;
  }

  // fallback: any StatsRow (pre-existing wrapper, not introduced by this
  // feature) whose label cell reads "Area"
  const rows = Array.from(elementStats.querySelectorAll(".exc-stats__row"));
  for (const r of rows) {
    const cells = r.querySelectorAll(":scope > div");
    if (
      cells.length >= 2 &&
      /^area$/i.test(cells[0].textContent?.trim() || "")
    ) {
      return Number(cells[1].textContent);
    }
  }

  return null;
};

describe("Stats panel: live shape area readout", () => {
  beforeEach(async () => {
    await render(<Excalidraw handleKeyboardGlobally={true} />);
    API.setElements([]);
    openStatsPanel();
  });

  it("rectangle: area = width * height, unchanged by rotation", () => {
    const rect = API.createElement({
      type: "rectangle",
      x: 0,
      y: 0,
      width: 120,
      height: 40,
    });
    const elementStats = selectAndReadElementStats(rect);
    expect(readAreaValue(elementStats)).toBeCloseTo(120 * 40, 1);

    const rotated = API.createElement({
      type: "rectangle",
      x: 0,
      y: 0,
      width: 120,
      height: 40,
      angle: degreesToRadians(30) as Degrees,
    });
    const rotatedStats = selectAndReadElementStats(rotated);
    expect(readAreaValue(rotatedStats)).toBeCloseTo(120 * 40, 1);
  });

  it("ellipse: area = pi * (w/2) * (h/2)", () => {
    const ellipse = API.createElement({
      type: "ellipse",
      x: 0,
      y: 0,
      width: 80,
      height: 50,
    });
    const elementStats = selectAndReadElementStats(ellipse);
    expect(readAreaValue(elementStats)).toBeCloseTo(Math.PI * 40 * 25, 1);
  });

  it("diamond: area = (width * height) / 2", () => {
    const diamond = API.createElement({
      type: "diamond",
      x: 0,
      y: 0,
      width: 100,
      height: 60,
    });
    const elementStats = selectAndReadElementStats(diamond);
    expect(readAreaValue(elementStats)).toBeCloseTo((100 * 60) / 2, 1);
  });

  it("closed non-rectangular polygon-mode line: area = shoelace area of the actual points, not the bounding box", () => {
    const points: LocalPoint[] = [
      pointFrom(0, 0),
      pointFrom(100, 0),
      pointFrom(50, 100),
      pointFrom(0, 0),
    ];
    const line = API.createElement({
      type: "line",
      x: 0,
      y: 0,
      width: 100,
      height: 100,
      points,
      polygon: true,
      backgroundColor: "#000000",
    });
    const elementStats = selectAndReadElementStats(line);
    const area = readAreaValue(elementStats);
    expect(area).not.toBeNull();
    // true (shoelace) area of the triangle
    expect(area!).toBeCloseTo(5000, 0);
    // must differ measurably from the bounding-box area (100*100=10000)
    expect(Math.abs(area! - 100 * 100)).toBeGreaterThan(1000);
  });

  it("open line: no area row shown", () => {
    const points: LocalPoint[] = [
      pointFrom(0, 0),
      pointFrom(100, 0),
      pointFrom(50, 100),
    ];
    const line = API.createElement({
      type: "line",
      x: 0,
      y: 0,
      width: 100,
      height: 100,
      points,
      backgroundColor: "transparent",
    });
    const elementStats = selectAndReadElementStats(line);
    expect(readAreaValue(elementStats)).toBeNull();
  });

  it("arrow: no area row shown", () => {
    const arrow = API.createElement({
      type: "arrow",
      x: 0,
      y: 0,
      width: 100,
      height: 50,
    });
    const elementStats = selectAndReadElementStats(arrow);
    expect(readAreaValue(elementStats)).toBeNull();
  });

  it("text: no area row shown", () => {
    const text = API.createElement({
      type: "text",
      x: 0,
      y: 0,
      width: 100,
      height: 25,
    });
    const elementStats = selectAndReadElementStats(text);
    expect(readAreaValue(elementStats)).toBeNull();
  });
});
