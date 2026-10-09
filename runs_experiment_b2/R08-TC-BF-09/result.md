# R08-TC-BF-09

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: True
Cost: $1.6467171
Duration: 176617ms, turns: 33

## Agent's own summary

# Scope Resolution Report

## Task Summary
Implement periodic, constraint-gated, resumable cleanup of orphaned attachment/thumbnail cache files (files under the `parts` directory no longer referenced by any attachment row), replacing today's event-only trigger (app-init, thread-deletion) with a recurring background schedule that respects "not on a call" / "battery not critically low" conditions and survives being killed mid-pass.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `app/src/main/java/org/thoughtcrime/securesms/jobmanager` | Documents the `Job`/`Job.Factory`, `Job.Parameters`, `Constraint`/`Constraint.Factory` extension points that the new/modified cleanup job and its constraints plug into | High |
| `app/src/main/java/org/thoughtcrime/securesms/database` | Documents `SignalDatabase`/`DatabaseTable` convention; `AttachmentTable` (the concrete table holding `deleteAbandonedAttachmentFiles()`, the sweep logic to make resumable) is a member of this cell, standing in for the ~90 tables it represents | High |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| `app/src/main/java/org/thoughtcrime/securesms/jobmanager` | `Job.Factory` keyed by `getFactoryKey()` is how the concrete cleanup Job (new or modified `DeleteAbandonedAttachmentsJob`) is registered/dispatched; `Constraint.Factory` is how `NotInCallConstraint`/`BatteryNotLowConstraint` get attached to `Job.Parameters` |
| `app/src/main/java/org/thoughtcrime/securesms/database` | `AttachmentTable.deleteAbandonedAttachmentFiles()` is the exact orphan-detection/deletion routine being made chunked and resumable |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `app/src/main/java/org/thoughtcrime/securesms/dependencies` | Service locator wiring is infrastructural-only for this change; no new singleton/provider is being introduced, only a `Job.Factory` registration that already follows an established pattern in `JobManagerFactories` (not itself a documented cell) |
| `app/src/main/java/org/thoughtcrime/securesms/recipients` | No behavioral participation — cleanup keys on attachment/message file paths, not recipient identity |
| `core/util/src/main/java/org/signal/core/util/billing`, `lib/billing/.../org/signal/billing` | Unrelated domain (billing), no data flow or manifest participation |
| `lib/libsignal-service/.../signalservice/api` | Unrelated domain (network/protocol client), no participation in local file cleanup |
| `feature/registration/...`, `feature/media-send/...` | Independent feature modules verified decoupled from the app module; no participation in attachment storage cleanup |

## Usage Relationships

| Usage | Relevance |
|---|---|
| *(none declared)* | Neither the `jobmanager` nor `database` cell declares any `.usages/*.md` practices in the current schema (`usages: []` for both), and `.goga/config.yml` has no `codemanifest.usages`/`codemanifest.annotations` configured — no practice-level guidance applies to this change |

## Semantic Participation Summary
`jobmanager` participates because the fix is expressed entirely through its two documented extension points: a `Job.Factory` for the (modified) cleanup job's scheduling/resumability contract, and `Constraint.Factory` for the two gating conditions (call state, battery). `database` participates because the actual orphan-file detection algorithm targeted for the resumability fix (`AttachmentTable.deleteAbandonedAttachmentFiles()`) is a method on `AttachmentTable`, the representative table type documented in that cell. No other documented cell has runtime, manifest, or data-flow involvement in periodic file-cache cleanup.

## Final Investigation Scope
- `app/src/main/java/org/thoughtcrime/securesms/jobmanager`
- `app/src/main/java/org/thoughtcrime/securesms/database`

## Scope Risks
- **Under-scoping risk**: the concrete classes actually being touched (`DeleteAbandonedAttachmentsJob`, a new `PersistentAlarmManagerListener` subclass, `AttachmentTable.deleteAbandonedAttachmentFiles()`, `NotInCallConstraint`, `BatteryNotLowConstraint`, `ApplicationContext.java`, `AndroidManifest.xml`) are *not themselves* individually documented as cells — `database` documents only `RecipientTable` as representative, and `jobmanager`'s body lists the framework types, not every concrete `Job`/`Constraint` implementation. Investigation must verify these concrete classes' current behavior directly from source rather than assuming CODEMANIFEST completeness.
- **Over-scoping risk**: none identified — the two included cells are both directly load-bearing for the change; no speculative inclusion was needed.

## Notes
No `.usages/*.md` files or project-level base usages/annotations exist to constrain this change further; scope and conventions must be inferred entirely from `goga schema` output and the concrete source of the two included cells, consistent with the exploratory investigation already performed in this session.
