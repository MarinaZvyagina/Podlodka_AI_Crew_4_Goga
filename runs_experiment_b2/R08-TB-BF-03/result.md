# R08-TB-BF-03

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: True
Cost: $2.8111829999999998
Duration: 434863ms, turns: 65

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add a per-item "send in full quality" override on the media-send review screen: a way to mark a single attachment in a multi-item batch so it skips the normal compression pass, while the rest of the batch keeps using the batch-wide `SentMediaQuality` setting. The toggle must take effect even if that item's upload already started, and the choice must survive process death mid-send.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `feature/media-send/src/main/java/org/signal/mediasend` | Owns `MediaSendFlowState`/`MediaSendFlowViewModel` (selection + review state), `PreUploadController` (in-flight upload cancel/restart), and the review screen's quality-picker UI (`QualitySelectorSheetContent`, `MediaEditorToolbar`) — every piece of behavior this task changes lives here | High |
| `core/util/src/main/java/org/signal/core/util/billing` | Listed in schema | none — no semantic relevance |
| `app/src/main/java/org/thoughtcrime/securesms/database` | Listed in schema; `AttachmentTable`/`TransformProperties` persistence lives in this area of the app module | Low — but see Excluded Dependencies |
| `app/src/main/java/org/thoughtcrime/securesms/jobmanager` | Listed in schema; `AttachmentCompressionJob` (which already honors `skipTransform`) runs on this framework | none — infrastructural only, unmodified |
| `app/src/main/java/org/thoughtcrime/securesms/dependencies` | Listed in schema (root DI locator) | none |
| `app/src/main/java/org/thoughtcrime/securesms/recipients` | Listed in schema | none |
| `lib/libsignal-service/.../api` | Listed in schema | none |
| `lib/billing/src/main/java/org/signal/billing` | Listed in schema | none |
| `feature/registration/src/main/java/org/signal/registration` | Listed in schema, unrelated feature | none |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| `feature/media-send/src/main/java/org/signal/mediasend` | Sole cell whose documented contract (`MediaSendFlowViewModel`) gains new behavior (a new toggle method/event) and whose UI files implement the new affordance |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `app/src/main/java/org/thoughtcrime/securesms/database` | Already verified by direct code reading: `TransformProperties.skipTransform` and `AttachmentTable.TRANSFORM_PROPERTIES` already exist and already do the right thing (persist per-attachment, read fresh on every job run). This task does not add or change any behavior here — it only *relies on* an existing, unmodified guarantee. Not a documented type in this cell's manifest (`AttachmentTable`/`TransformProperties` aren't listed among the cell's documented types), and no code in it will be touched. |
| `app/src/main/java/org/thoughtcrime/securesms/jobmanager` | `AttachmentCompressionJob` already returns early on `shouldSkipTransform()` — confirmed by reading `AttachmentCompressionJob.java`. Purely infrastructural reliance; no change to jobmanager or the compression job is planned or needed. |
| `app/.../mediasend/v3` (`MediaSendV3Repository`, `MediaSendV3PreUploadRepository`) | Not a documented cell in `goga schema` (app-layer bridge implementing the feature cell's `Provider`/`Repository`/`PreUploadRepository` interfaces). Verified by reading both files that this task requires no change to `MediaSendRepository`'s or `PreUploadRepository`'s interface shape, so the bridge implementations are untouched. |
| `app/.../mediasend/v2/MediaSelectionRepository.kt` | Not a documented cell. Verified by reading `buildModelsToTransform`/`SentMediaQualityTransform`/`transformPropertiesForSentMediaQuality` that the existing batch-quality transform pipeline already preserves `skipTransform` when it rewrites `sentMediaQuality`. No change needed or planned there. |

## Usage Relationships

| Usage | Relevance |
|---|---|
| (none declared) | `feature/media-send`'s CODEMANIFEST declares no `Usages`/`Imports` sections currently (leaf cell, no cross-cell imports) — confirmed by reading the manifest in full. No practice files apply. |

## Semantic Participation Summary

Only `feature/media-send/src/main/java/org/signal/mediasend` participates behaviorally. It owns:
- The state that must carry the per-item override (`MediaSendFlowState.selectedMedia[i].transformProperties.skipTransform`, via the existing `Media` model — already a field there, no schema change to `Media` needed since `Media` is defined in `core/models`, imported by value only, not part of this cell's own contract surface).
- The view model (`MediaSendFlowViewModel`) that must expose a new operation to flip that flag and restart any in-flight pre-upload for the affected item via its own `PreUploadController`.
- The screen-level event plumbing (`MediaEditScreenEvents` → `MediaSendFlowEvent`) and the UI (`QualitySelectorSheetContent`/`MediaEditorToolbar`) that surface the affordance to the user.

All durability guarantees (DB persistence of `TransformProperties`, JobManager job persistence, compression-job skip logic) are pre-existing, unmodified, and outside this cell's documented contract — they are dependencies whose *existing* behavior this change relies on, not behavior this change alters.

## Final Investigation Scope

- `feature/media-send/src/main/java/org/signal/mediasend` (CODEMANIFEST + implementation: `MediaSendFlowState.kt`, `MediaSendFlowEvent.kt`, `MediaSendFlowViewModel.kt`, `screens/edit/MediaEditScreenEvents.kt`, `screens/edit/MediaEditViewModel.kt`, `screens/edit/MediaEditorToolbar.kt`, `screens/edit/QualitySelectorSheetContent.kt`, `res/values/strings.xml`, associated tests)

## Scope Risks

- **Under-scoping risk (accepted):** excluding the app-layer `v2`/`v3` bridge and `AttachmentCompressionJob`/`AttachmentTable` cells means the investigation will not re-derive their behavior from scratch. This is deliberate — that behavior was already read and verified line-by-line in this session (skip-transform is honored at compression time; `sentMediaQuality` rewrites preserve `skipTransform`; `hasSameTransformProperties` and `PreUploadController.startUpload`'s cancel-then-restart semantics were read directly). The Investigation step (Step 2) will re-confirm these facts against current source rather than trusting memory, since they are load-bearing for correctness even though they sit outside the change's cell boundary.
- **Over-scoping risk:** none identified — the change is naturally contained to one cell.

## Notes

- The CODEMANIFEST's own `location:` fields must stay at the cell root per the DSL (`AttachmentCompressionJob`-style subdirectory files can't be referenced as `location:` targets), but the manifest already documents this cell as covering only a *representative subset* of its filesystem contents (it currently omits `screens/edit/*`, `preupload/*`, etc. entirely). The new contract surface being added is a method on the already-documented `MediaSendFlowViewModel` entity; UI-only files (`QualitySelectorSheetContent.kt`, `MediaEditorToolbar.kt`) are not separately documented types today and are not expected to become one for a single new sheet parameter.
