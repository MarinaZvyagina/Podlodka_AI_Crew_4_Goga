# R10-TA-GC-03

Condition: goga_native_architecture
Base tag: condition-c-r10-v1
Functional success: True
Full architecture conformance: False
ACR: 0.25
Dangerous success: True
Goga engagement signal: True
Cost: $0.7939299
Duration: 93578ms, turns: 28

## Agent's own summary

Done. Added a new `.voiceMessage` case to `MediaBandwidthPreferences.MediaType` and wired it through everywhere the enum is used:

1. **`MediaBandwidthPreferenceStore.swift`** — new case with default `.wifiAndCellular` (matching audio's prior default, preserving today's effective behavior for large voice messages).
2. **`AutoDownloadPolicy.swift`** — the `.body` context handler now keeps the small-voice-message fast path (`.always` below `alwaysLimit`) but falls through to `.preference(mediaType: .voiceMessage)` instead of `.audio` for larger ones. Non-voice audio attachments still map to `.preference(mediaType: .audio)`, unchanged.
3. **`AutoDownloadPolicyTest.swift`** — updated the large-voice-message test expectation to `.voiceMessage`.
4. **`MediaDownloadSettingsViewController.swift`** + **`Localizable.strings`** — new "Voice Messages" row/label in the settings screen (it appears automatically since the screen iterates `MediaType.allCases`).
5. **`BackupArchiveAccountDataArchiver.swift`** — both archive and restore switches handle `.voiceMessage` as a no-op `break`, since the cross-client backup proto has no field for it yet.
6. Updated both `CODEMANIFEST` files under `Downloads/` and `Downloads/Preferences/` to describe the new case, since this checkout is goga-governed for this subtree.

`goga lint` stays clean (52 cells, 0 errors) before and after. No CocoaPods installed in this checkout, so verification was via grep/read plus `goga lint` rather than a full build.
