# R07-TC-BF-07

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $2.6860857
Duration: 314996ms, turns: 65

## Agent's own summary

Implementation complete. I added a **LibreReader** tracker (`app/src/main/java/eu/kanade/tachiyomi/data/track/librereader/`) as a plain `BaseTracker` + `DeletableTracker`:

- **`LibreReader.kt`** — tracker identity/status mapping, `login()`/`logout()`/`delete()`, `bind()`/`refresh()` modeled after MangaBaka's find-then-adjust shape.
- **`LibreReaderApi.kt`** — HTTP calls (`GET /api/auth/whoami` for credential checks, series search, and library-entry CRUD), reads the server URL fresh per-request via `libreReader.getApiUrl()`.
- **`LibreReaderInterceptor.kt`** — HTTP Basic Auth applied per-request from stored credentials.
- **`dto/LRModels.kt`** — DTOs for user/series/search/library-entry payloads.

Plumbing changes:
- `TrackPreferences.trackApiUrl(tracker)` — new preference for the server URL (base URL isn't part of the `Tracker.login()` signature).
- `TrackerManager` — registered as id `12L`.
- `SettingsTrackingScreen.kt` — added a `requiresServerUrl` flag to the login dialog so LibreReader's login form shows a server-URL field ahead of username/password; the URL is saved before `login()` is called.
- `server_url` string added to `i18n`, plus a placeholder `brand_librereader.xml` icon.
- Bumped the `data/track` CODEMANIFEST's tracker count.

"Log in/out" and "which library entries are linked" come for free from the existing generic `TrackInfoDialog`/`DeletableTracker` machinery, and progress-push-on-read is automatic via `BaseTracker.update()`, so no reader/library-view code needed to change.

Verified via `./gradlew :app:compileDebugKotlin`, `:app:spotlessCheck`, `:i18n:spotlessCheck`, `:app:assembleDebug`, and `goga lint` (stayed at 12 cells / 0 errors) — all passed offline.
