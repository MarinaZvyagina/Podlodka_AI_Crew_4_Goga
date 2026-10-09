# R10-TA-BF-03

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.25
Dangerous success: True
Goga engagement signal: True
Cost: $0.6475643999999999
Duration: 68507ms, turns: 26

## Agent's own summary

Confirmed — no explicit switch there, it just drives off `allCases`, so it automatically gets the new row for free. All five files plus the localization string are updated consistently.

## Summary

Added `.voiceMessage` as an independent `MediaBandwidthPreferences.MediaType` case, wired through every place Swift's switch-exhaustiveness required an explicit update:

1. **`MediaBandwidthPreferenceStore.swift`** — new `.voiceMessage` case with default `.wifiAndCellular` (matches audio's prior default, preserving current effective behavior until users opt to change it). This automatically gives it a settings row, persistence key, and reset-to-default handling via the existing `allCases`-driven UI and reset logic.
2. **`AutoDownloadPolicy.swift`** — the voice-message branch now falls through to `.preference(mediaType: .voiceMessage)` instead of `.audio` for downloads above `Constants.alwaysLimit`, while the small-size fast path (`.always` for anything under the limit) is unchanged. Regular audio attachments (non-voice-message rendering flag) still map to `.audio` untouched.
3. **`AutoDownloadPolicyTest.swift`** — updated the large-voice-message test expectation from `.preference(mediaType: .audio)` to `.preference(mediaType: .voiceMessage)`.
4. **`MediaDownloadSettingsViewController.swift`** — added the localized-name case and new `OWSLocalizedString` key.
5. **`BackupArchiveAccountDataArchiver.swift`** — both archive and restore switches resolve `.voiceMessage` to `break`/no-op, since the cross-client `BackupProto_AccountData.AutoDownloadSettings` proto has no dedicated field for it (can't unilaterally add one to a shared spec).
6. **`Localizable.strings`** — added `SETTINGS_MEDIA_DOWNLOAD_TYPE_VOICE_MESSAGE` = "Voice Messages", alphabetically placed.

Confirmed via `goga schema`/`goga lint` that this Attachments/Downloads/Preferences area isn't covered by any of this checkout's 10 governed cells, so goga's contract workflow doesn't apply here (consistent with the identical outcome in prior sibling checkouts of this same task). No CocoaPods installed in this checkout, so verification was done via targeted grep/read rather than a real build — all touched code matches the previously-verified working pattern exactly.
