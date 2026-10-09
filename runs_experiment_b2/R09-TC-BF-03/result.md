# R09-TC-BF-03

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.4
Dangerous success: False
Goga engagement signal: False
Cost: $2.8904807999999993
Duration: 480175ms, turns: 63

## Agent's own summary

# Change Plan

## Task Classification
**Feature (extension)** — additive, backward-compatible extension of an existing documented constructor to support an A/B experiment flag.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `BrowserKit/Sources/QuickAnswersKit/UI` | `CODEMANIFEST` | Update `QuickAnswersViewController()` entry's `annotations` prose to mention the new `speechEngineVariant` dependency |
| `BrowserKit/Sources/QuickAnswersKit/UI` | `QuickAnswersViewController.swift` | Add trailing defaulted param `speechEngineVariant: SpeechEngineVariant = .standard` to the public convenience init; forward it to the `QuickAnswersViewModel(...)` construction at line 84 |
| `BrowserKit/Sources/QuickAnswersKit/UI` | `QuickAnswersViewModel.swift` | Add trailing defaulted param `speechEngineVariant: SpeechEngineVariant = .standard` to `init`; pass it through to the `makeService` closure's default implementation, which forwards to `DefaultQuickAnswersService.init(speechEngineVariant:)` |

No other cell in the governed forest is affected (per Scope Resolution Report — `QuickAnswersKit/UI` has no documented dependencies or dependents).

## Root Cause Analysis
No existing seam lets the app layer influence which `TranscriptionEngine` is used; selection is hardcoded to an OS-version check (`DefaultQuickAnswersService.swift:104-119`). A new parameter is the minimal seam consistent with the existing `configFetcher`/`model` precedent for threading Nimbus-driven choices from `QuickAnswersCoordinator` down into this cell.

## Trace Summary
`QuickAnswersCoordinator.start()` (app layer, out of cell) → `QuickAnswersViewController` public convenience init (in cell) → inline `QuickAnswersViewModel(...)` construction (in cell, `internal`) → `makeService` default closure (in cell) → `DefaultQuickAnswersService.init` (out of cell, out of scope) → `makeDefaultEngine(variant:)` (out of cell). Only the two in-cell hops are governed by this plan.

## Change Strategy
1. In `QuickAnswersViewController.swift`, add `speechEngineVariant: SpeechEngineVariant = .standard` as the new trailing parameter of the public convenience init (before `notificationCenter`, which is itself already defaulted and trailing — Swift requires defaulted params to be usable by keyword regardless of order, but keep `notificationCenter` last since it's the existing "internal/test-seam" default; both approaches are equivalent for callers using keyword args, so preserve current order and simply insert the new param immediately before `notificationCenter`).
2. Pass `speechEngineVariant` into the `QuickAnswersViewModel(prefs:telemetry:configFetcher:speechEngineVariant:)` construction on line 84.
3. In `QuickAnswersViewModel.swift`, add the same trailing defaulted parameter to `init`, store nothing new as a stored property (it's only needed to build the default service), and pass it into the default `makeService` closure's call to `DefaultQuickAnswersService(configFetcher:speechEngineVariant:prefs:)`.
4. Update the `CODEMANIFEST` prose for `QuickAnswersViewController()` to append "...and a speech-engine experiment variant" to the existing dependency list sentence.
5. `SpeechEngineVariant` itself, `AlternativeTranscriptionEngine`, and the `DefaultQuickAnswersService` changes are implemented afterward as ordinary (non-governed) code changes in the out-of-scope backend area, per the manifest's own "out of scope" declaration.

## Specification Impact
Only the `annotations` block of the `"QuickAnswersViewController()"` entry changes — the sentence "Constructed with a navigation handler, a presentation transition style, user preferences, the presenting window's UUID, a theme manager, a telemetry sink, a config fetcher, and an optional 'learn more' URL." becomes "...a config fetcher, a speech-engine experiment variant, and an optional 'learn more' URL." No `methods`, `properties`, header (`Imports`/`Usages`), or footer sections change.

## Usage Impact
None — this cell has no `.usages/` directory and declares no `Usages`/`Imports` today; nothing to reconcile.

## Compatibility Verification
**Backward compatible.** Confirmed in the Investigation Report: the new parameter is trailing and defaulted to `.standard`, which reproduces today's exact OS-version-based engine selection. Both existing call sites (`QuickAnswersCoordinator.swift`, `QuickAnswersViewControllerTests.swift`) use keyword arguments and omit already-defaulted parameters, so they compile and behave identically without modification. No STOP condition triggered.

## Test Strategy
- Add/extend a `QuickAnswersViewControllerTests` case constructing the VC with `speechEngineVariant: .alternative` to confirm it accepts the parameter and builds successfully (governed-cell-level test).
- The deeper behavioral tests (both engines selected correctly, identical record/stream/error/cancel behavior regardless of variant) belong to the out-of-scope backend (`DefaultQuickAnswersServiceTests`, new `AlternativeTranscriptionEngineTests`) and are handled in the separate, non-governed implementation step.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `SpeechEngineVariant` type not yet defined when this cell's code is compiled | Medium | Build failure (undefined type) | Implement `SpeechEngineVariant` (out-of-scope backend file) in the same change set, before or alongside this cell's edits, since both live in the same Swift target |
| CODEMANIFEST prose drifts from actual constructor signature over time | Low | Documentation staleness | Manifest Reconciliation step (Step 7) re-verifies prose against final code |
| Parameter ordering confuses future readers (experiment flag placed among stable dependencies) | Low | Minor readability | Keep it adjacent to `configFetcher` (the other Nimbus-driven value) and defaulted, matching existing convention |

---

Do you approve this plan? Proceed to implementation?
