# SCOPE.md — R10 (signalapp/Signal-iOS)

## Method

Scope was decided from `SignalServiceKit`'s own module layout — directories at depth ≤ 3 under
`SignalServiceKit/` (per `TREATMENT_DESIGN.md` §4), taking `SignalServiceKit/` as the relevant
source root, analogous to R01's use of `freqtrade/` as its source root. `SignalServiceKit` is
the platform-independent core framework shared by the Signal iOS app, the notification-service
extension (`SignalNSE`), and the share extension (`SignalShareExtension`) — the genuine
architectural spine of the repository, as opposed to `Signal` (the app's UI/view-controller
layer) or `SignalUI` (shared presentation components), which are consumers of it.

Candidates were verified by directly reading source files and by repo-wide `grep` for how many
distinct files reference a candidate type (a proxy for "is this genuinely load-bearing, not just
present"), performed **before** reading `tasks/R10/task_A.md`–`task_D.md` (see
`PLAUSIBILITY_CHECK.md` for the post-hoc self-check, done only after this scoping and authoring
work was complete). Reference counts gathered during reconnaissance: `DependenciesBridge` (399
files), `TSAccountManager` (151 files), `SDSDatabaseStorage` (55 files), `GroupsV2` (48 files),
`ThreadDeletionManager`/`InteractionDeleteManager` (13–14 files each), `MessageSender`/
`MessageProcessor` (8–11 files each) — all well above incidental-use thresholds.

`SignalServiceKit` has ~90 top-level directories; the ten below were selected as the subset that
is both genuinely cross-cutting (imported by many other subsystems, not just internally
cohesive) and architecturally distinct (each is describable in one phrase without "and", per
`goga-cookbook`'s cell-granularity rule).

## Cells covered (10) and why

| Cell | Evidence it's load-bearing |
|---|---|
| `SignalServiceKit/Account/TSAccountManager` | `TSAccountManager` is the sole source of truth for local registration/account identity (local ACI/PNI/phone number, device id, registration id); referenced in 151 files across `SignalServiceKit`. Every other subsystem that needs "who is this device" depends on it. |
| `SignalServiceKit/Storage/Database` | `KeyValueStore`, `GRDBDatabaseStorageAdapter`, and the base `SDSModel`/`SDSRecord` persistence protocols underlie every persisted domain type in the app — the lowest, most foundational layer in the forest. |
| `SignalServiceKit/Storage/Database/SDSDatabaseStorage` | `SDSDatabaseStorage` is the single database transaction facade (`read`/`write`/`asyncWrite`/`awaitableWrite`) that every read or write of persisted state in the entire app goes through; referenced in 55 files, and by name in `DependenciesBridge` itself. |
| `SignalServiceKit/Jobs/JobRecords` | `JobRecord` is the base persisted unit of Signal's durable background-job framework — the row that survives an app relaunch so a queued job (message send, bulk delete, gift-badge redemption, contact sync, and others) is not lost. |
| `SignalServiceKit/Jobs` | `JobQueueRunner`/`JobRecordFinder` is a genuine, real extension-point pattern: a new durable job type is added by subclassing `JobRecord` and implementing a `JobRunner`/`JobRunnerFactory` pair, without modifying the runner framework itself. Used by at least 7 concrete job queues in the codebase (message sending, bulk interaction deletion, call-record cleanup, donation-receipt redemption, contact sync, gift-badge sending, and the local-user-leaves-group flow). |
| `SignalServiceKit/Threads` | `ThreadDeletionManager`/`ThreadStore` own the lifecycle of every conversation thread — lookup, per-thread associated-data updates, and the soft-delete-by-default deletion contract used by every "delete this conversation" flow; referenced in 13 files, and consumed directly by `Groups` and `Environment` in this forest. |
| `SignalServiceKit/Groups` | `GroupManager`/`GroupsV2` orchestrate all local and remote group mutation and state reconciliation — creation, membership/attribute/access changes, and persisting the resulting model; `GroupsV2`-related types are referenced in 48 files. |
| `SignalServiceKit/Messages/Interactions` | `InteractionDeleteManager` owns removal of persisted interactions (messages, call-event rows) and the multi-step side-effect cascade (associated call-record cleanup, owning-thread update, linked-device "delete for me" sync) that must accompany it; a real, non-trivial coordination point referenced in 14 files. |
| `SignalServiceKit/Messages` | `MessageSender`/`MessageProcessor`/`MessagePipelineSupervisor`/`MessageReceiver` form the single outgoing/incoming message pipeline: one send choke point, buffered envelope processing, and a suspension mechanism shared by every processing stage — the core of what a messaging app's "core" framework does. |
| `SignalServiceKit/Environment` | `DependenciesBridge` is the app's composition root: a single aggregate, constructed once at launch and published as a shared instance, exposing nearly every modern manager/store (accounts, threads, groups, interactions, messaging, database) that other code depends on; referenced in 399 files, the single most-referenced type found during reconnaissance. |

## Deliberately excluded / deprioritized

- **`Signal` (the app target) and `SignalUI`** — real and substantial (274k and 77k lines
  respectively), but they are consumers of `SignalServiceKit`'s contracts (view controllers,
  view models, presentation-layer glue), not the platform-independent architectural spine
  itself. `SignalServiceKit` alone is ~397k of the repository's ~548k Swift lines and is shared
  by three separate targets/extensions, making it the more defensible "spine" choice.
- **`SignalServiceKit/Attachments`, `SignalServiceKit/Backups`, `SignalServiceKit/StorageService`,
  `SignalServiceKit/Calls`, `SignalServiceKit/Contacts`, `SignalServiceKit/Usernames`,
  `SignalServiceKit/Subscriptions`, `SignalServiceKit/Registration`, `SignalServiceKit/Payments`,
  `SignalServiceKit/ZeroKnowledge`, `SignalServiceKit/Axolotl`, `SignalServiceKit/KeyTransparency`,
  `SignalServiceKit/SecureValueRecovery`** — each is a real, large, independently meaningful
  subsystem (attachments alone spans a `V2` model migration; Backups has 6 sub-directories), but
  given the "roughly 6–10 cells, genuine coverage of the spine, not a shallow pass at everything"
  budget for a single-repository forest, these were deprioritized in favor of the ten cells above,
  which have the deepest, most cross-cutting reference counts found during reconnaissance
  (identity, persistence, background jobs, threads, groups, interactions, messaging, and the
  composition root that ties them together) rather than domain-specific feature areas.
- **`SignalServiceKit/Contacts/TSThread.swift`** — the *abstract base* `TSThread` class is
  declared in `Contacts/`, not `Threads/` (confirmed by direct source inspection: `open class
  TSThread: NSObject, SDSCodableModel, InheritableRecord` at `Contacts/TSThread.swift:25`,
  whereas `Threads/` holds only `TSThread+OWS.swift`, an extension, plus the concrete subclasses
  `TSContactThread`/`TSGroupThread`/`TSPrivateStoryThread`/`TSReleaseNotesThread`). Rather than
  add an eleventh cell for one abstract base class living in an otherwise out-of-scope directory,
  `TSThread` is treated as an ambient/external type referenced by name in signatures (consistent
  with how R01 treated widely-shared value types like `SignalServiceAddress`), while the two
  concrete subclasses that *are* declared directly inside `Threads/` (`TSGroupThread`,
  `TSContactThread`) are documented as real body entities of the `Threads` cell.
- **Sub-packages containing individual types whose real source file lives in a nested
  subdirectory relative to an otherwise-documented directory** — e.g. `Jobs/JobRecords/`
  (`JobRecord.swift`) and `Storage/Database/SDSDatabaseStorage/` (`SDSDatabaseStorage.swift`)
  were each promoted to their **own** cell (matching the CODEMANIFEST `location` constraint that
  a documented file must sit at the same directory level as its `CODEMANIFEST`, not in a
  subdirectory) rather than folding them inaccurately into their parent directory's cell. This
  mirrors R01's `SCOPE.md` finding that the same constraint forced excluding `optimize/hyperopt/`
  and `data/history/` as separate concerns from the `optimize`/`data` root-file cells.

This scoping was performed and frozen before `tasks/R10/task_A.md`–`task_D.md` were read (see
`PLAUSIBILITY_CHECK.md`).
