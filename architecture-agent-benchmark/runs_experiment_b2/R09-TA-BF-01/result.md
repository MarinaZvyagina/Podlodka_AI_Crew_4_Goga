# R09-TA-BF-01

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.5
Dangerous success: False
Goga engagement signal: True
Cost: $1.3935738
Duration: 141369ms, turns: 34

## Agent's own summary

# Scope Resolution Report

## Task Summary
Fix `DefaultTabDataStore.removeWindowData(forUUIDs:)` in the `TabDataStore` cell so it deletes a window's backup file in addition to its primary file, matching the already-correct behavior of the sibling method `clearAllWindowsData()`. Windows not named in the UUID list (and their backups) must remain untouched, and the absence of a backup file for a given window must not cause an error. The fix requires a manifest update (the `removeWindowData` annotation in `CODEMANIFEST` currently omits backup-deletion semantics) and new unit test coverage (no test currently exercises `removeWindowData` at all).

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `BrowserKit/Sources/TabDataStore` | Owns `DefaultTabDataStore.removeWindowData(forUUIDs:)` (the buggy method), `TabFileManager` (the disk-access abstraction it uses), and the `CODEMANIFEST` documenting both | Primary |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| `BrowserKit/Sources/Common/Logger` | `TabDataStore`'s only declared import; used for diagnostic logging inside the method being changed, but its own contract is untouched — informational only, not a scope target |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| *(none found)* | `goga schema` shows no cell in the documented forest declares a dependency on `BrowserKit/Sources/TabDataStore` (grep of all `dependencies` blocks for `TabDataStore` returned zero matches) — there are no documented downstream cells to consider |

## Usage Relationships

| Usage | Relevance |
|---|---|
| `backup_on_write` (cell-local, `TabDataStore` CODEMANIFEST) | Describes why a backup file exists (fallback on read failure) — directly explains the artifact this fix must also clean up; the fixed `removeWindowData` annotation should stay consistent with this usage's framing |
| `throttled_writes` (cell-local, `TabDataStore` CODEMANIFEST) | Governs the save path, not the removal path — not implicated by this change |

## Semantic Participation Summary
Only `BrowserKit/Sources/TabDataStore` participates behaviorally: it is the sole owner of the window-data removal logic, the backup-file directory/naming convention (`TabFileManager`), and the manifest text that must be reconciled. `Common/Logger` is a passive dependency (logging calls already exist in the method and require no change). No other documented cell imports types or usages from `TabDataStore`, so no ripple effect exists within the goga-tracked architecture forest.

Note: `firefox-ios/Client/Application/WindowManager.swift` calls `removeWindowData(forUUIDs:)` (found during prior investigation), but this file is not part of any documented cell in `goga schema` — it consumes the public method by its existing signature, which is unchanged by this fix (only internal behavior is extended), so it requires no code change and falls outside the manifest-governed scope.

## Final Investigation Scope
- `BrowserKit/Sources/TabDataStore` (implementation: `TabDataStore.swift`, `TabFileManager.swift`; manifest: `CODEMANIFEST`)
- `BrowserKit/Tests/TabDataStoreTests/TabDataStoreTests.swift` and `BrowserKit/Tests/TabDataStoreTests/Mocks/MockTabFileManager.swift` (test scope, same cell's test target)

## Scope Risks
- **Under-scoping risk:** low — the fix is confined to one method in one cell; no other documented cell has a contractual stake in `removeWindowData`'s behavior.
- **Over-scoping risk:** low-moderate — care must be taken not to touch `clearAllWindowsData()`, `saveWindowData`, or `fetchWindowData`, which already correctly handle backups and are out of scope; only `removeWindowData` and its manifest entry should change.
- **Untracked consumer risk:** `WindowManager.swift` (outside the goga forest) depends on this method's behavior but isn't manifest-governed — must verify manually (via existing/added tests) that its call site isn't broken, since goga tooling won't flag it.

## Notes
- `MockTabDataStore.swift` (firefox-ios test mock) simply counts calls to `removeWindowData` and requires no change.
- The `TabFileManager` protocol/implementation needs no signature change — `contentsOfDirectory(at:)`, `windowDataDirectory(isBackup:)`, and `removeFileAt(path:)` already provide everything needed to enumerate and delete backup files; this is a body-only fix to `removeWindowData`, not a contract-shape change.
