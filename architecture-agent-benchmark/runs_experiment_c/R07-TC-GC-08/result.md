# R07-TC-GC-08

Condition: goga_native_architecture
Base tag: condition-c-r07-v1
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $2.9304039000000004
Duration: 395116ms, turns: 73

## Agent's own summary

`library_id` is already generically persisted end-to-end (DB ↔ domain ↔ database model), confirming the design is fully wired without further plumbing.

## Summary

Added a new self-hosted-library tracker, **LibreReader**, following this repo's existing `Tracker`/`BaseTracker` extension point:

- **`data/track/librereader/`** — `LibreReader.kt` (plain `BaseTracker` + `DeletableTracker`, id `12L`), `LibreReaderApi.kt`, `LibreReaderInterceptor.kt` (HTTP Basic Auth, credentials read fresh per request), and `dto/` (search results, library entries, whoami response).
- **Login**: username/password + a server URL field, verified via a pre-credential-save `GET /api/auth/whoami` call over a plain (non-interceptor) client, matching the pattern used by MangaBaka/MangaUpdates for other real-login trackers here.
- **`TrackPreferences.trackApiUrl(tracker)`** — new preference to store the server URL per tracker.
- **`SettingsTrackingScreen.kt`** — `LoginDialog` gained a `requiresServerUrl` flag that renders an extra "Server URL" field; wired a new `TrackerPreference` entry into the existing "Services" group.
- **Progress sync, logout, and "linked entries" visibility** all come for free — those flows in `BaseTracker`/`TrackInfoDialog.kt` are generic across every registered tracker, so no extra work was needed there.
- Added the `server_url` string, a placeholder `brand_librereader.xml` icon, and bumped the tracker-count text in the `data/track` CODEMANIFEST ("eleven" → "twelve").

Verified with `./gradlew :app:compileDebugKotlin`, `spotlessCheck`, `:app:assembleDebug`, and `goga lint` (stayed at 12 cells / 0 errors) — all passed offline with no fixes needed.
