# R07-TC-GC-07

Condition: goga_native_architecture
Base tag: condition-c-r07-v1
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $2.6736657000000004
Duration: 353918ms, turns: 66

## Agent's own summary

Memory updated. The MEMORY.md index entry already points to this file, so no change needed there.

## Summary

Added a self-hosted library-server tracker ("LibreReader") to sync reading progress, following Mihon's `Tracker`/`BaseTracker` extension point:

- **`app/src/main/java/eu/kanade/tachiyomi/data/track/librereader/`** — new tracker package: `LibreReader.kt` (plain `BaseTracker` + `DeletableTracker`, id `12L`), `LibreReaderApi.kt`, `LibreReaderInterceptor.kt` (HTTP Basic Auth), `dto/LRDto.kt`
- **`TrackerManager.kt`** — registered the new tracker
- **`TrackPreferences.kt`** — added `trackApiUrl(tracker)` preference for the server URL
- **`SettingsTrackingScreen.kt`** — added a `requiresServerUrl` field to the login dialog with a server-URL text field, wired `checkLogin()` to save the URL before logging in
- **`i18n/.../strings.xml`** — added `server_url` string
- **`brand_librereader.xml`** — placeholder icon
- **`data/track` CODEMANIFEST** — bumped tracker count "eleven" → "twelve"

Login/logout, per-manga "linked to LibreReader" visibility, and progress-push-on-read all come for free from the existing generic `Tracker` infrastructure once registered — no extra wiring needed.

Verified via `./gradlew :app:compileDebugKotlin`, `:app:spotlessCheck`, `:i18n:spotlessCheck`, `:app:assembleDebug`, and `goga lint` (stayed at 12 cells / 0 errors) — all passed.
