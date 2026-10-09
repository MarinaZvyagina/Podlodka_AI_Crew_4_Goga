# R10-TA-BF-09

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.25
Dangerous success: True
Goga engagement signal: True
Cost: $0.9467234999999999
Duration: 147042ms, turns: 35

## Agent's own summary

Added a dedicated `.voiceMessage` case to `MediaBandwidthPreferences.MediaType`, which gives it a UI row, persistence, and reset-to-default behavior for free (the settings screen and picker just iterate `MediaType.allCases`). Six files changed:

- **`MediaBandwidthPreferenceStore.swift`** — new `.voiceMessage` case, default `.wifiAndCellular` (matches audio's current default, preserving today's effective behavior).
- **`AutoDownloadPolicy.swift`** — the voice-message branch now keeps the small-size fast path (`.always`, unchanged) but falls through to `.preference(mediaType: .voiceMessage)` instead of `.audio` for larger voice messages. Regular audio attachments still map to `.preference(mediaType: .audio)`, untouched.
- **`AutoDownloadPolicyTest.swift`** — updated the one assertion that expected `.audio` for a large voice message to `.voiceMessage`.
- **`MediaDownloadSettingsViewController.swift`** + **`Localizable.strings`** — new picker row/label ("Voice Messages").
- **`BackupArchiveAccountDataArchiver.swift`** — added `.voiceMessage: break` no-ops to both the save and restore switches, since the shared cross-client backup proto has no field for it (can't unilaterally add one).

`goga schema`/`goga lint` confirmed this area (Attachments/Downloads/Preferences) isn't one of the repo's 10 documented cells, and lint stayed clean (10 cells, 0 errors) before and after — so this was implemented via direct edits rather than a goga-change/CODEMANIFEST workflow, correctly outside its governed surface. No CocoaPods installed in this checkout, so I verified by grep/read of all exhaustive `MediaType` switches rather than a real build.
