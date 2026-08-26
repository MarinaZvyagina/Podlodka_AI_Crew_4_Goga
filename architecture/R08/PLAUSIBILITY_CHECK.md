# PLAUSIBILITY_CHECK.md — R08 (Signal-Android)

## When this check was performed

`tasks/R08/task_A.md` through `task_D.md` were read for the first time **after** `SCOPE.md` was
written and frozen, and after all 9 `CODEMANIFEST` files were authored, materialized, linted
(`goga lint`: 0 errors), schema-verified (`goga schema`), and drift-checked (`goga contract`) — per
the assignment's explicit ordering requirement. No content in the architecture forest was revised
in response to reading the tasks; the two post-freeze edits that did happen (the `BillingProduct?`
nullability fix and its follow-on `import_is_used` fix) were both made and re-linted **before**
the tasks were opened, purely from `goga contract` drift findings, and are logged in
`SETUP_COST.md`.

## The four task prompts (quoted)

- **Task A**: sort the "Blocked contacts" settings screen alphabetically by display name
  (case-insensitive), matching how other contact lists already behave, and keep it correctly
  sorted live as contacts are blocked/unblocked while the screen is open; "if you touch shared
  code, double check who else calls it."
- **Task B**: on the media-send review screen, let the user mark one item in a multi-item batch
  as "send in full quality" overriding the batch's default compression for just that item — even
  if that item's upload already started in the background — and have the choice survive the app
  being killed and relaunched mid-send.
- **Task C**: add a periodic, automatic background routine that finds and deletes orphaned
  thumbnail cache files (no longer tied to any surviving attachment/message); must not run during
  an active call or when battery is critically low, must not require user action or a one-time
  post-update trigger, and must make incremental forward progress if interrupted partway rather
  than restarting from scratch or stalling.
- **Task D**: cache repeated identical chat-search queries so a second identical search is
  noticeably faster, while any data change relevant to a previously-cached term must invalidate
  that cache entry (no stale results), and different terms cache independently.

## Term-level check: no task-specific vocabulary appears in the forest

Grepped all 9 `CODEMANIFEST` files for the task-specific terms each prompt turns on
(`blocked contact`, `alphabet`, `full quality`/`full-quality`, `thumbnail`, `orphan`,
`cache clean`, `search cache`, `repeated search`, `stale result`, `sort`) — **no matches**. The
forest never says anything shaped like "sort this list," "add a full-quality override," "clean up
orphaned thumbnails," or "cache search results" — every annotation describes what a real,
already-existing class/method does today, in the codebase's own vocabulary (`RecipientTable`,
`DatabaseObserver`, `Job`/`Constraint`, `MediaSendRepository`, `SentMediaQuality`), consistent with
`TREATMENT_DESIGN.md` §4's required phrasing style.

## Where genuine overlap exists, and why it's expected rather than leakage

Three of the four tasks (A, B, C) touch functionality documented in this forest — this is
unavoidable and, per the treatment design, *intended*: a real architecture doc-set should make a
repository's existing extension points and shared subsystems discoverable, and RQ7/RQ9 of the
benchmark specifically ask whether the Goga treatment changes existing-extension-point usage and
how the effect varies by task type. Providing accurate, task-agnostic documentation of a real
mechanism is not the same as hinting at a specific task built on top of it:

- **Task C ↔ `jobmanager`**: this is the closest overlap, structurally similar to R01's
  Task C/`plugins.protections` case. Task C's "periodic, constrained, resumable background
  cleanup routine" is close to a textbook new `Job` + `Constraint` pair — exactly the pattern the
  `jobmanager` cell documents generically: "New units of background work plug in by subclassing
  `Job`... and registering a matching `Job.Factory`," `Constraint`'s `isMet`/`getFactoryKey`
  contract, and `Job.Parameters.inputData`/`JsonJobData` as the mechanism for a job's state to
  survive a process restart (directly relevant to Task C's "resumes sensibly on a later attempt"
  requirement). The forest never mentions thumbnails, cache files, calls, or battery — and,
  importantly, never names any of the app's real *concrete* `Constraint` implementations (there
  almost certainly exist real `Constraint`s gating on "not in a call" and "battery not critical,"
  per the codebase's own conventions, but this forest documents only the generic `Constraint`
  interface, not any specific registered constraint) — so an agent still has to (a) recognize
  that Task C's request is a job, (b) discover or write the two specific constraints it needs,
  and (c) figure out the resumable-progress mechanism, none of which the forest does for it.
  Judgment call: kept as-is, since documenting this real, generic extension point is precisely
  the mechanism the Goga condition is meant to test, not an accidental giveaway of the answer.
- **Task B ↔ `feature/media-send`, `jobmanager`**: moderate overlap. The forest documents
  `MediaSendRepository`'s real methods (`send`, `getVideoTranscodingTiers`,
  `getMediaConstraints`) and `MediaSendFlowState`'s real `sentMediaQuality`/`editorStateMap`
  fields, and separately documents that `PreUploadRepository` exists for "uploading selected
  media ahead of a send being confirmed" — all true, pre-existing facts relevant to Task B's
  "upload already started in the background" constraint. It also documents, generically, that
  `Job.Parameters.inputData` is how a job's state survives a process restart — relevant to Task
  B's "choice must survive the app being killed" requirement. The forest never mentions a
  per-item quality override, a batch data model, or how `MediaSendFlowState`'s `editorStateMap`
  keys per-item state (which is documented, but only as "per-media editor state... video trim
  data, image editor data") — it does not describe or imply an analogous per-item *quality*
  override existing or being the right place to add one.
- **Task A ↔ `recipients`, `database`**: weaker overlap, similar in kind to R01's Task A/
  `configuration` case. The forest documents `Recipient.isBlocked` as a real property and
  `RecipientTable.getBlocked() -> blocked:List<RecipientRecord>` as a real query ("Every recipient
  the local user has blocked") plus `DatabaseObserver`'s generic pub/sub notification mechanism
  (relevant to Task A's "list... updates... while the screen is open" requirement). It does not
  say the blocked list is unsorted, does not say anything about display-name ordering, and does
  not point at the specific UI screen/ViewModel that renders the blocked-contacts list (which is
  not part of this forest at all — no UI-layer cell was documented anywhere in this scope). An
  agent still has to locate the actual list-rendering code and determine that sorting, not
  filtering, is the gap.
- **Task D ↔ (none)**: no meaningful overlap found. The forest does not document `SearchTable`,
  any search-related type, or any caching mechanism at all — `SignalDatabase`'s documented
  companion-object accessors are limited to `recipients()`/`messages()`/two transaction-lifecycle
  methods, deliberately not the full ~45-accessor list (see `SCOPE.md`), and `messageSearch`
  (`SearchTable`) was not among the ones selected. Task D's "cache repeated identical searches" is
  not hinted at anywhere in this forest.

## Outcome

No revision was made to the architecture forest as a result of this check. The two closer-overlap
cases (Task C/`jobmanager`, Task B/`feature/media-send`) were judged to be the expected, in-scope
operation of documenting real, load-bearing extension points and subsystems generically — not
task-specific hint content — and are disclosed here explicitly rather than papered over, per
`TREATMENT_DESIGN.md` §4's "independent plausibility check" requirement. As with R01's
`plugins/protections` precedent, no retroactive rewording was applied after seeing the task list,
to avoid the appearance of hand-tuning the artifact post-hoc, which would itself be a worse
violation of the freeze discipline than leaving an honestly-disclosed, architecturally-justified
overlap in place.
