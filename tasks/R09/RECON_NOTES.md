# R09 (mozilla-mobile/firefox-ios) — Recon Notes

Repository: `mozilla-mobile/firefox-ios`
Pinned commit: `de940072da700c2af7d74348b5775674d106d503`
Method: GitHub API only (`gh api repos/mozilla-mobile/firefox-ios/contents/...` and
`raw.githubusercontent.com/.../<commit>/...`), plus one `git ls-tree --recursive`-equivalent via
`gh api .../git/trees/<commit>?recursive=1`. No local clone was made (disk constraint honored — nothing
to `rm -rf`).

## Repository shape (confirmed)

Root-level monorepo layout (`gh api repos/.../contents/?ref=<commit>`):
`BrowserKit/`, `firefox-ios/` (the actual Client app + Focus-adjacent code lives under here, NOT at repo
root — `firefox-ios/Client/...`), `focus-ios/` (out of scope per instructions), `adr/`, `docs/`, `AGENTS.md`,
`CLAUDE.md` (confirmed to be a symlink `@AGENTS.md`, i.e. identical content to AGENTS.md), `CONTRIBUTING.md`.

`AGENTS.md` (45 lines) — key points used to ground tasks: monorepo has three projects
(`firefox-ios/` = Fennec scheme, `focus-ios/` = Focus scheme, `BrowserKit/` = shared SwiftPM package);
build/test via `fxios test`; SwiftLint via Xcode build phases; comments should be minimal; tests should be
updated/added when refactoring/adding code.

`BrowserKit/Package.swift` (swift-tools-version 6.2) declares ~20 library targets. Verified via raw fetch:
`Shared`, `SiteImageView`, `Common`, `TabDataStore`, `Redux`, `ComponentLibrary`, `WebEngine`, `TestKit`,
`ToolbarKit`, `MenuKit`, `AppAttestKit`, `MLPAKit`, `SummarizeKit`, `JWTKit`, `LLMKit`, `UnifiedSearchKit`,
`ContentBlockingGenerator`, `OnboardingKit`, `ActionExtensionKit`, `QuickAnswersKit`,
`WebCompatReporterKit`, plus an executable target. Each library target with source also has a matching
`Tests/<Target>Tests` test target (confirmed via `BrowserKit/Tests/*` directory listing) — e.g.
`TabDataStoreTests`, `QuickAnswersKitTests`, `ReduxTests`, `ToolbarKitTests`, `CommonTests`, etc. — all
runnable via plain `swift test` from inside `BrowserKit/`, independent of Bitrise/Xcode.

`adr/` contains real, dated Architecture Decision Records including:
- `0002-coordinators-for-navigation.md`
- `0003-redux-pilot.md`, `0004-using-redux-to-replace-mvvm.md`, `0005-redux-and-navigation.md`
- `0011`, `0012-redux-action-guidelines.md`, `0013` — all about Redux state-reducer/action conventions.

**The Redux-style framework mentioned in the task brief is real and independently verified by code
reading**, not just by docs: `BrowserKit/Sources/Redux/{Action,DispatchStore,Middleware,Reducer,State,
Store,StoreSubscriber,Subscription}.swift`. Read `Action.swift`, `Reducer.swift`, `Store.swift`,
`Middleware.swift` in full. Confirmed: `Store<State>` is a `@MainActor final class` holding `state`,
`reducer: Reducer<State>`, `middlewares: [Middleware<State>]`; `dispatch(_:)` queues actions and calls
`executeAction`, which runs the reducer to produce `newState`, then runs all middlewares, then sets
`state` (which fans out to subscribers via `didSet`). The framework is mid-migration from a legacy
`Action`/`ActionType` protocol pair to a new `ModernAction` protocol (both reducer and middleware typealiases
are `(legacyReducer, modernReducer)` / `(legacyMiddleware, modernMiddleware)` tuples) — this migration is
explicitly documented in `adr/0012-redux-action-guidelines.md`, which also shows the *actual* current
`ToolbarAction` (30 optional properties) as a still-not-fully-migrated real example, and which I cross-checked
against the live `firefox-ios/Client/Frontend/Browser/Toolbars/Redux/ToolbarAction.swift` (confirmed
byte-for-byte consistent with the ADR's description: 30 optional/near-optional properties, still legacy
`Action`).

Redux itself (the `BrowserKit/Sources/Redux` target) is a pure framework with **no feature-specific usage
inside BrowserKit** — grepped BrowserKit source tree paths and confirmed no BrowserKit target other than
`Redux`/`TestKit` references it. All real *usage* (Action/Reducer/Middleware/State per feature) lives in
the Client app under `firefox-ios/Client/Frontend/**/Redux/` (confirmed dozens of per-feature `Redux/`
subfolders: MainMenu, SearchEngines, Toolbars, Homepage, TrackingProtection, etc.). This matters for scoping:
**tasks that exercise the Redux chain necessarily live in the Client app**, which is documented as not
independently testable outside Bitrise — see per-task notes below.

## Task-by-task evidence

### Task A — Local Change: `BrowserKit/Sources/TabDataStore/TabDataStore.swift`

Read `TabDataStore.swift` and `TabFileManager.swift` in full (both files fetched via raw.githubusercontent).

- `TabFileManager.windowDataDirectory(isBackup: Bool)` returns one of two real directories:
  `PathInfo.primary = "window-data"` or `PathInfo.backup = "window-data-backup"`.
- `DefaultTabDataStore.saveWindowData` creates a backup copy (`createWindowDataBackup`) before overwriting
  the primary file, precisely so a corrupted primary file can be recovered from the backup
  (`fetchWindowData` already falls back to the backup file on primary-read failure).
- `removeWindowData(forUUIDs:)` (bottom of `TabDataStore.swift`) only calls
  `fileManager.windowDataDirectory(isBackup: false)`, lists that directory, and removes matching files. It
  **never touches the `isBackup: true` directory** — confirmed by reading the full method body. This is a
  genuine, real gap (not invented): backups for removed windows are permanently orphaned.
- Confirmed test scaffolding exists to make this testable and gradeable: `BrowserKit/Tests/TabDataStoreTests/
  TabDataStoreTests.swift` + `Mocks/MockTabFileManager.swift`. The mock already tracks
  `removeAllFilesAtCalledCount` / `removeFileAtPathCalledCount` and lets tests set distinct
  `primaryDirectoryURL` / `backupDirectoryURL`, and `windowDataDirectory(isBackup:)` in the mock already
  branches on `isBackup` — i.e. the test infrastructure already supports asserting on backup-vs-primary
  directory interactions without any new mock work. An existing test, `testClearAllTabData`, already asserts
  `removeAllFilesAtCalledCount == 2` (primary + backup) for `clearAllWindowsData()`, confirming the "both
  primary and backup must be handled" expectation is an established test pattern in this exact test file,
  just not yet applied to `removeWindowData(forUUIDs:)`.
- **Scope**: entirely inside the `TabDataStore` BrowserKit target. `Package.swift` shows
  `TabDataStore` depends only on `Common`. **This task stays fully within BrowserKit-testable scope**
  (`cd BrowserKit && swift test --filter TabDataStoreTests`).

### Task B — Cross-module Feature: navigation-toolbar middle-button customization

Read in full: `firefox-ios/Client/Frontend/Browser/Toolbars/Redux/NavigationBarState.swift` (616-line
`ToolbarMiddleware.swift` also read in full), `.../Toolbars/Redux/ToolbarAction.swift`,
`.../Toolbars/Models/NavigationToolbarContainerModel.swift`,
`.../BrowserViewController/Actions/GeneralBrowserAction.swift`,
`.../Toolbars/ToolbarTelemetry.swift` (partially, via grep + targeted reads),
`.../Toolbars/SearchBarLocationSaver.swift`, `.../Toolbars/ToolbarLayoutStyle.swift`.

- `NavigationBarMiddleButtonType` (`NavigationBarState.swift`) is a real, currently-two-case
  (`.home`, `.newTab`) `CaseIterable` enum with `label`/`imageName` computed properties, used to decide
  which `ToolbarActionConfiguration` occupies the toolbar's middle slot
  (`NavigationBarState.getMiddleButtonAction(url:isPrivateMode:middleButton:)`, confirmed by reading the
  function body).
- Persistence confirmed real, not hypothetical: `ToolbarMiddleware.swift` line ~97 reads
  `prefs.stringForKey(PrefsKeys.Settings.navigationToolbarMiddleButton)` and maps the raw value back to
  `NavigationBarMiddleButtonType(rawValue:)`, defaulting to `.newTab`. This is the exact same
  `Middleware`-reads-`Prefs` pattern also used one line later for `PrefsKeys.Settings.translationsFeature`
  — i.e. this is an established, repeated pattern in this middleware, not a one-off.
- Tap-handling confirmed real: `ToolbarMiddleware.handleToolbarButtonTapActions` switches on
  `action.buttonType` (e.g. `.home` -> `toolbarTelemetry.homeButtonTapped(...)` then
  `store.dispatch(GeneralBrowserAction(actionType: .goToHomepage))`; `.newTab` ->
  `toolbarTelemetry.oneTapNewTabButtonTapped(...)` then `.addNewTab`). `ToolbarTelemetry.swift` confirmed
  (via grep of fetched raw file) to have real per-button methods: `homeButtonTapped`, `oneTapNewTabButtonTapped`,
  `backButtonTapped`, `forwardButtonTapped`, `tabTrayButtonTapped`, `menuButtonTapped`, etc., each calling
  `gleanWrapper.recordEvent(for: GleanMetrics.Toolbar.<x>, extras: ...)`.
- `GeneralBrowserActionType.didCloseTabFromToolbar` **already exists** as a declared case in
  `GeneralBrowserAction.swift` (confirmed via full-file fetch) — grepped the whole repo tree/paths and did
  not find it dispatched from the middle-button tap path, so it's available to reuse/extend for the new
  "Close Tab" option without inventing a new action type from scratch. (I did not exhaustively trace every
  existing dispatch site of this case across the whole app within the disk/time budget of this recon; the
  task treats reusing-or-adding-an-equivalent action as equally valid, since the point being tested is
  "dispatch through Redux," not the exact identifier.)
- **Why this is genuinely cross-module**: correct implementation must touch (1) Settings/Prefs persistence
  layer, (2) the Redux Action/Middleware/Reducer chain for the Toolbar state slice (three sub-layers in
  their own right), and (3) Telemetry (`ToolbarTelemetry`) — three real, separately-owned pieces of the
  Client app that must all agree, exactly matching the "Action/Reducer/Middleware/Store chain" alternative
  explicitly allowed by the task brief for Task B (the brief's example wording is "e.g. across a BrowserKit
  library target and the Client app's Redux-style state layer, **or** across the Action/Reducer/Middleware/
  Store chain").
- I checked whether a BrowserKit-target code change is *strictly necessary* (to see if I could get a
  stronger BrowserKit+Client crossing): `NavigationToolbarContainerModel.swift` (Client) maps the generic
  `ToolbarActionConfiguration` to `ToolbarKit`'s generic `ToolbarElement` — BrowserKit's `NavigationToolbar`
  rendering is feature-agnostic and doesn't hardcode button identities, and the icon needed
  (`StandardImageIdentifiers.Large.cross`, defined in `BrowserKit/Sources/Common/Constants/
  StandardImageIdentifiers.swift`) already exists, confirmed via grep of the fetched file. So a *minimal*
  correct solution does not require modifying BrowserKit source. I designed the task and its architectural
  constraints/checks accordingly (AC4 in `metadata_B.yaml` explicitly checks that BrowserKit stays
  untouched/uncoupled from Client types, rather than requiring a BrowserKit edit that isn't actually
  warranted).
- **Scope**: entirely inside `firefox-ios/Client`. Per the stated known limitation, the full Client app test
  suite depends on Mozilla's private Bitrise CI. `functional_check_command` in `metadata_B.yaml` flags this
  explicitly and specifies manual code review (plus optional `fxios test` if a macOS/Xcode/Fennec
  environment is available) as the validation path.

### Task C — Existing Extension Point: `TranscriptionEngine` protocol (QuickAnswersKit)

Read in full: `BrowserKit/Sources/QuickAnswersKit/Backend/SpeechService/{Abstractions,TranscriptionEngine,
SFSpeechRecognizerEngine,AudioManager}.swift`, `.../SpeechAnalyzerEngine.swift` (partial),
`.../Backend/{QuickAnswersService,DefaultQuickAnswersService}.swift`,
`BrowserKit/Tests/QuickAnswersKitTests/Mocks/MockTranscriptionEngine.swift`.

- I initially considered using the task brief's suggested Redux Action/Reducer/Middleware/Store mechanism
  for Task C, but **verified by code reading that Redux has zero usage inside any BrowserKit target**
  (only the Client app uses it — see above), which conflicts with the stated preference to keep tasks
  BrowserKit-testable where possible. I therefore looked specifically for "a specific BrowserKit library's
  own extension mechanism" per the task brief's explicit fallback instruction, and found a strictly better
  fit.
- `TranscriptionEngine` (`BrowserKit/Sources/QuickAnswersKit/Backend/SpeechService/TranscriptionEngine.swift`)
  is a 3-method protocol (`prepare()`, `start(continuation:)`, `stop()`) with **two real, independent
  production conformers already in the codebase**: `SFSpeechRecognizerEngine` (AVAudioEngine +
  SFSpeechRecognizer-backed) and `SpeechAnalyzerEngine` (`@available(iOS 26.0, *)`, built on iOS 26's newer
  `SpeechAnalyzer`/`SpeechTranscriber` APIs). Selection between them is centralized in one place:
  `DefaultQuickAnswersService.makeDefaultEngine()`, a private static method that branches on
  `#available(iOS 26.0, *)` — confirmed by reading the full `DefaultQuickAnswersService.swift` file,
  including its doc comment: "Engine selection — iOS 26+ uses `SpeechAnalyzerEngine`. Earlier versions use
  `SFSpeechRecognizerEngine`."
- Both engines are constructed with injected `AudioManagerProtocol` and `AuthorizeProvider` dependencies
  (confirmed via both files' `init`), i.e. audio-session/permission plumbing is already centralized in
  `AudioManager`/`AuthorizationHandler`, not duplicated per engine — this is the concrete "reuse this, don't
  duplicate it" boundary the negative control is built around.
- A `MockTranscriptionEngine` test double already exists
  (`BrowserKit/Tests/QuickAnswersKitTests/Mocks/MockTranscriptionEngine.swift`, read in full) with call-count
  tracking (`prepareCallCount`, `startCallCount`, `stopCallCount`) and configurable errors/results — strong
  independent evidence that the protocol is the codebase's own intended seam for substituting
  implementations in tests, i.e. a genuine, pre-existing extension point, not one I'm inferring from a
  single production usage.
- I deliberately avoided phrasing the task around "use Apple's newest on-device transcription," since that
  describes `SpeechAnalyzerEngine`, which **already exists** — that would make the task trivially
  "already done." Instead the task asks for a distinct, flag-selected alternative pipeline (framed as an
  internal A/B experiment), which is not yet implemented, to keep the task genuinely open.
- **Scope**: entirely inside the `QuickAnswersKit` BrowserKit target. `swift test --filter QuickAnswersKitTests`
  is directly runnable from `BrowserKit/`.
- **Prompt leak check**: `task_C.md` does not mention "TranscriptionEngine," "protocol," "Strategy,"
  "SFSpeechRecognizerEngine," "SpeechAnalyzerEngine," "QuickAnswersKit," or any file/class/pattern name. It
  is phrased purely as a product/experimentation request ("run an internal experiment," "alternative
  speech-to-text pipeline," "a simple flag").

### Task D — Architecture Trap: "Copy Address" toast bypassing Redux

Read in full: `firefox-ios/Client/Frontend/Browser/ToastType.swift`,
`.../BrowserViewController/Actions/GeneralBrowserAction.swift`,
`.../BrowserViewController/State/BrowserViewControllerState.swift` (768 lines, read via targeted `sed`
windows plus full grep pass), and large portions (via grep + targeted reads) of the 5217-line
`.../BrowserViewController/Views/BrowserViewController.swift`.

- `adr/0005-redux-and-navigation.md` (read in full) states the architectural rule in so many words: *"these
  changes formalize a pattern: navigation is expressed as Redux state or actions (intents), not direct view
  controller calls inside reducers or view logic."* This ADR is about navigation specifically, but the same
  `state.toast` mechanism in `BrowserViewControllerState` is the toast-flavored instance of the identical
  pattern, and — critically — **the codebase has its own in-source comment making this explicit for toasts**:
  at `BrowserViewController.swift` line ~2324-2325 (confirmed by direct read):
  ```
  /// This toast was tied into the legacy main menu, moved it to it's own function.
  /// New toasts should be piped through Redux.
  ```
  This is about as strong a piece of ground truth as a benchmark task can ask for — it is the *codebase
  telling itself* what the correct pattern is, immediately next to a legacy counter-example.
- The correct pipeline, fully traced by reading the actual code (not inferred):
  1. `ToastType` enum (`ToastType.swift`) — currently 8 cases (`addBookmark`, `addToReadingList`,
     `clearCookies`, `openNewTab`, `removeFromReadingList`, `removeShortcut`, `retryTranslatingPage`,
     `shakeToSummarizeNotAvailable`), each with a `title` and optional `buttonText`/`reduxAction(for:)`.
     No `copyURL`/`copyAddress` case exists yet — confirmed absent via full read + targeted grep.
  2. `GeneralBrowserAction` (`GeneralBrowserAction.swift`) has a `toastType: ToastType?` field and
     `GeneralBrowserActionType.showToast` case (confirmed via full-file read).
  3. `BrowserViewControllerState`'s reducer (confirmed via `sed`-window read around the relevant lines):
     `guard let toastType = action.toastType ... .copy(toast: toastType)`.
  4. `BrowserViewController.newState(state:)` (confirmed via direct read, lines ~976-1034): `if let toast =
     state.toast { self.showToastType(toast: toast) }`, and `showToastType(toast:)` does the actual
     `ButtonToast`/`showPlainToast`/`showBookmarkToast` presentation, with a comment: `// This toast is
     generated from GeneralBrowserActionType.showToast`.
- The trap's realism is corroborated by the fact that **legacy direct-call sites already exist in the same
  5217-line file** (I found and read several, e.g. around lines ~4002-4012, ~4237-4270, ~4864, where
  `ButtonToast`/`PlainToast` are constructed and `show(toast:)` is called directly, bypassing Redux for
  older, not-yet-migrated features) — so an agent grepping the file for "how do I show a toast" is very
  likely to land on one of these legacy call sites and copy the (explicitly deprecated-by-comment) pattern
  instead of the Redux-driven one used for every *other* recently added toast (`clearCookies`, `addBookmark`,
  etc., which are the majority of `ToastType`'s current cases).
- The concrete, currently-silent trigger point for the new feature is real, not invented: `copyAddressAction`
  (`AccessibleAction`, confirmed via direct read around line 1158 of `BrowserViewController.swift`) already
  copies `tabManager.selectedTab?.canonicalURL?.displayURL` (falling back to `currentURL()`) to
  `UIPasteboard.general.url` and returns `true` — with **no toast/feedback of any kind today**, confirmed by
  reading the full closure body.
- **Scope**: entirely inside `firefox-ios/Client`, same Bitrise-only limitation as Task B; flagged
  identically in `metadata_D.yaml`.
- **Prompt leak check**: `task_D.md` names no class, file, or pattern ("ToastType," "Redux," "GeneralBrowserAction,"
  "copyAddressAction," "dispatch," "reducer," "state" all absent from the prompt text); it is phrased purely
  as a UX ticket about the existing, real, currently-silent "Copy Address" action.

## Cross-task independence check

- Task A (TabDataStore) and Task C (QuickAnswersKit) touch disjoint BrowserKit targets with no shared files.
- Task B (Toolbar middle-button) and Task D (Copy Address toast) both live in `firefox-ios/Client` but touch
  disjoint feature areas/files (`Toolbars/Redux/*` + `ToolbarTelemetry.swift` vs. `ToastType.swift` +
  `BrowserViewControllerState.swift` + the `copyAddressAction` closure in `BrowserViewController.swift`).
  Both do dispatch through the shared `store`/`GeneralBrowserAction`/`BrowserViewControllerState` plumbing
  (that's unavoidable — it's the one global app-state Store), but the specific action types, reducer
  branches, and UI surfaces exercised do not overlap.
- No task prompt (`task_A.md`..`task_D.md`) names Redux, Action, Reducer, Middleware, Store, Protocol,
  Strategy, TranscriptionEngine, ToastType, NavigationBarMiddleButtonType, TabFileManager, or any other
  internal identifier — verified by rereading each prompt file's final text above before writing this
  document.

## BrowserKit-testable vs. Client-app-only summary

| Task | Scope | Independently testable via `swift test`? |
|---|---|---|
| A (Local Change) | `BrowserKit/Sources/TabDataStore` | Yes — `cd BrowserKit && swift test --filter TabDataStoreTests` |
| B (Cross-module) | `firefox-ios/Client` (Settings/Prefs + Toolbar Redux + Telemetry) | No — Bitrise-only; manual review specified |
| C (Extension Point) | `BrowserKit/Sources/QuickAnswersKit` | Yes — `cd BrowserKit && swift test --filter QuickAnswersKitTests` |
| D (Architecture Trap) | `firefox-ios/Client` (ToastType + BrowserViewControllerState + BrowserViewController) | No — Bitrise-only; manual review specified |

This 2-of-4 split was a deliberate outcome of recon, not a starting assumption: Task B's natural
architectural crossing (Settings/Prefs, Redux, Telemetry) and Task D's architecture-trap material (the
Redux-vs-direct-call toast pattern, backed by an explicit in-repo comment) both live in the Client app by
the nature of what they're testing — Redux *usage* and navigation/UI-state conventions are Client-app
concerns in this codebase, not BrowserKit concerns (BrowserKit's `Redux` target is the framework only, with
zero feature usage inside BrowserKit itself, confirmed above). Tasks A and C were deliberately chosen from
BrowserKit to satisfy the "favor BrowserKit-testable scope where possible" instruction wherever the
underlying architectural question allowed it.
