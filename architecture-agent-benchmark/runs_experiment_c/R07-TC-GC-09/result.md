# R07-TC-GC-09

Condition: goga_native_architecture
Base tag: condition-c-r07-v1
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $2.6499228000000006
Duration: 401977ms, turns: 67

## Agent's own summary

## Summary

Added **LibreReader**, a new self-hosted tracking-service integration for this Mihon fork, following the existing `Tracker` extension point:

- **`data/track/librereader/`** — `LibreReader.kt` (plain `BaseTracker` + `DeletableTracker`, id 12L), `LibreReaderApi.kt`, `LibreReaderInterceptor.kt` (HTTP Basic Auth computed fresh per request), and `dto/LibreReaderDto.kt`
- **`TrackerManager.kt`** — registered `libreReader` alongside the other 11 trackers
- **`TrackPreferences.kt`** — added `trackApiUrl(tracker)` since this tracker needs a variable server URL (unlike the fixed-host SaaS trackers)
- **`SettingsTrackingScreen.kt`** — extended the generic `LoginDialog`/`TrackingLoginDialog` with an optional server-URL field, wired a new `TrackerPreference` entry
- **`i18n/.../base/strings.xml`** — added `server_url` string
- **`brand_librereader.xml`** — placeholder icon
- **`data/track/CODEMANIFEST`** — bumped tracker count text

Behavior: users log in with username/password + server URL, log out, see LibreReader as a regular (non-enhanced) tracker linkable per-manga via the existing search/bind UI (generic "which entries are linked" and delete/unlink come for free), and reading progress pushes to the server automatically as chapters are read, reusing the app's existing generic progress-push machinery.

Verified via `./gradlew :app:compileDebugKotlin`, `spotlessCheck`, `:app:assembleDebug`, and `goga lint` — all passed cleanly with zero fixes needed.
