# R08-TB-G-03

Condition: goga
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Cost: $3.4235862
Duration: 554548ms, turns: 63

## Agent's own summary

I've traced the full send pipeline enough to design a minimal, correct fix. Here's the investigation summary and proposed plan before I touch any code.

## What I found

The architecture already has almost everything needed:

- **`Media.transformProperties: TransformProperties?`** (`core/models/.../Media.kt`) already carries a per-item `skipTransform: Boolean` field. `TransformProperties.withSkipTransform()` already exists.
- **`AttachmentCompressionJob.onRun()`** (`app/.../jobs/AttachmentCompressionJob.java:145-171`) re-reads the attachment's `transformProperties` **fresh from the database** every time it runs, and returns immediately (no compression) if `shouldSkipTransform()` is true.
- **`AttachmentUploadJob`** likewise always re-reads the attachment row fresh at `onRun()`, rather than trusting stale enqueue-time data.
- Both jobs are persisted in a dedicated `JobDatabase` (survives process death), and attachment rows live in the normal `SignalDatabase` (also survives process death) — this is the same mechanism that already makes resumable uploads work today.
- `feature/media-send`'s `PreUploadController.startUpload(mediaItems, recipientId)` already supports **canceling and restarting a single item's** pre-upload (by URI) without touching the rest of the batch — this exact capability already exists and is unconditional (no "did anything change" check to fight).
- `MediaSendFlowViewModel.send()` builds `SendRequest.selectedMedia` directly from `state.value.selectedMedia`, and pre-upload triggers from that same list — so if `Media.transformProperties` on one item carries `skipTransform=true`, that's honored consistently on both the pre-upload path and the finalize path, no separate plumbing needed.

**Conclusion:** the DB schema, job design, and per-item data model already support exactly this feature — nothing in `app/` needs to change. This is achievable as a self-contained change to `feature/media-send`.

## Plan

1. **`MediaEditScreenEvents.kt` / `MediaSendFlowEvent.kt`**: add `SetFullQuality(media: Media, isFullQuality: Boolean)` to both, bubbled the same way `SetMediaQuality` already is.
2. **`MediaSendFlowViewModel.kt`**: add `setFullQuality(media, isFullQuality)` — finds the matching item in `state.selectedMedia`, sets `transformProperties.copy(skipTransform = isFullQuality)`, updates state, and if pre-upload is active, calls `preUploadController.startUpload(listOf(updatedMedia), recipientId)` to cancel+restart **only that item's** upload (guaranteeing effect even if upload already started).
3. **`MediaEditState.kt`**: expose the focused item's current full-quality flag (derived from `focusedMedia?.transformProperties?.skipTransform`) so the toolbar can show toggle state; wire through `withParentState`.
4. **`MediaEditViewModel.kt`**: handle the new event, bubble to parent.
5. **`MediaEditorToolbar.kt`**: add a toggle button in `MediaEditorToolbarSharedButtons` (same place the existing per-item mute/save/quality controls live) for "send in full quality," with a new string resource + icon.
6. **Edge case to handle**: `MediaEditState.isOnlyCameraFirstCapture` compares `selectedMedia.first() == cameraFirstCapture` by structural equality; toggling changes `transformProperties`, so `cameraFirstCapture` needs updating in lockstep if it's the toggled item, to avoid a false "not just the capture" state.
7. Add/update Kotlin tests for the new ViewModel method and state derivation (repo convention per `AGENTS.md`), plus reconcile `feature/media-send`'s `CODEMANIFEST` (`MediaSendFlowViewModel` method list, `MediaSendFlowState` annotation) afterward per the `goga-change` pipeline.

No changes to `app/database`, `app/jobmanager`, or job parameter serialization are needed — this rides entirely on their existing re-read-fresh-from-DB, persisted-job design.

Want me to proceed with implementation on this plan?
