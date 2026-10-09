# R10-TA-GC-08

Condition: goga_native_architecture
Base tag: condition-c-r10-v1
Functional success: True
Full architecture conformance: False
ACR: 0.25
Dangerous success: True
Goga engagement signal: True
Cost: $1.1921886000000002
Duration: 147274ms, turns: 34

## Agent's own summary

## Summary

Added a dedicated `.voiceMessage` case to `MediaBandwidthPreferences.MediaType`, giving voice messages their own on/never/Wi-Fi-only/Wi-Fi-and-cellular auto-download control, separate from generic audio:

1. **`MediaBandwidthPreferenceStore.swift`** — new `.voiceMessage` case with default `.wifiAndCellular` (this automatically gives it a UI row, persistence key, and reset behavior since the settings screens iterate `MediaType.allCases`).
2. **`AutoDownloadPolicy.swift`** — `build()` restructured so small voice messages still fast-path to `.always` (unchanged), but larger voice messages now resolve to `.preference(mediaType: .voiceMessage)` instead of `.preference(mediaType: .audio)`. Non-voice audio attachments are untouched.
3. **`AutoDownloadPolicyTest.swift`** — updated the pre-existing test expectation for a large voice message from `.audio` to `.voiceMessage`.
4. **`MediaDownloadSettingsViewController.swift`** + **`Localizable.strings`** — added the "Voice Messages" label row.
5. **`BackupArchiveAccountDataArchiver.swift`** — archive/restore switches resolve the new case to a no-op `break`, since the shared cross-client backup proto has no field for it yet.

Also updated both governing `CODEMANIFEST` files (`Downloads` and `Downloads/Preferences`) to describe the new case and behavior. `goga lint` stays clean at "cells: 52 errors: 0" before and after. This checkout has no working CocoaPods setup (nested `Pods/Pods/...` layout), so verification was via grep/read + `goga lint` rather than a compile.
