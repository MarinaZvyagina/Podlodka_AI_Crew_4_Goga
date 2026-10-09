# R07-TC-GC-02

Condition: goga_native_architecture
Base tag: condition-c-r07-v1
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $2.0083221
Duration: 310951ms, turns: 55

## Agent's own summary

Added a self-hosted-server tracker ("LibreReader") to `app/src/main/java/eu/kanade/tachiyomi/data/track/librereader/`:

- **`LibreReader.kt`** — plain `BaseTracker` + `DeletableTracker` (id `12L`), HTTP Basic Auth via a per-request `Interceptor`, status vocabulary (Reading/Completed/On hold/Dropped/Plan to read), 0-10 score scale.
- **`LibreReaderApi.kt`** / **`LibreReaderInterceptor.kt`** / **`dto/LibreReaderDto.kt`** — REST calls for search, link/bind, update, refresh, delete, and a credential-check `authenticate()` call made on a separate non-interceptor client before credentials are saved.
- **`TrackerManager.kt`** — registered as the 12th tracker.
- **`TrackPreferences.kt`** — new `trackApiUrl(tracker)` preference for the server URL.
- **`SettingsTrackingScreen.kt`** — added a `requiresServerUrl` flag to the login dialog with a new "Server URL" field, wired only for LibreReader; login/logout dialogs and the per-manga "linked trackers" UI are fully generic so they needed no changes.
- Added the `server_url` string resource and a placeholder `brand_librereader.xml` icon, and bumped the tracker-count text in the `data/track` CODEMANIFEST.

Since this integration is a plain (non-`EnhancedTracker`) tracker, users link library entries manually via the existing generic search/link flow — same as MangaUpdates — and progress-push-on-read, login/logout, and "which entries are linked" are all handled by the existing generic tracker machinery.

Verified via `./gradlew :app:compileDebugKotlin`, `spotlessCheck` (one `spotlessApply` pass needed for line-wrap), `:app:assembleDebug`, and `goga lint` (stayed at `cells: 12 errors: 0`) — all green.
