# R10 (signalapp/Signal-iOS @ 6e3a059f752785b349d5938dfa4c36f216fb0ae3) — Phase 4/5 Control Results

This document records the runnable validators (Phase 4) and positive/negative control results (Phase 5) for
tasks A–D. All work was done against a local clone at `/tmp/benchmark-repos/R10`, pinned to the specified commit
(`git log -1` confirms `6e3a059 Update translations`, `HEAD detached at 6e3a059`).

## Build/toolchain verification — what actually happened

- `git clone --depth 1` + `git fetch --depth 1 origin <sha>` + `git checkout <sha>` succeeded; working tree
  confirmed clean and at the pinned commit throughout.
- `pod install` succeeded (CocoaPods 1.17.0; 17 pods installed, including prebuilt `LibSignalClient` and
  `SignalRingRTC` binaries downloaded from their public GitHub release artifacts — no paid credentials needed).
- `xcodebuild -workspace Signal.xcworkspace -list` succeeded and confirmed a standalone `SignalServiceKit` scheme
  exists, separate from the full `Signal` app scheme — this was used as the smaller, independently buildable
  target per the task's fallback guidance, instead of the full app (which additionally needs code-signing).
- **A real build was attempted** (`xcodebuild -workspace Signal.xcworkspace -scheme SignalServiceKit -destination
  'platform=iOS Simulator,name=iPhone 17' build`) with Task A's positive-control diff applied. The build
  progressed deep into compiling the `SignalServiceKit` target itself — hundreds of first-party `.swift` files
  compiled successfully, including files adjacent to and depending on the changed files (e.g.
  `SignalServiceKit/Messages/DeviceSyncing/DeleteForMe/*.swift`) — before failing at the `Ld` (link) step for the
  **third-party `LibSignalClient` Pod** with `LLVM ERROR: IO failure on output stream: No space left on device`.
  This is a disk-space/environment failure in a vendored dependency, not a compile error in any code we wrote.
  Free disk space in this environment is small and shared across the whole APFS container (started at ~26GB free
  after cloning, dropped under ~14GB after a single build attempt's module caches/intermediates); a second retry
  after cleaning `DerivedData` reproduced the same disk-exhaustion linker failure. Continuing to retry full builds
  for all 8 controls (4 tasks × positive/negative) was not feasible in this environment without a materially
  larger disk allocation, consistent with the task's own stated expectation that a full build "may fail... or
  take a very long time... that's an acceptable, expected limitation."
- One incidental **real finding** came out of the build attempt: Task A's positive control (adding a 5th case to
  `MediaBandwidthPreferences.MediaType`) does not compile as originally written, because
  `SignalServiceKit/Backups/Archiving/Archivers/AccountData/BackupArchiveAccountDataArchiver.swift` has two
  additional exhaustive `switch type { case .photo: ... }` statements (backup-export and backup-restore of the
  auto-download preferences) that are *not* mentioned anywhere in `metadata_A.yaml`'s `architecture_checks`. The
  positive control diff includes a minimal, correct fix (an added `case .voiceMessage: break`, since the backup
  proto has no field for the new preference yet) — this is exactly the kind of "Swift will fail to build
  otherwise, which is itself a useful functional signal" the task's own `functional_check_command` predicts, and
  it was caught by an actual build attempt, not by inspection alone.
- **Given the disk constraint, full builds were not re-run for every one of the remaining 7 controls.**
  Functional verification for tasks B, C, and D (and the re-verification of Task A's later controls) is
  **manual/code-level review** — reading the actual call signatures, access modifiers, and module boundaries in
  the real source files before writing each diff (e.g. confirming `TSMessage.hasBodyAttachments` is `public`,
  confirming `InteractionDeleteManager.delete(interactions:sideEffects:tx:)`'s exact signature, confirming
  `JobRecordColumns`/`GRDBSchemaMigrator` migration-registration mechanics) — exactly as the task's fallback
  option describes. No claim of "it compiles" is made for B/C/D; every diff is honestly a best-effort,
  precedent-matched implementation that was **not compiled**.
- All 17 validator scripts are static/`git diff`-based (grep-driven pattern checks against the working tree,
  arg `$1` defaulting to `.`) and were exercised directly — that part of Phase 4/5 verification *is* fully
  "executed," not just reviewed.

## Validators (Phase 4)

17 scripts total, one per `architecture_checks` entry across the 4 metadata files:
`validators/task_A_AC{1..4}.sh`, `validators/task_B_AC{1..4}.sh`, `validators/task_C_AC{1..5}.sh`,
`validators/task_D_AC{1..4}.sh`. Each takes a repo path as `$1` (default `.`), operates on `git diff` (including
untracked new files, via a `safe_diff`/`safe_new_files` helper that reads `git ls-files --others` instead of
mutating the index — an early version used `git add -N` for this and it silently truncated a new file's content
on the subsequent `git checkout --`, which was caught and fixed), prints `PASS`/`FAIL` plus a reason, and exits
0/1. Two checks (`task_A_AC3`, `task_D_AC3`) are partly judgment calls per their own `method` text; those scripts
automate what's greppable and explicitly print `MANUAL REVIEW REQUIRED`/`PARTIAL PASS (automated signal only)`
for the remainder rather than fabricating a verdict.

## Task A — Voice-message auto-download preference (local_change)

**Positive control** (`controls/task_A_positive.diff`): adds `case voiceMessage` to
`MediaBandwidthPreferences.MediaType` (+ `defaultPreference`), adds a `renderingFlag == .voiceMessage` branch in
`AutoDownloadPolicy.build`'s `.body`/audio handling that preserves the small-file always-download fast path and
falls through to `.audio` for non-voice audio, extends `MediaDownloadSettingsViewController.name(forMediaDownloadType:)`'s
switch by one case, and (the build-discovered fix) extends the two exhaustive `MediaType` switches in
`BackupArchiveAccountDataArchiver.swift`. `DataSettingsTableViewController.swift`'s `allCases` loop is
deliberately left untouched.

**Negative control** (`controls/task_A_negative.diff`): adds a new, bespoke
`VoiceMessageAutoDownloadSettingsViewController.swift` backed by a hand-rolled `UserDefaults`-keyed
`VoiceMessageAutoDownloadPreference` enum, wired into `DataSettingsTableViewController.swift` via a manually
appended `OWSTableItem` outside the `allCases` loop. `AutoDownloadPolicy.swift` is never touched, so the toggle
is cosmetically real (persists, shows a checkmark) but never affects actual download behavior.

| Check | Positive | Negative |
|---|---|---|
| Functional (manual/build review) | PASS — new case + branch present; build attempt compiled the surrounding SignalServiceKit files (link step failed on disk, unrelated) | PASS (shallow) — setting exists, is togglable, persists — passes a shallow "setting exists" check |
| AC1 (reuse MediaType/store) | PASS | **FAIL** — new UserDefaults-backed enum |
| AC2 (logic lives in AutoDownloadPolicy) | PASS | **FAIL** — AutoDownloadPolicy.swift untouched |
| AC3 (non-voice audio unaffected) | PASS (automated signal; flagged MANUAL REVIEW) | PASS (trivially — nothing changed there) |
| AC4 (reuse settings-screen pattern) | PASS | **FAIL** — new bespoke VC + manual row |

**Verdict: DISCRIMINATES.** Positive passes all 4; negative fails 3/4 (AC1, AC2, AC4) while still passing the
shallow functional bar and AC3. Re-applying both diffs to a fresh checkout and re-running all 4 validators
reproduced identical results.

## Task B — Attachment-only filter for in-conversation search (cross_module_feature)

**Positive control** (`controls/task_B_positive.diff`): adds an `attachmentsOnly: Bool = false` parameter to
`FullTextSearcher.searchWithinConversation`; when true, `appendMessage` skips messages for which
`message.hasBodyAttachments(transaction:)` is false (checked for both the FTS-matched and mention-matched
candidates, so it composes with existing group-mention search). `ConversationSearchController` gains a public
`isAttachmentsOnlyFilterEnabled` property that re-triggers `updateSearchResults(for:)` and threads the flag
through `performSearch` into `dbSearcher.searchWithinConversation`.

**Negative control** (`controls/task_B_negative.diff`): only touches `ConversationSearch.swift`. Adds the same
`isAttachmentsOnlyFilterEnabled` property, but the actual filtering happens inside `performSearch` itself: after
getting the normal (unfiltered) result set from `dbSearcher`, it runs a hand-written raw SQL query
(`Row.fetchAll(tx.database, sql: "SELECT DISTINCT messageRowId FROM MessageAttachmentReference WHERE ...")`)
against the attachment-reference table directly, bypassing both `FullTextSearcher` and the `AttachmentStore`/
`hasBodyAttachments` abstraction.

| Check | Positive | Negative |
|---|---|---|
| Functional (manual review) | PASS — new param threads through cleanly; reuses existing result-bar/result-set plumbing | PASS (shallow) — results are filtered correctly for a same-device test |
| AC1 (no new SignalServiceKit→SignalUI import) | PASS | PASS (trivially — no SignalServiceKit files touched) |
| AC2 (uses AttachmentStore abstraction) | PASS | **FAIL** — raw SQL against the attachment table |
| AC3 (orchestration lives in FullTextSearcher) | PASS | **FAIL** — FullTextSearcher.swift never touched; filtering duplicated in the UI-layer controller |
| AC4 (no new index/table) | PASS | PASS (reuses existing table, just via raw SQL instead of the abstraction) |

**Verdict: DISCRIMINATES.** Positive passes all 4; negative fails 2/4 (AC2, AC3 — the two checks this task is
specifically designed to test) while passing the shallow functional bar, AC1, and AC4. Reproduced on re-apply.

## Task C — Message retention cleanup via the job framework (existing_extension_point)

**Positive control** (`controls/task_C_positive.diff`, 449 lines — the largest of the four): adds
`MessageRetentionCleanupJobRecord: JobRecord` (new `JobRecordType` case `102`, persists a single
`cutoffReceivedAtTimestamp` field), `MessageRetentionCleanupJobRunner: JobRunner` /
`MessageRetentionCleanupJobRunnerFactory: JobRunnerFactory` wired into a `JobQueueRunner` inside a new
`MessageRetentionCleanupJobQueue` (all modeled directly on `BulkDeleteInteractionJobQueue`), batches deletion via
`TimeGatedBatch.processAll`, deletes via `interactionDeleteManager.delete(interactions:sideEffects:tx:)`, and is
started via `sskEnvironment.messageRetentionCleanupJobQueueRef.start(appContext:)` alongside the other job queues
at app-launch readiness (`AppSetup.swift`). Also adds a small standalone `MessageRetentionPreferenceStore`
(on/off + window-in-days) and a real GRDB schema migration
(`GRDBSchemaMigrator.swift`: new `MigrationId` case + `ALTER TABLE model_SSKJobRecord ADD COLUMN
MRCJR_cutoffReceivedAtTimestamp`) plus the corresponding `JobRecordColumns` entry — this migration/DI wiring goes
beyond what any architecture check requires, but is needed for the code to be structurally real rather than a
stub. **Not implemented**: an actual Settings UI picker screen for the retention window (out of scope of every
`architecture_check`, which test the job-framework pattern only; noted here for honesty).

**Negative control** (`controls/task_C_negative.diff`, single new file `MessageRetentionManager.swift`): a
singleton observing `AppContext.OWSApplicationDidBecomeActive`, storing `retentionWindowDays` and a
`lastCleanupCompletedThroughDate` row-ID cursor in a plain `KeyValueStore`, running a `while` loop of
`databaseStorageRef.awaitableWrite` batches that fetch via raw SQL and call `interaction.anyRemove(transaction:)`
directly — never touching `JobRecord`/`JobRunner`/`JobRunnerFactory`/`JobQueueRunner`/`TimeGatedBatch`/
`InteractionDeleteManager` anywhere.

| Check | Positive | Negative |
|---|---|---|
| Functional (manual review) | PASS — new record/runner/factory/queue present, started at launch, migration added; **not compiled** (disk-constrained) | PASS (shallow) — messages do get deleted, and it "resumes" via its own UserDefaults-style cursor |
| AC1 (new JobRecord + JobRecordType case) | PASS | **FAIL** — no JobRecord subclass anywhere |
| AC2 (JobRunner + JobRunnerFactory pair) | PASS | **FAIL** — no changes under `Jobs/` at all |
| AC3 (not a bolt-on Timer/lifecycle scheduler) | PASS | **FAIL** — exactly the `applicationDidBecomeActive` + UserDefaults-cursor bolt-on pattern this check targets |
| AC4 (TimeGatedBatch batching) | PASS | **FAIL** — no changes under `Jobs/` |
| AC5 (deletion via InteractionDeleteManager) | PASS | **FAIL** — no changes under `Jobs/` (also directly calls `anyRemove`) |

**Verdict: DISCRIMINATES, strongly.** Positive passes all 5; negative fails all 5, while still being a plausible
"looks like it works" implementation a shallow functional test wouldn't catch (this is the task the recon notes
flagged as the one where "does the agent discover the existing extension point" matters most — the validators
draw the line cleanly). Reproduced on re-apply. Two validator bugs were found and fixed during first-run testing
against these exact diffs: (1) `task_C_AC1`'s "were the exhaustive switches extended" check originally grepped
literal substrings `concreteType`/`jobRecordLabel` in added lines, which don't recur on each `case` line — fixed
to count occurrences of the new case identifier itself (expect ≥3: enum + two switches); (2) `task_C_AC3`'s
Timer/lifecycle-hook grep matched a doc comment in the positive control that *named* the anti-pattern while
explaining why it wasn't used — fixed by excluding `+`-added comment-only lines before pattern matching; (3)
`task_C_AC5`'s `anyRemove` grep flagged the positive control's own (correct, template-matching)
`jobRecord.anyRemove(transaction:)` self-cleanup call — fixed to exclude `jobRecord.anyRemove` specifically,
since that deletes the job-bookkeeping row, not a `TSInteraction`. All three fixes were miscalibrated validators,
not miscalibrated tasks; corrected scripts are what's in `validators/`.

## Task D — Delete all messages sent by me in a conversation (architecture_trap)

**Positive control** (`controls/task_D_positive.diff`): new `DeleteAllMessagesSentByLocalUserManager` struct
(SignalServiceKit) holding an `InteractionDeleteManager` dependency; its one method enumerates the thread's
interactions via `InteractionFinder(threadUniqueId:).enumerateInteractionsForConversationView`, filters to
`TSOutgoingMessage`, and calls `interactionDeleteManager.delete(interactions:sideEffects:tx:)` with
`.custom(deleteForMeSyncMessage: .sendSyncMessage(interactionsThread: thread))` explicitly overriding the
otherwise-`.doNotSend` default.

**Negative control** (`controls/task_D_negative.diff`): same public shape/method name, same interaction-selection
logic, but the body is a `for interaction in interactionsAuthoredByLocalUser { interaction.anyRemove(transaction:
tx) }` loop — no `InteractionDeleteManager`, no sync message, no call-record/cache side effects.

| Check | Positive | Negative |
|---|---|---|
| Functional (manual review) | PASS — correct signature/call reused verbatim from `InteractionDeleteManager`'s real API; **not compiled** | PASS (same-device) — deletes the right messages locally |
| AC1 (routed through InteractionDeleteManager) | PASS | **FAIL** — direct `anyRemove` loop |
| AC2 (delete-for-me sync message requested) | PASS | **FAIL** — no sync message sent at all |
| AC3 (CallRecord consistency) | PASS | **FAIL** — anyRemove bypasses call-record cleanup |
| AC4 (immediate UI/cache consistency) | PASS | **FAIL** — anyRemove bypasses InteractionReadCache/thread-preview updates |

**Verdict: DISCRIMINATES.** Positive passes all 4; negative fails all 4, and — as the task's own notes predict —
is exactly the implementation that would pass a naive same-device functional test while silently breaking
multi-device sync and leaving orphaned `CallRecord`/stale-cache state, which is precisely what this
`architecture_trap`-category task is designed to surface. Reproduced on re-apply.

## Summary

| Task | Positive result | Negative result | Verdict |
|---|---|---|---|
| A | 4/4 architecture checks PASS | 3/4 FAIL (AC1, AC2, AC4) | DISCRIMINATES |
| B | 4/4 architecture checks PASS | 2/4 FAIL (AC2, AC3) | DISCRIMINATES |
| C | 5/5 architecture checks PASS | 5/5 FAIL | DISCRIMINATES |
| D | 4/4 architecture checks PASS | 4/4 FAIL | DISCRIMINATES |

All four tasks discriminate correctly between an architecturally-correct implementation and a plausible,
shallow-functionally-passing "easy but wrong" trap. No validator was fudged to force a result: three genuine
validator bugs (all in Task C's scripts, see above) were found by running them against real diffs and were fixed
based on what the *code* actually needed to say, not to force a particular PASS/FAIL outcome — in every case the
fix made the check match its own documented `method`/`expected_result_if_correct` text more faithfully.

Functional verification is **build-attempted-and-partially-confirmed** for Task A (real `xcodebuild` run against
the `SignalServiceKit` scheme, which compiled deep into the target before an unrelated third-party-Pod
disk-space linker failure) and **manual/code-level review only** for Tasks B, C, and D, due to this
environment's limited and shared disk space making repeated full-target builds impractical across 8 total
control variants. This is reported honestly per the task's own explicitly-anticipated fallback, and no diff's
functional correctness is overstated as "verified by build" when it was not.
