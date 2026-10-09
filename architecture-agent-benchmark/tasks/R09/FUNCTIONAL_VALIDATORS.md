# R09 (mozilla-mobile/firefox-ios) — Functional Validators

Repository: `mozilla-mobile/firefox-ios`, pinned commit `de940072da700c2af7d74348b5775674d106d503`,
cloned to `/tmp/benchmark-repos/R09`. These validators supplement the Phase 4 architecture
validators (`validators/task_X_AC*.sh`) with real, standalone `functional_success` checks for each
of the 4 tasks. Usage: `validators/task_X_functional.sh [path-to-repo]` (default `.`).

Environment facts confirmed by direct reproduction before writing these scripts:
- Plain `swift build`/`swift test` in `BrowserKit/` fail with `error: no such module 'UIKit'`
  (the `Common` target unconditionally `import UIKit`, and bare SwiftPM resolves against the host
  macOS SDK). `xcodebuild test` against an iOS Simulator destination is the actually-working
  equivalent, exactly as Phase 5 found — used for Tasks A and C.
- `xcodebuild build -scheme Fennec` (the Client app) gets real distance (resolves the full
  ~98-target dependency graph, begins real compilation) before failing on
  `bin/nimbus-fml.sh: No such file or directory` (Mozilla's Nimbus codegen tool, fetched by
  `bootstrap.sh` from an external URL). Attempting to fetch/pipe that bootstrap script into `bash`
  was explicitly denied by this environment's own tooling-execution policy, confirming this is a
  hard, reproducible environment limitation for Tasks B and D, not a defect in any diff.

## Task A — TabDataStore backup-cleanup fix

**Script:** `validators/task_A_functional.sh`. **Fixture:** `validators/fixtures/task_A_test.swift`
(injected as `BrowserKit/Tests/TabDataStoreTests/R09TaskAFunctionalTests.swift`, removed afterward).

**What's checked:** a black-box XCTest suite that calls only the public
`TabDataStore.removeWindowData(forUUIDs:)` API against the pre-existing `MockTabFileManager` test
double, asserting: (1) a UUID present in both the primary and backup directory listings gets
`removeFileAt(path:)` called twice (once per directory) — the ticket's core requirement; (2) a
window with no backup file doesn't throw; (3) an untouched window's files are left alone; (4)
`clearAllWindowsData()` still clears both directories. It never touches a candidate's private
helpers, so it is agnostic to how the fix is implemented internally.

**Command:** `cd BrowserKit && xcodebuild test -scheme TabDataStore -destination 'platform=iOS Simulator,name=<device>' -only-testing:TabDataStoreTests/R09TaskAFunctionalTests`

**Controls (both actually run):** pristine pinned commit → **FAIL** (bug unfixed, count is 1 not
2). Positive control (`controls/task_A_positive.diff`) → **PASS** (4/4 injected tests). Negative
control (`controls/task_A_negative.diff`, which reaches around `TabFileManager` with a hand-built
`FileManager.default` container path) → **FAIL** (backup-removal assertion gets count 1, not 2,
because the mock is bypassed). This intentionally mirrors Phase 5's `task_A_AC4.sh`, which is a
stronger functional guard than a literal reading of `functional_check_command` (the pre-existing
20-test suite passes for both controls since it never exercises this exact code path) — the
injected fixture is the actual functional discriminator here. Fully automated, no manual review.

## Task C — Alternative speech-to-text pipeline (QuickAnswersKit)

**Script:** `validators/task_C_functional.sh`. **Fixture:** `validators/fixtures/task_C_test.swift`
(injected as `BrowserKit/Tests/QuickAnswersKitTests/R09TaskCFunctionalTests.swift`, removed
afterward).

**What's checked:** two layers. (1) A black-box Swift Testing fixture that injects an arbitrary
`TranscriptionEngine` conformer (the pre-existing `MockTranscriptionEngine`) via
`DefaultQuickAnswersService`'s existing `engine:` init parameter (predates this task, part of the
stable public contract) and asserts `record()`/`stopRecording()`/`search(text:)` behave identically
regardless of which engine backs the service, and that two independently-constructed instances
don't share state. This deliberately does not guess the candidate's new flag/engine name, since the
metadata allows that name to vary. (2) The full `QuickAnswersKitTests` target is run (picking up
whatever tests the candidate added), plus a structural grep of
`Sources/QuickAnswersKit/Backend/SpeechService/*.swift` requiring a `TranscriptionEngine` conformer
count `>= 3` (baseline at the pinned commit is 2: `SFSpeechRecognizerEngine`, `SpeechAnalyzerEngine`)
to confirm "a second pipeline is added" structurally.

**Command:** `cd BrowserKit && xcodebuild test -scheme BrowserKit-Package -destination 'platform=iOS Simulator,name=<device>' -only-testing:QuickAnswersKitTests`

**Controls (both actually run):** pristine pinned commit → **FAIL** (suite passes, 61 tests, but
only 2 conformers found — correctly flags the pipeline as not-yet-added). Positive control
(`controls/task_C_positive.diff`, adds `AlternateTranscriptionEngine`) → **PASS** (70 tests
including the fixture's 3, 3 conformers found). Negative control (`controls/task_C_negative.diff`,
duplicates AVFoundation/Speech plumbing directly inside `DefaultQuickAnswersService` instead of
adding a `TranscriptionEngine` conformer) → **FAIL** (suite still passes at 61 tests since nothing
regresses, but conformer count stays at 2). Fully automated, no manual review.

## Task B — Toolbar middle-button "Close Tab" (Client-app-scoped)

**Script:** `validators/task_B_functional.sh`. No fixture (Client app isn't independently
buildable; see environment facts above).

**What's checked, automated:** (1) real `swiftc -parse` (against the iOS Simulator SDK) on the
feature's known files (`NavigationBarState.swift`, `ToolbarMiddleware.swift`,
`ToolbarTelemetry.swift`, `ToolbarActionConfiguration.swift`, `NavigationToolbarContainerModel.swift`,
`NavigationBarMiddleButtonSelectionView.swift`, `GeneralBrowserAction.swift`) plus any other `.swift`
file changed relative to the pinned commit — a genuine syntax gate, FAILs on real breakage; (2) an
automated structural check that a third case actually exists in `NavigationBarMiddleButtonType` —
if not, FAILs immediately ("ticket not implemented" is not a matter of judgement). **What's manual:**
whether tapping the button actually closes the tab at runtime, whether the Settings picker shows 3
options live, whether the choice persists across relaunch, and whether telemetry fires — the script
extracts and prints exact evidence (persistence read/write sites, the tab-closing call site,
telemetry method + call site) so a reviewer can confirm quickly, then reports **MANUAL REVIEW
REQUIRED** (exit 2) rather than fabricating a verdict.

**Controls (both actually run):** pristine pinned commit → **FAIL** (no third case exists). Positive
control (`controls/task_B_positive.diff`) → parses clean, third case `closeTab` found, evidence
shows the Redux dispatch + `removeTab` call, new `closeTabButtonTapped` telemetry method and its
call site, and the shared Prefs key read/write sites → **MANUAL REVIEW REQUIRED**, manually confirmed
correct (all functional pieces present). Negative control (`controls/task_B_negative.diff`) → also
parses clean, third case found, evidence shows the tab actually gets closed via
`windowManager.tabManager(...)?.removeTab(...)` (so a user would see it work) but reveals a
`UserDefaults.standard.set(...)` call instead of the shared Prefs key and no new telemetry method →
**MANUAL REVIEW REQUIRED**, manually confirmed: functionally the tab still closes (indistinguishable
to a black-box tester, exactly as `CONTROL_RESULTS.md` documents), which is why this task's
architectural discrimination lives in `task_B_AC1.sh`..`task_B_AC5.sh`, not here.

## Task D — Copy Address confirmation toast (Client-app-scoped, architecture trap)

**Script:** `validators/task_D_functional.sh`. No fixture (same Client-app constraint as Task B).

**What's checked, automated:** (1) real `swiftc -parse` on `BrowserViewController.swift`,
`ToastType.swift`, `Strings.swift`, `BrowserViewControllerState.swift`, `GeneralBrowserAction.swift`
plus any other changed `.swift` file; (2) the `copyAddressAction` closure body is extracted (brace
depth tracking) and checked for the pre-existing `UIPasteboard.general.url = ...` assignment and
`return true` — regresses to **FAIL** if either is missing/altered (ticket requires pasteboard
behaviour stay unchanged); (3) an automated check that *some* confirmation trigger exists at all
(`store.dispatch(...)` or a direct `show(toast:)`/`showPlainToast(...)` call) inside that closure —
**FAILs** immediately if neither is present ("no confirmation added" is not a matter of judgement).
**What's manual:** whether the confirmation actually renders and auto-dismisses on screen — the
script notes (and cites the actual method signature) that auto-dismiss is inherited for free from
the shared `Toast`/`show(toast:)` infrastructure as long as an existing presentation path is used,
then reports **MANUAL REVIEW REQUIRED** (exit 2).

**Controls (both actually run):** pristine pinned commit → **FAIL** (no dispatch, no direct toast
call — feature absent). Positive control (`controls/task_D_positive.diff`) → parses clean,
pasteboard behaviour intact, `store.dispatch(GeneralBrowserAction(toastType: .copyURL, ...))` found,
new `ToastType.copyURL` case found → **MANUAL REVIEW REQUIRED**, manually confirmed correct. Negative
control (`controls/task_D_negative.diff`, inline `showPlainToast(message: "Address Copied")`) →
parses clean, pasteboard behaviour intact, a direct toast trigger is found (so a confirmation does
appear and auto-dismiss, identically to the positive control from a user's point of view — this is
the deliberate point of this architecture-trap task) but no new `ToastType` case exists → **MANUAL
REVIEW REQUIRED**, manually confirmed: visually indistinguishable from positive, exactly as
`CONTROL_RESULTS.md` documents; the Redux-vs-ad-hoc distinction is caught by `task_D_AC1.sh`/`AC2.sh`,
not by this functional script.

## Summary

| Task | Automated functional gate | Positive control | Negative control | Manual-review-only part |
|---|---|---|---|---|
| A (TabDataStore) | Real `xcodebuild test` of injected black-box XCTest | PASS | FAIL | None — fully automated |
| B (Toolbar Close Tab) | `swiftc -parse` + "3rd case exists" structural check | MANUAL REVIEW (confirmed correct) | MANUAL REVIEW (confirmed functionally equivalent, architecturally wrong) | Runtime tap behaviour, live picker, persistence-across-relaunch, telemetry firing |
| C (QuickAnswersKit pipeline) | Real `xcodebuild test` of injected fixture + full suite + conformer-count check | PASS | FAIL | None — fully automated |
| D (Copy Address toast) | `swiftc -parse` + pasteboard-preserved check + "trigger exists" structural check | MANUAL REVIEW (confirmed correct) | MANUAL REVIEW (confirmed visually identical, architecturally wrong) | On-screen rendering/auto-dismiss timing |

Every validator was run against the pristine pinned commit (sanity baseline) and both its own
positive and negative control at least once, with the repo reset to a clean pinned-commit state
(`git checkout --` / removing untracked control-diff files) between each run and after finishing.
DerivedData/`.build` artifacts generated during verification were cleaned up to keep disk usage
under control.
