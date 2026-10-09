# R10-TA-GC-04

Condition: goga_native_architecture
Base tag: condition-c-r10-v1
Functional success: True
Full architecture conformance: False
ACR: 0.25
Dangerous success: True
Goga engagement signal: True
Cost: $1.2062595
Duration: 105250ms, turns: 32

## Agent's own summary

Added a new `.voiceMessage` case to `MediaBandwidthPreferences.MediaType` in `MediaBandwidthPreferenceStore.swift`, giving voice messages their own independently-configurable on/never/Wi-Fi-only/Wi-Fi-and-cellular setting (default `.wifiAndCellular`, matching audio's prior effective behavior).

Changes:
- **Settings UI**: `MediaDownloadSettingsViewController` gets a new localized label (`SETTINGS_MEDIA_DOWNLOAD_TYPE_VOICE_MESSAGE` = "Voice Messages"); the row appears automatically in `DataSettingsTableViewController` since it just iterates `MediaType.allCases`.
- **Download logic** (`AutoDownloadPolicy.build`): voice messages below the small-size threshold still auto-download immediately (fast path preserved); larger voice messages now fall through to `.preference(mediaType: .voiceMessage)` instead of `.preference(mediaType: .audio)` — a real behavior change, decoupling them from generic audio attachments, which keep their existing behavior unchanged.
- **Persistence**: works automatically via the existing key-value store keyed on `MediaType.rawValue`.
- **Backup sync**: since the shared cross-client backup proto has no field for voice messages, both export and restore switches in `BackupArchiveAccountDataArchiver.swift` resolve the new case to a no-op.
- Updated the existing test expectation in `AutoDownloadPolicyTest.swift` and both governed `CODEMANIFEST` files (this checkout is goga-governed for this subtree) to reflect the new case; `goga lint` stayed clean (52 cells, 0 errors).

No CocoaPods installed here, so verification was via careful grep/read of all exhaustive switches over `MediaType` plus `goga lint`, not a real build.
