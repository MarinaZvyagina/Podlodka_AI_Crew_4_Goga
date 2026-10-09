# R10-TC-GC-03

Condition: goga_native_architecture
Base tag: condition-c-r10-v1
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: True
Cost: $1.1603928000000001
Duration: 154273ms, turns: 30

## Agent's own summary

# Scope Resolution Report

## Task Summary
Add a global, user-configurable message-retention setting to Signal-iOS: pick a window (e.g. 30 days, or off) and auto-delete older messages across all conversations, non-blocking on large histories, resumable across app kill/backgrounding/network interruption, safe under mid-cleanup sign-out, immediately consistent (previews/unread counts) after a pass, changeable/disableable anytime, and retroactive on first enablement. Implementation reuses `BulkDeleteInteractionJobQueue` (existing resumable/batched/sign-out-safe job) rather than new job infrastructure, adding a cutoff→row-id query to `InteractionFinder`, new prefs to `SSKPreferences`, a launch/foreground sweep trigger in `AppSetup`, and a Settings picker in `ChatsSettingsViewController`.

## Candidate Cells
| Cell | Reason | Priority |
|---|---|---|
| `SignalServiceKit/Storage/Database/Records` | Declares `InteractionFinder` as a contract type; task adds a new public method to it | High |
| `SignalServiceKit/Jobs` | Declares `JobQueueRunner`/`JobRecordFinder` (generic job framework); `BulkDeleteInteractionJobQueue` is built on this framework but is not itself a documented type | Low |
| `SignalServiceKit/Environment` | Declares `DependenciesBridge`; `AppSetup.swift` physically lives in this cell's directory but is not a documented contract type | Low |

## Included Dependencies
| Cell | Behavioral Relevance |
|---|---|
| `SignalServiceKit/Storage/Database/Records` | Direct: new method added to a documented type (`InteractionFinder`) in this cell — manifest must be reconciled |

## Excluded Dependencies
| Cell | Exclusion Reason |
|---|---|
| `SignalServiceKit/Jobs` | `BulkDeleteInteractionJobQueue` (the file being extended) is not among this cell's documented types (only `JobQueueRunner`, `JobRecordFinder` are) — confirmed via `goga schema`. Per the contract-boundary rule, obligations don't extend to undocumented types built on top of a documented framework |
| `SignalServiceKit/Environment` | `AppSetup` is not among this cell's documented types (only `DependenciesBridge` is) — no manifest obligation |
| `SignalServiceKit/Jobs/JobRecords` | `BulkDeleteInteractionJobRecord` (used unmodified, no new job-record type added) isn't touched; existing `JobRecord` contract is unaffected |
| All 47 other schema cells | No file touched, no dependency edge, no usage relationship |

## Usage Relationships
| Usage | Relevance |
|---|---|
| None declared | No `.usages` files exist under `SignalServiceKit/Storage/Database/Records/`; no project-level `.goga/usages/` entries exist (`codemanifest.usages` config absent) |

## Semantic Participation Summary
Only `SignalServiceKit/Storage/Database/Records` has manifest-level semantic participation: the new `rowIdOfNewestInteraction`-style method is a genuine addition to `InteractionFinder`'s public contract and must be reflected in its CODEMANIFEST. `SSKPreferences`, `BulkDeleteInteractionJobQueue`, `AppSetup`, `ChatsSettingsViewController`, and `PrivacySettingsViewController` all sit outside any cell's documented type set (confirmed via `goga schema`, 52 total cells, none listing these types) — changes to them are implementation-only, governed by ordinary code conventions rather than a CODEMANIFEST contract. No cell declares a dependency on `Storage/Database/Records` either, so there are no downstream consumer cells whose usages need updating.

## Final Investigation Scope
- `SignalServiceKit/Storage/Database/Records` (manifest-governed — investigate `InteractionFinder`'s existing `SELECT MAX(id)` precedent, e.g. `maxInteractionRowId`, and its `RowIdFilter`/`finder_scoping` usages)
- Non-cell implementation files (investigate as ordinary code, no manifest obligation): `SignalServiceKit/Jobs/BulkDeleteInteractionJobQueue.swift`, `SignalServiceKit/Util/SSKPreferences.swift`, `SignalServiceKit/Environment/AppSetup.swift`, `Signal/src/ViewControllers/AppSettings/ChatsSettingsViewController.swift`, `Signal/src/ViewControllers/AppSettings/Privacy/PrivacySettingsViewController.swift` (read-only reference)

## Scope Risks
- **Under-scoping risk**: if `BulkDeleteInteractionJobQueue` is later added as a documented cell type (it currently isn't), a future change would need to retrofit a manifest entry — not a risk for *this* change, but worth flagging in the final report.
- **Over-scoping risk**: none identified — the two-tier split (one governed cell vs. five ungoverned implementation files) matches exactly what `goga schema` shows; no speculative inclusion made.

## Notes
The `SignalServiceKit/Jobs` CODEMANIFEST's own usage notes (per prior cross-checkout precedent) state the cell documents only the generic `JobQueueRunner`/`JobRecordFinder` extension point, explicitly noting no manifest change is needed to add a new job type built on it — consistent with what `goga schema` shows here. This is the first checkout of this recurring feature where a *real* manifest touch-point (`InteractionFinder`) exists, so Step 7 (Manifest Reconciliation) will have actual work to do, unlike prior sibling checkouts.
