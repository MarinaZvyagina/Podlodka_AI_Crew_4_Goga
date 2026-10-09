# R08-TB-BF-02

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: False
Cost: $4.781973300000001
Duration: 636943ms, turns: 77

## Agent's own summary

Confirmed: no `MediaSendFlowViewModelTest` exists at all, and none of the sibling toggle methods have dedicated tests — matches the assumption. Now producing the plan.

# Change Plan

## Task Classification
**Feature** (additive) — new per-item override threaded through an existing, unchanged event pipeline. One incidental **bugfix** bundled in (`VideoTrimTransform.kt`'s hardcoded `skipTransform = false`), justified because it's on the direct data path of this feature and is currently unreachable/behavior-neutral dead code otherwise.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `feature/media-send/src/main/java/org/signal/mediasend` (CODEMANIFEST-governed) | `MediaSendFlowEvent.kt`, `MediaSendFlowViewModel.kt`, `screens/edit/MediaEditScreenEvents.kt`, `screens/edit/MediaEditViewModel.kt`, `screens/edit/MediaEditorToolbar.kt`, `test/TestTags.kt`, `res/values/strings.xml` | New event type + new private ViewModel method + new toolbar button + new test tag + new strings, all additive |
| *(undocumented, plain code)* | `app/src/main/java/org/thoughtcrime/securesms/mediasend/VideoTrimTransform.kt` | One field's value expression changed from a hardcoded literal to a passthrough of the input `Media`'s existing flag |

## Root Cause Analysis
Not a defect fix — the codebase already has a designed, persisted, job-honored extension point (`TransformProperties.skipTransform`) for "send this attachment without the compression pass." Nothing currently exposes it as a per-item user choice in the review screen. This plan wires that existing mechanism to a new UI control, reusing the identical event-chain shape already proven by `ToggleVideoMuted`.

## Trace Summary
`MediaEditorToolbarSharedButtons` (UI) → `MediaEditScreenEvents.ToggleFullQuality` → `MediaEditViewModel.processEvent` → `MediaSendFlowEvent.ToggleFullQuality` → `MediaSendFlowViewModel.onEvent` → `toggleFullQuality()` → mutates `MediaSendFlowState.selectedMedia`/`focusedMedia` + cancels the item's pre-upload via `PreUploadController.cancelUpload`. Downstream of this cell (attachment insert, `AttachmentCompressionJob`, `AttachmentTable`) is unchanged and was already confirmed in investigation to read `skipTransform` fresh from durable storage at execution time — no cell boundary crossed by this plan beyond emitting a `Media` with the flag set.

## Change Strategy

1. **`MediaSendFlowEvent.kt`** — add `data object ToggleFullQuality : MediaSendFlowEvent` in the "Edits" region (after `ToggleVideoMuted`, line 49).
2. **`MediaSendFlowViewModel.kt`**:
   - Add import `org.signal.core.models.media.TransformProperties`.
   - Add `is MediaSendFlowEvent.ToggleFullQuality -> toggleFullQuality()` arm in `onEvent` (alongside the `ToggleVideoMuted` arm, line 263).
   - Add private `toggleFullQuality()` in the `//region Quality` block, after `setSentMediaQuality`: wrapped in `mutateSelection { }`, computing the flipped `skipTransform`, updating `selectedMedia`/`focusedMedia`, sending the toast, then `preUploadController.cancelUpload(target)`.
3. **`screens/edit/MediaEditScreenEvents.kt`** — add `data object ToggleFullQuality : MediaEditScreenEvents` (after `ToggleVideoMuted`, line 39).
4. **`screens/edit/MediaEditViewModel.kt`** — add `MediaEditScreenEvents.ToggleFullQuality -> parentEventEmitter(MediaSendFlowEvent.ToggleFullQuality)` (after line 79).
5. **`screens/edit/MediaEditorToolbar.kt`**:
   - Add import `androidx.compose.ui.res.stringResource`.
   - In `MediaEditorToolbarSharedButtons`, add a new button block gated by `isQualityVisible(state, editorState)` (same gate as the batch quality button), placed immediately after that button's block. Reads `state.focusedMedia?.transformProperties?.skipTransform == true` locally to pick icon (`CheckCircle` on / `QualityHigh` off) and a single content-description string (see strings below — one string is enough, matching the mute button's precedent of not needing two, though the mute button passes none at all; this button will pass one static description since "full quality" toggle state is otherwise only conveyed by icon+toast, and an accessibility label improves on today's baseline without touching the existing mute button's behavior).
   - Wire `onClick = { onEvent(MediaEditScreenEvents.ToggleFullQuality) }`, `modifier = Modifier.testTag(TestTags.MEDIA_EDITOR_TOOLBAR_FULL_QUALITY_BUTTON)`.
6. **`test/TestTags.kt`** — add `const val MEDIA_EDITOR_TOOLBAR_FULL_QUALITY_BUTTON = "media_editor_toolbar_full_quality_button"` under the `// Media Editor Toolbar` group (after line 20).
7. **`res/values/strings.xml`** — add three entries near the existing `MediaSendViewModel__`/quality strings, each preceded by a descriptive XML comment in the file's existing style:
   - `MediaEditorToolbar__full_quality` = "Full quality" (content description)
   - `MediaSendViewModel__item_will_be_sent_in_full_quality` = "This item will be sent in full quality"
   - `MediaSendViewModel__item_quality_override_removed` = "This item will use the batch's compression setting"
8. **`app/src/main/java/org/thoughtcrime/securesms/mediasend/VideoTrimTransform.kt`** — change `skipTransform = false` to `skipTransform = media.transformProperties?.skipTransform ?: false` inside the `TransformProperties(...)` call; no other field touched.

## Specification Impact
**None.** `MediaSendFlowEvent` and `MediaEditScreenEvents` are both `internal sealed interface`s, not documented as CODEMANIFEST types (the manifest documents `MediaSendFlowState`, `MediaSendFlowViewModel`, `MediaSendRepository`, `MediaSendDependencies`/`.Provider` only). `toggleFullQuality()` is `private`, matching the manifest's existing precedent of not listing `toggleVideoMuted`/`onEditVideoDuration` (also private) among `MediaSendFlowViewModel`'s documented methods. No CODEMANIFEST edit is required — confirmed against the file read in Step 1.

## Usage Impact
None — this cell has no `.usages/*.md` files (empty `Imports`/`Usages` header, confirmed leaf cell).

## Compatibility Verification
**Backward compatible.** Every change is additive (new sealed-interface case, new private method, new UI button, new resources) or a behavior-neutral fix (`VideoTrimTransform.kt`'s changed branch is only reachable once this feature starts setting `skipTransform=true`, which no existing caller does today). No existing public signature, file path, output format, or manifest-documented guarantee changes. Matches the Investigation Report's Breaking Change Assessment (all six checks: NO).

## Test Strategy
**No new test file.** Confirmed via direct search: no `MediaSendFlowViewModelTest` exists, and the two closest sibling toggle methods (`toggleVideoMuted`, `onEditVideoDuration`) have zero dedicated unit tests anywhere in `feature/media-send/src/test`. Adding a test suite solely for `toggleFullQuality()` would be inconsistent with this cell's actual coverage conventions and constitutes scope growth beyond what the ticket or existing practice calls for. (Compose UI tests like `MediaEditorToolbarSharedButtonsTest.kt` exist — if it asserts on the full current button set, implementation should verify it still compiles/passes; no new assertions added there per the same minimal-scope reasoning.)

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `MediaEditorToolbarSharedButtonsTest.kt` (existing test) makes assertions sensitive to the toolbar's exact button count/order and starts failing once a button is added | Low-Medium | Low (test-only, caught by build) | Run the existing test after implementation; adjust only if it breaks, without touching its unrelated assertions |
| Two independent quality controls (batch STANDARD/HIGH selector + this per-item full-quality toggle) visible in the same toolbar row could read as confusing UI without a design pass | Medium | Low (UX polish, not correctness) | Out of scope for this ticket (backend/architecture-focused); icon choice (`CheckCircle` vs `QualityHigh`, distinct from the batch button's `QualityHigh`/`QualityHighSlash` pair) and a content-description string keep the two visually and semantically distinguishable |
| `preUploadController.cancelUpload(target)` deletes the stale attachment row but does not immediately re-trigger upload — item sits without a pre-upload until Send is pressed | Low | Low | Matches the exact established behavior of `toggleVideoMuted`/`onEditVideoDuration` today; final send's `applyMediaUpdates` path (confirmed in prior research) re-uploads correctly-flagged media, so correctness holds even though the UX doesn't eagerly restart the background upload |

---

Do you approve the plan? Proceed to implementation?
