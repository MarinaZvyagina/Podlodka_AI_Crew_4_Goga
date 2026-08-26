# PLAUSIBILITY_CHECK.md — R10 (signalapp/Signal-iOS)

## When this check was performed

`tasks/R10/task_A.md` through `task_D.md` were read for the first time **after** `SCOPE.md` was
written and frozen, and after all 10 CODEMANIFEST files were authored, materialized, linted
(1 correction round), schema-verified, and drift-checked via `goga contract` — per the
assignment's explicit ordering requirement. No content in the architecture forest was revised in
response to reading the tasks (see "Outcome" below).

## The four task prompts (quoted)

- **Task A**: add an independently configurable auto-download setting specifically for voice
  messages (on/never/Wi-Fi-only/Wi-Fi-and-cellular), separate from the existing per-type
  (photo/video/audio/document) auto-download controls, that persists across launches and
  actually changes download behavior for larger voice messages (the existing "small voice
  message downloads immediately regardless of network" fast path is preserved).
- **Task B**: add a filter/mode on top of existing in-conversation text search that narrows
  results to only messages with a photo/video/voice-message/file attachment, working in both
  1:1 and group chats, without requiring a full re-index and without showing a message before
  its attachment is actually associated with it.
- **Task C**: add a user-configurable message-retention window (e.g. "keep messages for 30
  days") that deletes older messages across all conversations, safely on large histories
  (non-blocking, resumable across app-close/backgrounding/network-drop, safe under sign-out
  mid-cleanup, immediately-correct conversation previews/unread counts after a pass, retroactive
  on first enablement).
- **Task D**: add a way to delete every message the local user personally sent within one
  conversation (not other participants' messages), propagated to the user's other linked
  devices, with immediate conversation-preview/unread/list updates and consistent call-history
  state for any deleted messages that correspond to a call.

## Term-level check: no task-specific vocabulary appears in the forest

Grepped all 10 CODEMANIFEST files for the task-specific terms each prompt turns on: none of
"voice message", "auto-download", "auto download", "cellular", "Wi-Fi"/"wifi", "retention
window", "30 day"/"30-day", "search filter", "filtered results", "my side", "delete my
message(s)" appear anywhere in the forest (checked case-insensitively). The forest never says
anything shaped like "add a per-type download toggle" or "delete only my own messages" — every
annotation describes what a real, already-existing class/method does today, in the codebase's
own vocabulary (e.g. `TSAccountManager`, `SDSDatabaseStorage`, `JobQueueRunner`,
`ThreadDeletionManager`, `InteractionDeleteManager`, `GroupManager`), consistent with
`TREATMENT_DESIGN.md` §4's required phrasing style.

One real (not invented) identifier from the actual Swift source does appear:
`sendDeleteForMeSyncMessage` — the genuine boolean parameter name on
`ThreadDeletionManager.deleteThreads`, confirmed present in the real
`SignalServiceKit/Threads/ThreadDeletionManager.swift` before any task was read. This is
Signal's own existing name for its "delete for me" linked-device-sync feature, not phrasing
introduced to hint at Task D — see the disclosure below.

## Where genuine overlap exists, and why it's expected rather than leakage

Two of the four tasks (C, D) touch functionality that lives near or inside cells this forest
documents — unavoidable and, per the treatment design, *intended*: a real architecture doc-set
should make a repository's existing extension points and coordination mechanisms discoverable
(RQ7/RQ9 specifically ask whether the Goga treatment changes existing-extension-point usage and
how the effect varies by task type). Providing accurate, task-agnostic documentation of a real
mechanism is not the same as hinting at the specific task built on top of it:

- **Task D ↔ `Messages/Interactions` (`InteractionDeleteManager`) and `Threads`
  (`ThreadDeletionManager`)**: this is the closest overlap, comparable to R01's disclosed
  Task C/`IProtection` case. The forest's `InteractionDeleteManager` annotation genuinely
  documents a "side-effect policy object" pattern — deletion cascades through optional
  associated-call-record cleanup, owning-thread update, and a linked-device sync notification —
  using only real, pre-existing names (`side_effect_policy_object`, `sendDeleteForMeSyncMessage`).
  It never mentions "delete only messages I sent," per-conversation scoping, or anything else
  specific to Task D's request. An agent still has to (a) realize Task D's "delete my messages
  in this conversation, sync to my other devices, keep call history consistent" maps onto this
  existing cascade rather than a naive per-row `DELETE`, and (b) figure out how to scope the
  deletion to "messages authored by the local user" — the forest documents the mechanism, not
  that mapping. Judgment call: kept as-is, since documenting this real coordination mechanism
  generically is precisely what the Goga condition is meant to test, not an accidental giveaway
  of the answer. Note also that the forest's scope deliberately omits `Calls/` and
  `Devices/DeviceSyncing` — the call-record and device-sync subsystems Task D also touches — so
  the forest gives, at most, a partial map of the mechanism, not a full solution outline.
- **Task C ↔ `Jobs`/`Jobs/JobRecords`**: weaker overlap than Task D's. The forest documents the
  durable background-job framework's real properties — resumable across app relaunch, automatic
  retry with exponential backoff, an extension point for new job types — which happen to match
  Task C's "must not block the UI, must resume after the app closes/backgrounds, mustn't restart
  from scratch" requirements almost point-for-point, because a large-scale, safely-resumable
  bulk-deletion feature in this codebase would plausibly be *built* as a durable job. However,
  the forest never mentions retention windows, time-based cutoffs, deleting old messages, or
  bulk cleanup of any kind — it describes the job-execution framework in fully generic terms
  (any job type: message sending, contact sync, etc.) that predates and is independent of Task
  C's specific feature. This is comparable to R01's weaker Task A/`Configuration` overlap: it
  tells an agent *that* a resumable-background-job mechanism exists at all (a real, load-bearing
  architecture fact), not *that this task should use it* or *how to scope the job to a time
  cutoff*.
- **Task A ↔ forest**: no overlap found. Voice-message auto-download logic lives in
  `SignalServiceKit/Attachments`/`Attachments/V2`, which is entirely outside this forest's scope
  (see `SCOPE.md`'s exclusion list); nothing in the ten documented cells mentions attachments,
  download settings, or network-condition gating.
- **Task B ↔ forest**: no meaningful overlap found. In-conversation search and its full-text
  index (`Search/`, `FullTextSearchIndexer`) are outside this forest's scope; the only place a
  related name surfaces is a passing mention of `FullTextSearchIndexer` as a cross-directory
  dependency *discovered during source reading* for the `SDSDatabaseStorage` cell's research
  pass, but that name was not carried into the actual materialized CODEMANIFEST content (verified
  by grep — see below), and even if it had been, it names a component outside the documented
  cell, not a hint about filtering search results by attachment type.

## Outcome

No revision was made to the architecture forest as a result of this check. The one genuine
close-overlap case (Task D / `InteractionDeleteManager` + `ThreadDeletionManager`) was judged to
be the expected, in-scope operation of documenting a real, load-bearing coordination mechanism —
not task-specific hint content — and is disclosed here explicitly rather than papered over, per
`TREATMENT_DESIGN.md` §4's "independent plausibility check" requirement. Consistent with R01's
precedent, no retroactive rewording (e.g. abstracting away the `side_effect_policy_object`
practice or the `sendDeleteForMeSyncMessage` parameter name) was performed after seeing the task
list, since doing so after the fact would itself be a worse violation of the freeze discipline
than leaving an honestly-disclosed, architecturally-justified overlap in place.
