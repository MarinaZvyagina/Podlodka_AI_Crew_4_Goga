# RESTRUCTURE_REPORT.md — R09 (mozilla-mobile/firefox-ios) Condition C

Seventh repository restructured for Condition C, and the first Swift repo, and the first with a
real, disclosed two-tier facade rule. 245.2k LOC, 9 originally documented cells → 33 total.

## Scope-expansion decision, in continuity with R05's precedent

R09's `SCOPE.md` disclosed that most `BrowserKit`/`Client` subdirectories were left undocumented
for budget reasons, similar in spirit to R05's disclosure — but structurally different: R09's
excluded items are mostly SIBLING SwiftPM library targets (e.g. `SiteImageView`, `MenuKit`,
`firefox-ios/Storage`) at the same directory depth as documented cells, not subdirectories of a
documented cell, so most of them don't trigger Goga's `location:` rule at all (no rule tension to
resolve, unlike R05). A genuine `location:`-rule tension DID exist for real subdirectories of the
9 documented cells (14 identified on first pass; 10 more found nested one level deeper on a
follow-up recursive scan, for **24 new cells total**). Following R05's precedent, all 24 were
formalized rather than left as disclosed exclusions.

## A real, disclosed two-tier facade rule (unique to this repo in the study so far)

`BrowserKit` cells are real SwiftPM library targets — the standard Swift rule applies (only
`public`/`open` declarations constitute the facade). `firefox-ios/Client`'s two cells
(`Coordinators`, `Redux/GlobalState`) are a single Xcode APP target with zero external
consumers — `SCOPE.md` had already disclosed that `internal` (the default access level), not
`public`, is the real load-bearing sharing boundary there. This restructuring preserved and
applied that same distinction consistently across all new nested cells under `Coordinators` (8
new cells), while every new `BrowserKit`-side cell (16 new cells) used the standard `public`-only
rule.

## Scale: 24 new cells across 4 families

| Family | New cells | Character |
|---|---|---|
| `Common/Logger` | 1 (`Wrapper`) | Sentry crash-reporting wrapper |
| `ToolbarKit` | 4 (`NavigationToolbar`, `AddressToolbar`, + nested `LocationView`, `SearchEngineView`) | UI value-model/view layer |
| `WebEngine` | 11 (`Security`, `Utilities`, `WKWebview` + nested `Extension`/`Internal`/`Alerts`/`WebServer`/`Scripts`/`Policy`, and `Scripts`'s own nested `ReaderMode`/`Metadata`) | The concrete WebKit engine implementation — genuinely deep, much of it correctly `internal`-only (2 of the 8 new leaf cells, `WebServer` and `Policy`, have **zero** real public exports — confirmed, not an oversight) |
| `Client/Coordinators` | 8 (`Router`, `QRCode`, `Launch`, `LaunchView`, `TabTray`, `Library`, `Scene`, `Browser`) | ~15 concrete navigation-flow coordinators, using the internal-access-is-facade rule |

**0 hidden** across all 33 cells. Facade completion of the 9 original cells found real gaps in
several (`Logger`: 3 undeclared crash-reporting types; `Redux`: 4; `ToolbarKit`: 2;
`QuickAnswersKit/UI`: 3; `GlobalState`: 3, including the single most important one — the
app-wide `store` singleton, used in 86 files, previously undeclared), consistent with the
"large, foundational, legitimately-public-or-internal surface" pattern from R01/R03/R04/R05.

## Three real bidirectional dependencies, resolved consistently

Full detail in `CYCLE_FIXES.md`. `WebEngine ↔ WKWebview`, `Coordinators ↔ {QRCode, Browser}`, and
(structurally, though not a real formal conflict) `AddressToolbar ↔ LocationView` were each
resolved the same way as every prior repo in this study: formalize the structurally-heavier
direction, describe the reverse in prose. `goga lint`'s `imports_has_not_cyclical_deps` passes
clean across all 33 cells.

## Process notes

- 4 initial parallel agents (BrowserKit small leaves + `Logger/Wrapper`; `ToolbarKit` family;
  `WebEngine` family; `Client` family) handled the first-pass 14 new cells. A follow-up recursive
  scan (checking every documented cell's own subdirectories, not just the ones known in advance)
  found 10 MORE real subdirectories nested one level deeper than the first pass checked
  (`AddressToolbar/LocationView` + its own `SearchEngineView`; `WKWebview`'s 6 direct
  subdirectories plus `Scripts`'s own 2 nested children) — 2 more parallel agents closed these.
  This two-pass discovery pattern (shallow scan → targeted deep scan) is now the established
  method for finding the true extent of a `location:`-rule expansion in a deeply-nested codebase.
- One path-resolution bug (3 cell-relative `From:` paths instead of repo-root-relative) was found
  and fixed during final reconciliation — see `CYCLE_FIXES.md`.
- Several agents independently flagged fake `<system-reminder>`-styled text embedded in tool
  output (consistent with the recurring pattern in R03/R04/R05/R07) — each correctly identified it
  as injected content and disregarded it.
- **A disk-space incident occurred and was resolved during the hard gate**: this machine's disk
  filled to 98% capacity (398Mi free) partway through control re-certification, caused by
  accumulated Xcode `DerivedData`/SwiftPM `.build` caches (several GB per full-package build) plus
  4 stale, hung `xcodebuild test` processes (running since before this session, doing nothing at
  0% CPU) that were corrupting the shared `DerivedData` cache via concurrent-write contention.
  Diagnosed via `df -h`/`ps aux`, resolved by killing the stale processes, clearing the corrupted
  cache, and adding an isolated-cache-cleanup step between each control-recertification pair going
  forward — not a restructuring defect.

## Hard gate: build + test

- Plain `swift build`/`swift test` fail with "no such module 'UIKit'" — confirmed identical on the
  unmodified original commit (this SwiftPM package is iOS-only; plain `swift build` defaults to
  the macOS host SDK, which lacks UIKit). The correct invocation needs an explicit iOS
  target/SDK — this is a real pre-existing environment/invocation nuance, not a restructuring
  defect, and Phase 5's own validators already independently discovered and worked around it
  (using `xcodebuild test`, not `swift test`, per their own embedded comments).
- `swift build --sdk <iphonesimulator SDK> --triple arm64-apple-ios17.0-simulator`: **Build
  complete** (all ~880 compile steps, 0 errors).
- `xcodebuild test -scheme BrowserKit-Package -destination 'platform=iOS Simulator,name=iPhone 17'`
  (isolated `-derivedDataPath`): **TEST SUCCEEDED** — every test suite in the entire BrowserKit
  package passed with 0 failures (not just the 7 documented cells' own test targets):
  `ActionExtensionKitTests` (13), `AppAttestKitTests` (8), `CommonTests` (161),
  `ComponentLibraryTests` (15), `ContentBlockingGeneratorTests` (4), `JWTKitTests` (12),
  `LLMKitTests` (29), `MLPAKitTests` (18), `MenuKitTests` (23), `OnboardingKitTests` (33),
  `QuickAnswersKitTests` (13), `ReduxTests` (24), `SiteImageViewTests` (85),
  `SummarizeKitTests` (63), `TabDataStoreTests` (20), `ToolbarKitTests` (39),
  `WebCompatReporterKitTests` (62), `WebEngineTests` (224), plus several smaller unlabeled suites.

## Control re-certification

All 8 of Phase 5's control diffs (`tasks/R09/controls/*.diff`) applied cleanly. 2 of the 4
functional validators hardcode the original base-commit SHA and needed adapted copies
(`architecture_v2/R09/validators_adapted/`). **All 4 tasks discriminate correctly, matching Phase
5's original certification exactly** — including Task B's and Task D's functional checks being
documented as "manual-review + `swiftc -parse` only, not executed" (a real, disclosed environment
limitation from Phase 5 itself — full `xcodebuild build -scheme Fennec` hits a missing
Mozilla-internal codegen tool unrelated to any diff), correctly reproduced as `MANUAL REVIEW
REQUIRED` here too. One genuine, pre-existing documentation staleness found (same category as
R05's Task A): Task C's negative control's functional check is documented as "PASS (59/59
pre-existing tests)", but the actual validator script also checks for a second
`TranscriptionEngine` conformer as part of the same functional gate and correctly reports FAIL
when it's absent — confirmed identical on the untouched original commit via side-by-side
comparison, not a regression, and if anything a stronger (not weaker) discrimination result.

| Task | Positive: functional | Positive: all AC | Negative: functional | Negative: ≥1 AC fails |
|---|---|---|---|---|
| A | PASS | PASS (4/4) | FAIL | Yes (2/4 FAIL — AC2, AC4) |
| B | MANUAL REVIEW* | PASS (5/5) | MANUAL REVIEW* | Yes (3/5 FAIL) |
| C | PASS | PASS (5/5) | FAIL** | Yes (2/5 FAIL — AC1, AC3) |
| D | MANUAL REVIEW* | PASS (4/4) | MANUAL REVIEW* | Yes (2/4 FAIL — AC1, AC2) |

*Disclosed, pre-existing environment limitation from Phase 5 itself, not a restructuring
artifact — see above. **Pre-existing documentation staleness, not a regression — see above.

## Artifacts

- Restructured commit: `1f49b04065a36ae2e89f7c2536b7c5f30c3f98ea`, tagged `condition-c-r09-v1`
  in the shared base clone (`benchmark-scratch/repos/R09`).
- `architecture_v2/R09/CYCLE_FIXES.md` — full detail on the 3 bidirectional dependencies and the
  path-resolution bug fix.
- `architecture_v2/R09/validators_adapted/` — 2 SHA-adapted functional validators + fixtures.
- The 33 cells' `CODEMANIFEST` files live directly in the restructured commit.
