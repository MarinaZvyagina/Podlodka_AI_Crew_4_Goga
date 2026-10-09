# SETUP_COST.md — R09 (mozilla-mobile/firefox-ios)

## initial_generation_time

Active tool-call work spanned roughly **90–100 minutes** on 2026-08-26 for the full pipeline:
reading `TREATMENT_DESIGN.md`/`PROTOCOL.md`'s Amendment 1, loading the `goga-cell`/
`goga-cookbook`/`goga-lang-disp`→`goga-cell-swift` DSL skills directly (the Skill tool did not
surface `goga-apply`/`goga-cell` in this session, confirming Amendment 1's fallback note), `goga
init` (non-interactive `swift` recipe), extensive direct source-reading across `BrowserKit/
Package.swift` and ~9 real Swift files/directories (`Common/DependencyInjection`, `Common/
Logger`, `Redux`, `TabDataStore`, `WebEngine`, `ToolbarKit`, `QuickAnswersKit/UI`, `Client/
Redux/GlobalState`, `Client/Coordinators`) to extract real public types/methods/properties,
authoring the ~700-line `docs/arch/architecture-overview.md` plan (9 cells) incrementally (one
`Write` for the skeleton, then one `Edit` per cell, per the R01-derived mitigation for large
single-`Write` transport failures — no transport failures occurred this time), manually
materializing the plan into 9 real `CODEMANIFEST` files (the Skill tool did not surface
`goga-apply` for this session either, so materialization followed `goga-apply`'s/
`goga-cells-by-brainstorm`'s `SKILL.md` procedure by hand, exactly as anticipated by Amendment 1),
3 rounds of `goga lint` correction, `goga schema` verification, and `goga contract` drift
spot-checks on 5 cells (3 required + 2 bonus) with 3 resulting corrections.

## manual_correction_time

Concentrated in three lint-correction passes plus one contract-correction pass, all within the
session above (not separately timed, but roughly a third of the total session): the first and
largest pass fixed a systematic authoring mistake (constructor parameters described only in
annotation prose with an empty-parens entity signature, rather than placed in the signature
itself, which made every prose-only parameter name an invalid backtick target) plus ~150 invalid
backtick cross-references; the second pass fixed a small residual set of self-referential/
cross-cell backtick targets; the third pass fixed one nested-arrow closure-type signature that
the parser mis-read as a missing return-type label. The contract-correction pass fixed two
invented placeholder type names that drifted from the real Swift generic names, and two more
entities that repeated the same empty-parens-with-real-params mistake in a different cell.

## number_of_manual_corrections

- **Lint correction rounds: 3** (`goga lint` was run 4 times total, from an empty forest to 0
  errors):
  1. Initial `goga lint` on the freshly materialized forest: **163 errors**, three rule types:
     `annotation_links_exists` (148), `import_is_used` (8), `import_type_exists` (2),
     `return_type_has_link` (5).
     **Root-cause finding (new, not seen in the R01/Python run):** the largest error category
     traced back to a single authoring mistake repeated across multiple cells — describing an
     `Entity`'s constructor parameters only in its `annotations:` prose (`` `param`: description
     ``) while leaving the type's own signature as empty parens (e.g. `"Store()"` instead of
     `"Store(state: State, reducer: Reducer, ...)"`.) Per the DSL spec, an Entity signature is
     supposed to capture "the input data required to construct the type" — parameters that never
     appear in the signature are not real signature parameters, so backtick references to them
     in prose (`` `state` ``, `` `reducer` ``, `` `logger` ``, etc.) are invalid link targets.
     Fixing this (moving constructor parameters into the actual signature parentheses) resolved
     the majority of `annotation_links_exists` errors in `Redux`, `BrowserURL`,
     `EngineSessionDependencies`/`EngineDependencies`, `TabDataStore`'s two concrete file-manager
     types, `ToolbarMenuElement`, `LoadingConfig`, and `AddressToolbarBorderConfiguration`.
  2. Remaining errors after the signature fix (**133 errors**) were invalid backtick
     cross-references with no single root cause: enum-case literals (`.debug`, `.homepage`),
     dotted method/property references (`Store.subscribe`, `AppState.reducer`), Swift keywords
     (`switch`, `nil`), generic type-parameter placeholders (`State`, `SubState`,
     `SubscriberStateType`), external/out-of-scope type names (`Router`, `Route`, `FileManager`,
     `WKWebView`, concrete-coordinator subclass names, `#filePath`/`#function`/`#line` compiler
     directives), and cross-property name mentions (a property's annotation backtick-referencing
     a *sibling* property's name, e.g. `` `a11yId` `` from within `cacheId`'s own annotation).
     All were converted to plain (non-backtick) prose, following the same rule confirmed in the
     R01 run: backticks are valid only for signature parameters of *that same* member, imported
     types, local entity/routine names, or Usages/Imports practice keys — never for sibling
     members, keywords, dotted expressions, or names outside the forest's scope. Also fixed:
     3 unused `Imports.Types` entries removed from cells that only ever mentioned the imported
     name in prose rather than a real signature/property (`DefaultLogger` in `Redux`/
     `TabDataStore`/`WebEngine`/`Coordinators` — the app-wide singleton is a *default value* hint
     in prose, not a formal contract element, so only the bare `Logger` protocol needed
     importing); 2 `import_type_exists` errors from `GlobalState`'s import list naming
     `ReducerMethod`/`LegacyReducerMethod`, which were never actually declared as their own
     entities in `Redux` (only a single `Reducer` routine was declared) — removed from the
     import list. Re-lint: **7 errors** remained (5 stray `` `Redux` ``/`` `AppComponent` ``
     backticks in `GlobalState`, 1 nested-arrow signature issue below).
  3. **Nested-arrow signature parsing bug** (a second, more specific instance of the pattern
     already flagged in the R01 run's Amendment for a different reason): a method or entity
     signature containing a closure-typed parameter written with an inline `->` (e.g.
     `transform: ((Subscription<State>) -> Subscription<SubState>)?`) causes the linter's
     "does the signature have a semantic return-type label" check to key off the *last* `->` in
     the whole signature string, misidentifying the closure's own return type as the method's
     missing return label. Fixed in `Redux`'s `subscribe(subscriber:transform:)` and
     `ToolbarMenuElement`'s entity signature by describing the closure parameter's type with a
     plain, non-arrow placeholder name (`SubstateTransform`, `SelectionHandler`) in the
     signature, with the real closure shape described in prose instead. Re-lint: **0 errors**.
- **Contract-drift corrections: 3** (found via `goga contract`, see below): `StoreSubscriber.
  newState`'s parameter type (`SubscriberState` → `SubscriberStateType`, matching the real
  associated-type name) and `Subscription.observer`'s property type (a placeholder
  `SubscriptionObserver?` → the real `((State?, State) -> Void)?` closure type, once it was
  confirmed that — unlike method/entity signatures — `PropertyNode` type strings containing an
  inline `->` do **not** trigger the nested-arrow parsing bug, so the real closure shape could be
  restored safely) in `Redux`; `DefaultTabFileManager`'s and `DefaultTabSessionStore`'s
  signatures in `TabDataStore`, which had the same empty-parens-despite-real-params mistake as
  the first lint-correction pass but were introduced fresh during that pass's rewrite and so
  were missed until the contract check surfaced them (both were fixed to include their real
  `fileManager`/`logger` init parameters). All three re-verified clean against `goga contract`
  after correction.

## artifact_size

- **9 CODEMANIFEST files** (one per documented cell)
- **1,083 total lines** (`wc -l` across all 9 files in the deliverable directory)
- Cell sizes range from roughly 45 lines (`Common/DependencyInjection`) to roughly 200 lines
  (`Redux`, the largest and most central cell)
- No `.usages/` files were created — every practice used the DSL's **inline** `Usages` form
  (per `goga-cookbook`'s guidance: inline is appropriate when a practice is short and specific to
  one cell), consistent with the R01 run's choice for the same reason.

## contract_drift_findings

`goga contract --lang swift` was run against **5 cells** (3 required by the task instructions,
plus 2 bonus checks that surfaced additional findings): `BrowserKit/Sources/Redux`,
`BrowserKit/Sources/Common/Logger`, `BrowserKit/Sources/TabDataStore`, plus bonus checks on
`firefox-ios/Client/Coordinators` and `BrowserKit/Sources/WebEngine`.

- **`Redux`** — found and fixed 2 genuine placeholder-vs-real-name drifts (listed above). After
  correction: near-perfect match on every method/property/signature across `Action`,
  `ModernAction`, `DispatchStore`, `DefaultDispatchStore`, `Store`, `StoreSubscriber`,
  `Subscription`, `StateType`; only cosmetic, expected drift remains (`Reducer`/`[Middleware]`
  shown without their `<State>` generic parameter, `any StoreSubscriber` shown as bare
  `StoreSubscriber`, external parameter labels like `_ subscriber` collapsed to `subscriber` —
  the same category of intentional public-contract-only simplification documented in the R01
  run for internal type aliases).
- **`Common/Logger`** — all `Logger`/`DefaultLogger` methods matched exactly. Two null results
  are tool-side extraction gaps, not content errors: `DefaultLogger.shared`'s implementation
  type shows empty (its real declaration, `public static let shared = DefaultLogger()`, has no
  explicit type annotation for the extractor to read), and `Logger.crashedLastLaunch`'s
  implementation shows `null` (the extractor does not associate a Swift `protocol`'s `var { get
  }` requirement with an implementation — consistent with `goga-cell-swift`'s own advice to map
  Swift protocols to methods only, which turns out to describe a real limitation of the
  contract-extraction tool itself, not just a stylistic recommendation for authors).
- **`TabDataStore`** — found and fixed 2 genuine errors (listed above, `DefaultTabFileManager`/
  `DefaultTabSessionStore` signatures). After correction, re-verified clean. All method
  signatures across `TabFileManager`/`TabDataStore`/`TabSessionStore` matched exactly (modulo
  the DSL's semantic-label convention, e.g. `-> Bool` documented as `-> exists:Bool`). `TabData`/
  `WindowData`'s signatures show `null` implementations — another tool-side gap: the extractor
  does not appear to associate a plain Swift `struct`'s custom, multi-line `public init` with the
  struct's own name reliably; the CODEMANIFEST content itself was authored directly from reading
  the real `init` in source, so this is not believed to be a genuine content error.
- **`Coordinators`** (bonus) — surfaced a structural finding, not a content error: because
  `Client` is a single app target with **no `public` declarations anywhere** (see `SCOPE.md`),
  and the `goga contract` Swift extractor enforces the "only `public` constitutes the Facade"
  rule programmatically, every `Client`-side declaration's `implementation` field comes back
  `null` or empty (e.g. `BaseCoordinator`'s real 3-parameter `internal init` is reported as `()`
  because that `init` isn't `public`) even though the CODEMANIFEST content is a faithful
  transcription of the real (internal-access) Swift source. This is disclosed here and in
  `SCOPE.md` as a known consequence of applying a SwiftPM-library-oriented convention to a
  monolithic app target, not a drift in the documentation's actual accuracy.
- **`WebEngine`** (bonus) — all protocol methods (`Engine`, partial view of `EngineSession`)
  matched exactly where implementations were extractable; struct signatures (`BrowserURL`,
  `EngineDependencies`) show the same `null`-for-struct-init tool-side gap noted above for
  `TabDataStore`.

No drift was found that would materially mislead an agent about a cell's real public shape
after the corrections above; the remaining `null`/empty results are tool-extraction limitations
(struct inits, protocol property requirements, and — specific to this Swift-app-target
repository — internal-access declarations in the `Client` target) rather than content errors,
and are disclosed rather than papered over.

## maintenance_steps

N/A — one-time freeze, not yet exercised. Per `PROTOCOL.md` §6, this CODEMANIFEST forest is
frozen as-is for the duration of `benchmark-v1` and is not regenerated if firefox-ios or Goga
change mid-benchmark.
