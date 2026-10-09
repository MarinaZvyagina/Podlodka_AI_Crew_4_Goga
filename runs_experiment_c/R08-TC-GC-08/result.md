# R08-TC-GC-08

Condition: goga_native_architecture
Base tag: condition-c-r08-v1
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: False
Cost: $1.8937887000000002
Duration: 320609ms, turns: 52

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add an automatic, periodic background routine that deletes cached thumbnail/preview files on disk that no longer correspond to any surviving attachment or message. It must respect not-in-call and battery-not-critically-low conditions, run on a recurring cadence without user action or reliance on a one-time post-update migration, and — because the file set can be large and Android routinely kills background work — make resumable forward progress across interrupted passes rather than restarting from scratch or stalling indefinitely.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `app/src/main/java/org/thoughtcrime/securesms/database` | Contains `AttachmentTable.kt`, which owns the on-disk "parts" directory (shared by attachment data files and `THUMBNAIL_FILE` preview files) and the existing `deleteAbandonedAttachmentFiles()` orphan-scan routine this feature must extend/reuse | High |
| `app/src/main/java/org/thoughtcrime/securesms/jobmanager` | Defines `Job`, `CoroutineJob`, `Job.Parameters`, `Job.Result` — base types the new periodic cleanup Job must extend/use | Medium |
| `app/src/main/java/org/thoughtcrime/securesms/jobmanager/impl` | Defines `NotInCallConstraint` and `BatteryNotLowConstraint`, the two existing constraint types this job must attach to satisfy the call/battery conditions | Medium |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| `jobmanager` | New job's runtime behavior (scheduling, retry/serialization semantics, cancellation) is governed by `Job`/`CoroutineJob`/`Job.Parameters`/`Job.Result` contracts |
| `jobmanager/impl` | New job attaches `NotInCallConstraint.KEY` and `BatteryNotLowConstraint.KEY` to its `Parameters`; the constraints' `isMet()` semantics directly determine when the cleanup pass is allowed to run |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `app/src/main/java/org/thoughtcrime/securesms/database/model` | No orphan-file or thumbnail-path behavior; pure DTO/read-model layer, no data-flow participation |
| `app/src/main/java/org/thoughtcrime/securesms/database/identity` | Unrelated aggregation logic over identity records, no participation in attachment/thumbnail lifecycle |
| `app/src/main/java/org/thoughtcrime/securesms/recipients*` | No participation in file storage or job scheduling |
| `lib/libsignal-service/**` | Protocol/network layer, no involvement in local disk cache cleanup |
| `feature/media-send/**`, `feature/registration/**` | UI/flow features unrelated to background storage maintenance |
| `core/util/src/main/java/org/signal/core/util/billing` | Unrelated leaf cell (billing), no behavioral relevance |

## Usage Relationships

| Usage | Relevance |
|---|---|
| None declared in candidate cells' `.usages/` that bind to this behavior | The relevant cells (`jobmanager`, `jobmanager/impl`) expose only type contracts (Job base classes, constraint classes) referenced via `Imports`/type dependency, not via a documented consumer practice file |

## Semantic Participation Summary
- **`database`**: This is the true implementation site. `AttachmentTable` already tracks `THUMBNAIL_FILE` per attachment row and already contains one relevant routine, `deleteAbandonedAttachmentFiles()`, which diffs on-disk files in the attachment "parts" directory against `DATA_FILE`/`THUMBNAIL_FILE` values still referenced in the DB and deletes the rest. This is the existing mechanism that already conceptually "finds thumbnail cache files with no corresponding attachment/message." However, it runs as a single unbatched full-directory scan with no persisted cursor — it does not satisfy the resumable-forward-progress requirement for very large file sets, and it is only invoked ad hoc (thread deletion, `OptimizeMediaJob`, a one-time migration job), never on a true recurring cadence. **Note:** `AttachmentTable` is not currently a CODEMANIFEST-documented type within this cell (the cell's contract only covers `DatabaseObserver`, `DatabaseTable`, `RecipientTable`, `SignalDatabase`), so extending it does not modify any existing documented contract.
- **`jobmanager` / `jobmanager/impl`**: Pure dependency participation. The new periodic job will be built on top of `Job`/`CoroutineJob` and will declare `NotInCallConstraint.KEY` + `BatteryNotLowConstraint.KEY` in its `Parameters` to satisfy the call/battery constraints — consuming these contracts as-is, not altering them.
- **Non-cell implementation surface (informational, not CODEMANIFEST-governed):** the actual new Job class belongs in `org.thoughtcrime.securesms.jobs` (sibling to `DeleteAbandonedAttachmentsJob`), the new recurring-schedule trigger belongs in `org.thoughtcrime.securesms.service` (sibling to `AnalyzeDatabaseAlarmListener`, built on `PersistentAlarmManagerListener`), and wiring into app startup belongs in `ApplicationContext.java`. None of these directories have a CODEMANIFEST, so they are outside cell governance but are necessary implementation locations for this change.

## Final Investigation Scope
- `app/src/main/java/org/thoughtcrime/securesms/database` (primary: extend `AttachmentTable`'s orphaned-file logic to be resumable/batchable and thumbnail-aware)
- `app/src/main/java/org/thoughtcrime/securesms/jobmanager` (dependency only: Job base contract)
- `app/src/main/java/org/thoughtcrime/securesms/jobmanager/impl` (dependency only: `NotInCallConstraint`, `BatteryNotLowConstraint`)

Non-cell files that are part of the implementation but outside CODEMANIFEST governance: `org.thoughtcrime.securesms.jobs.*` (new job), `org.thoughtcrime.securesms.service.*` (new alarm listener), `ApplicationContext.java` (startup wiring), `org.thoughtcrime.securesms.keyvalue.SignalStore` (persisted resume-cursor / next-run-time state, following the existing `SignalStore.misc.nextDatabaseAnalysisTime` pattern).

## Scope Risks
- **Under-scoping risk**: If the resumable cursor is stored purely in serialized job data (as `ArchiveAttachmentReconciliationJob` does) rather than also considering `SignalStore`, a canceled/replaced job instance could lose its cursor; investigation must confirm which persistence approach guarantees resumption across process death, not just across job retries.
- **Over-scoping risk**: It is tempting to touch `ThreadTable.kt`'s existing calls to `trimAllAbandonedAttachments()`/`deleteAbandonedAttachmentFiles()` or to unify all abandoned-attachment cleanup (data files + thumbnails) into one new mechanism. That would broaden the change beyond thumbnails specifically and risks altering behavior of existing call sites relied on by unrelated flows (thread deletion, `OptimizeMediaJob`, `AttachmentCleanupMigrationJob`). Scope must stay limited to adding new resumable/periodic/constrained behavior, reusing but not restructuring the existing eager call sites.
- **Contract risk is low**: since `AttachmentTable` is not a CODEMANIFEST-documented type in the `database` cell, and `jobmanager`/`jobmanager/impl` types are consumed unmodified, no existing contract is expected to require reconciliation — this should be validated during Investigation, not assumed.

## Notes
- No cell exists for `org.thoughtcrime.securesms.jobs` or `org.thoughtcrime.securesms.service`; per the Goga cell model, new code there is ordinary implementation, not subject to CODEMANIFEST contract rules, since neither directory has been brought under cell governance in this project.
- Existing precedent for "recurring daily job via AlarmManager" is `AnalyzeDatabaseAlarmListener` (`service/`) + `AnalyzeDatabaseJob` (`jobs/`), scheduled from `ApplicationContext.initializePeriodicTasks()`. Existing precedent for "resumable job across process death via serialized cursor" is `ArchiveAttachmentReconciliationJob` (`jobs/`). Both should inform the Investigation/Planning steps as the idiomatic patterns to follow rather than inventing new scheduling or persistence mechanisms.
