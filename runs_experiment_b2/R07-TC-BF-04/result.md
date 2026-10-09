# R07-TC-BF-04

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $2.6214245999999997
Duration: 322582ms, turns: 62

## Agent's own summary

## Summary

Added a new self-hosted tracker integration, **LibreReader**, to Mihon's tracker extension point at `app/src/main/java/eu/kanade/tachiyomi/data/track/`:

- **`librereader/LibreReader.kt`** — plain `BaseTracker` + `DeletableTracker` (id `12L`), with real username/password login, server URL support, status mapping (Reading/Completed/On hold/Dropped/Plan to read), and progress-push-on-read via the standard `update()`/`bind()`/`refresh()` contract.
- **`librereader/LibreReaderApi.kt`** — HTTP client for the self-hosted server: `authenticate()` (Basic Auth credential check via `GET /api/auth/whoami`, using a plain non-interceptor client so it works before credentials are saved), search, find/add/update/delete library entries.
- **`librereader/LibreReaderInterceptor.kt`** — attaches HTTP Basic Auth to authenticated requests.
- **`librereader/dto/LibreReaderDto.kt`** — DTOs for user, series, and library entries.
- **`brand_librereader.xml`** — placeholder icon.
- Registered in `TrackerManager`, added `TrackPreferences.trackApiUrl(tracker)`, wired a server-URL field into `SettingsTrackingScreen`'s login dialog (only shown for trackers that need it, so existing OAuth/Kitsu/MangaUpdates logins are untouched), added the `server_url` string, and bumped the tracker-count note in the `data/track` CODEMANIFEST.

Users can now log in/out with a server URL + username/password, see which library entries are linked (for free, via the existing generic tracker UI), and progress syncs automatically as chapters are read.

Verified via `goga lint` (12 cells/0 errors, unchanged), `:app:compileDebugKotlin`, `:app:spotlessCheck`, `:i18n:spotlessCheck`, and `:app:assembleDebug` — all passed with zero fixes needed.
