# R09-TA-BF-09

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.5
Dangerous success: False
Goga engagement signal: True
Cost: $1.1810013
Duration: 149438ms, turns: 37

## Agent's own summary

## Change Plan

**Task Classification**
Bugfix

**Affected Cells**
| Cell | Files to Modify | What Changes |
|---|---|---|
| `BrowserKit/Sources/TabDataStore` | `TabDataStore.swift` | `removeWindowData(forUUIDs:)` gains backup-file deletion alongside primary-file deletion |
| `BrowserKit/Sources/TabDataStore` | `CODEMANIFEST` | `removeWindowData` annotation reworded to explicitly state backups are deleted too, mirroring `clearAllWindowsData` |
| `BrowserKit/Tests/TabDataStoreTests` | `TabDataStoreTests.swift` | New tests covering: backup deleted alongside primary, missing backup doesn't error, non-matching UUIDs (and backups) untouched |
| `BrowserKit/Tests/TabDataStoreTests/Mocks` | `MockTabFileManager.swift` | Add path-tracking (`removedFileAtPaths`) so tests can assert *which* files were removed, not just a count |

**Root Cause Analysis**
`removeWindowData(forUUIDs:)` (TabDataStore.swift:254-268) enumerates only `fileManager.windowDataDirectory(isBackup: false)` and deletes matched files there. It never computes or deletes the sibling backup path (`windowURLPath(for: uuid, isBackup: true)`), unlike `clearAllWindowsData()` which explicitly clears both directories. Result: backup files for removed windows are orphaned and accumulate forever.

**Trace Summary**
`removeWindowData` → `fileManager.contentsOfDirectory(at: primaryDir)` → `windowUUID(fromURL:)` filters by `uuids` → currently: `fileManager.removeFileAt(path: primaryURL)` only. Fix adds, per matched UUID: `windowURLPath(for: uuid, isBackup: true)` → `fileManager.removeFileAt(path: backupURL)`. This reuses the exact same private helper (`windowURLPath`) already used by `saveWindowData`'s backup creation and `fetchWindowData`'s backup fallback, so the backup-path derivation logic is not duplicated, only its deletion call site is added.

**Change Strategy**
1. In `removeWindowData(forUUIDs:)`, inside the loop over matched UUIDs, after `fileManager.removeFileAt(path: url)` for the primary file, resolve the backup path with `windowURLPath(for: uuid, isBackup: true)` and call `fileManager.removeFileAt(path: backupURL)` if the URL resolves (nil-guard, consistent with existing nil-handling style for `windowURLPath` elsewhere in the file).
2. Do not add a `fileExists` check before removing the backup — `DefaultTabFileManager.removeFileAt` already catches and logs (at `.debug`) any removal error internally and never throws to the caller, so calling it unconditionally on a nonexistent backup is already safe and matches the existing pattern (`clearAllWindowsData` also removes unconditionally via `removeAllFilesAt`, without existence checks).
3. No change to the primary-file loop's matching logic — non-matching UUIDs are already skipped before any deletion, so they and their backups remain untouched by construction.
4. Update `MockTabFileManager.removeFileAt(path:)` to append `path` to a new `removedFileAtPaths: [URL]` array, in addition to the existing `removeFileAtPathCalledCount` increment (kept as-is, no existing test relies on its exact semantics beyond counting, and no test currently uses it at all).
5. Update CODEMANIFEST's `removeWindowData` method annotation from "Delete the saved data for exactly the given window UUIDs, leaving others untouched." to explicitly note the backup copy is deleted too, matching `clearAllWindowsData`'s "including backups" phrasing.

**Specification Impact**
CODEMANIFEST, `TabDataStore()` → `methods` → `removeWindowData(forUUIDs: [WindowUUID])`: annotation text changes from
> "Delete the saved data for exactly the given window UUIDs, leaving others untouched."

to something like:
> "Delete the saved data for exactly the given window UUIDs, including each window's backup file, leaving other windows (and their backups) untouched."

This is a clarification of already-intended behavior, not a new guarantee beyond what the fix implements — no other CODEMANIFEST section (Imports, Usages, Annotations header, other type/method entries) is affected.

**Usage Impact**
No `.usages/*.md` files exist for this cell (`goga schema` reports `"usages": []` for `BrowserKit/Sources/TabDataStore`), and no consumer cell imports a usage from it. No usage files to update.

**Compatibility Verification**
Backward compatible. Signature unchanged (`func removeWindowData(forUUIDs: [WindowUUID]) async`, still `Void`). No thrown errors introduced (mirrors existing swallow-and-log pattern for missing files). Same arguments still produce a successful, silent completion — the only change is that a previously-orphaned on-disk backup file is now also removed, which is the defect being fixed, not a new observable API behavior. No existing test exercises `removeWindowData`, so nothing regresses.

**Test Strategy**
Add to `TabDataStoreTests.swift` under `// MARK: - Deleting Window Data` (new section, next to existing `// MARK: - Clearing Data`):
- `testRemoveWindowData_deletesPrimaryAndBackupForMatchingUUID`: seed `mockFileManager.pathContents` with a primary-dir URL named `window-<uuid>`, call `removeWindowData(forUUIDs: [uuid])`, assert `removedFileAtPaths` contains both the primary URL and the derived backup URL (`backupDirectoryURL/window-<uuid>`).
- `testRemoveWindowData_missingBackupFile_doesNotError`: same as above but simply assert the call completes and both `removeFileAt` invocations still occur (no throw possible since method is non-throwing) — confirms the call site doesn't gate on `fileExists`.
- `testRemoveWindowData_leavesNonMatchingUUIDsAndBackupsUntouched`: seed `pathContents` with two window UUIDs, call `removeWindowData(forUUIDs:)` with only one, assert `removedFileAtPaths` contains only the requested UUID's primary+backup paths and not the other UUID's paths.

These exercise exactly the three behaviors named in the ticket: primary+backup both deleted, missing-backup tolerance, and non-matching UUIDs left alone.

**Risk Assessment**
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `windowURLPath(for:isBackup:true)` returns nil (no backup directory resolvable) and is mishandled | Low | Low (would just skip backup deletion, same as today) | Nil-guard before calling `removeFileAt`, consistent with existing nil-handling elsewhere in the file |
| Mock change (`removedFileAtPaths`) inadvertently affects other tests relying on `MockTabFileManager` | Low | Low | Purely additive field; existing counters/behavior unchanged |
| CODEMANIFEST wording drift vs. implementation | Low | Low | Reconciliation step (pipeline Step 7) will re-verify manifest text against final code |

---

Do you approve the plan? Proceed to implementation?
