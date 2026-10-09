# R08-TB-BF-01

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: True
Cost: $2.9307488999999993
Duration: 413616ms, turns: 53

## Agent's own summary

Confirmed: the `feature/media-send` cell is a leaf cell with zero declared dependencies/usages in the documented forest. Now producing the Scope Resolution Report.

# Scope Resolution Report

## Task Summary
Add a per-item "send at full/original quality" override to the media-send review/edit screen, so the user can mark exactly one attachment in a multi-item batch to skip the normal compression pass, while the rest of the batch continues to be compressed per the batch default. The override must take effect even if that item's background pre-upload has already started, and must survive the app being killed and relaunched mid-send.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `feature/media-send/src/main/java/org/signal/mediasend` | Owns `MediaSendFlowState`/`MediaSendFlowViewModel` (documented types), the pre-upload controller, and every review/edit-screen UI file identified as needing changes. This is the only documented cell whose manifest-declared types (`MediaSendFlowState`, `MediaSendFlowViewModel`) are behaviorally involved. | High |

No other cell in `goga schema` matched task intent — `feature/media-send` is the sole candidate.

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| *(none)* | `feature/media-send` is documented as a leaf cell with `"dependencies": {}` and `"usages": []` in `goga schema`. It has no declared Imports from any other documented cell. |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `app/src/main/java/org/thoughtcrime/securesms/database` (documents `RecipientTable`, `SignalDatabase`, etc.) | `AttachmentTable`/`AttachmentCompressionJob`/`MediaUploadRepository` are the actual files with behavioral relevance, but none of them are part of this documented cell's contract (only `RecipientTable` is documented as representative of ~90 tables). No manifest-level type from this cell is read or mutated by the change. Infrastructural-only, non-speculative exclusion. |
| `app/src/main/java/org/thoughtcrime/securesms/jobmanager` | `AttachmentCompressionJob`/`JobManager` durability is *relied upon* (already-working behavior), but the change does not modify anything in this cell's contract (`Job`, `Constraint`, etc.). Dependency is infrastructural-only from this change's perspective. |
| `app/src/main/java/org/thoughtcrime/securesms/dependencies` | Root DI locator; not touched, not read by the change. No participation. |
| `core/util/src/main/java/org/signal/core/util/billing`, `lib/billing/...`, `lib/libsignal-service/...`, `feature/registration/...` | No semantic or data-flow relationship to media quality/compression. |

## Usage Relationships

| Usage | Relevance |
|---|---|
| *(none)* | `feature/media-send`'s `usages: []` in the schema — no cell-level `.usages/` practices are declared for this cell today, and no project-level `codemanifest.usages` exist (`goga config codemanifest.usages` → not found). No practice needs to be created or referenced to implement this change; a plain code+manifest change suffices. |

## Semantic Participation Summary

Only `feature/media-send` participates. It owns:
- The state (`MediaSendFlowState.selectedMedia: List<Media>`) that must carry the per-item override.
- The behavior (`MediaSendFlowViewModel`) that must expose a way to set/clear the override and propagate it to an in-flight pre-upload (`preupload/PreUploadController`, a non-manifest-documented file *inside* this cell's directory tree — still in scope because it's part of the cell's file set, just not individually itemized as a manifest type).
- The UI (`screens/edit/MediaEditorToolbar.kt`, `screens/edit/QualitySelectorSheetContent.kt`, `screens/edit/MediaEditState.kt`, `screens/edit/MediaEditScreenEvents.kt`, `screens/edit/MediaEditViewModel.kt`, `screens/edit/ThumbnailRow.kt`) through which the user makes the choice.

The out-of-cell files identified in the task brief (`TransformProperties.kt`, `Media.kt`, `MediaUploadRepository.java#asAttachment()`, `AttachmentCompressionJob.java`) already correctly support a per-item `skipTransform` override with no changes needed — they are dependencies-of-fact (the mechanism this change builds on), not cells requiring modification, and are not part of any documented cell's contract, so they fall outside CODEMANIFEST governance entirely.

## Final Investigation Scope

- `feature/media-send/src/main/java/org/signal/mediasend/CODEMANIFEST`
- `feature/media-send/src/main/java/org/signal/mediasend/MediaSendFlowState.kt`
- `feature/media-send/src/main/java/org/signal/mediasend/MediaSendFlowViewModel.kt`
- `feature/media-send/src/main/java/org/signal/mediasend/preupload/PreUploadController.kt`
- `feature/media-send/src/main/java/org/signal/mediasend/screens/edit/MediaEditState.kt`
- `feature/media-send/src/main/java/org/signal/mediasend/screens/edit/MediaEditScreenEvents.kt`
- `feature/media-send/src/main/java/org/signal/mediasend/screens/edit/MediaEditViewModel.kt`
- `feature/media-send/src/main/java/org/signal/mediasend/screens/edit/MediaEditorToolbar.kt`
- `feature/media-send/src/main/java/org/signal/mediasend/screens/edit/QualitySelectorSheetContent.kt`
- `feature/media-send/src/main/java/org/signal/mediasend/screens/edit/ThumbnailRow.kt`
- `feature/media-send/src/main/java/org/signal/mediasend/MediaSendFlowEvent.kt` (event-forwarding convention, needs inspection)
- `feature/media-send/src/main/java/org/signal/mediasend/test/TestTags.kt` (new test tag(s) for the new control)
- `feature/media-send/src/main/res/values/strings.xml` (new UI copy — app-module string resources are *not* touched; this module owns its own `res/values/strings.xml`)
- `feature/media-send/src/test/java/org/signal/mediasend/**` (test updates)

## Scope Risks

- **Under-scoping risk**: if the per-item override needs a new icon not already present in `SignalIcons`, that icon lives outside this cell (likely `core/ui`), which is undocumented in the forest — would need a targeted, minimal addition outside cell governance. To be confirmed during investigation; prefer reusing an existing icon (e.g. `SignalIcons.QualityHigh`/`QualityHighSlash` already used for the batch quality button) to avoid this.
- **Over-scoping risk**: it would be tempting to also "fix" the batch `sentMediaQuality` → `Media.transformProperties.sentMediaQuality` threading gap noted during prior investigation (never observed being set explicitly before pre-upload). That is pre-existing behavior, unrelated to this ticket's acceptance criteria (which only requires `skipTransform`, not `sentMediaQuality`), and must be excluded from scope to honor "minimize scope."
- **App-module wiring risk**: `MediaSendV3PreUploadRepository.kt` and `MediaUploadRepository.java` (app module) are outside any documented cell and outside `feature/media-send`. They require no changes (verified: `asAttachment()` already reads `media.getTransformProperties()`), but this should be re-verified during investigation rather than assumed, since an incorrect assumption here would silently break app-kill durability.

## Notes
- `feature/media-send` is explicitly documented as "verified fully decoupled from the app module and from every other cell in this forest" — this change must preserve that invariant (no new imports of `AppDependencies`, `SignalDatabase`, or app-module types into the cell).
- No CODEMANIFEST `Imports`/`Usages` changes are anticipated; the change is additive within the existing single-cell contract (new method on `MediaSendFlowViewModel`, no new type, no new cell).
