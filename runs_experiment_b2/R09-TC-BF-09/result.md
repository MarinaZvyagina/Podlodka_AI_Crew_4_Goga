# R09-TC-BF-09

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.6
Dangerous success: False
Goga engagement signal: True
Cost: $2.3290017
Duration: 289907ms, turns: 46

## Agent's own summary

# Investigation Report

## Task Summary
Requested: wire an alternative, flag-selectable `TranscriptionEngine` into the Quick Answers voice-search backend for an internal A/B experiment, without altering any user-visible behavior, with per-user-session isolation (no shared mutable state) and test coverage for both pipeline selections.

## Candidate Cells
| Cell | Reason | Priority |
|---|---|---|
| `BrowserKit/Sources/QuickAnswersKit/UI` | Bordering cell; verified as a boundary-only concern, not an implementation target (confirmed below) | Low (boundary check only) |

## Tracing Summary
Call flow, outermost to innermost:
1. `firefox-ios/Client/Coordinators/QuickAnswersCoordinator.start()` — creates a **new** `QuickAnswersViewController` every time it's invoked (i.e., every time the user opens the mic-search feature). Reads `nimbusModel()` fresh on each `start()` call — no caching. This is the existing precedent for "flag read at construction time, never cached globally."
2. `QuickAnswersViewController.swift:84` — constructs a **new** `QuickAnswersViewModel(prefs:telemetry:configFetcher:)` per controller instance.
3. `QuickAnswersViewModel.swift:29-46` — constructs a **new** `DefaultQuickAnswersService` via the injectable `makeService` closure (default: `DefaultQuickAnswersService(configFetcher:prefs:)`), passing the same `prefs` reference the coordinator was given.
4. `DefaultQuickAnswersService.swift:37` — `self.engine = engine ?? Self.makeDefaultEngine()`. `makeDefaultEngine()` (lines 104-119) is a `static func` with **no parameters**, selecting purely via `#available(iOS 26.0, *)`. It does not currently receive `prefs`.

Confirmed: **no singleton, no global/shared engine instance anywhere in the traced path.** Every layer (`QuickAnswersCoordinator` → `QuickAnswersViewController` → `QuickAnswersViewModel` → `DefaultQuickAnswersService` → `engine`) is freshly constructed per invocation of the feature. Two concurrent users (or two concurrent sessions in the same process, e.g. multi-window iPad) each get their own object graph and their own `engine` instance — satisfying the "no shared mutable state" requirement structurally, before any new code is written.

## Data Flow Analysis
`Prefs` flows in one direction only: `QuickAnswersCoordinator` (owns app's `Prefs` instance) → `QuickAnswersViewModel` → `Store` (reads `optInCompleted`) and → `DefaultQuickAnswersService.init(prefs:)` (currently only forwarded to `resultsServiceFactory.make(prefs:configFetcher:)`, never consulted for engine choice). `SpeechResult` flows the opposite direction: `engine.start(continuation:)` → `AsyncThrowingStream` → `DefaultQuickAnswersService.record()` → `QuickAnswersViewModel.recordVoiceTask` → `onStateChange` → UI. This stream contract (`SpeechResult { text, isFinal }`) is the sole coupling between engine implementation and the rest of the app; any `TranscriptionEngine` conformer that respects it is a drop-in replacement.

## Manifest Algorithm Analysis
No CODEMANIFEST governs any file touched by this change. The bordering `QuickAnswersKit/UI` CODEMANIFEST's only relevant statement is its own Annotations header: "the speech-capture and results-fetch backend behind it (recording engines, transcription, the results service) is a separate, internal implementation detail of this same target and is out of scope for this cell." No algorithm text applies.

## Affected Usages
| Usage | Cell | Classification | Reason |
|---|---|---|---|
| *(none)* | — | — | No `.usages` practice exists for `QuickAnswersKit/UI` or any other cell that references speech/transcription/Prefs flag behavior. |

## Rejected Hypotheses
- **"Thread a Nimbus multi-variant flag down from firefox-ios/Client, mirroring `QuickAnswersModel`/`nimbusModel()`."** Rejected. This would require: adding a new Nimbus feature variable to `nimbus-features/quickAnswersFeature.yaml`, a new case to `FeatureFlagID`/`NimbusFeatureFlagLayer` or extending the existing feature, changing `QuickAnswersCoordinator` to compute and thread a new parameter through `QuickAnswersViewController` → `QuickAnswersViewModel` → `DefaultQuickAnswersService.init`, and — critically — introducing a `Nimbus`/`FxNimbus` dependency into the `BrowserKit` package, which today has no such dependency (`BrowserKit/Sources/QuickAnswersKit` only imports `Foundation`, `Shared`, `LLMKit`, `MLPAKit`, `Common`). That crosses a package boundary this codebase currently keeps intact and is far larger than "a simple flag we can flip for testing" as specified in the ticket. Violates the goga-change invariant to minimize scope and avoid architectural drift.
- **"Introduce a shared/singleton engine cached across sessions to avoid re-selecting on every construction."** Rejected. Evidence shows the existing architecture already avoids this (fresh construction per session, Step "Tracing Summary" above); introducing a singleton would be a net-new anti-pattern, not a fix, and would directly violate the ticket's "no shared mutable state that would leak between them" requirement.

## Confirmed Root Cause
Not applicable in the traditional bug sense — this is an additive feature request. The "gap" to close is precise: `DefaultQuickAnswersService.makeDefaultEngine()` (`DefaultQuickAnswersService.swift:104-119`) is a static, parameterless factory that only branches on `#available`; it has no path to consult `prefs` (which it already receives in `init` but currently only forwards to the results-service factory). Closing this gap requires: (1) a new `TranscriptionEngine` conformer for the alternative pipeline, (2) a new `PrefsKeys.QuickAnswers` flag following the `optInCompleted` convention (`Prefs.swift:136-138`), (3) making `makeDefaultEngine` (or its call site at line 37) consult that flag before falling back to the existing `#available` branch.

## Confidence Level
**HIGH.** Full evidence chain traced from app-layer coordinator down to the engine factory, confirming: (a) no shared/global state exists today, (b) `prefs` is already available at the exact point engine selection happens, (c) `MockProfilePrefs.boolForKey` returns `nil` for unset keys and every existing call site uses `?? false`-style defaulting (confirmed in `Store.swift:18`), so a new flag defaulting to "off" cannot alter any existing test or runtime behavior, and (d) no CODEMANIFEST governs any touched file, confirmed via `goga schema`.

## Breaking Change Assessment
1. **Will existing function call with same arguments produce different behavior?** NO — `DefaultQuickAnswersService.init(engine:configFetcher:resultsServiceFactory:prefs:)` keeps its exact signature; when the new pref key is unset (the default, and the only state any existing caller/test exercises), `makeDefaultEngine` still resolves via `#available` exactly as today.
2. **Will existing file paths change?** NO — only new files added; no renames.
3. **Will output format change?** NO — `SpeechResult`/`SearchResult` unchanged.
4. **Will return value semantics change?** NO — `record()`/`stopRecording()`/`search(text:)` semantics unchanged.
5. **Will manifest-defined guarantees be altered?** N/A — no manifest governs these files.
6. **Will existing tests break?** NO — `DefaultQuickAnswersServiceTests` injects `engine:` explicitly, bypassing the factory entirely; `SFSpeechRecognizerEngineTests`/`SpeechAnalyzerEngineTests` test those concrete types directly and are unaffected by a new sibling type; `MockProfilePrefs` defaults the new key to `nil` → `false` via the `?? false` pattern, matching current behavior.

**No breaking change detected.** Proceeding to Planning.
