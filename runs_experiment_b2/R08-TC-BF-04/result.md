# R08-TC-BF-04

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: True
Cost: $3.457824600000001
Duration: 599303ms, turns: 65

## Agent's own summary

# Change Plan

## Task Classification
**Feature (additive extension)** — new periodic background routine built entirely on existing, documented extension points; no existing behavior is modified in an observable way.

## Affected Cells
| Cell | Files to Modify | What Changes |
|---|---|---|
| `app/src/main/java/org/thoughtcrime/securesms/jobmanager` | *(none — read-only use of documented extension points)* | New job/constraint usage only; `NotInCallConstraint`/`BatteryNotLowConstraint`/`Job`/`Job.Parameters` consumed exactly as documented, nothing added to this cell |
| `app/src/main/java/org/thoughtcrime/securesms/database` | `AttachmentTable.kt` | Add `limit: Int = Int.MAX_VALUE` default parameter to `deleteAbandonedAttachmentFiles()` |
| *(undocumented — `jobs/`)* | `ThumbnailCacheCleanupJob.kt` (new), `JobManagerFactories.java`, `keyvalue/MiscellaneousValues.kt`, `ApplicationContext.java` | New Job class + factory registration + new SignalStore timestamp key + one new call in `onForeground()` |

## Root Cause Analysis
Orphaned attachment/thumbnail files are only cleaned via `AttachmentTable.deleteAbandonedAttachmentFiles()`, which is invoked exclusively from reactive mutation events (thread trim, conversation delete, backup restore, media optimization) with no cadence-based trigger, no call/battery gating beyond `DataRestoreConstraint`, and no batching — an unbounded single pass unsafe to interrupt at scale.

## Trace Summary
`ApplicationContext.onForeground()` → (new) `ThumbnailCacheCleanupJob.enqueueRoutineCleanupIfNecessary()` → gate on `SignalStore.misc.lastThumbnailCacheCleanupTime` (24h) → `AppDependencies.jobManager.add(ThumbnailCacheCleanupJob())` → constraints `NotInCallConstraint` + `BatteryNotLowConstraint` gate eligibility → `run()` → `attachments.deleteAbandonedAttachmentFiles(limit = BATCH_SIZE)` → `Result.retry()` if batch was full (more work remains) else `Result.success()`. Retries persist via existing `JobController`/`JobStorage` round-trip (`job.serialize()` re-persisted after every retry attempt), so a process death mid-pass resumes correctly: already-deleted files can't reappear in the next disk listing, so each fresh attempt's diff is strictly smaller — guaranteed forward progress with no persisted cursor.

## Change Strategy
1. **`AttachmentTable.kt`**: change `fun deleteAbandonedAttachmentFiles(): Int` → `fun deleteAbandonedAttachmentFiles(limit: Int = Int.MAX_VALUE): Int`; inside the deletion loop, stop once `deleted == limit`. No other line changes.
2. **`keyvalue/MiscellaneousValues.kt`**: add `LAST_THUMBNAIL_CACHE_CLEANUP_TIME` const key + `var lastThumbnailCacheCleanupTime by longValue(...)` property, following the exact shape of `lastProfileRefreshTime`.
3. **New `jobs/ThumbnailCacheCleanupJob.kt`**: `Job` subclass with `KEY`, `enqueueRoutineCleanupIfNecessary()` companion method (gate + stamp + enqueue, mirroring `RetrieveProfileJob`), `Parameters` built with `NotInCallConstraint.KEY`, `BatteryNotLowConstraint.KEY`, `PRIORITY_LOWER`, `setQueue(KEY)`, `setMaxInstancesForFactory(1)`, `setMaxAttempts(UNLIMITED)`; `run()` calls the batched delete and decides retry vs success; nested `Factory`.
4. **`jobs/JobManagerFactories.java`**: one new alphabetically-placed `put(ThumbnailCacheCleanupJob.KEY, new ThumbnailCacheCleanupJob.Factory());` line.
5. **`ApplicationContext.java`**: one new line inside the existing `SignalExecutors.BOUNDED.execute { ... }` block in `onForeground()`, alongside `RetrieveProfileJob.enqueueRoutineFetchIfNecessary()`: `ThumbnailCacheCleanupJob.enqueueRoutineCleanupIfNecessary();`.

## Specification Impact
**None.** `jobmanager` CODEMANIFEST documents `Job`/`Constraint` purely as extension points and explicitly states concrete subclasses "live outside this cell" — adding a new subclass and reusing existing constraint implementations doesn't touch any documented type's signature or annotation. `database` CODEMANIFEST documents `SignalDatabase` as an aggregator with `RecipientTable` as a representative example of ~90 undocumented tables; `AttachmentTable` is one of those undocumented tables, so adding a default parameter to one of its methods doesn't require a manifest body edit. No `Imports`/`Usages`/`Annotations` header changes needed in either cell.

## Usage Impact
**None.** Neither `jobmanager` nor `database` has any `.usages/*.md` files today (confirmed via `goga schema`: `"usages": []` for both). No usage file is created, since this change doesn't introduce a new reusable cell-facade pattern — it's a single additional concrete job following an existing, already-established convention (companion-object `enqueueXIfNecessary()` gated by a `SignalStore` timestamp) that is not itself documented as a usage anywhere in this repo.

## Compatibility Verification
**Backward compatible.** `deleteAbandonedAttachmentFiles()` called with zero arguments retains byte-for-byte identical behavior (default `limit = Int.MAX_VALUE` never trips the new early-exit). All other changes are pure additions (new file, new registration line, new SignalStore key, new call in an existing fire-and-forget executor block). No signature, file path, output format, or return semantics of any existing public member changes.

## Test Strategy
- **`AttachmentTableTest`-style unit coverage** (if an existing test class covers `AttachmentTable` file-cleanup behavior, extend it; otherwise add a focused test) verifying: (a) `deleteAbandonedAttachmentFiles()` with no args still deletes all orphans (regression guard for the default-parameter change), (b) `deleteAbandonedAttachmentFiles(limit = N)` deletes at most `N` files and returns the count deleted.
- **`ThumbnailCacheCleanupJobTest`**: verify `run()` returns `Result.retry()` when the batch is fully consumed (more work likely remains) and `Result.success()` when fewer than `limit` files were deleted (pass complete) — mirroring the existing `BackfillNotifiedStateJobTest`-style pattern if one exists, or a lightweight mock-based test otherwise given no existing job test in this codebase mocks file I/O directly.
- Manual/integration check per repo convention: confirm `JobManagerFactories` registration compiles and the job is reconstructable (exercised indirectly by `JobManagerFactoriesTest.kt` if it enumerates all registered keys).

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| New job runs too often / competes with foreground work | Low | Medium | `PRIORITY_LOWER`, `NotInCallConstraint`, `BatteryNotLowConstraint`, 24h routine gate, small batch size |
| Deletes a file that's actually still referenced due to a race with a concurrent write | Low | Medium | Reuses the exact same diff logic already trusted in production via `deleteAbandonedAttachmentFiles()`; DB read happens inside `readableDatabase.withinTransaction` for a consistent snapshot, same as today |
| Job never converges if orphans are created faster than deleted | Low | Low | Each attempt still deletes real files (monotonic progress on the backlog); cadence + batch size tunable if ever observed in practice |
| `BatteryNotLowConstraint`'s Android "battery low" threshold (~15%) doesn't exactly match "critically low" wording in the ticket | Low | Low | This is the only existing, documented, reusable battery constraint in the codebase; introducing a second, stricter threshold would be a new undocumented mechanism duplicating an existing one — explicitly against `goga-cookbook` guidance to extend/compose rather than parallel-build |

Do you approve the plan? Proceed to implementation?
