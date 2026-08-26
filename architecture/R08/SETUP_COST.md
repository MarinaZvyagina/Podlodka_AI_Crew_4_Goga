# SETUP_COST.md — R08 (signalapp/Signal-Android)

## initial_generation_time

Active tool-call work spanned the full pipeline: reading `TREATMENT_DESIGN.md`/`PROTOCOL.md`
(including Amendment 1), verifying the pinned repository state, running `goga init`
(language: kotlin), dispatching 8 parallel source-reading research agents over real
Signal-Android source, then — because this session's own direct file reads turned out to be more
reliable for exact signatures than trusting the background agents' summarized reports — re-reading
roughly 40 real source files directly (`Recipient.kt`, `RecipientId.kt`, `RecipientRepository.kt`,
`LiveRecipient.java`, `LiveRecipientCache.java`, `Job.java`, `JobManager.java`, `Constraint.java`,
`ConstraintObserver.java`, `Scheduler.java`, `JobTracker.java`, `CoroutineJob.kt`,
`JsonJobData.java`, `SignalServiceMessageSender.java`, `SignalServiceMessageReceiver.java`,
`SignalServiceAccountManager.java`, `SignalServiceDataStore.java`,
`SignalServiceAccountDataStore.java`, `SignalSessionLock.java`, the 7 `core/util/billing` files,
`RegistrationDependencies.kt`, `RegistrationFlowState.kt`, `RegistrationRepository.kt` (signature
grep), `RegistrationViewModel.kt` (signature grep), `MediaSendDependencies.kt`,
`MediaSendFlowState.kt`, `MediaSendRepository.kt` (signature grep), `MediaSendFlowViewModel.kt`
(signature grep), `BillingApiImpl.kt`, `BillingFactory.kt`, `SignalDatabase.kt`,
`DatabaseTable.java`, `DatabaseObserver.java` (signature grep), `RecipientTable.kt` (signature
grep), `AppDependencies.kt` in full), authoring the ~1,400-line `docs/arch/architecture-overview.md`
plan (9 cells, written incrementally: one `Write` for the skeleton, then one `Edit` per cell, per
Amendment 1's mitigation), materializing it to 9 real `CODEMANIFEST` files via `sed`-based
extraction from the frozen plan document (chosen over hand-retyping to eliminate transcription
risk on ~1,200 lines of DSL content), 1 round of `goga lint` correction, `goga schema` verification
of the full dependency graph, and `goga contract --lang kotlin` drift spot-checks on 3 cells with
1 follow-up correction.

## manual_correction_time

One concentrated pass, scripted rather than hand-edited line-by-line: a Python pass over all 9
materialized `CODEMANIFEST` files that stripped invalid backtick cross-references (see
`number_of_manual_corrections` below), followed by a second, much smaller pass fixing one
signature-nullability drift found by `goga contract` (and one follow-on `import_is_used` error
that fix introduced).

## number_of_manual_corrections

- **Lint correction rounds: 1** (`goga lint` was run 3 times total):
  1. Initial `goga lint` on the freshly materialized forest: **142 errors**, all
     `annotation_links_exists` — invalid backtick cross-references. Consistent with the R01
     finding: only signature parameters, `Imports`/`Usages` entries, and same-document
     Entity/Routine top-level type names may be backtick-referenced — sibling method/property
     names (even within the same entity), dotted expressions (`Job.Parameters.inputData`,
     `MediaSendRepository.send`), enum-member names (`OK`, `USER_CANCELED`, `PENDING`), path
     fragments (`core/util/billing`, `jobmanager`), and wildcards (`external*`, `register*`) are
     all invalid link targets. A Python script stripped backticks (converting to plain prose)
     from the ~100 distinct invalid strings identified in the lint output, across all 9 files.
     Re-lint: **0 errors** on the first re-run.
  2. A subsequent, unplanned second correction: fixing a `goga contract`-discovered nullability
     drift (see below) by changing `BillingProduct` to `BillingProduct?` in two cells introduced
     one new `import_is_used` error in `lib/billing` (the lint tool's usage-detection did not
     recognize the type name with a trailing `?` as satisfying the earlier bare-name usage that
     had passed). Fixed by adding one explicit backtick reference to `BillingProduct` in that
     method's prose annotation. Re-lint: **0 errors**.
- **Contract-drift corrections: 1** (found via `goga contract`, see below): `BillingApi.queryProduct`
  (and its `lib/billing` implementation `BillingApiImpl.queryProduct`) return `BillingProduct?`
  (nullable) in the real code, documented as non-nullable `BillingProduct` in the first draft;
  corrected in both cells.

## artifact_size

- **9 `CODEMANIFEST` files** (one per documented cell)
- **1,194 total lines** (`wc -l` across all 9 files in the deliverable directory)
- Cell sizes range from 66 lines (`lib/billing`) to 245 lines (`jobmanager`)
- **76 KB** total (`du -sh`)
- No `.usages/` files were created — all practice/convention text used the DSL's inline `Usages`/
  prose-in-`Annotations` form; nothing warranted a separate reusable practice file at either the
  project or cell level for this forest.

## contract_drift_findings

`goga contract --lang kotlin` was run against 3 cells (`app/.../recipients`,
`core/util/.../billing`, `lib/billing/.../billing`). `app/.../jobmanager`, `app/.../database`, and
`lib/libsignal-service/.../api` were **intentionally skipped** — all three are predominantly Java,
and per this task's language-scoping note `goga contract`'s Kotlin-mode implementation extractor
cannot resolve Java source; running it against them would either error or silently return
`implementation: null` for everything, which would not be a meaningful signal.

- **`core/util/.../billing`** — near-perfect match on every method/property of `BillingApi` and
  `BillingDependencies` (`getApiAvailability`, `getBillingPurchaseResults`, `launchBillingFlow`,
  `queryPurchases`, `getProductId`, `getBasePlanId`, `context` all matched exactly). One genuine,
  now-corrected drift: `queryProduct` returns `BillingProduct?` in the real interface, documented
  as non-nullable `BillingProduct`. `BillingResponseCode`'s enum found a constructor
  `(code: Int)` against a documented empty-parens signature — noted as an inherent, expected
  simplification (CODEMANIFEST's Entity-signature model does not have a clean way to express "each
  enum constant carries a different constructor argument"), not a real error. `BillingError`/
  `BillingProduct`/`BillingPurchaseResult`/`BillingPurchaseState` all reported
  `implementation: null` — verified by direct source re-read to be a tool-side limitation for
  plain data/sealed classes with no methods (not a real discrepancy).
- **`lib/billing/.../billing`** — `BillingFactory.create` matched exactly. Every `BillingApiImpl`
  member reported `implementation: null`: on inspection, `BillingApiImpl` is declared `internal
  class BillingApiImpl` in the real source. Per the connected `goga-cell-kotlin` skill's own facade
  rule ("Private and `internal` declarations are not part of the contract"), `goga contract`'s
  Kotlin extractor appears to deliberately exclude `internal` declarations from its
  "implementation" side. This is disclosed here as an honest finding rather than treated as
  drift: the CODEMANIFEST content is verified correct by direct source reading, but this
  particular tool check has no signal to offer for an intentionally-`internal` implementation
  class. (The class is documented anyway, because understanding the concrete swappable
  implementation behind `BillingApi` is architecturally useful — the DSL itself does not forbid
  documenting non-public types, only the language-specific facade convention discourages it.)
- **`app/.../recipients`** — `RecipientId` matched exactly on every method, property, and its
  primary-constructor signature (`(id: Long)`). `Recipient.getDisplayName`, `Recipient.live`, and
  three of six documented properties (`hasServiceId`, `isGroup`, `isRegistered`) matched exactly;
  the other three (`isBlocked`, `isSelf`, `isReleaseNotes`) reported `implementation: null` —
  verified by direct re-read of `Recipient.kt` to be real, correctly-typed primary-constructor
  properties (`val isBlocked: Boolean = false`, etc.) that the contract tool's Kotlin extractor
  simply does not resolve when they are constructor parameters rather than body-declared
  computed properties (it did resolve `isGroup`/`isRegistered`, which are declared as `val ...
  get() = ...` inside the class body) — a tool-side pattern-coverage gap, not a documentation
  error. `Recipient`'s own primary-constructor signature is documented as the simplified
  `(id: RecipientId)` against a real ~70-parameter constructor; this is an intentional,
  disclosed simplification for public-contract legibility (the same convention
  `architecture/R01/SETUP_COST.md` used for freqtrade's `Trade`/`Order` classes), not something
  corrected, since documenting all 70 constructor parameters would not make the cell more useful
  to an implementing agent. `LiveRecipient`/`LiveRecipientCache` (both Java) reported
  `implementation: null` throughout, consistent with `goga contract --lang kotlin` not resolving
  Java source — expected, not a finding.

No drift was found that would materially mislead an agent about a cell's real public shape after
the one correction above.

## maintenance_steps

N/A — one-time freeze, not yet exercised. Per `PROTOCOL.md` §6, this CODEMANIFEST forest is
frozen as-is for the duration of `benchmark-v1` and is not regenerated if Signal-Android or Goga
change mid-benchmark.
