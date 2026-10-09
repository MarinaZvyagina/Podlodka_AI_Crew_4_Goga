# R07-TC-GC-01

Condition: goga_native_architecture
Base tag: condition-c-r07-v1
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $2.7724479000000004
Duration: 432145ms, turns: 75

## Agent's own summary

The MEMORY.md index already points to this file, so no update needed there. Implementation is complete and verified.

## Summary

Added a new self-hosted-library tracker, **LibreReader**, to this Mihon app under `app/src/main/java/eu/kanade/tachiyomi/data/track/librereader/`:

- **`LibreReader.kt`** — plain `BaseTracker` + `DeletableTracker` (no source-extension pairing needed), with real username/password + server-URL login, HTTP Basic Auth, status tracking (unread/reading/completed), and `library_id`-based link tracking distinct from the series' `remote_id`.
- **`LibreReaderApi.kt`** / **`LibreReaderInterceptor.kt`** / **`dto/LibreReaderDto.kt`** — REST client: search, find/create/update/delete a library link, plus a separate non-authenticated client call for the initial login credential check.
- **`TrackPreferences.trackApiUrl(tracker)`** — new preference for the server URL.
- **`SettingsTrackingScreen.kt`** — login dialog gained an optional "Server URL" field (`requiresServerUrl` flag), wired for LibreReader only; other trackers unaffected.
- **`TrackerManager.kt`** — registered as tracker id `12L`.
- New `server_url` string resource and a placeholder `brand_librereader.xml` icon.

Once logged in, per-manga linking, unlink (delete), and progress-push-on-read all work automatically through the existing generic tracker machinery (`TrackInfoDialog`, `ReaderViewModel`) — no extra wiring needed, matching how MangaUpdates/AniList already work.

Verified via `./gradlew :app:compileDebugKotlin`, `spotlessCheck`, `:app:assembleDebug`, and `goga lint` (this repo has Goga cell contracts — the `data/track` CODEMANIFEST already documents this exact extension point, so I only bumped its tracker-count text; `goga lint` still reports 0 errors).
