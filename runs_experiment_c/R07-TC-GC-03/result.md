# R07-TC-GC-03

Condition: goga_native_architecture
Base tag: condition-c-r07-v1
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $2.813672999999999
Duration: 459529ms, turns: 64

## Agent's own summary

Memory index already points to this file, so no change needed there. Everything's implemented and verified.

## Summary

Added a new self-hosted-library tracker, **LibreReader**, to `eu.kanade.tachiyomi.data.track.librereader`:

- **`LibreReader.kt`** — plain `BaseTracker` + `DeletableTracker`, id `12L`, registered in `TrackerManager`
- **`LibreReaderApi.kt`** / **`LibreReaderInterceptor.kt`** — HTTP Basic Auth via a per-request interceptor; login does a separate unauthenticated credential check before saving credentials
- **`dto/LRSeries.kt`**, **`dto/LRLibraryEntry.kt`** — search results and library-entry (progress) payloads
- **`TrackPreferences.trackApiUrl(tracker)`** — new preference for the server URL
- **`SettingsTrackingScreen.kt`** — login dialog now conditionally shows a "Server URL" field (`requiresServerUrl`), and the tracker list gained a LibreReader entry alongside the existing ones
- Added the `server_url` string resource and a placeholder `brand_librereader.xml` icon
- Bumped the tracker-count text in the `data/track` CODEMANIFEST

Users can log in (username/password + server URL), log out, and see LibreReader linked entries via the existing generic `TrackInfoDialog`/search-and-link flow — same mechanism every other tracker uses, so no extra UI work was needed there. Progress push-on-read is likewise automatic via the existing `update()` dispatch.

Verified with `:app:compileDebugKotlin`, `spotlessCheck`, `:app:assembleDebug`, and `goga lint` — all passed clean with zero fixes needed.
