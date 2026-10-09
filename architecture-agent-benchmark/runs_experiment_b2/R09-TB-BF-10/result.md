# R09-TB-BF-10

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.4
Dangerous success: False
Goga engagement signal: True
Cost: $4.39851465
Duration: 803566ms, turns: 67

## Agent's own summary

## Change Plan — Add "Close Tab" middle-button option

I've traced the full Home/New Tab feature end-to-end. Here's the plan (goga-change Step 3), scoped as narrowly as possible to avoid touching the tab-tray or Home/New Tab code paths:

**Core enum + rendering** — `firefox-ios/Client/Frontend/Browser/Toolbars/Redux/NavigationBarState.swift`
- Add `case closeTab` to `NavigationBarMiddleButtonType` (label + icon `StandardImageIdentifiers.Large.cross`)
- Add `.closeTab` to `ToolbarActionConfiguration.ActionType` (`ToolbarActionConfiguration.swift`)
- Add a `closeTabAction` template and wire it into `getMiddleButtonAction`'s switch (homepage still forces the search icon regardless of choice — unchanged existing behavior, so Home/New Tab/Close Tab are all treated identically there)

**Tap handling + telemetry** — `ToolbarMiddleware.swift`
- Add `case .closeTab:` in `handleToolbarButtonTapActions` that calls a new `toolbarTelemetry.closeTabButtonTapped(isPrivate:)` and then `tabManager.removeTab(selectedTab.tabUUID)` directly — the same primitive used by the keyboard shortcut and toolbar long-press "Close Tab" action, so last-tab handling (auto-opens a new tab) comes for free. This avoids threading a brand-new action through `GeneralBrowserAction`/`BrowserViewControllerState`/`BrowserViewController`, since the middleware already has direct `tabManager` access (same pattern used today for `.summarizer`).

**Settings UI** — `NavigationBarMiddleButtonSelectionView.swift`: add a third `GenericSelectableItemCellView` row + `.closeTab` case in `identifierName(for:)`. `AddressBarSettingsView.swift` needs no change (already generic over the enum/rawValue).

**Telemetry probe** — `firefox-ios/Client/Glean/probes/toolbar.yaml`: add a `close_tab_button_tapped` event (mirroring `home_button_tapped`/`one_tap_new_tab_button_tapped`, same `is_private` extra key); update `middle_button_type`'s description to mention the third value.

**Strings/identifiers**: add `Settings.Toolbar.Navigation.MiddleButton.CloseTab.v156` label, a `TabToolbarCloseTabAccessibilityLabel`, and `closeTabButton` accessibility identifiers (Settings + Toolbar), following existing naming.

**Persistence**: none needed beyond the enum gaining a raw value — it's already stored generically as a `String` pref.

**Tests**: extend `ToolbarMiddlewareTests.swift` (launch-with-pref + tap→telemetry/removeTab) and `NavigationBarStateTests.swift`/`ToolbarStateTests.swift` (action-mapping) with `.closeTab` equivalents of the existing Home/New Tab tests.

**Not touched**: `GeneralBrowserAction.swift`, `BrowserViewControllerState.swift`, `BrowserViewController.swift`, `NavigationToolbarContainerModel/Container.swift`, `BrowserKit/ToolbarKit` (all button-agnostic, no changes required), tab-tray close flow. No documented Goga cell (`goga schema` shows only 9 governed cells; this feature lives entirely in undocumented app code — only `BrowserKit/Sources/ToolbarKit` is a documented dependency, and its contract — `ToolbarElement`'s existing fields — doesn't need to change).

Shall I proceed with implementation?
