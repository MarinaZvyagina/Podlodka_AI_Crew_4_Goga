# R09-TA-BF-02

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.5
Dangerous success: False
Goga engagement signal: False
Cost: $1.36930155
Duration: 114368ms, turns: 33

## Agent's own summary

# Scope Resolution Report

## Task Summary
`DefaultTabDataStore.removeWindowData(forUUIDs:)` in cell `BrowserKit/Sources/TabDataStore` deletes matching window-data files only from the primary directory (`windowDataDirectory(isBackup: false)`). It never deletes the corresponding backup file (`windowDataDirectory(isBackup: true)`), created by `createWindowDataBackup(windowPath:)` during throttled saves. This leaves orphaned backup files on disk for windows that were otherwise fully removed. The fix must delete both the primary and backup copies for each targeted UUID, leave non-targeted UUIDs (and their backups) untouched, and not error when no backup file exists for a given UUID.

## Candidate Cells

| Cell | Reason | Priority |
|---|---|---|
| `BrowserKit/Sources/TabDataStore` | Owns `DefaultTabDataStore.removeWindowData`, `TabFileManager` (primary/backup directory + file removal), and `WindowData`/`TabData` types — the entire bug surface | High |

## Included Dependencies

| Cell | Behavioral Relevance |
|---|---|
| `BrowserKit/Sources/Common/Logger` | `TabDataStore`'s only declared dependency; used for logging inside `removeWindowData` — no behavioral change needed, referenced only for consistency of log calls |

## Excluded Dependencies

| Cell | Exclusion Reason |
|---|---|
| `firefox-ios/Client` (app target, `WindowManager.swift`) | Not a documented Goga cell in this schema (app-layer consumer, not part of the CODEMANIFEST forest). It calls `removeWindowData(forUUIDs:)` but the public signature is unchanged — only internal deletion behavior changes. No behavioral participation in the fix itself; verified via `grep` that it is the sole external caller and makes no assumption about backup-file survival. |

## Usage Relationships

| Usage | Relevance |
|---|---|
| `backup_on_write` (TabDataStore CODEMANIFEST) | Directly relevant — explains why a backup file exists; the fix's manifest update should stay consistent with this practice's framing (backup = recovery copy tied to the same window) |
| `throttled_writes` (TabDataStore CODEMANIFEST) | Not relevant to deletion path — only governs the save path |

## Semantic Participation Summary
Only `BrowserKit/Sources/TabDataStore` participates behaviorally: it owns the file-system layout (primary vs. backup directories), the file-naming scheme (`window-<uuid>`), and the `removeWindowData`/`clearAllWindowsData` deletion logic. `clearAllWindowsData` already correctly wipes both directories, confirming the intended invariant that "removing saved window data" spans both copies — `removeWindowData` is the outlier that violates this invariant. No other cell defines or mutates this file layout.

## Final Investigation Scope
- `BrowserKit/Sources/TabDataStore` (CODEMANIFEST, `TabDataStore.swift`, `TabFileManager.swift`)
- `BrowserKit/Tests/TabDataStoreTests` (test cell, non-manifest-governed, for coverage updates)

## Scope Risks
- **Under-scoping risk**: none identified — the bug and its fix are fully contained within `TabDataStore.swift`'s `removeWindowData` and its use of `TabFileManager`'s existing `isBackup` parameter; no new files or types are required.
- **Over-scoping risk**: touching `firefox-ios/Client/Application/WindowManager.swift` is unnecessary — its call site is unaffected since the protocol signature (`removeWindowData(forUUIDs:)`) does not change.

## Notes
- No `codemanifest.usages`/`codemanifest.annotations` base config exists in `.goga/config.yml` (confirmed via `goga config`), so no project-wide practice constraints apply beyond the cell's own manifest.
- The CODEMANIFEST entry for `removeWindowData(forUUIDs:)` currently reads "Delete the saved data for exactly the given window UUIDs, leaving others untouched" — ambiguous as to backups. `clearAllWindowsData`'s entry already sets precedent with "including backups," which the reconciled manifest should mirror for consistency.
