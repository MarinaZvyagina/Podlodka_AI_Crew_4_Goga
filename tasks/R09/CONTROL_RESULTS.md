# R09 (mozilla-mobile/firefox-ios) — Phase 4/5 Control Results

Repository: `mozilla-mobile/firefox-ios`, pinned commit `de940072da700c2af7d74348b5775674d106d503`, cloned to
`/tmp/benchmark-repos/R09`.

## Verification methods used, and why (read this first)

- **Tasks A and C (BrowserKit-scoped)**: functional correctness was verified by **actually
  executing** the real test suites, not by inspection alone. `swift test` / `swift build` from the
  command line **do not work** in this sandboxed environment: the `Common` BrowserKit target
  unconditionally `import UIKit`, and a bare `swift build`/`swift test` resolves against the host
  macOS SDK (no UIKit) rather than an iOS SDK, so it fails with `no such module 'UIKit'` before any
  of our targets even compile. The actually-working equivalent, used throughout, is:
  `xcodebuild test -scheme <Target> -destination 'platform=iOS Simulator,name=<device>'` (for
  `TabDataStore`, which has its own working per-target scheme) and
  `xcodebuild test -scheme BrowserKit-Package -destination '...' -only-testing:<TestTarget>` (for
  `QuickAnswersKit`, whose own auto-generated per-target scheme turned out to have no Test action
  wired to a test bundle in this environment — "There are no test bundles available to test" — so
  the aggregate `BrowserKit-Package` scheme scoped down with `-only-testing:` was used instead).
  Both were run against a real iPhone 17 Pro simulator and produced real pass/fail XCTest/
  swift-testing output, which is what "PASS"/"FAIL" means below for Tasks A and C.
- **Tasks B and D (Client-app-scoped)**: as anticipated in the task metadata, the full `Client`
  (Fennec) app cannot be independently built/tested here. `xcodebuild build -project
  Client.xcodeproj -scheme Fennec -destination 'platform=iOS Simulator,name=...'` was attempted (not
  skipped) and got substantial real distance — it resolved the full 98-target/~20-package dependency
  graph, required disabling an interactive Swift-macro trust gate
  (`defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES`), and began real
  compilation (e.g. our modified `AccessibilityIdentifiers.swift` compiled successfully as part of
  the `ShareTo` extension target) — before failing on a missing build-time tool,
  `bin/nimbus-fml.sh: No such file or directory` (Mozilla's Nimbus Feature Manifest Language
  compiler, fetched by `bootstrap.sh`, which was not run because it installs global tooling outside
  the task's `/tmp/benchmark-repos/R09` + deliverable-paths scope). This confirms the task
  metadata's own claim that Client needs Bitrise-style bootstrapping and is a genuine environment
  limitation, not a defect in the diffs. **No claim of an executed pass is made for B/D.** Instead,
  for B and D: (1) every changed/added Swift file was checked with `swiftc -parse` against the
  iOS Simulator SDK (catches syntax errors — unbalanced braces, invalid grammar — though not full
  type-checking, which requires the whole module); (2) careful manual code review tracing every
  call site, mirroring existing, already-shipped patterns in the same files (e.g. Task B's
  tab-closing code is a byte-for-byte mirror of the pre-existing `getCloseTabAction()` in
  `BrowserViewController+ToolBarActionMenuDelegate.swift`); (3) all architecture-check validator
  scripts, which are fully mechanical grep/diff-based scripts, were run and did execute for real.

## Task A — TabDataStore backup-cleanup fix

**Files:** `validators/task_A_AC1.sh`..`task_A_AC4.sh`, `controls/task_A_positive.diff`,
`controls/task_A_negative.diff`.

**Positive control.** `removeWindowData(forUUIDs:)` in
`BrowserKit/Sources/TabDataStore/TabDataStore.swift` was extended to also fetch and remove matching
files from the backup directory (`fileManager.windowDataDirectory(isBackup: true)`), reusing the
same `TabFileManager` abstraction and UUID-matching helper already used for the primary directory,
via a small shared private helper `removeWindowDataFiles(inDirectory:forUUIDs:)`.

**Negative control (trap).** Same functional goal, but backup removal reaches around
`TabFileManager` and calls `FileManager.default.containerURL(...)` /
`FileManager.default.removeItem(at:)` directly with a hand-built path, duplicating logic that
already exists in `DefaultTabFileManager`.

| Check | Method | Positive | Negative |
|---|---|---|---|
| AC1 (scope) | git-status-diff scoping | PASS | PASS |
| AC2 (uses TabFileManager, not raw FileManager) | grep for `FileManager.default`/`FileManager()` | PASS | **FAIL** (new `FileManager.default` calls found) |
| AC3 (Package.swift deps unchanged) | diff of target's `dependencies:` line | PASS | PASS |
| AC4 (functional regression guard — injected XCTest) | real `xcodebuild test` run of an injected, diff-independent test asserting `removeFileAtPathCalledCount == 2` for a UUID present in both dirs | PASS (3/3 injected tests pass) | **FAIL** (1 of 3 injected tests fails: count is 1, not 2) |
| Full pre-existing `TabDataStoreTests` suite (20 tests) | real `xcodebuild test -scheme TabDataStore` | PASS (20/20) | PASS (20/20 — trap doesn't touch code paths the pre-existing suite exercises) |

**Verdict: DISCRIMINATES.** Positive = functional PASS + all architecture PASS. Negative =
functional PASS (pre-existing suite, exactly matching the task's own `functional_check_command`)
but architecture FAIL on AC2 and on the purpose-built AC4 regression test. This is the cleanest
result of the four tasks because it is the only one with zero environment-limitation caveats:
everything here was mechanically executed end to end.

## Task C — Alternative speech-to-text pipeline (QuickAnswersKit)

**Files:** `validators/task_C_AC1.sh`..`task_C_AC5.sh`, `controls/task_C_positive.diff`,
`controls/task_C_negative.diff`.

**Positive control.** Added `AlternateTranscriptionEngine: TranscriptionEngine` (new file), reusing
the existing `AudioManagerProtocol`/`AuthorizeProvider` abstractions exactly like
`SFSpeechRecognizerEngine`/`SpeechAnalyzerEngine` already do. `DefaultQuickAnswersService` gained one
new `Bool` init parameter (`useAlternateTranscriptionPipeline`, default `false`) and
`makeDefaultEngine(useAlternateTranscriptionPipeline:)` picks the engine with a single flag check —
no branching added anywhere else. Added `AlternateTranscriptionEngineTests.swift` (mirrors
`SFSpeechRecognizerEngineTests`) and `DefaultQuickAnswersServicePipelineSelectionTests.swift`
(asserts flag → concrete engine type, and that `record()`/`stopRecording()` behave identically for
both an injected default-style engine and an injected `AlternateTranscriptionEngine`).

**Negative control (trap).** The alternate pipeline is instead built as a second, duplicated
recording path directly inside `DefaultQuickAnswersService` (`startAlternateRecording`/
`stopAlternateRecording`), talking to `AVAudioSession`/`AVAudioEngine`/`SFSpeechRecognizer` and
`SFSpeechRecognizer.requestAuthorization`/`requestRecordPermission` directly, switched on with an
`if useAlternatePipeline` inside `record()`/`stopRecording()`. It never conforms to
`TranscriptionEngine` at all.

| Check | Method | Positive | Negative |
|---|---|---|---|
| AC1 (new TranscriptionEngine conformer) | grep for `: TranscriptionEngine` (baseline = 2) | PASS (3 found) | **FAIL** (still 2 — no new conformer) |
| AC2 (selection centralized) | diff-scoped grep for branching in UI/QuickAnswersService.swift | PASS | PASS (branching is inside `DefaultQuickAnswersService`, outside this check's literal scope — see note below) |
| AC3 (reuses AudioManagerProtocol/AuthorizeProvider, no direct AVFoundation) | inspect new file(s) beyond the known baseline set | PASS | **FAIL** (no new file exists at all — same underlying defect as AC1, surfaced differently) |
| AC4 (QuickAnswersService.swift byte-identical) | `git diff` | PASS | PASS |
| AC5 (tests exercise both pipelines via real entry points) | real `xcodebuild test` run + heuristic grep | PASS (68/68 tests, including new ones) | N/A — trap adds no tests (see note) |
| Full pre-existing `QuickAnswersKitTests` suite | real `xcodebuild test -scheme BrowserKit-Package -only-testing:QuickAnswersKitTests` | PASS (68/68) | PASS (59/59 pre-existing tests — trap compiles and doesn't break anything the existing suite touches) |

**Note on AC2:** the metadata's own `method` for AC2 scopes the grep to the ViewModel/ViewController/
`QuickAnswersService.swift` layer specifically (catching branching leaking into the UI layer), not
`DefaultQuickAnswersService.swift` itself. Our trap keeps its branching inside
`DefaultQuickAnswersService`, so this specific check does not fire on it — but AC1 and AC3 fire
unambiguously and for the right underlying reason (no `TranscriptionEngine` conformer was created at
all, which is the actual architectural defect). This was verified deliberately, not glossed over:
AC2's grep is diff-aware (compares against the pinned commit) precisely because a first draft of it
false-positived on the *positive* control (pre-existing, unrelated `if #available(iOS 26, *)` checks
already present in `OptInView.swift`/`QuickAnswersViewController.swift` at the pinned commit) — fixed
by scoping the grep to added (`+`) diff lines only.

**Verdict: DISCRIMINATES.** Positive = functional PASS (68/68, including new coverage) + all 5
architecture checks PASS. Negative = functional PASS (59/59 pre-existing tests, compiles cleanly)
but 2 of 5 architecture checks (AC1, AC3) unambiguously FAIL for the correct underlying reason (no
`TranscriptionEngine` conformer; duplicated AVFoundation/Speech plumbing).

## Task B — Toolbar middle-button "Close Tab" (cross-module)

**Files:** `validators/task_B_AC1.sh`..`task_B_AC5.sh`, `controls/task_B_positive.diff`,
`controls/task_B_negative.diff`.

**Functional verification status: manual-review + `swiftc -parse` only — not executed.** See
"Verification methods" above for what was actually attempted (a real `xcodebuild build -scheme
Fennec` got to real compilation of some targets before failing on a missing Mozilla-internal
codegen tool, `bin/nimbus-fml.sh`, unrelated to this diff).

**Positive control.** Adds `.closeTab` to `NavigationBarMiddleButtonType` (label/imageName) and to
`ToolbarActionConfiguration.ActionType` (a Client-app file, not BrowserKit); extends
`getMiddleButtonAction`'s switch; `ToolbarMiddleware.handleToolbarButtonTapActions` gets a
`.closeTab` case that closes the active tab via `tabManager(for:)?.removeTab(...)` and then
`store.dispatch(GeneralBrowserAction(..., actionType: .didCloseTabFromToolbar))` — this is a
byte-for-byte mirror of the **pre-existing** `getCloseTabAction()` closure in
`BrowserViewController+ToolBarActionMenuDelegate.swift`, which does exactly
`tabManager.removeTab(tab.tabUUID)` then dispatches the same `didCloseTabFromToolbar` action — i.e.
this is not a novel pattern invented for this task, it is the codebase's own established idiom for
this exact action, reused. Added `ToolbarTelemetry.closeTabButtonTapped(isPrivate:)` (new Glean
event `close_tab_button_tapped` added to `toolbar.yaml`, mirroring `home_button_tapped`) and a third
`GenericSelectableItemCellView` in `NavigationBarMiddleButtonSelectionView.swift`. Persistence
untouched (same `PrefsKeys.Settings.navigationToolbarMiddleButton` read/write sites).

**Negative control (trap).** Same enum/UI surface exists, but: (1) the Close Tab cell in
`NavigationBarMiddleButtonSelectionView.swift` writes directly to
`UserDefaults.standard.set(..., forKey: "NavigationToolbarMiddleButtonCloseTabPreference")` instead
of going through the shared Prefs key; (2) `NavigationToolbarContainerModel.getOnSelected` special-
cases `.closeTab` to resolve `WindowManager`/`TabManager` and call `removeTab(...)` directly from the
view-model layer, never dispatching a Redux action, never touching `ToolbarMiddleware` or
`ToolbarTelemetry` at all.

| Check | Method | Positive | Negative |
|---|---|---|---|
| AC1 (enum extended, not ad hoc) | grep enum + label/imageName switches | PASS | PASS (enum itself is still modeled correctly — this trap's defect is elsewhere) |
| AC2 (dispatches via Redux from middleware) | grep + nearby-`store.dispatch` check + BrowserKit/ToolbarKit TabManager check | PASS | **FAIL** (no close-tab dispatch found in ToolbarMiddleware) |
| AC3 (reuses existing Prefs key, no new key) | grep for the shared key + grep for `UserDefaults`/ad hoc key names | PASS | **FAIL** (new `UserDefaults.standard` key found) |
| AC4 (no BrowserKit→Client coupling) | grep BrowserKit/Sources/ToolbarKit | PASS | PASS (trap lives entirely in Client, doesn't touch BrowserKit) |
| AC5 (telemetry via ToolbarTelemetry) | grep for new `*ButtonTapped` method + call site | PASS | **FAIL** (no new telemetry method added at all) |

**Verdict: DISCRIMINATES on architecture checks (3 of 5 fail for the trap).** Functional
equivalence between positive and negative was judged by code reading, not execution: the trap's
`removeTab(...)` call is real and would close the active tab exactly like the positive control from
a user's point of view (same `TabManager.removeTab` API, same tab), so a manual/black-box tester
would very plausibly see "the button works" for both. Architecturally, however, the trap
reintroduces exactly the "view mutates app state directly instead of going through the Store"
anti-pattern this codebase's Redux migration (ADR 0004/0005) moved away from, and it silently drops
telemetry and settings persistence — both caught mechanically by the validators above.

## Task D — Copy Address confirmation toast (architecture trap)

**Files:** `validators/task_D_AC1.sh`..`task_D_AC4.sh`, `controls/task_D_positive.diff`,
`controls/task_D_negative.diff`.

**Functional verification status: manual-review + `swiftc -parse` only — not executed.** Same
environment limitation as Task B (shared Client app target/build).

**Positive control.** Adds `case copyURL` to `ToastType` (title = new
`.CopyAddressConfirmMessage` string, "Address Copied") and routes it through the existing
`showPlainToast` branch in `showToastType(toast:)` (same branch as `.clearCookies`/
`.shakeToSummarizeNotAvailable`, per the task's own hint). `copyAddressAction`'s closure, after
`UIPasteboard.general.url = url`, now calls
`store.dispatch(GeneralBrowserAction(toastType: .copyURL, windowUUID: windowUUID, actionType:
GeneralBrowserActionType.showToast))` — the existing `BrowserViewControllerState` reducer and
`newState(state:) -> showToastType(toast:)` pipeline (unmodified) does the rest.

**Negative control (trap).** `copyAddressAction`'s closure instead calls
`showPlainToast(message: "Address Copied")` directly, inline, immediately after the pasteboard
write — no `ToastType` case, no dispatch, no reducer involvement. This mirrors the several
**pre-existing legacy direct-call sites** already present elsewhere in the same 5000+-line
`BrowserViewController.swift` file (which is exactly why this is a realistic trap: an agent grepping
the file for "how do I show a toast" is likely to copy one of those, right next to the file's own
comment "New toasts should be piped through Redux").

| Check | Method | Positive | Negative |
|---|---|---|---|
| AC1 (new ToastType case exists) | grep enum + title switch | PASS | **FAIL** (no new case — trap builds the toast ad hoc) |
| AC2 (dispatches via store.dispatch, no direct toast call) — central check | extract `copyAddressAction` closure body, check for dispatch + absence of direct toast calls | PASS | **FAIL** (direct `showPlainToast(...)` call found in the closure, no dispatch) |
| AC3 (reducer path reused unmodified) | `git diff` of `BrowserViewControllerState.swift` | PASS (unchanged) | PASS (unchanged — trap doesn't touch the reducer at all, consistent with bypassing it entirely) |
| AC4 (showToastType stays the single presentation path) | grep `switch toast {` occurrence count + parallel-method check | PASS | PASS (trap doesn't add a second presentation method — it just calls the existing `showPlainToast` helper directly, which is architecturally wrong for a different reason than "parallel presentation path") |

**Verdict: DISCRIMINATES on the two checks that matter most for this task (AC1, AC2 — the ones
the task was explicitly designed around).** From a user's/manual tester's point of view the two
diffs are indistinguishable (the toast "Address Copied" appears and disappears identically either
way) — that is the whole point of this architecture-trap task design. AC1 and AC2 catch the
violation mechanically and unambiguously: no `ToastType` case was added, and the `copyAddressAction`
closure body (extracted programmatically via brace/paren-depth tracking, not just "does this file
contain a bad pattern anywhere") contains a direct `showPlainToast(...)` call instead of a
`store.dispatch(...)`.

## Summary

| Task | Functional verification | Architecture checks | Discriminates? |
|---|---|---|---|
| A (TabDataStore) | **Executed** (`xcodebuild test`, real simulator) | 4/4 automated, all runnable | **Yes** |
| B (Toolbar Close Tab) | Manual review + `swiftc -parse` only (Client app build hit an unrelated missing-tool environment limit) | 5/5 automated, all runnable; 3/5 fail for the trap | **Yes** (on architecture checks) |
| C (QuickAnswersKit pipeline) | **Executed** (`xcodebuild test`, real simulator) | 5/5 automated, all runnable | **Yes** |
| D (Copy Address toast) | Manual review + `swiftc -parse` only (same environment limit as B) | 4/4 automated, all runnable; 2/4 fail for the trap (the 2 that matter) | **Yes** (on architecture checks) |

No cherry-picking: every validator script was run against both its own positive and negative
control and against the untouched pinned commit (as a baseline sanity check) at least once; two
validator bugs found during that process (a `\s` GNU-regex construct silently failing under macOS
BSD `sed`, and a telemetry-method regex matching a pre-existing unrelated method) were fixed and
re-verified against both controls, not just papered over.
