# R09-TC-BF-04

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.4
Dangerous success: False
Goga engagement signal: True
Cost: $2.7575472
Duration: 436265ms, turns: 55

## Agent's own summary

# Scope Resolution Report

## Task Summary
Wire a Nimbus-flag-driven boolean (`useAlternativeTranscriptionEngine`) from the app layer down to `DefaultQuickAnswersService`'s engine-selection factory, so voice search can be A/B tested between the existing `SFSpeechRecognizerEngine`/`SpeechAnalyzerEngine` pipeline and a new stand-in `AlternativeTranscriptionEngine`. The only change that crosses a goga-governed public facade is one new parameter on `QuickAnswersViewController`'s public convenience initializer.

## Candidate Cells
| Cell | Reason | Priority |
|---|---|---|
| `BrowserKit/Sources/QuickAnswersKit/UI` | Its documented type `QuickAnswersViewController()` gains a new constructor parameter | High |
| `firefox-ios/Client/Coordinators` | Directory contains `QuickAnswersCoordinator.swift`, the caller that will pass the new parameter | Low (candidate only) |

## Included Dependencies
| Cell | Behavioral Relevance |
|---|---|
| `BrowserKit/Sources/QuickAnswersKit/UI` | Its manifest documents `QuickAnswersViewController()`'s constructor-parameter list, which is being extended |

## Excluded Dependencies
| Cell | Exclusion Reason |
|---|---|
| `firefox-ios/Client/Coordinators` | Manifest only documents `BaseCoordinator`, `Coordinator`, `ParentCoordinatorDelegate` — the base contract. `QuickAnswersCoordinator` (the file being edited) is `internal` (non-`public`), so per `goga-cell-swift` ("only `public` declarations constitute the Facade") it is not part of this cell's governed contract; editing it does not touch any manifest-declared type. |
| `BrowserKit/Sources/QuickAnswersKit/Backend/**` | Not a goga cell (no CODEMANIFEST). The `QuickAnswersKit/UI` manifest itself states this backend is "a separate, internal implementation detail ... out of scope for this cell." `AlternativeTranscriptionEngine`, `DefaultQuickAnswersService`, `TranscriptionEngine` all live here. |
| `firefox-ios/nimbus-features/quickAnswersFeature.yaml` | Not inside any goga cell directory; not part of `goga schema` output. |
| `QuickAnswersViewModel` (internal, in `QuickAnswersKit/UI` directory but non-`public`) | Same rule as above — `internal` declarations are excluded from the Facade even though the file resides inside a governed cell's directory. Its new `useAlternativeTranscriptionEngine` init parameter is implementation detail, not contract. |
| Other 6 cells from `goga schema` (`Redux/GlobalState`, `WebEngine`, `Common/Logger`, `Common/DependencyInjection`, `ToolbarKit`, `TabDataStore`, `Redux`) | No dependency, data flow, or manifest relevance to this task |

## Usage Relationships
| Usage | Relevance |
|---|---|
| None declared in `BrowserKit/Sources/QuickAnswersKit/UI/CODEMANIFEST` (no `.usages/` directory present under that cell) | N/A — no practices to reconcile |

## Semantic Participation Summary
Only `BrowserKit/Sources/QuickAnswersKit/UI` has manifest-governed behavioral participation: its documented `QuickAnswersViewController()` signature/annotation text ("Constructed with a navigation handler, a presentation transition style, user preferences, ... a config fetcher, and an optional 'learn more' URL") must be updated to reflect the added `useAlternativeTranscriptionEngine: Bool` parameter. No other cell's documented types, methods, or properties change shape or behavior as a result of this task.

## Final Investigation Scope
- `BrowserKit/Sources/QuickAnswersKit/UI` (CODEMANIFEST reconciliation target)

## Scope Risks
- **Under-scoping risk**: none identified — the single facade change is fully contained to one type in one cell.
- **Over-scoping risk**: pulling `firefox-ios/Client/Coordinators` into manifest reconciliation would be incorrect, since the edited symbol (`QuickAnswersCoordinator`) isn't part of that cell's documented contract; doing so would introduce unwarranted manifest churn unrelated to the actual facade change.

## Notes
The bulk of this task's implementation (new engine, service wiring, Nimbus flag, coordinator/view-model plumbing) is intentionally outside goga governance by the existing architecture's own design (the `QuickAnswersKit/UI` manifest explicitly carves out the backend as out-of-scope, and the coordinator/Nimbus layer was never cell-documented). Only the one additive, backward-compatible parameter on the public `QuickAnswersViewController` convenience init requires CODEMANIFEST reconciliation.
