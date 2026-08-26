// Functional validator fixture for R04 Task C (hide-captions toggle).
//
// Implementation-agnostic by design: the ticket never names a mechanism,
// appState field, or keyboard shortcut, so this fixture drives the feature
// purely through the *visible* UI surfaces the ticket describes ("reachable
// from the same places users already go to trigger other drawing-wide
// display toggles ... menu ... shows its current on/off state the way
// similar switches do elsewhere"), using the exact same surfaces the
// codebase's own sibling toggles (grid mode, zen mode) use by default:
//
//   1) the canvas right-click context menu (`.context-menu`, built by
//      `App.getContextMenuItems()` from the list of registered actions --
//      this is how gridMode/zenMode are reachable out of the box, per this
//      repo's own `tests/excalidraw.test.tsx`). Each item's "on" state is
//      read via the generic `checkmark` CSS class every action-backed
//      context-menu item gets from `action.checked?.(appState)` --
//      independent of any specific appState field name.
//   2) as a fallback, the main hamburger menu when the host app composes
//      `<MainMenu><MainMenu.DefaultItems.Preferences/></MainMenu>` (the
//      officially exported location for exactly this class of toggle,
//      alongside `PreferencesToggleGridModeItem` etc.), reading "on" state
//      via the shared `DropdownMenuItemCheckbox` icon convention (a
//      checkmark svg vs. an empty placeholder).
//
// It does NOT assume a specific appState field name (e.g.
// `captionsHiddenEnabled`) or keyboard shortcut, and does NOT import any
// new symbol the candidate might introduce -- only the pre-existing
// `Excalidraw`/`MainMenu` components, test helpers, and the pre-existing
// `gridModeEnabled` field (used only as an independent, unrelated toggle to
// check for cross-talk). A candidate implementation that -- like this
// task's negative/trap control -- bypasses the action registry entirely
// (e.g. a bespoke global `keydown` listener with no menu wiring at all) is
// expected to correctly FAIL this check, since "not reachable from any
// menu" is a literal, explicit requirement of the ticket, not an
// implementation-detail nicety.
import React from "react";

import { Excalidraw, MainMenu } from "../index";
import { API } from "../tests/helpers/api";
import {
  act,
  fireEvent,
  GlobalTestState,
  render,
  toggleMenu,
} from "../tests/test-utils";

const { h } = window;

let container: HTMLElement;

type Found =
  | { kind: "context"; li: HTMLElement }
  | { kind: "menu"; button: HTMLElement };

// intentionally far from the origin: test elements created via
// `API.createElement`/`API.createTextContainer` default to x=0, y=0,
// width=100, height=100, and right-clicking *on* an element opens a
// different ("element") context menu that doesn't carry this canvas-wide
// toggle.
const EMPTY_CANVAS_POINT = { clientX: 900, clientY: 900 };

const findInContextMenu = (): HTMLElement | null => {
  fireEvent.contextMenu(GlobalTestState.interactiveCanvas, {
    button: 2,
    ...EMPTY_CANVAS_POINT,
  });
  const menu = document.querySelector(".context-menu");
  if (!menu) {
    return null;
  }
  const li = Array.from(menu.querySelectorAll("li")).find((el) =>
    /caption/i.test(el.textContent || ""),
  );
  return (li as HTMLElement) || null;
};

const findInMainMenu = (): HTMLElement | null => {
  if (!document.querySelector(".dropdown-menu")) {
    act(() => {
      toggleMenu(container);
    });
  }
  const menu = document.querySelector(".dropdown-menu");
  if (!menu) {
    return null;
  }
  const button = Array.from(menu.querySelectorAll("button")).find((b) =>
    /caption/i.test(b.textContent || ""),
  );
  return (button as HTMLElement) || null;
};

const findToggle = (): Found | null => {
  const li = findInContextMenu();
  if (li) {
    return { kind: "context", li };
  }
  const button = findInMainMenu();
  if (button) {
    return { kind: "menu", button };
  }
  return null;
};

const isChecked = (found: Found): boolean => {
  if (found.kind === "context") {
    return (
      found.li.querySelector("button")?.classList.contains("checkmark") ??
      false
    );
  }
  return !!found.button.querySelector(".dropdown-menu-item__icon svg");
};

const clickToggle = (found: Found) => {
  if (found.kind === "context") {
    fireEvent.click(found.li);
  } else {
    fireEvent.click(found.button);
  }
};

const activateCaptionsToggle = (): Found => {
  const found = findToggle();
  if (!found) {
    throw new Error(
      "no menu item (context menu or main menu) found whose visible label contains 'caption' -- feature is not reachable from any menu, unlike sibling display toggles (grid mode, zen mode)",
    );
  }
  clickToggle(found);
  return found;
};

describe("hide captions toggle", () => {
  beforeEach(async () => {
    ({ container } = await render(
      <Excalidraw handleKeyboardGlobally={true}>
        <MainMenu>
          <MainMenu.DefaultItems.Preferences />
        </MainMenu>
      </Excalidraw>,
    ));
    API.setElements([]);
  });

  it("is reachable from a menu, off by default, and toggles reversibly", () => {
    let found = findToggle();
    expect(found).not.toBeNull();
    expect(isChecked(found!)).toBe(false);

    activateCaptionsToggle();

    found = findToggle();
    expect(found).not.toBeNull();
    expect(isChecked(found!)).toBe(true);

    activateCaptionsToggle();

    found = findToggle();
    expect(found).not.toBeNull();
    expect(isChecked(found!)).toBe(false);
  });

  it("works with nothing selected", () => {
    expect(h.state.selectedElementIds).toEqual({});
    expect(() => activateCaptionsToggle()).not.toThrow();
  });

  it("toggling never mutates, deletes, or moves the underlying shape or its bound caption text, and restores exactly on toggle-back", () => {
    const [rectangle, text] = API.createTextContainer({
      label: { text: "caption text" },
    });
    API.setElements([rectangle, text]);

    const elementsBefore = JSON.parse(JSON.stringify(h.elements));

    activateCaptionsToggle();

    // toggling must not mutate the underlying elements/bindings
    expect(JSON.parse(JSON.stringify(h.elements))).toEqual(elementsBefore);
    expect(h.elements.length).toBe(2);
    const boundText = h.elements.find((el) => el.id === text.id);
    expect(boundText?.isDeleted).toBe(false);
    expect((boundText as any)?.text).toBe("caption text");

    activateCaptionsToggle();

    expect(JSON.parse(JSON.stringify(h.elements))).toEqual(elementsBefore);
  });

  it("does not turn off other display toggles (e.g. grid mode) and vice versa", () => {
    act(() => {
      h.setState({ gridModeEnabled: true });
    });
    expect(h.state.gridModeEnabled).toBe(true);

    activateCaptionsToggle();

    // an implementation that (incorrectly) clobbers the whole appState
    // instead of merging in its own field would silently reset this
    expect(h.state.gridModeEnabled).toBe(true);
  });
});
