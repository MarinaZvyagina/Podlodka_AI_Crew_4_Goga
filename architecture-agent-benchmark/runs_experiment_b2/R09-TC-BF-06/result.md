# R09-TC-BF-06

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.6
Dangerous success: False
Goga engagement signal: False
Cost: $3.0731941500000013
Duration: 378802ms, turns: 62

## Agent's own summary

# Investigation Report

## Task Summary
The ticket requests A/B-test wiring for voice search transcription: a Nimbus-controlled flag should let a portion of users get transcription from a new "alternative" pipeline while everyone else keeps today's default (OS-version-selected) pipeline, with zero visible behavior change to recording, streaming, error handling, or stop/cancel, and no shared mutable state between enrolled/non-enrolled users.

## Candidate Cells
| Cell | Reason | Priority |
|---|---|---|
| `BrowserKit/Sources/QuickAnswersKit/UI` | `QuickAnswersViewController()`'s documented public constructor gains a new `pipeline` parameter | High |
| `firefox-ios/Client/Coordinators` | Ungoverned file `QuickAnswersCoordinator.swift` reads new Nimbus variable, passes it into the documented constructor | Low (no manifest impact) |

## Tracing Summary
See Trace Report (prior step): `QuickAnswersCoordinator.start()` → `QuickAnswersViewController` public init (documented) → `QuickAnswersViewModel` → `DefaultQuickAnswersService.makeDefaultEngine()` → concrete `TranscriptionEngine`. Engine selection today depends only on `#available(iOS 26, *)`, with no external input. The `TranscriptionEngine` protocol fully abstracts engine identity from everything downstream, so introducing a third conformer requires no changes to `QuickAnswersViewModel`'s or `QuickAnswersViewController`'s state-handling logic — only to how the engine instance is *selected* at construction time.

## Data Flow Analysis
Nimbus feature value is resolved once per `QuickAnswersCoordinator.start()` call (i.e., once per presentation of the modal) and flows one-way, by constructor injection, down to `DefaultQuickAnswersService`. There is no shared/static/global engine-selection state anywhere in the current implementation — each presentation constructs its own `QuickAnswersViewModel` → `DefaultQuickAnswersService` → engine graph. This is the property that guarantees "no shared mutable state that would leak" between enrolled and non-enrolled sessions, and it must be preserved (i.e., the new pipeline value must also be resolved once per construction and passed by value, not read from a shared singleton at recognition time).

## Manifest Algorithm Analysis
`BrowserKit/Sources/QuickAnswersKit/UI/CODEMANIFEST` documents `QuickAnswersViewController()`'s constructor parameter list in prose (navigation handler, transition style, prefs, window UUID, theme manager, telemetry, config fetcher, learn-more URL) and gives no algorithmic description of engine selection — that logic lives entirely outside any documented cell (`Backend/SpeechService`, explicitly declared "out of scope" by this same manifest's header). Therefore the only manifest-governed change is a textual/contract update to the constructor's documented parameter list; the actual pipeline-selection algorithm is free-form implementation.

## Affected Usages
| Usage | Cell | Classification | Reason |
|---|---|---|---|
| (none exist) | `BrowserKit/Sources/QuickAnswersKit/UI/.usages/` | N/A | No `.usages` directory currently exists for this cell; nothing to reconcile beyond CODEMANIFEST text itself |

## Rejected Hypotheses
- **H1: Reuse the existing `model: QuickAnswersModel` Nimbus variable to also encode pipeline choice.** Rejected — `model` governs the results/search backend (Exa vs Liner), a semantically distinct concern from speech transcription; conflating them would make the flag not "simple" and would force unrelated experiments to co-vary.
- **H2: Make the alternative engine a real third-party API integration.** Rejected — ticket explicitly scopes this to "a reasonable stand-in/mock implementation for now."
- **H3: Store pipeline selection in a shared/static property (e.g., a singleton config) read lazily by the engine.** Rejected — violates the "no shared mutable state that would leak between [enrolled and non-enrolled users]" requirement and diverges from the existing per-construction injection pattern already used for `model`.

## Confirmed Root Cause
The current architecture has no injection point for transcription-engine choice — `DefaultQuickAnswersService.makeDefaultEngine()` is a private static function keyed solely on OS availability — so there is no way to steer engine selection from an external (Nimbus) flag without adding a new parameter threaded through `DefaultQuickAnswersService` → `QuickAnswersViewModel` → `QuickAnswersViewController`'s public constructor, mirroring the existing `configFetcher`/`model` injection pattern. This is an additive extension of an existing, already-proven injection pathway, not a redesign.

## Confidence Level
**HIGH** — full evidence chain read directly from source (constructor signatures, protocol definitions, CODEMANIFEST text, Nimbus FML precedent for `model`), no speculative inference required.

## Breaking Change Assessment
1. Will existing function call with same arguments produce different behavior? **NO** — new `pipeline` parameter will default to `.standard`, preserving current OS-version-based selection for all existing call sites that don't pass it.
2. Will existing file paths change? **NO** — only new files added; existing files modified in place, none moved/renamed.
3. Will output format change? **NO** — `SpeechResult`/`SearchResult` shapes and the `AsyncThrowingStream<SpeechResult, Error>` contract are unchanged.
4. Will return value semantics change? **NO** — `TranscriptionEngine.prepare/start/stop` contract unchanged; new conformer obeys the same contract.
5. Will manifest-defined guarantees be altered? **NO** — existing documented guarantees (navigation handler, transition style, prefs, window UUID, theme manager, telemetry, config fetcher, learn-more URL all still accepted and behave identically) remain true; the manifest text will be *extended*, not altered, to describe the additive parameter.
6. Will existing tests break? **NO** — expected, pending Step 6 confirmation; all changes are additive with defaulted parameters.

No YES answers → **not a breaking change**. Proceeding to Planning.
