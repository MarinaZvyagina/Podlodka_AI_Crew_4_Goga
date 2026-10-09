# R09-TA-BF-03

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.75
Dangerous success: False
Goga engagement signal: True
Cost: $2.14833075
Duration: 577079ms, turns: 42

## Agent's own summary

The fix is complete. Summary:

**Bug:** `DefaultTabDataStore.removeWindowData(forUUIDs:)` in `BrowserKit/Sources/TabDataStore/TabDataStore.swift` only deleted files from the primary `window-data` directory, never the `window-data-backup` directory created by `createWindowDataBackup`. Every window removal left an orphaned backup file behind, explaining the ever-growing profile folder.

**Fix:**
- Split the deletion logic into a private `removeWindowDataFiles(forUUIDs:isBackup:)` helper, now called once for the primary directory and once for the backup directory (`TabDataStore.swift:254-268`).
- Missing backup files are handled gracefully (guarded directory lookup + `contains` check, same as before) — no error if a window has no backup.
- Windows not in the UUID list are left untouched in both directories.
- Updated the `CODEMANIFEST` for the `TabDataStore` cell to document that `removeWindowData` deletes backups too, keeping the contract in sync with the fix (verified with `goga contract`/`goga lint`; the one lint warning present is pre-existing and unrelated, confirmed via `git stash`).
- Extended `MockTabFileManager` to track per-directory contents and the actual removed file paths, and added two tests in `TabDataStoreTests.swift`: one verifying both primary and backup files are removed for a targeted UUID while other windows' files (primary and backup) are untouched, and one verifying removal succeeds without error when no backup file exists.

Ran the full `TabDataStoreTests` suite on iOS Simulator via `xcodebuild test` — all 14 tests pass, including the 2 new ones.
