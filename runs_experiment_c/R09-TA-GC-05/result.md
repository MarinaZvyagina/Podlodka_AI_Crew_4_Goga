# R09-TA-GC-05

Condition: goga_native_architecture
Base tag: condition-c-r09-v1
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: False
Cost: $1.3014826499999994
Duration: 264083ms, turns: 24

## Agent's own summary

Fixed. In `BrowserKit/Sources/TabDataStore/TabDataStore.swift`, `removeWindowData(forUUIDs:)` now also removes each window's backup copy (via `windowURLPath(for:isBackup: true)`) alongside the primary file. Since `TabFileManager.removeFileAt` already swallows "file not found" errors internally, windows without a backup file are handled without error, and UUIDs not in the removal list are left untouched (unchanged loop logic still filters on `uuids.contains`).

I also added three unit tests in `TabDataStoreTests.swift` (plus a `removedFilePaths` tracking array in `MockTabFileManager`) covering: primary+backup both removed, untouched UUIDs left alone, and the case where no backup directory exists (only primary removed, no crash).

Note: I couldn't run the actual test suite — `xcodebuild`/`swift build` in this sandbox fail on package resolution (missing cached SPM checkout dirs, no network), unrelated to this change. Worth running `fxios test` for `BrowserKit` locally to confirm before merging.
