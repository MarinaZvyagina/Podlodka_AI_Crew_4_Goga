# R08-TC-G-01

Condition: goga
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Cost: $2.1183388499999998
Duration: 376560ms, turns: 28

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add a new periodic, resumable background routine that scans on-disk thumbnail/preview cache files for attachments and deletes those with no corresponding attachment/message remaining in the database. It must respect not-in-call and battery-not-low conditions, run on its own recurring cadence without user action or one-shot-after-update behavior, and survive/resume across process death using a persisted cursor rather than restarting or stalling.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `app/src/main/java/org/thoughtcrime/securesms/jobmanager` | Defines the `Job`/`Job.Factory`/`Constraint` extension points the new cleanup routine must plug into; already documents `NotInCallConstraint`-class and `BatteryNotLowConstraint`-class eligibility gating via the generic `Constraint` contract | Runtime participation (highest) |
| `app/src/main/java/org/thoughtcrime/securesms/database` | Documents the `DatabaseTable` convention that `AttachmentTable` (undocumented individually, but governed by convention) follows; the new routine must query attachment/message existence through this layer | Runtime participation |
| `app/src/main/java/org/thoughtcrime/securesms/dependencies` | `AppDependencies` is the sole wiring point through which a new job accesses `JobManager` and any table accessor at runtime, and through which a periodic scheduler (alarm listener) would enqueue the job | Manifest relevance (indirect access path) |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| `app/src/main/java/org/thoughtcrime/securesms/jobmanager` | New `Job` subclass + reuse of existing `Constraint` keys (not-in-call, battery-not-low) for eligibility; cursor persisted via the existing `Job.serialize()`/`Job.Factory.create()` contract so a killed pass resumes rather than restarting |
| `app/src/main/java/org/thoughtcrime/securesms/database` | New/reused query surface on the attachment table to determine "does this file still correspond to a live attachment/message" during the scan; must follow existing `DatabaseTable` construction convention if a new query method is added |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `app/src/main/java/org/thoughtcrime/securesms/recipients` | No data-flow or behavioral participation — recipient identity is irrelevant to attachment/thumbnail file existence |
| `core/util/src/main/java/org/signal/core/util/billing`, `lib/billing/...` | Infrastructural-only, unrelated domain (billing) |
| `lib/libsignal-service/.../api` | No participation — this is a local on-disk cleanup with no network/protocol surface |
| `feature/registration/...`, `feature/media-send/...` | Verified fully decoupled leaf cells with no relation to attachment storage or job scheduling |

## Usage Relationships
None declared in any candidate cell's `usages` (all three candidate cells show `"usages": []` in `goga schema`). No project-level `.goga/usages/` practices exist either, since `.goga/config.yml` is absent from the project root.

## Semantic Participation Summary
- **jobmanager**: primary behavioral participant. The task is fundamentally "a new kind of background job with specific constraints and resumable state" — exactly the extension point this cell documents (subclass `Job`, register a `Job.Factory`, declare `constraintKeys` referencing the existing not-in-call/battery-not-low `Constraint` factory keys). The periodic (timer-driven, not reactive) re-scheduling mechanism is **not** part of this cell's documented contract — it lives in undocumented app code (`ApplicationContext`/`PersistentAlarmManagerListener`), so that part of the implementation sits outside governed-cell scope.
- **database**: secondary behavioral participant, for the existence check ("does this thumbnail file still correspond to a live attachment/message"). Only participates through the general `DatabaseTable` convention already documented; no new type needs to be added to the manifest itself unless a new public query method is exposed as part of the module's facade.
- **dependencies**: participates only as the lookup path (`AppDependencies.jobManager`) already used by every other job in the app — no new contractual surface, purely a call-through.

## Final Investigation Scope
- `app/src/main/java/org/thoughtcrime/securesms/jobmanager` (CODEMANIFEST + `impl/` constraints)
- `app/src/main/java/org/thoughtcrime/securesms/database` (CODEMANIFEST + `AttachmentTable.kt` convention)
- `app/src/main/java/org/thoughtcrime/securesms/dependencies` (CODEMANIFEST, read-only reference — access path, not modified)

## Scope Risks
- **Under-scoping risk**: the periodic-scheduling mechanism (alarm registration in `ApplicationContext`) is real implementation work required by the acceptance criteria but is not owned by any governed cell — it must still be implemented, just outside CODEMANIFEST-governed boundaries, so it won't surface again in later cell-consistency steps. Flagging now so it isn't dropped.
- **Over-scoping risk**: `database` cell's manifest only formally documents `RecipientTable` as the representative table; `AttachmentTable` itself is not an enumerated contract type. Care must be taken in Step 3 (Planning) not to invent manifest obligations for `AttachmentTable` beyond the shared `DatabaseTable` convention.

## Notes
No `.goga/config.yml` at project root — no base usages/annotations constrain this change. Language for new code is Kotlin, consistent with every recent addition in the affected cells (`BatteryNotLowConstraint.kt`, `DeleteAbandonedAttachmentsJob.kt`, `BackfillCollapsedMessageJob.kt`).
