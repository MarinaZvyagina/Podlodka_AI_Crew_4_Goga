# R08-TC-BF-07

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: True
Cost: $3.854461950000001
Duration: 467713ms, turns: 52

## Agent's own summary

# Change Plan

## Task Classification
**Feature** (new capability: periodic, resumable, constraint-respecting orphaned attachment/thumbnail cache cleanup) implemented as a **minimal extension** of existing, undocumented internals — no new architectural surface, no CODEMANIFEST-governed type touched.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `app/src/main/java/org/thoughtcrime/securesms/database` | `AttachmentTable.kt` | Extract existing orphan-detection logic into a private helper; add a new batched overload alongside the unchanged existing method. `AttachmentTable` is not a documented type in this cell's CODEMANIFEST. |
| `app/src/main/java/org/thoughtcrime/securesms/jobmanager` | *(none — read-only reference)* | `Job.Parameters`/`Constraint` extension points consumed exactly as documented; no file in this cell is edited. |
| *(ungoverned — no CODEMANIFEST)* | `DeleteAbandonedAttachmentsJob.kt`, new `OrphanedAttachmentCleanupAlarmListener.kt`, `MiscellaneousValues.kt`, `AndroidManifest.xml`, `ApplicationContext.java` | Constraint/priority/retry wiring on the existing job; new daily scheduler; new persisted "next run" timestamp; manifest receiver registration; startup wiring. |

## Root Cause Analysis
Per the Investigation Report: orphan-detection logic for attachment/thumbnail cache files already exists and is correct (`AttachmentTable.deleteAbandonedAttachmentFiles()`), but the job that runs it (`DeleteAbandonedAttachmentsJob`) is wired only to a one-time post-install/update trigger and reactive trim events — never an independent recurring cadence — and lacks call/battery constraints and any bounded/resumable batching. The gap is purely in scheduling and execution shape, not detection logic.

## Trace Summary
- `deleteAbandonedAttachmentFiles(): Int` has exactly 3 callers (`DeleteAbandonedAttachmentsJob`, `AttachmentCleanupMigrationJob`, `OptimizeMediaJob`) — only the first is touched.
- `DeleteAbandonedAttachmentsJob` is enqueued from `AppInitialization` and `ThreadTable` — both are fire-and-forget `JobManager.add()` calls unaffected by the job internally retrying more.
- `NotInCallConstraint`/`BatteryNotLowConstraint` already registered in `JobManagerFactories` and combined together elsewhere (`RestoreAttachmentJob`, `AttachmentDownloadJob`) — pure reuse, no new registration.
- `PersistentAlarmManagerListener` + `AnalyzeDatabaseAlarmListener` is the established once-daily background-scheduling pattern, already wired into `ApplicationContext` startup and the manifest.

## Change Strategy
Implementation order (leaf/no-dependency files first):

1. **`AttachmentTable.kt`** — leaf change, no dependents yet. Extract `findAbandonedAttachmentFiles(): Set<String>` private helper from the current body of `deleteAbandonedAttachmentFiles()`. Keep the public no-arg method delegating to it with byte-for-byte identical behavior. Add `AbandonedAttachmentFileSweepResult(deletedCount: Int, hasMoreToDelete: Boolean)` and the new `deleteAbandonedAttachmentFiles(maxDeletes: Int)` overload built on the same helper.
2. **`MiscellaneousValues.kt`** — leaf change (no dependents among the files being added, only consumed by the new listener next). Add `NEXT_ORPHANED_ATTACHMENT_CLEANUP_TIME` constant and `nextOrphanedAttachmentCleanupTime` property.
3. **`DeleteAbandonedAttachmentsJob.kt`** — depends on step 1's new overload. Add constraints (`NotInCallConstraint.KEY`, `BatteryNotLowConstraint.KEY`), `setGlobalPriority(PRIORITY_LOWER)`, `setMaxAttempts(UNLIMITED)`, and rewrite `run()` to loop via the batched overload, returning `Result.retry(...)` while `hasMoreToDelete` is true.
4. **`OrphanedAttachmentCleanupAlarmListener.kt`** (new file) — depends on steps 2 and 3 (reads/writes the new `SignalStore.misc` field, enqueues the job). Modeled on `AnalyzeDatabaseAlarmListener`.
5. **`AndroidManifest.xml`** — depends on step 4 existing (receiver class must exist to be referenced). Register the new receiver.
6. **`ApplicationContext.java`** — depends on step 4. Add the `.schedule(this)` call at startup.

## Specification Impact
**None.** No CODEMANIFEST file requires editing:
- `database/CODEMANIFEST` does not document `AttachmentTable`, so adding a private helper and an additive overload to it does not touch any documented type, method, property, or the cell's stated conventions (its `Annotations` only describe the `DatabaseTable`/`DatabaseObserver` notification convention, which this change doesn't interact with — file deletion isn't a row-level write requiring `DatabaseObserver` notification, consistent with the existing method's behavior).
- `jobmanager/CODEMANIFEST` documents `Job.Parameters`/`Constraint` as generic, freely-combinable extension points; this change only *consumes* them through already-documented builder methods (`addConstraint`, `setGlobalPriority`, `setMaxAttempts`) — it does not add, remove, or alter any documented type or method.

## Usage Impact
**None.** Both cells have `usages: []` in `goga schema` — no `.usages/*.md` practice files exist to update, and this change doesn't introduce a new cell or a new documented extension point that would warrant creating one.

## Compatibility Verification
**Backward compatible.** 
- `deleteAbandonedAttachmentFiles(): Int` keeps its exact signature, return type, and behavior for its 2 existing full-sweep callers.
- The new `deleteAbandonedAttachmentFiles(maxDeletes: Int)` overload is strictly additive (new name-resolvable signature, no ambiguity with the no-arg version).
- `DeleteAbandonedAttachmentsJob`'s public `enqueue()` API and `KEY` are unchanged; only its internal `Parameters` and `run()` body change, which is invisible to its 3 existing call sites (`AppInitialization`, `ThreadTable` ×2, plus the new alarm listener) since they only ever call `enqueue()`.
- New file, new manifest receiver, new `SignalStore.misc` field, and one new startup call are all purely additive.

## Test Strategy
- **Unit test** for `AttachmentTable.deleteAbandonedAttachmentFiles(maxDeletes: Int)`: given N orphaned files on disk and a smaller `maxDeletes`, assert exactly `maxDeletes` are deleted, `deletedCount == maxDeletes`, and `hasMoreToDelete == true`; given `maxDeletes >= N`, assert all are deleted and `hasMoreToDelete == false`. Reuse existing `AttachmentTable` test scaffolding for the no-arg method if present.
- **Unit test** for the existing no-arg `deleteAbandonedAttachmentFiles(): Int` to confirm it still deletes the full orphan set in one call (regression guard on the refactor).
- **Job-level test** (or targeted logic extraction if `DeleteAbandonedAttachmentsJob.run()` is hard to unit test directly) verifying: `Result.retry(...)` is returned while more files remain, and `Result.success()` once the batch reports no more to delete.
- No test needed for the alarm listener itself beyond what `AnalyzeDatabaseAlarmListener` already establishes as an untested, thin scheduling shim (consistent with existing project convention — that class has no dedicated test either).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Overload resolution ambiguity between `deleteAbandonedAttachmentFiles()` and `deleteAbandonedAttachmentFiles(maxDeletes: Int)` at Kotlin call sites | Low | Low (compile error, caught immediately) | Distinct arity makes this a non-issue in Kotlin/Java; verified no call site uses default-argument-style invocation that could collide |
| Batched job takes many retries to fully drain a very large orphan set, delaying full cleanup | Medium | Low | Acceptable — this is explicitly a low-priority hygiene job (`PRIORITY_LOWER`, `NotInCallConstraint`, `BatteryNotLowConstraint`); ticket only requires eventual cleanup, not bounded latency |
| New alarm listener never fires on a device that keeps Signal in the background for a long time (no reboot, no app open) | Low | Low | Matches existing accepted behavior of `AnalyzeDatabaseAlarmListener`/`RotateSignedPreKeyListener`, which use the same `AlarmManager` mechanism today for equally low-urgency maintenance |
| Forgetting to register the new receiver in `AndroidManifest.xml` silently breaks scheduling | Low | Medium | Explicit implementation + build-time `BroadcastReceiver` resolution failure would surface immediately on `schedule(this)` if misregistered; will verify via `goga lint` + manual manifest diff review |

---

Plan complete — no breaking change, no CODEMANIFEST or usage-file edits required.

**Do you approve the plan? Proceed to implementation?**
