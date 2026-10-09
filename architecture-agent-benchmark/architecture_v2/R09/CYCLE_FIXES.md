# CYCLE_FIXES.md — R09 (mozilla-mobile/firefox-ios) Condition C

No formal two-cell import cycle exists in the final restructured manifests — `goga lint`'s
`imports_has_not_cyclical_deps` check passes clean across all 33 cells. Three real bidirectional
structural relationships were found during restructuring and resolved the same way each time:
formalize the structurally-heavier direction as a Goga `Imports:`, describe the reverse in prose.

## `WebEngine` ↔ `WebEngine/WKWebview`

`WKWebview` (the concrete WebKit-backed implementation, 8 nested cells / ~50 files once fully
expanded) has a real, heavy dependency on `WebEngine`'s protocols (`Engine`, `EngineSession`,
`EngineView`, `EngineSessionDependencies`, etc. — it implements them). `WebEngine` itself only
needs one narrow type back (`WKWebViewParameters`, used in `EngineSessionDependencies`'s public
init). Formalized: `WKWebview → WebEngine` (8 types). Left informal: `WebEngine`'s reference to
`WKWebViewParameters`, described in prose in `WebEngine`'s own Annotations. This also updated a
stale claim in the original (Condition B) manifest that WKWebview was "out of scope, one level
deeper" — no longer true once scope was expanded.

## `firefox-ios/Client/Coordinators` ↔ its own children (`QRCode`, `Browser`)

`Coordinators`' 12 root-level concrete coordinator types (`SettingsCoordinator`,
`PasswordManagerCoordinator`, etc.) are the real parent of the whole navigation-flow forest, and
several of its own root files reference `QRCodeCoordinator` (from the new `QRCode` cell) and
`BrowserNavigationHandler`/`BrowserCoordinator` (from the new `Browser` cell). At the same time,
every child cell under `Coordinators` (`QRCode`, `Launch`, `LaunchView`, `TabTray`, `Library`,
`Scene`, `Router`, `Browser`) needs `Coordinator`/`BaseCoordinator`/`ParentCoordinatorDelegate`
back from the parent. Formalized: all 8 children `→ Coordinators` (the base pattern types every
coordinator conforms to — the heavier, structurally foundational direction). Left informal:
`Coordinators`' own references to `QRCodeCoordinator`/`Browser`'s types, described in prose in
`Coordinators`' own Annotations (using the real local Swift type names as plain signature text,
not backticked cross-references).

## `BrowserKit/Sources/ToolbarKit/AddressToolbar` ↔ `AddressToolbar/LocationView`

`AddressToolbarConfiguration`'s public initializer takes a `LocationViewConfiguration` parameter
(from the nested `LocationView` cell), while `LocationView`'s own internal code references
`AddressToolbarUXConfiguration`/`AddressToolbarPosition` from its parent — but only via
non-`public` signatures, so per the Swift-facade rule (only `public` counts) that reverse
reference was never a real formal-Import candidate to begin with, and the situation resolved
itself without a deliberate prose-vs-formal tradeoff: `AddressToolbar → LocationView`
(`LocationViewConfiguration`) is formal; the reverse was already out of facade scope.

## Path-resolution bug found and fixed during reconciliation

Three `From:` entries used cell-relative paths (`AddressToolbar`, `LocationView`, `../..`)
instead of the repo-root-relative paths every other cell in this study's manifests use (e.g.
`BrowserKit/Sources/ToolbarKit/AddressToolbar`). `goga lint`'s `import_has_valid_from_path` check
caught these correctly (not a false positive this time) when run from the true project root;
fixed by rewriting all three to full repo-root-relative paths.
