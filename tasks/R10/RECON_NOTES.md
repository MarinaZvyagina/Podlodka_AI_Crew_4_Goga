# R10 Recon Notes — signalapp/Signal-iOS @ 6e3a059f752785b349d5938dfa4c36f216fb0ae3

All exploration was done via the GitHub API (`gh api repos/signalapp/Signal-iOS/...`), never a local clone, per the
disk constraint. Raw tree fetched with:

```
gh api "repos/signalapp/Signal-iOS/git/trees/6e3a059f752785b349d5938dfa4c36f216fb0ae3?recursive=1" > /tmp/signal_tree_raw.json
```

`truncated: false`, `sha` matches the pinned commit, 5614 entries. (One intermediate `gh api ... --jq '...' > file`
redirect produced a corrupted local file that briefly appeared to contain Android/Kotlin paths — re-verified against
the raw JSON directly and confirmed this was a local shell/file artifact, not a real repository property; all
findings below are re-verified against the clean re-fetch.) Individual files were read with:

```
curl -s https://raw.githubusercontent.com/signalapp/Signal-iOS/6e3a059f752785b349d5938dfa4c36f216fb0ae3/<path>
```

and cross-checked with `gh api "search/code?q=...+repo:signalapp/Signal-iOS"` to confirm symbol locations.

## Module layout confirmed

Top-level Swift modules at this commit: `Signal` (app target, `Signal/src/...`, `Signal/ConversationView/...`),
`SignalServiceKit` (business logic + persistence), `SignalUI` (shared presentation layer), `SignalNSE` (notification
service extension), `SignalShareExtension`. Confirmed one-directional layering: no file under `SignalServiceKit/`
imports `SignalUI`; `SignalUI` and `Signal` import `SignalServiceKit`. `SignalServiceKit` is also linked into the
share/notification-service extensions, which is the concrete reason it must stay UI-agnostic (used as a forbidden-
dependency justification in Tasks B/D).

## The verified extension point: JobRunner / JobRunnerFactory / JobQueueRunner (for Task C)

File: `SignalServiceKit/Jobs/JobQueueRunner.swift`. Key evidence (doc comment on the `JobRunner` protocol, lines
86-104):

> "A `JobRunner` is responsible for running a `JobRecord`... When should you use this type as opposed to
> `TaskQueueLoader` and `TaskRecord`? The JobRunner classes use a single db table across all jobs, and thus provide
> more in-built functionality around scheduling, starting, retrying, and failing jobs..."

This is a self-documented, intentional extension point, not something inferred. Protocols:

```swift
public protocol JobRunner<JobRecordType> {
    associatedtype JobRecordType: JobRecord
    associatedtype JobAttemptResultSuccessType
    func runJobAttempt(_ jobRecord: JobRecordType) async -> JobAttemptResult<JobAttemptResultSuccessType>
    func didFinishJob(_ jobRecordId: JobRecord.RowId, result: JobResult<JobAttemptResultSuccessType>) async
}

public protocol JobRunnerFactory<JobRunnerType> {
    associatedtype JobRunnerType: JobRunner, Sendable
    func buildRunner() -> JobRunnerType
}
```

`JobRecord` base class + `JobRecordType` enum: `SignalServiceKit/Jobs/JobRecords/JobRecord.swift`. Confirmed 8
existing concrete job types (`incomingContactSync`, `localUserLeaveGroup`, `messageSender`,
`donationReceiptCredentialRedemption`, `sendGiftBadge`, `sessionReset`, `callRecordDeleteAll`,
`bulkDeleteInteractionJobRecord`), each requiring a raw `UInt` value that is persisted to the DB and must stay stable
("These values are persisted and must not change, even if they're misspelled").

Closest concrete analog for Task C's "delete old messages, resumably" feature:
`SignalServiceKit/Jobs/BulkDeleteInteractionJobQueue.swift` +
`SignalServiceKit/Jobs/JobRecords/BulkDeleteInteractionJobRecord.swift`. This existing job already: (a) persists an
`anchorMessageRowId` cursor so it can resume, (b) batches deletion via `TimeGatedBatch.processAll` to avoid
long-running write transactions, (c) deletes through `interactionDeleteManager.delete(...)`, (d) is restarted at app
launch via `jobQueueRunner.start(shouldRestartExistingJobs: appContext.isMainApp)`. This is essentially a structural
template for the retention-cleanup feature in Task C — confirming the task has a genuine, reachable "correct"
solution using the framework, not just a plausible-sounding one.

Confirmed no existing "message retention" / "auto-delete old messages" feature exists yet (`grep -i
"retention|autoDelete|AutoExpire|MessageRetention"` over the full tree returned nothing), so Task C is a real gap, not
something that already has a canonical implementation the agent could just copy verbatim.

**Verification that Task C's prompt (`task_C.md`) does not leak the mechanism**: the text never says "job", "queue",
"JobRecord", "JobRunner", "persist a record", "retry", "background task framework", or any class name. It describes
only externally observable behavior (resumes after interruption, doesn't freeze UI, survives sign-out, updates
conversation state immediately) — the same functional shape that motivated the framework's own doc comment, but
phrased as a product requirement.

## Task A grounding: MediaBandwidthPreferences / AutoDownloadPolicy

File: `SignalServiceKit/Messages/Attachments/V2/Downloads/Preferences/MediaBandwidthPreferenceStore.swift` — a small,
self-contained enum (`MediaBandwidthPreferences.MediaType`: `.photo/.video/.audio/.document`, each
`CaseIterable`, each with a `defaultPreference`) backed by `MediaBandwidthPreferenceStore` (a `NewKeyValueStore`
wrapper). Consumers confirmed via `gh api search/code`:
`SignalServiceKit/Messages/Attachments/V2/Downloads/AutoDownloadPolicy.swift` (decision logic — `.body` case already
special-cases `renderingFlag == .voiceMessage` for a small-file "always allow" fast path, but falls through to the
generic `.audio` preference for anything above `Constants.alwaysLimit`, confirmed at lines 48-52) and
`Signal/src/ViewControllers/AppSettings/Data Usage/{DataSettingsTableViewController,MediaDownloadSettingsViewController}.swift`
(UI — confirmed the settings list is generated by iterating `MediaBandwidthPreferences.MediaType.allCases`, so a new
enum case automatically produces a new settings row, and the two `name(for...)` switches are exhaustive so the
compiler forces the agent to handle the new case). This gives Task A a bounded, single-feature footprint (one enum +
one policy file + two UI files, all part of one existing, coherent subsystem) appropriate for "Local Change", while
still being concrete enough to check precisely.

## Task B grounding: in-conversation search layering

Confirmed three real layers for search, each independently verified by reading the file:

1. `Signal/ConversationView/ConversationSearch.swift` (Signal app target) — `ConversationSearchController` owns the
   `UISearchController`/`SearchResultsBar`, calls `dbSearcher.searchWithinConversation(...)` on a background task,
   updates the results bar.
2. `SignalUI/Search/FullTextSearcher.swift` — `public class FullTextSearcher`, method
   `searchWithinConversation(threadUniqueId:isGroupThread:searchText:...)` (line 1002) — orchestrates calling
   `FullTextSearchIndexer.search` and, for group threads, layering mention-search (`SearchableNameFinder`,
   `MentionFinder`) on top. This is exactly the kind of "extend the orchestration layer" precedent Task B's correct
   solution should follow for an attachment filter.
3. `SignalServiceKit/Search/FullTextSearchIndexer.swift` — the actual GRDB FTS query layer.

Attachment-presence abstraction confirmed: `TSMessage.hasBodyAttachments(transaction:)` in
`SignalServiceKit/Messages/Interactions/TSMessage.swift` (line 19), which calls
`DependenciesBridge.shared.attachmentStore.fetchReferences(owners:...)` — i.e. there is already a canonical,
non-UI, non-filesystem way to ask "does this message have an attachment," which the correct Task B solution should
reuse instead of a hand-rolled SQL/filesystem check.

## Task D grounding: InteractionDeleteManager as the deletion boundary

File: `SignalServiceKit/Messages/Interactions/InteractionDeleteManager.swift`. Doc comment (lines 81-96):

> "Responsible for deleting `TSInteraction`s, and initiating `CallRecord` deletion... this manager also provides an
> entrypoint for callers to delete call records alongside their associated interactions."

`InteractionDelete.SideEffects` explicitly models the side effects a caller can opt into/out of:
`associatedCallDelete` (`.localDeleteAndSendCallEventSyncMessage` / `.localDeleteOnly`),
`updateThreadOnInteractionDelete`, `deleteForMeSyncMessage` (`.sendSyncMessage(interactionsThread:)` /
`.doNotSend` — **`.doNotSend` is the default** inside `SideEffects.custom(...)`, which is exactly the trap: a caller
who uses defaults or who bypasses the manager entirely gets no cross-device sync). `InteractionDeleteManagerImpl`'s
concrete dependencies (`callRecordStore`, `callRecordDeleteManager`, `deleteForMeOutgoingSyncMessageManager`,
`interactionReadCache`) confirm it is the single place that currently coordinates all of: call-record cleanup,
sync-message dispatch (via `DeleteForMeOutgoingSyncMessageManager`,
`SignalServiceKit/Messages/DeviceSyncing/DeleteForMe/DeleteForMeOutgoingSyncMessageManager.swift`, confirmed to
exist at that path), and read-cache invalidation. The raw low-level alternative,
`anyRemove(transaction:)`, is confirmed to be a real, callable, low-level persistence method (generated as part of
`SDSCodableModel`, confirmed via `SignalServiceKit/Storage/Database/SDSCodableModel/SDSCodableModel.swift`) — i.e. an
agent absolutely can call it directly and have code that compiles and "deletes the message" while skipping every one
of the above side effects. `BulkDeleteInteractionJobRunner` (seen while researching Task C) was used as a working
example of the *correct* pattern (`interactionDeleteManager.delete(interaction, sideEffects: .custom(...), tx: tx)`),
giving confidence the "correct" implementation path is realistic and not hypothetical.

## Confirmation: no task prompt names the mechanism

- `task_A.md`: describes only a settings feature and download behavior; no mention of `MediaBandwidthPreferences`,
  `AutoDownloadPolicy`, `enum`, `CaseIterable`, or any file/class name.
- `task_B.md`: describes only user-visible search-filtering behavior; no mention of `FullTextSearcher`,
  `FullTextSearchIndexer`, `AttachmentStore`, `TSMessage`, or any class/file name.
- `task_C.md`: describes only resumability/UI-responsiveness/interruption-safety requirements; no mention of "job",
  "queue", "JobRecord", "JobRunner", "retry", "persisted record", or any class/file name. This is the task where
  leakage would most directly compromise the benchmark (it's the "does the agent discover the existing extension
  point" test), and it was written and re-checked specifically for this.
- `task_D.md`: describes only user-visible deletion/sync/consistency behavior; no mention of
  `InteractionDeleteManager`, `SideEffects`, `DeleteForMeOutgoingSyncMessageManager`, `anyRemove`, or any class/file
  name.

## Why these four tasks are architecturally distinct from each other

- Task A touches one coherent subsystem (auto-download preferences) across ~3 files but does not require crossing a
  real architectural boundary in a risky way — it's "extend an existing enum and its two exhaustive consumers."
- Task B requires spanning three independently-owned layers (Signal app-target UI → SignalUI search orchestration →
  SignalServiceKit query/storage), verified as real files with real existing precedent for exactly this kind of
  layering (the mention-search feature already does UI → SignalUI → SignalServiceKit for a different filter).
- Task C targets a specific, self-documented, named-in-source extension mechanism (JobRunner/JobRunnerFactory) that
  the prompt never names, with a concrete structurally-similar existing job (BulkDeleteInteractionJobQueue) to serve
  as a positive-control template and a very plausible bolt-on trap (Timer/Task+UserDefaults cursor) to serve as a
  negative-control template.
- Task D targets a different boundary than Task C on purpose (manager-vs-raw-persistence, not job-framework-vs-bolt-
  on), so the two "trap-shaped" tasks (C and D) don't collapse into testing the same architectural judgment twice.
