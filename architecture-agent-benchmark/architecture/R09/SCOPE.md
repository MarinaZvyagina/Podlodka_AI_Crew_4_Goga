# SCOPE.md — R09 (mozilla-mobile/firefox-ios)

## Method

Scope was decided from firefox-ios's own module layout — the `BrowserKit` SwiftPM package's
library targets (`Package.swift` at `BrowserKit/Package.swift`) and the `Client` app target's own
top-level directories (depth ≤ 3 from `BrowserKit/Sources/` or `firefox-ios/Client/`) — per
`TREATMENT_DESIGN.md` §4. This was done by reading `Package.swift`'s `targets:` list and
dependency graph, `ls`-ing `BrowserKit/Sources/*` and `firefox-ios/Client/*`, and grepping
`import <Target>` counts across the repository to confirm which targets are genuinely
load-bearing (widely depended upon), **before** reading `tasks/R09/task_A.md`–`task_D.md` (see
`PLAUSIBILITY_CHECK.md` for the post-hoc self-check).

`BrowserKit/Package.swift` declares ~20 library targets. Cross-referencing `grep -rl "import
<Target>"` counts against `firefox-ios/Client` and other `BrowserKit` targets confirmed which of
these are widely consumed (`Common`: 817 importing files; `Redux`: 129; `TabDataStore`: 9;
`ToolbarKit`: 9; `QuickAnswersKit`: 9) versus narrower, single-purpose targets not documented
here (e.g. `JWTKit`, `MLPAKit`, `LLMKit`, `AppAttestKit`, `ActionExtensionKit`,
`ContentBlockingGenerator` — real but each a thin, narrowly-scoped utility library consumed by
only 1–2 other targets, not part of the structural spine).

Per the task brief's explicit guidance, the Redux-style unidirectional-data-flow framework is a
real, central architectural mechanism worth documenting even though it lives inside `BrowserKit`
(as a generic library) while its actual composition root lives inside `Client` (the app target).
Both halves are documented as separate cells reflecting their real, separate locations and
dependency direction (`Client` depends on `BrowserKit`, never the reverse).

## Cells covered (9) and why

| Cell | Evidence it's load-bearing |
|---|---|
| `BrowserKit/Sources/Common/DependencyInjection` | `AppContainer.shared`/`ServiceProvider` is the app-wide DI container; part of the single most-imported target in the repo (`Common`, 817 importing files). |
| `BrowserKit/Sources/Common/Logger` | `Logger`/`DefaultLogger` is the single logging facade used throughout the codebase (seen directly inside `Redux/Store.swift`, `TabDataStore`, `WebEngine`, `Coordinators`, and hundreds of other files); part of `Common`. |
| `BrowserKit/Sources/Redux` | `Store`/`Action`/`ModernAction`/`Reducer`/`Middleware` — the app's Redux-style unidirectional-data-flow framework; imported by 129 files across the app, and by this forest's own `Client/Redux/GlobalState` cell. |
| `BrowserKit/Sources/TabDataStore` | `TabDataStore`/`TabSessionStore`/`WindowData`/`TabData` persist every open tab/window to disk for app-relaunch restoration — a core, well-isolated library target (9 importing files, but structurally central: tab-session survival is fundamental to a browser). |
| `BrowserKit/Sources/WebEngine` | `Engine`/`EngineSession`/`EngineView` is the engine-agnostic abstraction boundary between the browser and its WebKit-backed rendering engine (the concrete `WKWebview` implementation lives in the same target, one level deeper, and is out of scope here). |
| `BrowserKit/Sources/ToolbarKit` | `ToolbarElement`/`ToolbarManager` is the address/navigation toolbar's UI value-type model and border-display policy; consumed by the `Client` app's toolbar UI and its Redux slice. |
| `BrowserKit/Sources/QuickAnswersKit/UI` | `QuickAnswersViewController`/`QuickAnswersNavigationHandler`/`QuickAnswersTelemetry` — the public presentation surface of a real, shipping feature (voice-driven search/summarize), instantiated from `firefox-ios/Client/Coordinators/QuickAnswersCoordinator.swift`. |
| `firefox-ios/Client/Redux/GlobalState` | `AppState`/`PresentedComponentsState`/`ComponentAction` — the Redux composition root: the single root state type held by the app-wide store, assembled from ~25 per-feature middlewares (toolbar, homepage, tabs tray, tracking protection, etc.). |
| `firefox-ios/Client/Coordinators` | `Coordinator`/`BaseCoordinator` — the navigation-coordinator pattern used by ~15 concrete flow coordinators throughout the app (settings, browser, launch, password manager, Quick Answers, etc.). |

## Deliberately excluded / deprioritized

- **Most other `BrowserKit` library targets** (`SiteImageView`, `ComponentLibrary`, `MenuKit`,
  `WebCompatReporterKit`, `UnifiedSearchKit`, `OnboardingKit`, `AppAttestKit`, `MLPAKit`,
  `SummarizeKit`, `JWTKit`, `LLMKit`, `ContentBlockingGenerator`, `ActionExtensionKit`,
  `QuickAnswersKit/Backend`) — real, but each is either a narrower single-purpose utility with a
  small importer count, or (for `QuickAnswersKit/Backend` specifically) has **no `public`
  declarations at all** — the entire speech/results backend is `internal` to its own target, so
  under the Swift facade rule ("only `public` constitutes the Facade") it has no cross-module
  contract to document; only `QuickAnswersKit/UI`'s view controller and its two callback
  protocols are actually `public`.
- **`TestKit`** — test-infrastructure target, not part of the product's own architecture.
- **`firefox-ios/Storage`, `firefox-ios/Sync`, `firefox-ios/Account`, `firefox-ios/Push`,
  `firefox-ios/Providers`** — real, substantial `Client`-adjacent modules (bookmarks/history
  database, Firefox Sync, FxA, push notifications), but given the "roughly 6–10 cells, not an
  exhaustive catalog" budget, priority was given to the mechanisms with the widest, most direct
  fan-in confirmed by import-count grepping (`Common`, `Redux`) plus a deliberately varied sample
  of `BrowserKit` library kinds (persistence: `TabDataStore`; UI value model: `ToolbarKit`;
  engine abstraction: `WebEngine`; a concrete feature surface: `QuickAnswersKit/UI`) and the two
  `Client`-level mechanisms every screen in the app touches (`Redux/GlobalState`,
  `Coordinators`).
- **`Focus` browser** — explicitly out of scope per this task's instructions (this is a
  monorepo containing both `firefox-ios` and `focus-ios`; only `firefox-ios`/`BrowserKit` was
  scoped).
- **Individual feature Redux slices** (e.g. a specific screen's own `*State`/`*Reducer`/
  `*Middleware`, such as a toolbar-specific or homepage-specific slice) — real and numerous
  (~25, one per entry in `GlobalState`'s middleware list), but each lives inside its own
  feature's directory elsewhere in `Client/Frontend`, not inside the `Redux`/`Coordinators`
  directories scoped here; documenting the composition root (`GlobalState`) and the generic
  framework (`Redux`) covers the *mechanism* without needing to enumerate every slice.

## A note on Swift access control in `firefox-ios/Client`

`Client` is a single Xcode app target, not a library — `grep`-ing its entire `Coordinators` and
`Redux/GlobalState` directories confirms **zero** uses of the `public` keyword anywhere in either
directory (everything defaults to Swift's `internal` access level, which is correctly sufficient
for a single-module app with no external consumers). The `goga-cell-swift` language convention
("only `public` constitutes the Facade") is written with SwiftPM library targets in mind; taken
completely literally for `Client`, it would yield an empty Facade for every `Client`-side cell,
making it impossible to document the app's own composition root or navigation pattern at all.
For the two `Client`-side cells in this forest, `internal` (the default access level) was treated
as the Facade instead, since `internal` is the real, load-bearing sharing boundary within this
single-target app. This is disclosed transparently rather than silently: it produces a measurable
consequence during the `goga contract` drift check (see `SETUP_COST.md`) — the tool's Swift
contract extractor itself enforces the strict "public-only" rule, so it reports several
`Client`-side declarations' real implementations as absent even though the CODEMANIFEST content
was read directly from, and accurately reflects, the real (internal-access) source.

This scoping was performed and frozen before `tasks/R09/task_A.md`–`task_D.md` were read (see
`PLAUSIBILITY_CHECK.md`).
