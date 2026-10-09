# R08-TC-BF-05

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: True
Cost: $1.62066915
Duration: 97674ms, turns: 19

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add a periodically-running, resumable, constraint-gated cleanup routine that deletes orphaned thumbnail/preview cache files (files on disk with no corresponding attachment/message row remaining in the database). The routine must plug into the existing background-job framework, run on a recurring cadence without user action, defer to active foreground work, skip execution during an active call or critical battery, and make forward progress across process death instead of restarting a full scan or stalling.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `app/src/main/java/org/thoughtcrime/securesms/jobmanager` | Documents the generic background-job framework and its two extension points — `Job.Factory` (keyed by `Job.getFactoryKey`) and `Constraint.Factory` (keyed by `Constraint.getFactoryKey`) — through which the new cleanup job and its call/battery gating must be registered. | High |
| `app/src/main/java/org/thoughtcrime/securesms/database` | Documents `SignalDatabase` (persistence aggregator) and the `DatabaseTable` convention that `AttachmentTable` (the table owning `DATA_FILE`/`THUMBNAIL_FILE` and the orphan-file diff logic) follows. | High |
| `app/src/main/java/org/thoughtcrime/securesms/dependencies` | Documents `AppDependencies`, the static locator through which the job is enqueued (`AppDependencies.jobManager.add(...)`) and through which `JobManager`/`DatabaseObserver` are reached. | Medium |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| `app/src/main/java/org/thoughtcrime/securesms/jobmanager` | Directly implemented against: new `Job.Factory` for the cleanup job, reuse of existing `Constraint.Factory` extension point for call/battery gating, `Job.Parameters` for scheduling metadata. |
| `app/src/main/java/org/thoughtcrime/securesms/database` | `SignalDatabase`/`DatabaseTable` convention governs how the job queries live attachment rows to compute the orphan set; `RecipientTable` stands in for the sibling `AttachmentTable`, which is not itself enumerated in the manifest's `types` list but is described as following the identical convention. |
| `app/src/main/java/org/thoughtcrime/securesms/dependencies` | `AppDependencies.jobManager` is the enqueue path used by any periodic trigger (alarm listener) to hand work to the job framework. |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `app/src/main/java/org/thoughtcrime/securesms/recipients` | No behavioral participation — recipients are unrelated to attachment/thumbnail file lifecycle. |
| `core/util/src/main/java/org/signal/core/util/billing` | Infrastructural-only, unrelated domain (billing), no data flow participation. |
| `lib/billing/src/main/java/org/signal/billing` | Same as above — billing-specific, no relevance. |
| `lib/libsignal-service/.../api` | Network/protocol client boundary; the cleanup routine is purely local storage/DB, no network participation. |
| `feature/registration/.../org/signal/registration` | Unrelated feature module, no manifest semantic involvement. |
| `feature/media-send/.../org/signal/mediasend` | Handles composing/sending new media, not lifecycle cleanup of already-stored thumbnails; no data flow overlap with orphan detection. |

## Usage Relationships

| Usage | Relevance |
|---|---|
| *(none declared)* | `goga config codemanifest.usages` / `codemanifest.annotations` returned "Option not found" — no project-level base usages exist. No cell in this forest currently declares a `.usages/` practice file relevant to job scheduling or file cleanup, so none are imported. |

## Semantic Participation Summary
- **jobmanager**: owns the exact extension surface this change uses — a new `Job.Factory` implementation for the cleanup work, and existing `Constraint.Factory` implementations for gating. This is the cell whose documented contract is directly extended.
- **database**: owns the source of truth (`AttachmentTable`, via the `SignalDatabase` aggregator) that the cleanup routine must diff the on-disk file set against to determine orphan status. Behaviorally load-bearing but only through the convention `RecipientTable` represents in the manifest, since `AttachmentTable` itself is not a cataloged type.
- **dependencies**: only participates as the wiring/enqueue path (`AppDependencies.jobManager`); no new contract surface of its own is touched.

## Final Investigation Scope
- `app/src/main/java/org/thoughtcrime/securesms/jobmanager`
- `app/src/main/java/org/thoughtcrime/securesms/database`
- `app/src/main/java/org/thoughtcrime/securesms/dependencies`

Additionally, the following **undocumented** supporting files (outside the current 9-cell forest, discovered via prior codebase research and required for a complete, non-speculative implementation) fall within the same physical directories as the scoped cells or are conventional companions to them, and must be inspected/modified during investigation even though they have no CODEMANIFEST of their own:
- `app/src/main/java/org/thoughtcrime/securesms/jobs/` (concrete `Job` implementations, e.g. `DeleteAbandonedAttachmentsJob.kt`, `JobManagerFactories.java`)
- `app/src/main/java/org/thoughtcrime/securesms/jobmanager/impl/` (concrete `Constraint`/`ConstraintObserver` implementations, e.g. `NotInCallConstraint.java`, `BatteryNotLowConstraint.kt`)
- `app/src/main/java/org/thoughtcrime/securesms/database/AttachmentTable.kt`, `database/PartFileProtector.java`
- `app/src/main/java/org/thoughtcrime/securesms/service/` (`PersistentAlarmManagerListener.java`, `AnalyzeDatabaseAlarmListener.kt`) — the periodic-cadence trigger mechanism
- `app/src/main/java/org/thoughtcrime/securesms/keyvalue/` (`SignalStore` — persisted cursor/next-run-time state)
- `app/src/main/protowire/JobData.proto` (resumable job state)
- `app/src/main/AndroidManifest.xml`, `app/src/main/java/org/thoughtcrime/securesms/ApplicationContext.java` (receiver registration/startup wiring)

## Scope Risks
- **Under-scoping risk**: `AttachmentTable` is not individually named in the `database` cell's `types` list — treating it as out of scope would make the change impossible to investigate correctly. Mitigated by explicitly including it as the concretization of the documented `DatabaseTable`/`RecipientTable` convention.
- **Over-scoping risk**: Pulling in `recipients`, billing, registration, or media-send cells would add noise with zero behavioral connection to file/thumbnail lifecycle; explicitly excluded above.
- **Forest-coverage risk**: A large fraction of the actually-required files (concrete jobs, constraints, alarm scheduling, proto data) live outside the documented 9-cell forest entirely. Investigation and planning must treat these as real implementation surface even though `goga lint`/`goga schema` won't report drift against them — the manifest for `jobmanager` documents the *extension points*, not every concrete extension.

## Notes
- No breaking change is anticipated at this stage: the task adds a new `Job.Factory` and a new alarm-listener trigger; it does not alter existing `Job`/`Constraint` signatures or existing job behavior (`DeleteAbandonedAttachmentsJob`'s existing event-triggered invocations are expected to remain untouched, with the new periodic job as an addition rather than a replacement) — to be formally confirmed at the Investigation and Compatibility Guard steps.
