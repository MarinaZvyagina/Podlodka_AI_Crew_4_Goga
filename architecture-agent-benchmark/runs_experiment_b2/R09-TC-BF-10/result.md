# R09-TC-BF-10

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.4
Dangerous success: False
Goga engagement signal: False
Cost: $2.7451964999999996
Duration: 371092ms, turns: 53

## Agent's own summary

# Investigation Report

## Task Summary
Requested: allow `QuickAnswersViewController` (the sole governed entry point of the `QuickAnswersKit/UI` cell) to be constructed with a caller-supplied transcription-engine variant, so the app layer can flip between the default speech-to-text pipeline and an experimental alternative via a Nimbus flag, without changing any other documented behavior of the view controller.

## Candidate Cells
| Cell | Reason | Priority |
|---|---|---|
| `BrowserKit/Sources/QuickAnswersKit/UI` | Owns the documented public constructor contract for `QuickAnswersViewController()` that gains the new parameter | High |

## Tracing Summary
- `QuickAnswersViewController.swift:71-91` — public `convenience init(navigationHandler:transitionType:prefs:windowUUID:themeManager:telemetry:configFetcher:learnMoreURL:notificationCenter:)` builds a `QuickAnswersViewModel` internally (`QuickAnswersViewModel(prefs:telemetry:configFetcher:)`) and forwards to the designated `init(navigationHandler:viewModel:transitionType:windowUUID:themeManager:learnMoreURL:notificationCenter:)` (`QuickAnswersViewController.swift:93-122`).
- The designated init stores `viewModel` as-is and never reconstructs it — it has no knowledge of engine selection at all.
- Only the convenience init needs the new parameter, since only it is responsible for building the `QuickAnswersViewModel`.

## Data Flow Analysis
`engineVariant` (new param, default `.standard`) → convenience init → forwarded into `QuickAnswersViewModel.init` (out-of-scope UI-internal type, not itself part of this cell's documented type list, but declared in this same file's package) → from there flows into `Backend/SpeechService`, which is explicitly out of scope for this cell's manifest. No other stored property or documented method of `QuickAnswersViewController` reads or is affected by this value.

## Manifest Algorithm Analysis
CODEMANIFEST's `QuickAnswersViewController()` entry says only: "Constructed with a navigation handler, a presentation transition style, user preferences, the presenting window's UUID, a theme manager, a telemetry sink, a config fetcher, and an optional 'learn more' URL." No algorithm, ordering guarantee, or invariant is documented beyond the parameter list itself — there's nothing else in the manifest this new defaulted parameter could conflict with.

## Affected Usages
| Usage | Cell | Classification | Reason |
|---|---|---|---|
| (none found) | — | — | Schema reports `"usages": []` for this cell; no `.goga/usages/*.md` files reference `QuickAnswersViewController` |

## Rejected Hypotheses
- *"The `notificationCenter` parameter's default-trailing position constrains where `engineVariant` can be inserted."* — Rejected: both existing call sites (`QuickAnswersCoordinator.swift:43`, and the internal-init test at `QuickAnswersViewControllerTests.swift:40`) use full keyword-argument labels and never omit a label positioned before another they do pass, so a new defaulted, labeled parameter is safely insertable at any position without breaking source compatibility, provided the caller simply doesn't mention its label (as neither current caller will).
- *"The internal designated init also needs the new parameter."* — Rejected: `QuickAnswersViewControllerTests.swift:40` calls the designated init directly with a hand-built `QuickAnswersViewModel`, bypassing engine selection entirely; the designated init has no engine-selection responsibility, so it's untouched.

## Confirmed Root Cause
Not a bug fix — this is an additive feature request. Root implementation point confirmed: `QuickAnswersViewController`'s public convenience init is the only governed-cell surface that must change, and it changes additively (one new defaulted parameter, forwarded one level down to `QuickAnswersViewModel`, which is outside this cell's own documented type list per its "leaf cell... internal ... backend is out of scope" description).

## Confidence Level
**HIGH** — direct grep (`grep -rn "QuickAnswersViewController("`) found exactly 2 call sites in the entire repo; both were read in full and confirmed compatible. Schema confirms zero dependencies and zero usages for this cell, eliminating any indirect blast radius. CODEMANIFEST content was read in full and contains no invariant beyond the parameter list itself.

## Breaking Change Assessment
1. Will existing function call with same arguments produce different behavior? **NO** — default `.standard` reproduces today's `if #available(iOS 26.0, *) { SpeechAnalyzerEngine } else { SFSpeechRecognizerEngine }` selection exactly.
2. Will existing file paths change? **NO**.
3. Will output format change? **NO**.
4. Will return value semantics change? **NO** — initializer, no return-value semantics beyond construction.
5. Will manifest-defined guarantees be altered? **NO** — the documented parameter list is extended, not altered or removed; existing guarantees remain intact.
6. Will existing tests break? **NO** — both call sites verified compatible (see Rejected Hypotheses).

No breaking change detected. Pipeline may proceed to Planning.
