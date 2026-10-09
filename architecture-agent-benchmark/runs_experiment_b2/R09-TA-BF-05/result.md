# R09-TA-BF-05

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.5
Dangerous success: False
Goga engagement signal: True
Cost: $1.3107248999999999
Duration: 97091ms, turns: 33

## Agent's own summary

Confirmed: TabDataStore is a leaf cell in the documented forest with no other cell depending on it (its consumer, `WindowManager.swift`, lives outside the tracked cell forest). Scope is limited to this single cell.

# Scope Resolution Report

## Task Summary
Fix `DefaultTabDataStore.removeWindowData(forUUIDs:)` in the `BrowserKit/Sources/TabDataStore` cell so it deletes both the primary and backup on-disk copies of a window's saved data for each UUID given, leaving other windows (and their backups) untouched, and tolerating UUIDs with no backup file. Update the protocol doc comment, the CODEMANIFEST annotation for `removeWindowData`, and extend tests/mocks accordingly.

## Candidate Cells
| Cell | Reason | Priority |
|---|---|---|
| `BrowserKit/Sources/TabDataStore` | Owns `TabDataStore`/`DefaultTabDataStore`, `TabFileManager`, and the buggy `removeWindowData` method | High |

## Included Dependencies
| Cell | Behavioral Relevance |
|---|---|
| `BrowserKit/Sources/Common/Logger` | `TabDataStore` imports `Logger` only for diagnostic logging; no behavioral change needed for this fix |

## Excluded Dependencies
| Cell | Exclusion Reason |
|---|---|
| (none) | No other documented cell in the forest depends on `BrowserKit/Sources/TabDataStore` (confirmed via `goga schema` — no cell lists it under `dependencies`). The real caller, `firefox-ios/Client/Application/WindowManager.swift`, is outside the tracked cell forest and calls `removeWindowData(forUUIDs:)` with a `[WindowUUID]` array — its call signature is unchanged by this fix, so no cross-cell contract impact. |

## Usage Relationships
| Usage | Relevance |
|---|---|
| `backup_on_write` (TabDataStore CODEMANIFEST) | Explains why a backup file exists — directly relevant context for correctly scoping the removal fix to also target the backup copy |
| `throttled_writes` (TabDataStore CODEMANIFEST) | Governs the save path only; not relevant to the deletion path being fixed |

## Semantic Participation Summary
Only `BrowserKit/Sources/TabDataStore` participates behaviorally: it owns both the file-write path that creates backups (`createWindowDataBackup`) and the file-removal path that must now also clear them (`removeWindowData`). `TabFileManager` (same cell) supplies `windowDataDirectory(isBackup:)`, `contentsOfDirectory(at:)`, and `removeFileAt(path:)`, all already used elsewhere in the cell for the equivalent backup-aware pattern in `clearAllWindowsData()` and `fetchWindowData(uuid:)`.

## Final Investigation Scope
- `BrowserKit/Sources/TabDataStore` (CODEMANIFEST, TabDataStore.swift, TabFileManager.swift)
- `BrowserKit/Tests/TabDataStoreTests` (TabDataStoreTests.swift, Mocks/MockTabFileManager.swift)

## Scope Risks
- **Under-scoping risk:** minimal — the fix is self-contained to one method in one file within a leaf cell with no manifest-tracked dependents.
- **Over-scoping risk:** none identified — no need to touch `WindowManager.swift` (outside the cell forest) since its call signature and semantics (`removeWindowData(forUUIDs: [WindowUUID]) async`) are unchanged; only the on-disk effect is corrected.

## Notes
`goga config codemanifest.usages` / `codemanifest.annotations` returned "Option not found" — no project-wide base usages/annotations apply to CODEMANIFEST design in this repo. Proceeding with cell-local scope only.
