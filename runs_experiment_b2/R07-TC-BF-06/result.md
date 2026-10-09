# R07-TC-BF-06

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $2.8372683000000007
Duration: 420141ms, turns: 71

## Agent's own summary

I've implemented self-hosted server sync support for Mihon:

**What was added** — a new "LibreReader" tracker (`app/src/main/java/eu/kanade/tachiyomi/data/track/librereader/`):
- `LibreReader.kt` — plain `BaseTracker` + `DeletableTracker`, id 12L, statuses reading/completed/on-hold/dropped/plan-to-read
- `LibreReaderApi.kt` / `LibreReaderInterceptor.kt` — HTTP Basic Auth against a configurable server URL, with a separate unauthenticated request for the initial login check
- `dto/LRSeries.kt`, `dto/LRLibraryEntry.kt` — search results and library-link entries

**Wiring:**
- Registered in `TrackerManager.kt`
- Added `TrackPreferences.trackApiUrl(tracker)` for the per-tracker server URL
- `SettingsTrackingScreen.kt` — added a `requiresServerUrl` flag/field to the generic login dialog so LibreReader's login form shows a Server URL field alongside username/password; existing OAuth/username-password trackers (Kitsu, MangaUpdates, etc.) are untouched
- Added `server_url` string, a placeholder `brand_librereader.xml` icon, and bumped the `data/track` CODEMANIFEST's tracker count

Because linking/unlinking per manga and progress-push-on-read are already generic in Mihon's tracker system, login/logout, "which entries are linked," and progress sync all work for free once registered.

Verified: `goga lint` (12 cells, 0 errors, unchanged), `:app:compileDebugKotlin`, `spotlessCheck`, and `:app:assembleDebug` all passed with zero fixes needed.
