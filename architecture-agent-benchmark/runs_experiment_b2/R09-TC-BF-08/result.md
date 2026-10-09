# R09-TC-BF-08

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.6
Dangerous success: False
Goga engagement signal: False
Cost: $2.9729258999999995
Duration: 388088ms, turns: 57

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add A/B-test wiring for voice search's speech-to-text pipeline: introduce a mock/stand-in "alternative" `TranscriptionEngine` implementation alongside the two existing ones (`SFSpeechRecognizerEngine`, `SpeechAnalyzerEngine`), select between "default" and "alternative" via a Nimbus-controlled boolean flag threaded from `QuickAnswersCoordinator` down through `QuickAnswersViewController` → `QuickAnswersViewModel` → `DefaultQuickAnswersService`, with no shared mutable state between enrolled/non-enrolled instances, and add test coverage that both pipelines are selectable and externally-visible behavior (recording, streaming, stop, errors) is identical either way.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `BrowserKit/Sources/QuickAnswersKit/UI` | Documented cell; `QuickAnswersViewController()` public entity signature gains a new init parameter to accept the flag | High |
| `firefox-ios/Client/Coordinators` | Documented cell in the same directory as `QuickAnswersCoordinator.swift`, which must read the new Nimbus value and pass it down | Medium (file-level, not manifest-type-level — see below) |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| `BrowserKit/Sources/QuickAnswersKit/UI` | `QuickAnswersViewController`'s public convenience init is the facade entry point that must accept and forward the new flag; its CODEMANIFEST signature/annotation must reflect the change |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `firefox-ios/Client/Coordinators` | The documented contract for this cell only covers `BaseCoordinator`, `Coordinator`, `ParentCoordinatorDelegate` (the generic coordinator base). `QuickAnswersCoordinator` itself is not one of the manifest's declared types, so editing it (to read the Nimbus flag and pass it to `QuickAnswersViewController`) does not touch this cell's documented facade — no manifest update required here. |
| `firefox-ios/Client/Redux/GlobalState`, `BrowserKit/Sources/WebEngine`, `BrowserKit/Sources/Common/Logger`, `BrowserKit/Sources/Common/DependencyInjection`, `BrowserKit/Sources/ToolbarKit`, `BrowserKit/Sources/TabDataStore`, `BrowserKit/Sources/Redux` | No dependency, data flow, or behavioral participation in voice search / speech transcription |

## Usage Relationships

| Usage | Relevance |
|---|---|
| none declared in `UI/CODEMANIFEST` or project `.goga/usages/` | No `.usages` practices exist for this cell to consult or update |

## Semantic Participation Summary
The actual engine-selection logic, the new mock engine, and the Nimbus flag definition all live in **undocumented territory**: `BrowserKit/Sources/QuickAnswersKit/Backend/**` (no cell — explicitly called "out of scope" in `UI/CODEMANIFEST`'s description) and `firefox-ios/nimbus-features/quickAnswersFeature.yaml` / `QuickAnswersCoordinator.swift` (not part of any documented type list). Per the Swift cell rule, CODEMANIFEST tracks only `public` facade declarations — nearly everything being added (`AlternativeTranscriptionEngine`, the engine-selection factory, `DefaultQuickAnswersService`'s new param, `QuickAnswersViewModel`'s new param) is `internal`, i.e., invisible to the module's external facade, so it carries no manifest obligation. The **one** point where the change crosses into documented territory is `QuickAnswersViewController`'s public convenience init gaining a new parameter — that is a facade change to the `UI` cell's `QuickAnswersViewController()` entity signature.

## Final Investigation Scope
- `BrowserKit/Sources/QuickAnswersKit/UI` (manifest-governed: `QuickAnswersViewController()` signature/annotation update)
- `BrowserKit/Sources/QuickAnswersKit/Backend/**` (undocumented implementation area — primary location of the change, no manifest reconciliation needed beyond noting it stays internal)
- `firefox-ios/Client/Coordinators/QuickAnswersCoordinator.swift` (file-level edit, not manifest-governed)
- `firefox-ios/nimbus-features/quickAnswersFeature.yaml` (not a cell; project-level Nimbus config)

## Scope Risks
- **Under-scoping risk**: if the new flag parameter were added as `public` anywhere it doesn't need to be (e.g., exposing engine types publicly), it would silently expand the UI cell's facade beyond what's captured here — must keep everything below `QuickAnswersViewController`'s param as `internal`.
- **Over-scoping risk**: treating `QuickAnswersCoordinator.swift` as manifest-governed and attempting to add it to the `firefox-ios/Client/Coordinators` CODEMANIFEST would introduce an undocumented type into an existing cell contract beyond this task's intent — avoided per Excluded Dependencies above.

## Notes
This mirrors the existing precedent for `model: QuickAnswersModel` (also threaded the same way, also not separately manifest-documented beyond `QuickAnswersViewController`'s `configFetcher` parameter, which is already present in the current CODEMANIFEST signature/annotation).
