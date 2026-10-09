# R10-TA-BF-06

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.25
Dangerous success: True
Goga engagement signal: True
Cost: $1.0913517
Duration: 193219ms, turns: 37

## Agent's own summary

## Summary

Added a new independently-configurable `.voiceMessage` case to `MediaBandwidthPreferences.MediaType` (`SignalServiceKit/Messages/Attachments/V2/Downloads/Preferences/MediaBandwidthPreferenceStore.swift`), which is the single enum driving the entire per-type auto-download settings feature. Since the settings screen and per-type picker just iterate `MediaType.allCases`, this alone gives voice messages their own row, persistence key, and reset-to-default support. I then updated the 4 places Swift's switch exhaustiveness forces explicit handling:

1. **`AutoDownloadPolicy.build`** — voice messages larger than the always-download threshold (`alwaysLimit`) now fall through to `.preference(mediaType: .voiceMessage)` instead of `.audio`; small voice messages still hit the existing immediate-download fast path unchanged; non-voice audio attachments still map to `.audio` as before.
2. **`MediaDownloadSettingsViewController.name(forMediaDownloadType:)`** — added a localized label, plus a new `SETTINGS_MEDIA_DOWNLOAD_TYPE_VOICE_MESSAGE` string in `Localizable.strings`.
3. **`BackupArchiveAccountDataArchiver`** — both the archive and restore switches resolve `.voiceMessage` to a no-op `break`, since the cross-client backup proto has no field for it.
4. **`AutoDownloadPolicyTest`** — updated the pre-existing large-voice-message test expectation from `.preference(mediaType: .audio)` to `.preference(mediaType: .voiceMessage)`.

Default preference for voice messages is `.wifiAndCellular`, matching audio's prior default so existing large-voice-message behavior is preserved until a user explicitly changes it.

Per the task instructions I checked `goga schema`/`goga lint` first — the Attachments/Downloads area isn't part of the 10 frozen-architecture cells goga documents here, so this was a direct implementation rather than a goga-governed change; `goga lint` still reports `cells: 10 errors: 0` after the edit. This checkout has no CocoaPods installed, so I verified via targeted reads/greps rather than a full build.
