# R08-TC-BF-02

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: False
Cost: $2.6132716500000006
Duration: 287860ms, turns: 45

## Agent's own summary

# Change Plan

## Task Classification
**Extension** (of existing, working-but-partial machinery) with an accompanying **bugfix** (closing the "never runs periodically / never resumes" gap). No new cell, no framework changes — pure consumer of the already-documented `jobmanager` extension points.

## Affected Cells

| Cell | Files to Modify | What Changes |
|---|---|---|
| `app/src/main/java/org/thoughtcrime/securesms/database` | `AttachmentTable.kt` | Add a new **batched/cursor-based** overload of the abandoned-file sweep, alongside (not replacing) the existing zero-arg full-sweep method used by reactive callers |
| `app/src/main/java/org/thoughtcrime/securesms/jobmanager` (consumer files outside the documented core, inside cell's sibling `jobs`/`service` packages) | New `PeriodicAbandonedAttachmentCleanupJob.kt`, new `AbandonedAttachmentCleanupAlarmListener.kt`, `JobManagerFactories.java`, `ApplicationContext.java`, `MiscellaneousValues.kt` | New periodic-triggered, cursor-resumable `Job` using two already-registered constraints (`NotInCallConstraint`, `BatteryNotLowConstraint`); new `PersistentAlarmManagerListener` scheduling it daily; registration wiring; one new persisted `SignalStore.misc` timestamp |

No files inside `AttachmentTable`'s or `jobmanager`'s **documented** type list (`SignalDatabase`, `DatabaseTable`, `DatabaseObserver`, `RecipientTable`, `Job`, `CoroutineJob`, `Job.Factory`, `Job.Result`, `Job.Parameters`, `JobManager`, `Constraint`, `Constraint.Factory`, `ConstraintObserver`, `Scheduler`, `JobTracker`, `JsonJobData*`) are modified — this plan only adds a new sibling method/class and consumes existing documented contracts.

## Root Cause Analysis
Orphaned thumbnail files are never cleaned up because the only capable code path (`AttachmentTable.deleteAbandonedAttachmentFiles()` via `DeleteAbandonedAttachmentsJob`) is triggered exclusively reactively (thread deletion, first-ever launch), runs as a single unbatched, uncheckpointed pass, and declares no battery/call constraints.

## Trace Summary
`AlarmManager` → new `*AlarmListener` (modeled on `AnalyzeDatabaseAlarmListener`) → enqueues new `Job` (modeled on `BackfillCollapsedMessageJob`'s cursor/self-re-enqueue pattern) → gated by `NotInCallConstraint` + `BatteryNotLowConstraint` (already registered in `JobManagerFactories`) → calls `AttachmentTable`'s new batched sweep method, which reuses the existing disk-vs-DB diff logic.

## Change Strategy

1. **`AttachmentTable.kt`** — add `fun deleteAbandonedAttachmentFiles(afterFileName: String?, limit: Int): AbandonedAttachmentFileSweepResult` (new nested `data class AbandonedAttachmentFileSweepResult(val deletedCount: Int, val lastFileNameExamined: String?, val hasMore: Boolean)`):
   - List `parts` directory, filter `PartFileProtector`-protected files, **sort by absolute path** (deterministic total order → safe resumable cursor), filter to `> afterFileName`, take first `limit`.
   - Compute `filesInDb` the same way the existing method does (single `SELECT DATA_FILE, THUMBNAIL_FILE` + sticker files) — this query is cheap and re-running it every batch keeps the result correct even if rows changed between batches.
   - Delete files in the batch that aren't in `filesInDb`; track `deletedCount` and the last filename examined in the batch (whether deleted or not, so the cursor always advances even through batches with zero orphans).
   - `hasMore = (batch.size == limit)`.
   - Leave the existing zero-arg `deleteAbandonedAttachmentFiles(): Int` untouched — it keeps serving `DeleteAbandonedAttachmentsJob`'s reactive, immediate, small-blast-radius callers (post thread-delete, first launch) unchanged.
   - Also call the existing `trimAllAbandonedAttachments()` (DB-row cleanup for messages that no longer exist) from the new periodic job before each disk-diff batch — cheap, single `DELETE ... WHERE NOT IN`, needed so message-deletion orphans actually vanish from `filesInDb`.

2. **New `app/src/main/java/org/thoughtcrime/securesms/jobs/PeriodicAbandonedAttachmentCleanupJob.kt`** (mirrors `BackfillCollapsedMessageJob`'s constructor/serialize/Factory shape):
   - Constructor takes `cursor: String?` (null = start of a fresh pass).
   - `Parameters`: `.setQueue(KEY)` (serialize passes, avoid overlap), `.setMaxAttempts(UNLIMITED)`, `.setGlobalPriority(PRIORITY_LOWER)` (yields to user-facing jobs — satisfies "lower priority than anything the user is actively doing"), `.addConstraint(NotInCallConstraint.KEY)`, `.addConstraint(BatteryNotLowConstraint.KEY)`.
   - `serialize()`/`Factory.create()` round-trip `cursor` via a small new `JsonJobData`-based payload (`putString`/`getString`/`hasString`), per the documented `JsonJobData` contract — no new proto needed.
   - `run()`: call `attachments.trimAllAbandonedAttachments()`, then `attachments.deleteAbandonedAttachmentFiles(afterFileName = cursor, limit = BATCH_SIZE)`; if `hasMore`, re-enqueue `PeriodicAbandonedAttachmentCleanupJob(cursor = result.lastFileNameExamined)`; else the pass is complete (nothing further to persist — the next pass is started fresh by the alarm listener).
   - `BATCH_SIZE` sized generously (e.g. 500) to keep each `run()` short (non-janky) while still making real progress per invocation.

3. **New `app/src/main/java/org/thoughtcrime/securesms/service/AbandonedAttachmentCleanupAlarmListener.kt`** — copy of `AnalyzeDatabaseAlarmListener`'s shape: `extends PersistentAlarmManagerListener`, persists next-run time via a new `SignalStore.misc.nextAbandonedAttachmentCleanupTime: Long` (new `longValue` in `MiscellaneousValues.kt`, following the `NEXT_DATABASE_ANALYSIS_TIME` pattern exactly), `onAlarm()` enqueues `PeriodicAbandonedAttachmentCleanupJob()` (fresh pass, `cursor = null`) and schedules the next day (randomized hour, offset from the 2-5am `AnalyzeDatabaseAlarmListener` window to spread device load, e.g. 3-6am).

4. **Wiring**:
   - `JobManagerFactories.java` `getJobFactories()`: `put(PeriodicAbandonedAttachmentCleanupJob.KEY, new PeriodicAbandonedAttachmentCleanupJob.Factory());`
   - `ApplicationContext.java` `initializePeriodicTasks()`: add `AbandonedAttachmentCleanupAlarmListener.schedule(this);` next to the existing `AnalyzeDatabaseAlarmListener.schedule(this);` line.
   - No new `Constraint`/`Constraint.Factory`/`ConstraintObserver` registration needed — `NotInCallConstraint` and `BatteryNotLowConstraint` are already fully wired.

## Specification Impact
Neither `jobmanager/CODEMANIFEST` nor `database/CODEMANIFEST` requires a content change: this plan only *consumes* the already-documented extension points (`Job`, `Job.Factory`, `Constraint` by key, `JsonJobData`) and adds an undocumented sibling method to an undocumented table class (`AttachmentTable`), consistent with those cells' own stated scope ("concrete subclasses live outside this cell," "not individually documented"). **No CODEMANIFEST body edits are planned.** Manifest Reconciliation (Step 7) will re-verify this holds once code is written — if the reconciler finds the new `Job`/method meaningfully extends what a documented type must guarantee, that step will flag it rather than silently skip it.

## Usage Impact
Both cells have `usages: []` and no `.usages/*.md` files. No usage file exists to update, and none is warranted by the cookbook's own creation criteria (no new consumer-facing API surface on the documented facade types themselves — the new class is a `Job` subclass, which the `jobmanager` cell already says lives entirely outside the cell). **No usage files will be created or modified.**

## Compatibility Verification
**Backward compatible.** The existing zero-arg `deleteAbandonedAttachmentFiles()` and `trimAllAbandonedAttachments()` are untouched — all 5 existing call sites (`ThreadTable.kt:376,381,407,412,1381`, `AppInitialization.java:62` via `DeleteAbandonedAttachmentsJob`) keep identical behavior. `DeleteAbandonedAttachmentsJob` itself is untouched. Everything new is additive: a new method overload, a new `Job` class, a new alarm listener, a new factory-map entry, a new `SignalStore` field, one new line in `ApplicationContext`. No existing signature, file path, return semantics, or manifest guarantee changes. No test files reference the modified/added surface today (confirmed by search), so no existing test can break.

## Test Strategy
- **`AttachmentTable.kt` batched sweep** (androidTest, following `AttachmentTableTest.kt` conventions — `SignalActivityRule`, real on-device SQLite + filesystem): 
  - Orphaned thumbnail file (attachment row deleted, its old `THUMBNAIL_FILE` path left on disk) is detected and deleted by the batched method, matching the existing zero-arg method's behavior.
  - Batching: with `limit` smaller than the number of orphaned files, one call deletes only `limit` files, returns `hasMore = true` and a `lastFileNameExamined`; a second call starting `afterFileName` from that cursor makes forward progress and eventually finishes (`hasMore = false`) without re-processing already-examined files and without missing any.
  - A batch pass that only touches non-orphaned files still advances the cursor (`lastFileNameExamined` non-null, `deletedCount == 0`).
- **`PeriodicAbandonedAttachmentCleanupJob`** (unit-level, mirroring how `BackfillCollapsedMessageJob`/other job classes are typically tested in this repo, or a focused androidTest if a DB is required):
  - `Parameters` carry both `NotInCallConstraint.KEY` and `BatteryNotLowConstraint.KEY`.
  - `run()` re-enqueues itself with the returned cursor when `hasMore` is true, and does not re-enqueue when the pass completes.
  - `serialize()`/`Factory.create()` round-trip the cursor correctly (survives a simulated process restart).
- Manual/documented verification (since this is background-scheduling behavior, not something a unit test can observe end-to-end): confirm `AbandonedAttachmentCleanupAlarmListener` is registered in `ApplicationContext.initializePeriodicTasks()` and that `PeriodicAbandonedAttachmentCleanupJob.KEY` is registered in `JobManagerFactories`.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Lexicographic path sort as cursor basis breaks if files are renamed/added mid-pass | Low | Low (worst case: a file is examined twice or a newly-created file is skipped until the next daily pass, not silent data loss) | Files in `parts/` are effectively immutable/append-only per `PartFileProtector`'s protection of in-flight writes; re-running `filesInDb` fresh each batch keeps correctness even if DB rows change concurrently |
| New periodic job contends with foreground jobs and feels janky | Low | Medium | `PRIORITY_LOWER` + `NotInCallConstraint` + `BatteryNotLowConstraint` + bounded `BATCH_SIZE` per `run()` (short bursts, not one giant transaction) |
| Duplicate/overlapping passes if alarm fires while a resumable job chain is still in flight | Low | Low | `setQueue(KEY)` serializes all instances of this job; a fresh `cursor=null` enqueue simply queues behind the in-flight chain rather than running concurrently |
| Manifest/usage reconciliation later decides this *should* be documented (e.g. if `AttachmentTable` becomes a documented cell type in the future) | Low | Low | Explicitly re-checked in Step 7/8; today's manifests scope both affected cells as "representative only," so no drift is introduced now |
| Instrumented (`androidTest`) tests can't be executed in this text-only environment | High | Low | Tests will be written correctly per repo conventions and reviewed for correctness; flagged explicitly in the final report as not locally executed |

---

Do you approve this plan? Proceed to implementation?
