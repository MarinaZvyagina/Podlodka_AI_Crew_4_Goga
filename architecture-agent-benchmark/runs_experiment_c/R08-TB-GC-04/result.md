# R08-TB-GC-04

Condition: goga_native_architecture
Base tag: condition-c-r08-v1
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: False
Cost: $5.3580873000000055
Duration: 655228ms, turns: 68

## Agent's own summary

# Change Plan

## Task Classification
**Feature (additive extension)** — per-item quality override layered onto the existing batch-wide media-send quality system. No existing behavior changes when the new toggle is untouched.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `feature/media-send` (root) | `MediaSendFlowEvent.kt`, `MediaSendFlowViewModel.kt`, `CODEMANIFEST` | New `MediaSendFlowEvent.SetFullQuality(media: Media, fullQuality: Boolean)` event; new `MediaSendFlowViewModel.setFullQuality(media, fullQuality)` method; new `onEvent` branch |
| `feature/media-send/.../screens/edit` | `MediaEditScreenEvents.kt`, `MediaEditViewModel.kt`, `ThumbnailRow.kt`, `CODEMANIFEST` | New `MediaEditScreenEvents.ToggleFullQuality(media: Media)` event; translator branch in `MediaEditViewModel.onEvent`; new per-item toggle affordance in `ThumbnailRow.kt` (mirrors `DeleteBox`'s per-item overlay pattern), reading `media.transformProperties?.skipTransform == true` for toggle state |
| `feature/media-send/.../preupload` | `CODEMANIFEST` only (doc-only, if anything) | No code change — `PreUploadController.cancelUpload(media)` reused as-is per its existing documented contract |

Ungoverned (plain code, no CODEMANIFEST): none required to change — `TransformProperties`, `AttachmentCompressionJob`, `AttachmentTable`, `MediaUploadRepository`, `MediaSendV3Repository`, `MediaSendV3PreUploadRepository` all already do the right thing once `Media.transformProperties.skipTransform` is `true`.

## Root Cause Analysis
No defect. The compression-bypass primitive (`TransformProperties.skipTransform`) and its DB-persisted, job-re-reads-fresh semantics already exist and already satisfy the ticket's hard requirements (per-item, survives kill, effective even mid-upload via cancel). The only gap is a UI/state entry point in the `feature/media-send` cells to set it on one item.

## Trace Summary
`Media.transformProperties` (set in `selectedMedia`) → read directly by both `MediaUploadRepository.asAttachment()` (pre-upload path) and `MediaSelectionRepository.buildModelsToTransform()`/`transformMediaSync` (final-send path) → persisted into the attachment row's `transform_properties` column at attachment-insert time → read fresh by `AttachmentCompressionJob.onRun()` on every execution (including after process-death restore) → `shouldSkipTransform()` short-circuits compression.

## Change Strategy
1. **`MediaSendFlowEvent.kt`**: add `data class SetFullQuality(val media: Media, val fullQuality: Boolean) : MediaSendFlowEvent`.
2. **`MediaSendFlowViewModel.kt`**: add `onEvent` branch `is MediaSendFlowEvent.SetFullQuality -> setFullQuality(event.media, event.fullQuality)`. Add method `setFullQuality(media: Media, fullQuality: Boolean)`, placed in the "Media Selection" region near `removeMedia`:
   - Locate the matching item in `state.value.selectedMedia` by `uri` (matching the existing `removeMedia`/`onVideoEdited` convention of matching by URI, not equality).
   - Build updated `TransformProperties` via `(existing.transformProperties ?: TransformProperties.empty()).copy(skipTransform = fullQuality)`.
   - Replace that one item in `selectedMedia` with the updated copy; leave every other item untouched.
   - Call `preUploadController.cancelUpload(updatedMedia)` for **only that item** (never `cancelAllUploads()`), so the rest of the batch's in-flight pre-uploads are unaffected — mirrors `onVideoEdited`'s cancel-and-fall-through-to-final-send precedent.
   - Do not touch `isPreUploadEnabled` or the batch `sentMediaQuality` field.
3. **`MediaEditScreenEvents.kt`**: add `data class ToggleFullQuality(val media: Media) : MediaEditScreenEvents`.
4. **`MediaEditViewModel.kt`**: add translator branch `is MediaEditScreenEvents.ToggleFullQuality -> parentEventEmitter(MediaSendFlowEvent.SetFullQuality(event.media, event.media.transformProperties?.skipTransform != true))` (toggle semantics: flips current state).
5. **`ThumbnailRow.kt`**: add a small per-item icon/badge affordance (full-quality indicator + tap target) alongside the existing per-item `DeleteBox` overlay, dispatching `MediaEditScreenEvents.ToggleFullQuality(media)` on tap, visually reflecting `media.transformProperties?.skipTransform == true`.

No new field is added to `MediaEditState`/`MediaSendFlowState` — the per-item flag lives directly on `Media.transformProperties` inside the existing `selectedMedia` list, which is already parcelable/`SavedStateHandle`-persisted, so pre-send process-death survival requires zero new persistence code.

## Specification Impact
- **`feature/media-send` root CODEMANIFEST**: `MediaSendFlowEvent()` entity gains a documented `SetFullQuality` case (if events are enumerated there) or `MediaSendFlowViewModel` gains a new documented method `setFullQuality(media: Media, fullQuality: Boolean)` with an annotation describing the per-item-not-batch semantics and the cancel-single-item behavior.
- **`screens/edit` CODEMANIFEST**: `MediaEditScreenEvents()` annotation block gains one sentence documenting `ToggleFullQuality(media)`, following the exact prose style of the existing `RemoveMedia`/`FocusedMediaChanged` entries. `ThumbnailRow`'s (or equivalent) type annotation gains a note about the new per-item affordance, mirroring how `DeleteBox` is currently described.
- **`preupload` CODEMANIFEST**: no change expected; `PreUploadController.cancelUpload(media)`'s existing annotation already covers this exact usage ("Cancels the pre-upload (if present) for `media`..."). Will leave untouched unless implementation reveals an undocumented edge case.

## Usage Impact
No `.usages` files exist for any of the three cells and no project-level `.goga/usages/` practices are configured — nothing to update.

## Compatibility Verification
**Backward compatible.** No existing method signature, event, file path, or manifest-documented guarantee changes. All additions are new event variants / new methods. Existing calls with existing arguments produce identical behavior. `PreUploadController.cancelUpload` is consumed within its already-documented contract, not modified.

## Test Strategy
- **`MediaSendFlowViewModel`**: unit test that `setFullQuality(media, true)` sets `skipTransform = true` on only the targeted item's `transformProperties` in `selectedMedia`, leaves other items' `transformProperties` untouched, and calls `preUploadController.cancelUpload` with only that item (not the full selection). Test the reverse toggle (`false`) restores `skipTransform = false` without discarding other `TransformProperties` fields (e.g. an existing `videoTrim`).
- **`MediaEditViewModel`**: unit test that `ToggleFullQuality(media)` emits `MediaSendFlowEvent.SetFullQuality` with the correctly inverted `fullQuality` value based on the media's current flag.
- Existing tests for `removeMedia`, `setSentMediaQuality`, `onVideoEdited` must continue passing unmodified (regression guard that the new code path doesn't interfere with batch-wide quality or pre-upload cancellation logic).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Matching the target `Media` by URI picks the wrong item if two selected items somehow share a URI | Low | Medium | Reuse the exact same URI-matching convention already used by `removeMedia`/`onVideoEdited` — no new risk introduced beyond what's already accepted in the codebase |
| Toggling full quality after pre-upload already **completed** (not just started) leaves stale compressed bytes uploaded under the old quality | Medium | Medium | Out of scope per ticket wording ("started uploading" implies in-flight, not completed); matches existing `onVideoEdited` behavior for the same class of "edit after pre-upload" scenario — accepted existing product behavior, not a regression |
| UI affordance placement in `ThumbnailRow` collides visually/functionally with existing `DeleteBox` overlay on the focused item | Low | Low | Confirm exact layout during implementation by rendering both in the running app before finalizing |

**Do you approve this plan? Proceed to implementation?**
