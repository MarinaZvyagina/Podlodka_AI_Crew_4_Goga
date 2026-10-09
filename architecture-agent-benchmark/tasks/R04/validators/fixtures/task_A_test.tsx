// Functional validator fixture for R04 Task A (filename sanitization).
//
// Implementation-agnostic by design: it drives the *existing*, pre-existing
// registered action `actionChangeProjectName` (packages/excalidraw/actions/
// actionExport.tsx) exactly the way a user commits a new drawing name, and
// only ever asserts against the *observable* committed name
// (`h.state.name`) -- the stable public surface any correct fix must flow
// through, regardless of whether the candidate solution centralizes
// sanitization in a new helper module, inlines it in the action, or
// (incorrectly, per the architecture check) duplicates it across files.
//
// It does NOT import any new file/symbol the candidate might introduce
// (e.g. a hypothetical `sanitizeFilename` helper), so it runs unmodified
// against any implementation that fixes the underlying bug.
import React from "react";

import { Excalidraw } from "../index";
import { API } from "../tests/helpers/api";
import { act, render } from "../tests/test-utils";

import { actionChangeProjectName } from "./actionExport";

const { h } = window;

const RESERVED_CHARS = /[\\/:*?"<>|]/;

const commitName = (value: string) => {
  act(() => {
    h.app.actionManager.executeAction(actionChangeProjectName, "api", value);
  });
};

describe("project name sanitization (drawing name -> safe file name)", () => {
  beforeEach(async () => {
    await render(<Excalidraw />);
  });

  it("strips reserved filesystem characters from the committed name", () => {
    commitName("my/plan:v2*final?.txt.");
    expect(RESERVED_CHARS.test(h.state.name ?? "")).toBe(false);
  });

  it("strips <, > from the committed name", () => {
    commitName("a<b>c");
    expect(h.state.name).toBe("abc");
  });

  it("falls back to a non-empty default name for an empty string", () => {
    commitName("");
    expect(h.state.name).toBeTruthy();
    expect((h.state.name ?? "").length).toBeGreaterThan(0);
  });

  it("falls back to a non-empty default name for a whitespace-only string", () => {
    commitName("   ");
    expect(h.state.name).toBeTruthy();
    expect((h.state.name ?? "").length).toBeGreaterThan(0);
  });

  it("strips a trailing dot", () => {
    commitName("trailing.");
    expect((h.state.name ?? "").endsWith(".")).toBe(false);
    expect(h.state.name).not.toBe("");
  });

  it("strips trailing whitespace", () => {
    commitName("trailing ");
    expect((h.state.name ?? "").endsWith(" ")).toBe(false);
    expect(h.state.name).not.toBe("");
  });

  it("never leaves a name that starts/ends with a dot or whitespace, or contains reserved chars", () => {
    const cases = [
      "my/plan:v2*final?.txt.",
      "",
      "   ",
      "a<b>c",
      "trailing.",
      "trailing ",
      '"quoted"|pipe\\back/slash',
    ];
    for (const input of cases) {
      commitName(input);
      const result = h.state.name ?? "";
      expect(result.length).toBeGreaterThan(0);
      expect(/^[.\s]/.test(result)).toBe(false);
      expect(/[.\s]$/.test(result)).toBe(false);
      expect(RESERVED_CHARS.test(result)).toBe(false);
    }
  });
});
