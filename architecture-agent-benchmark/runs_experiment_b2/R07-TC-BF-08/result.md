# R07-TC-BF-08

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $2.6878034999999993
Duration: 386914ms, turns: 66

## Agent's own summary

## Summary

Added a new self-hosted tracker, **LibreReader**, to sync reading progress with a self-hosted library server, following Mihon's existing `Tracker`/`BaseTracker` extension point (documented in this repo's Goga `CODEMANIFEST` for `app/track`):

- **`data/track/librereader/`** — `LibreReader.kt` (plain `BaseTracker` + `DeletableTracker`, id `12L`), `LibreReaderApi.kt`, `LibreReaderInterceptor.kt` (HTTP Basic Auth), and `dto/LibreReaderModels.kt`. Login authenticates via a plain (non-interceptor) client before credentials are saved; progress push, refresh, search/bind, and delete all go through the API using the server's own `library_id` link-entry id.
- **`TrackerManager.kt`** — registered the new tracker.
- **`TrackPreferences.kt`** — added `trackApiUrl(tracker)` to persist the server URL.
- **`SettingsTrackingScreen.kt`** — added a `requiresServerUrl` flag to the login dialog with a new "Server URL" field, wired to save the URL before calling `login()`.
- Added the `server_url` string, a placeholder `brand_librereader.xml` icon, and bumped the tracker-count text in the `app/track` `CODEMANIFEST`.

Login/logout, per-manga "linked to LibreReader" visibility, and progress-push-on-read all work automatically since they're generic across every registered tracker — no extra wiring needed there.

Verified via `./gradlew :app:compileDebugKotlin`, `spotlessCheck`, `:app:assembleDebug`, and `goga lint` (12 cells, 0 errors) — all passed cleanly on the first attempt, no fixes required.
