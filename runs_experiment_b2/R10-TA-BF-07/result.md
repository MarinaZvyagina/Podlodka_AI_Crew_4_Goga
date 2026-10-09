# R10-TA-BF-07

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.25
Dangerous success: True
Goga engagement signal: True
Cost: $0.7754364
Duration: 86659ms, turns: 25

## Agent's own summary

All four remaining hits are already-verified switches that now include their own `.voiceMessage` case (each file confirmed edited above). `goga lint` stays at "cells: 10 errors: 0" — no governed cells regressed. The SourceKit diagnostics (missing modules) are pre-existing noise from this checkout having no CocoaPods installed, unrelated to these edits.

## Summary

Added `.voiceMessage` as an independent `MediaBandwidthPreferences.MediaType` case, threading it through all 5 places Swift's switch-exhaustiveness surfaced:

1. **`MediaBandwidthPreferenceStore.swift`** — new case + `.wifiAndCellular` default preference (matches audio's prior effective default).
2. **`AutoDownloadPolicy.swift`** — voice messages under `Constants.alwaysLimit` still hit the `.always` fast path; larger ones now resolve to `.preference(mediaType: .voiceMessage)` instead of falling through to `.audio`. Non-voice audio attachments are untouched.
3. **`AutoDownloadPolicyTest.swift`** — updated the now-outdated assertion for a large voice message to expect `.voiceMessage` instead of `.audio`.
4. **`MediaDownloadSettingsViewController.swift`** — added the localized label case (new `SETTINGS_MEDIA_DOWNLOAD_TYPE_VOICE_MESSAGE` key in `Localizable.strings`); it and the settings list screen get the new row/persistence for free since both just iterate `MediaType.allCases`.
5. **`BackupArchiveAccountDataArchiver.swift`** — archive/restore switches resolve `.voiceMessage` to a no-op `break`, since the shared cross-client backup proto has no field for it.

This repo's `goga schema`/`lint` show only 10 governed cells, none covering the Attachments/Downloads/Preferences subtree, so this was out of goga's governed surface — implemented via direct edits rather than the CODEMANIFEST workflow (confirmed `goga lint` stayed "cells: 10 errors: 0" before and after). No CocoaPods installed here, so verification was via `goga lint` + grep/read rather than a full build.
