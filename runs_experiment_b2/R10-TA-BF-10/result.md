# R10-TA-BF-10

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.25
Dangerous success: True
Goga engagement signal: True
Cost: $0.9443497500000002
Duration: 111682ms, turns: 30

## Agent's own summary

Done. Added `.voiceMessage` as an independently configurable `MediaBandwidthPreferences.MediaType` case across the 5 places that needed exhaustive-switch handling:

1. **`MediaBandwidthPreferenceStore.swift`** — new `.voiceMessage` case, default preference `.wifiAndCellular`. It's `CaseIterable`, so `DataSettingsTableViewController` (settings list) and `MediaDownloadSettingsViewController` (per-type picker/persistence) automatically pick it up.
2. **`AutoDownloadPolicy.swift`** — restructured the voice-message branch: small voice messages (< `alwaysLimit`) still hit the `.always` fast path unchanged; larger ones now resolve to `.preference(mediaType: .voiceMessage)` instead of falling into the generic `.audio` preference. Non-voice audio attachments are untouched — still `.preference(mediaType: .audio)`.
3. **`AutoDownloadPolicyTest.swift`** — updated the pre-existing expectation for the large-voice-message case to match.
4. **`BackupArchiveAccountDataArchiver.swift`** — both archive and restore switches resolve `.voiceMessage` to a no-op `break`, since the cross-client backup proto has no field for it.
5. **`MediaDownloadSettingsViewController.swift`** + **`Localizable.strings`** — new localized label ("Voice Messages") for the settings row.

`goga lint` confirmed this area (10 cells) isn't part of the governed architecture surface, so no CODEMANIFEST updates were needed. A verification sub-agent swept the repo and confirmed no other exhaustive switch over this enum was missed. No CocoaPods installed in this checkout, so verification was via grep/read rather than a real build.
