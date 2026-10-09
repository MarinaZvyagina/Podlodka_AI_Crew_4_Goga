# R09-TC-BF-07

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.6
Dangerous success: False
Goga engagement signal: True
Cost: $2.0689419
Duration: 434491ms, turns: 56

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add the ability to A/B test an alternative speech-to-text pipeline for the Quick Answers voice-search feature: introduce a flag-driven engine variant (`standard` vs `alternative`), a scripted stand-in `AlternativeTranscriptionEngine`, thread the variant from a Nimbus experiment through the existing `QuickAnswersConfigFetcher` vehicle into `DefaultQuickAnswersService`'s engine selection, and update tests — without changing any documented cell's public contract.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `BrowserKit/Sources/QuickAnswersKit/UI` | Only documented cell overlapping the QuickAnswersKit target; its CODEMANIFEST explicitly disclaims the backend as out of scope | Low (verify non-impact only) |
| `firefox-ios/Client/Coordinators` | `QuickAnswersCoordinator.swift` physically resides in this cell's directory | Low (verify non-impact only) |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| None | No documented cell's contract type is modified; `QuickAnswersConfigFetcher`, `DefaultQuickAnswersService`, `TranscriptionEngine` and all speech-service types live in `Backend/*`, which has no CODEMANIFEST anywhere in its subtree |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `BrowserKit/Sources/QuickAnswersKit/UI` | Documents exactly 3 types (`QuickAnswersViewController`, `QuickAnswersNavigationHandler`, `QuickAnswersTelemetry`) by `location:` in that same directory. `QuickAnswersConfigFetcher` is declared in `Backend/QuickAnswersService.swift` — a different directory — so per goga-cell-swift ("only declarations... constitute the Facade" + DSL `location` rule restricting a manifest to files in its own directory) it is never part of this cell's documented facade, regardless of being `public`. `QuickAnswersViewController`'s own init signature (the only thing this manifest documents about construction) is unchanged by this task. |
| `firefox-ios/Client/Coordinators` | Documents only the base pattern (`Coordinator`, `BaseCoordinator`, `ParentCoordinatorDelegate`) via `location: Coordinator.swift` / `BaseCoordinator.swift` / `ParentCoordinatorDelegate.swift`. Its own Annotations explicitly state route/router specifics are "out of scope for this cell" and that ~15 concrete coordinators (naming Quick Answers as an example) subclass the base pattern outside the documented contract. `QuickAnswersCoordinator.swift` is one such concrete subclass, never named in the manifest body — editing it (adding a Nimbus-read helper and passing a new constructor arg to `RemoteQuickAnswersConfigFetcher`) does not touch `Coordinator`/`BaseCoordinator`/`ParentCoordinatorDelegate`. |
| `BrowserKit/Sources/Common/Logger`, `BrowserKit/Sources/Redux/GlobalState`, `BrowserKit/Sources/WebEngine`, `BrowserKit/Sources/Common/DependencyInjection`, `BrowserKit/Sources/ToolbarKit`, `BrowserKit/Sources/TabDataStore`, `firefox-ios/Client/Redux/GlobalState` | No data flow, no import relationship, no behavioral participation in speech transcription at all |

## Usage Relationships

| Usage | Relevance |
|---|---|
| None | No cell in scope declares `Usages`/`Imports` referencing this feature area; `.goga/config.yml` has no `codemanifest.usages`/`codemanifest.annotations` configured (confirmed via `goga config`) |

## Semantic Participation Summary
No documented cell participates in this task's behavior. All touched files — `QuickAnswersKit/Backend/*` (SpeechService engines, `TranscriptionEngineVariant`, `QuickAnswersConfigFetcher`/`DefaultQuickAnswersConfigFetcher`, `DefaultQuickAnswersService`), `firefox-ios/nimbus-features/quickAnswersFeature.yaml`, `firefox-ios/Client/Frontend/QuickAnswers/RemoteQuickAnswersConfigFetcher.swift`, `firefox-ios/Client/Coordinators/QuickAnswersCoordinator.swift`, and the `BrowserKit/Tests/QuickAnswersKitTests/*` test files/mocks — sit either in explicitly-out-of-scope backend territory or in a concrete coordinator subclass the base-pattern manifest disclaims. The two candidate cells were checked purely to rule out contract impact, not because they participate.

## Final Investigation Scope
- `BrowserKit/Sources/QuickAnswersKit/Backend/SpeechService/*` (TranscriptionEngine, SFSpeechRecognizerEngine, SpeechAnalyzerEngine, Abstractions, SpeechError, AuthorizationHandler, AudioManager)
- `BrowserKit/Sources/QuickAnswersKit/Backend/QuickAnswersService.swift`
- `BrowserKit/Sources/QuickAnswersKit/Backend/DefaultQuickAnswersService.swift`
- `BrowserKit/Sources/QuickAnswersKit/Backend/ResultsService/QuickAnswersConfigFetcher.swift`
- `firefox-ios/nimbus-features/quickAnswersFeature.yaml`
- `firefox-ios/Client/Frontend/QuickAnswers/RemoteQuickAnswersConfigFetcher.swift`
- `firefox-ios/Client/Coordinators/QuickAnswersCoordinator.swift`
- `BrowserKit/Tests/QuickAnswersKitTests/**` (existing tests + mocks affected, plus new test files)
- No CODEMANIFEST or `.usages` file requires editing.

## Scope Risks
- **Under-scoping risk**: if `QuickAnswersViewModel`/`QuickAnswersViewController` needed a new public parameter (an earlier design alternative considered before this task), that would have pulled the UI cell's CODEMANIFEST into scope. The chosen design (threading the variant through the existing `QuickAnswersConfigFetcher`) avoids this, but implementers must not deviate from it — adding any new public init parameter to `QuickAnswersViewController` would immediately re-open the UI cell's contract and require reconciliation.
- **Over-scoping risk**: none identified — no cell boundary is at risk of unnecessary edits.

## Notes
`goga schema`/`goga lint` baseline (9 cells, 0 errors) confirmed by the orchestrator before this pipeline started. Because the final scope touches zero CODEMANIFEST-documented types, Step 7 (Manifest Reconciliation) and Step 8 (Usage Reconciliation) are expected to be no-ops later in the pipeline — this should be re-confirmed, not assumed, once implementation is complete.
