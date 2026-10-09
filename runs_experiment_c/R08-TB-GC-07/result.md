# R08-TB-GC-07

Condition: goga_native_architecture
Base tag: condition-c-r08-v1
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: False
Cost: $2.5418744999999996
Duration: 303916ms, turns: 44

## Agent's own summary

## Scope Resolution Report

### Task Summary
Add a per-item "send at full quality" override to the media-send review screen: one attachment in a multi-item batch skips the normal compression pass while the rest of the batch compresses per the existing batch-wide `SentMediaQuality` setting. The override must survive the item's pre-upload having already started, and must survive app process death mid-send.

### Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `feature/media-send/.../org/signal/mediasend` (root) | Owns `MediaSendFlowState`/`MediaSendFlowViewModel`, the batch-wide `sentMediaQuality` field, and the `SendRequest` construction that currently stamps one quality onto the whole batch | High |
| `feature/media-send/.../mediasend/preupload` | Owns `PreUploadController`/`PreUploadRepository`/`PreUploadResult` — the background pre-upload machinery that must accept a quality change for an item after upload already started | High |
| `feature/media-send/.../mediasend/screens/edit` | Owns the review screen UI (`MediaEditScreen`, `QualitySelectorBottomSheet`/`QualitySelectorSheetContent`, `MediaEditState`, `MediaEditViewModel`) where the per-item toggle must be exposed | High |

### Included Dependencies (uncellified, no CODEMANIFEST — outside cell governance but required for implementation)

| Path | Behavioral Relevance |
|---|---|
| `core/models/.../media/Media.kt`, `TransformProperties.kt` | `Media.transformProperties` is already per-item; `TransformProperties.skipTransform`/`forSkipTransform()` is the exact "full quality, no compression" carrier |
| `app/.../database/AttachmentTable.kt` + `TransformPropertiesUtil.kt` | `transform_properties` TEXT column is the durable, DB-backed source of truth that already survives process death — this is the persistence mechanism the ticket requires |
| `app/.../jobs/AttachmentCompressionJob.java` | Re-reads `transformProperties` from the DB at job-run time (not from job payload) and skips compression when `shouldSkipTransform()` — this is why toggling after pre-upload starts can still take effect |
| `app/.../mediasend/v2/MediaSelectionRepository.kt` (`buildModelsToTransform`) | Currently stamps the one batch-wide quality onto every `Media` uniformly — this loop is the uniform-application point that needs a per-item exception |
| `app/.../mediasend/SentMediaQualityTransform.java`, `mediasend/v3/MediaSendV3Repository.kt`, `mediasend/v3/MediaSendV3PreUploadRepository.kt`, `mediasend/MediaUploadRepository.java`, `jobs/AttachmentUploadJob.kt` | Carry `Media`/`transformProperties` through send/pre-upload/upload without alteration — pass-through, must remain compatible |

### Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `feature/media-send/.../screens/capture` | Capture-time flow; quality override applies at review time, no behavioral participation |
| `feature/media-send/.../screens/select` | Gallery browsing/selection only; no compression or quality concern |
| `feature/media-send/.../screens/edit/video`, `/document` | Per-type sub-editors; document has no compression concept, video editing (trim/mute) is orthogonal — no data-flow participation in the quality override itself |
| `feature/media-send/.../screens/edit/image` | Image editor canvas; not involved in quality/compression selection |
| `feature/media-send/.../util`, `/test` | Formatting/test-tag helpers; no behavioral relevance |
| `app/.../database` (parent cell), `/model`, `/identity` | `AttachmentTable` is explicitly documented as one of "~90 other tables ... not individually documented" — no manifest semantic involvement for this table |
| `app/.../jobmanager`, `/jobmanager/persistence` | Generic job-persistence framework; `AttachmentCompressionJob` already persists only `attachmentId` and re-reads state from the DB — framework itself needs no change |
| `core/util`, `core/network`, `core/ui` | No participation in media quality/compression data flow |

### Usage Relationships

| Usage | Relevance |
|---|---|
| None declared in `feature/media-send` CODEMANIFEST files (`Imports`/`Usages` sections are empty of cross-module references) — the module intentionally has zero documented dependency on `AppDependencies`/`SignalDatabase`/`jobmanager`, reaching the host app only through `MediaSendDependencies.Provider` and the `PreUploadRepository` interface | Confirms the feature must be implemented as an interface-level contract change (new field/method on `PreUploadRepository`, `SendRequest`, `Media`/`TransformProperties` per-item data) rather than a direct import |

### Semantic Participation Summary
- **`mediasend` (root)** participates because `MediaSendFlowState`/`ViewModel` own the single `sentMediaQuality` field and the `SendRequest` that both must change to also carry a per-item exception (e.g., an updated `Media.transformProperties` for the marked item, or a per-URI override set).
- **`preupload`** participates because it's explicitly named in the ticket: pre-upload can already be in flight, and `PreUploadController` already has a cancel-then-restart pattern (used today for caption/trim/URI edits) that is the natural mechanism to re-apply a changed per-item quality to an in-flight upload.
- **`screens/edit`** participates because it hosts the review screen and existing `QualitySelectorBottomSheet` UI pattern — the natural place to add a per-item "full quality" affordance.
- Uncellified app code participates because the actual compression skip (`AttachmentCompressionJob`) and durable persistence (`AttachmentTable.transform_properties`) already exist and already satisfy the "survives app kill" requirement — no new persistence mechanism is needed, only per-item plumbing through the existing uniform-application point (`MediaSelectionRepository.buildModelsToTransform`).

### Final Investigation Scope
1. `feature/media-send/src/main/java/org/signal/mediasend` (root cell)
2. `feature/media-send/src/main/java/org/signal/mediasend/preupload`
3. `feature/media-send/src/main/java/org/signal/mediasend/screens/edit`
4. (uncellified, implementation-only) `core/models/.../media/Media.kt`, `TransformProperties.kt`; `app/.../database/AttachmentTable.kt`, `TransformPropertiesUtil.kt`; `app/.../jobs/AttachmentCompressionJob.java`; `app/.../mediasend/v2/MediaSelectionRepository.kt`; `app/.../mediasend/SentMediaQualityTransform.java`; `app/.../mediasend/v3/MediaSendV3Repository.kt`, `MediaSendV3PreUploadRepository.kt`; `app/.../mediasend/MediaUploadRepository.java`

### Scope Risks
- **Under-scoping risk**: if the per-item override is only threaded through UI state and not through `PreUploadController`'s cancel/restart path, an item whose pre-upload already completed compression before the toggle is flipped would ship compressed anyway — must verify the compression job hasn't already run, or force a cancel+redo.
- **Over-scoping risk**: touching `jobmanager`/`jobmanager/persistence` (generic framework) is unnecessary — the existing "re-read transformProperties from DB at job-run time" behavior already satisfies durability; no framework change needed.
- **Governance boundary risk**: most of the actual behavior change lands in uncellified app code with no CODEMANIFEST. The compatibility guard/manifest reconciliation steps of this pipeline apply fully only to the three `feature/media-send` cells; changes to uncellified files must still be made carefully but won't go through manifest reconciliation.

### Notes
- `TransformProperties.skipTransform` / `forSkipTransform()` already exists and is already exactly "send at original quality, no compression" — confirmed by `AttachmentCompressionJob.onRun()` short-circuiting on `shouldSkipTransform()`. This substantially de-risks the change: the mechanism exists, only the per-item UI toggle and the per-item application in `buildModelsToTransform` (currently uniform across the batch) are missing.
- Persistence-across-kill is already solved: `AttachmentCompressionJob` re-reads `transformProperties` from the `AttachmentTable.transform_properties` DB column at run time rather than from job payload, and pre-upload already persists the attachment row before the job runs.

Given the confirmed mechanism, here's my recommended approach before I proceed to the full investigation/planning steps: **add a per-item "full quality" flag surfaced in the edit screen, thread it into the `Media` passed to `PreUploadController`/`SendRequest` as `transformProperties.skipTransform = true`, and reuse `PreUploadController`'s existing cancel-then-restart mechanism to re-apply it to an already-in-flight item.** This avoids inventing new persistence or job machinery. Want me to continue into the Investigation step (tracing exact call sites and confirming no edge cases), or do you want to weigh in on this direction first?
