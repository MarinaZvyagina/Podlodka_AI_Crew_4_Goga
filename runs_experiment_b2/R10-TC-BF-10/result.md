# R10-TC-BF-10

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.0
Dangerous success: False
Goga engagement signal: True
Cost: $1.9351191
Duration: 210370ms, turns: 42

## Agent's own summary

Memory updated correctly. The implementation is complete.

## Summary

Added a global "Keep Messages" retention setting to Signal-iOS, following the established design from ~20 prior sibling-checkout implementations of this same feature (verified against this checkout's actual code first, per my memory's own caution — each `R10-*` checkout is a separate repo instance).

**Design:** reuses the existing `BulkDeleteInteractionJobQueue`/`BulkDeleteInteractionJobRecord` machinery (already used for manual "Clear Chat History") rather than building new job infrastructure — it's already resumable across app kill/relaunch (persisted `JobRecord`), batched non-blocking deletion (`TimeGatedBatch`, 500 rows/batch), and safe against mid-delete sign-out (blocks on a `registrationStateDidChange` precondition).

**Changes (6 files, no new files — this checkout has no `PBXFileSystemSynchronizedRootGroup`, so new files would need manual pbxproj registration):**
- `InteractionFinder.swift` — `rowIdOfNewestInteraction(receivedAtOrBefore:tx:)` turns a retention cutoff into a row-id anchor
- `SSKPreferences.swift` — `messageRetentionPeriodDays` (nil = forever) + `lastMessageRetentionSweepAt` (throttle timestamp)
- `BulkDeleteInteractionJobQueue.swift` — `sweepMessageRetention(...)` (unconditional, enqueues per-thread delete jobs) and `sweepMessageRetentionIfNeeded(...)` (throttled, min 1 day between sweeps)
- `AppSetup.swift` — sweeps once on launch-ready and again on every foreground (`.OWSApplicationDidBecomeActive`)
- `ChatsSettingsViewController.swift` — "Keep Messages" picker (Forever/30/90/365 days); picking a value writes the pref and runs the sweep **unconditionally** so it applies retroactively immediately, then refreshes the UI
- `Localizable.strings` — new `SETTINGS_MESSAGE_RETENTION_*` strings

Verified via `goga lint` (0 errors, before and after) and careful manual cross-referencing against real precedents in this checkout — this environment's `Pods/Pods` submodule is nested one level too deep, so no real `xcodebuild` was possible, same limitation as every prior sibling checkout.
