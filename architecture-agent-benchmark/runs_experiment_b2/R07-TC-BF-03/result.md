# R07-TC-BF-03

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $2.5062773999999997
Duration: 372181ms, turns: 73

## Agent's own summary

Implemented a new self-hosted-library tracker, **LibreReader**, following the established pattern for this app's existing self-hosted trackers:

**New files** (`app/src/main/java/eu/kanade/tachiyomi/data/track/librereader/`):
- `LibreReader.kt` — plain `BaseTracker` + `DeletableTracker` (id `12L`), 6 statuses including rereading, HTTP Basic Auth
- `LibreReaderApi.kt` — search, bind/find-or-create library link, update progress, delete, and an `authenticate()` check against `GET /api/auth/whoami`
- `LibreReaderInterceptor.kt` — attaches `Credentials.basic(username, password)` to every authenticated request
- `dto/LibreReaderDto.kt` — DTOs + mapping to `Track`/`TrackSearch`

**Modified**:
- `TrackerManager.kt` — registered `LibreReader` with a stable, never-reused id
- `TrackPreferences.kt` — added `trackApiUrl(tracker)` since this is the first tracker with a real, user-typed server URL (as opposed to Kavita/Komga/Suwayomi's fixed dummy-credential pairing with an installed source extension)
- `SettingsTrackingScreen.kt` — added a `requiresServerUrl` flag to the login dialog with a new "Server URL" field, and a `TrackerPreference` entry for LibreReader
- `i18n/.../base/strings.xml` — added `server_url` string
- `app/track` `CODEMANIFEST` — bumped tracker count ("eleven" → "twelve"); no contract shape changes were needed since this is exactly the documented extension point
- Added a placeholder `brand_librereader.xml` icon

Users can now log in with username/password + server URL, log out, see linked library entries via the existing generic "linked tracker" UI (no extra wiring needed there), and reading progress pushes to the server automatically as they read — all for free from the existing generic `Tracker` machinery.

Verified via `./gradlew :app:compileDebugKotlin`, `spotlessCheck` (one `spotlessApply` pass fixed an import-order nit), `:app:assembleDebug`, and `goga lint` (stayed at 12 cells / 0 errors) — all passing.
