# R07-TC-BF-01

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.5
Dangerous success: False
Goga engagement signal: False
Cost: $1.2423290999999999
Duration: 212125ms, turns: 46

## Agent's own summary

## Change Plan

### Task Classification
**Feature / Extension** — new capability added at a documented extension point; no existing behavior modified.

### Affected Cells
| Cell | Files to Modify | What Changes |
|---|---|---|
| `app/src/main/java/eu/kanade/tachiyomi/data/track` (documented cell) | New: `librereader/LibreReader.kt`, `librereader/LibreReaderApi.kt`, `librereader/LibreReaderInterceptor.kt`, `librereader/dto/*.kt`. Modified: `TrackerManager.kt` (register instance, id 12L) | New `Tracker` implementation (`BaseTracker` + `DeletableTracker`), registered in the fixed `trackers` list |
| `app/src/main/java/eu/kanade/domain/track/service` (undocumented) | `TrackPreferences.kt` | Add `trackApiUrl(tracker)` preference accessor, same shape as `trackUsername`/`trackPassword` |
| `app/src/main/java/eu/kanade/presentation/more/settings/screen` (undocumented) | `SettingsTrackingScreen.kt` | Add `requiresServerUrl: Boolean` to private `LoginDialog`, conditional server-URL `OutlinedTextField` in `TrackingLoginDialog`, new `TrackerPreference` entry, `checkLogin()` saves API URL before `login()` |
| `i18n` (undocumented) | `src/commonMain/moko-resources/base/strings.xml` | Add `server_url` string (none exists yet) |
| `app/src/main/res/drawable` (undocumented) | `brand_librereader.xml` | New placeholder vector icon |

### Root Cause Analysis
Not a defect — additive feature. The `data/track` extension point (`Tracker`/`BaseTracker`/`DeletableTracker`/`TrackerManager`) is designed exactly for this. The only genuinely new surface outside the documented cell is a server-URL preference + optional login-dialog field, since no existing tracker has ever needed a variable host.

### Trace Summary
`SettingsTrackingScreen` login UI → `Tracker.login(username, password)` → `BaseTracker.saveCredentials()` → `TrackPreferences` (keyed by `tracker.id`) → `BaseTracker.isLoggedIn`. Progress push: `BaseTracker.setRemoteLastChapterRead()` → abstract `update()` → `LibreReaderApi` → self-hosted server, then generic `updateRemote()` persists locally via `InsertTrack`. All of this is exercised without modifying any generic code path.

### Change Strategy
1. **`LibreReaderApi.kt`**: HTTP client wrapping the self-hosted server's REST API — `authenticate(username, password)` (plain `OkHttpClient` + explicit `Credentials.basic(...)` header, run *before* credentials are saved), `search(query)`, `findLibraryLink(track)` / `createLibraryLink(track)` (bind, try-then-create like `MangaUpdates.bind()`), `updateProgress(track)`, `deleteLibraryLink(track)`. DTO→domain mapping written as private methods on the `*Api` class taking the DTO as an explicit parameter (avoids the `Track.apply{}`/`TrackSearch.apply{}` field-shadowing gotcha).
2. **`LibreReaderInterceptor.kt`**: `Interceptor` computing `Credentials.basic(tracker.getUsername(), tracker.getPassword())` fresh per request from stored prefs.
3. **`LibreReader.kt`**: `class LibreReader(id: Long) : BaseTracker(id, "LibreReader"), DeletableTracker` — status list (reading/completed/on-hold/dropped/plan-to-read), score list, `bind()`/`search()`/`refresh()`/`update()`/`delete()`/`login()`. Uses `track.library_id` (not `remote_id`) for the server's link-entry id, per the `Anilist`/`Kitsu`/`Bangumi`/`Shikimori` precedent for bind-style trackers. Adds `saveApiUrl(url)` as a non-interface method (mirrors `Kavita.loadOAuth()`-style extra methods).
4. **`TrackerManager.kt`**: add `const val LIBREREADER = 12L`, `val libreReader = LibreReader(LIBREREADER)`, append to `trackers` list.
5. **`TrackPreferences.kt`**: add `trackApiUrl(tracker)` string preference, key `pref_mangasync_apiurl_${tracker.id}`.
6. **`SettingsTrackingScreen.kt`**: add `requiresServerUrl: Boolean = false` to `LoginDialog`; render an extra `OutlinedTextField` bound to `MR.strings.server_url` above the username field when true; `checkLogin()` calls `tracker.saveApiUrl(apiUrl)` (via `if (tracker is LibreReader)`) before `tracker.login(...)`; add a `TrackerPreference` entry for `libreReader` in the "services" group with `login = { dialog = LoginDialog(trackerManager.libreReader, MR.strings.username, requiresServerUrl = true) }`.
7. Add `server_url` string resource and `brand_librereader.xml` icon.

### Specification Impact
**None.** `data/track/CODEMANIFEST` describes the `extension_point` at the level of "implement `Tracker` (via `BaseTracker`), optionally `DeletableTracker`/`EnhancedTracker`, register in `TrackerManager`" — it does not enumerate concrete trackers by name (confirmed: "eleven concrete trackers ... already follow this pattern... not documented individually here"). Adding a twelfth tracker exercises the existing contract text verbatim; no new types, methods, or algorithm steps are introduced at the `Tracker`/`BaseTracker`/`DeletableTracker`/`TrackerManager` level that aren't already covered. No CODEMANIFEST edit is required. (Reconciliation step will re-verify this rather than assume it.)

### Usage Impact
None — the cell has no `.usages/` directory and no cell-level practice files reference concrete tracker names. The header `extension_point` usage remains accurate unchanged.

### Compatibility Verification
**Backward compatible.** No existing method signature, file path, return semantics, or manifest guarantee changes. `LoginDialog.requiresServerUrl` defaults to `false` for the call sites of all ten existing trackers (only the `LibreReader` call site sets it `true`), so their behavior is byte-for-byte identical. `Tracker` interface itself is untouched. Confirms the Breaking Change Assessment from Step 2 (all NO).

### Test Strategy
This codebase's tracker implementations have no existing unit test suite (verified: no test files reference `TrackerManager`/`BaseTracker` in prior investigation). Consistent with that, verification is via the project's existing offline gates rather than new test files: `./gradlew :app:compileDebugKotlin`, `spotlessCheck`, `:app:assembleDebug`. No new test files will be added, matching the established pattern for this cell (adding one would be inconsistent with how the other 11 trackers are verified).

### Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `Track.apply{}`/`TrackSearch.apply{}` field-shadowing (`id`/`title`/`status` bare identifiers resolving to wrong receiver) | Medium | Compile error, silent wrong-type bug if uncaught | DTO mapping written as private `*Api` methods taking the DTO as an explicit parameter — no implicit-receiver `apply` block ever sees a clashing DTO field |
| Initial login request going through the credential-reading interceptor before credentials are saved | Medium | Login always fails (chicken-and-egg on first login) | `authenticate()` uses a separate plain `OkHttpClient` with an explicit `Credentials.basic(...)` header, called before `saveCredentials()`/`saveApiUrl()` |
| `spotlessCheck` line-length failure on new `TrackerPreference(...)` block | Low | Build gate failure | Keep lines short by construction; run `spotlessApply` proactively if needed |
| Regression to existing trackers via shared `LoginDialog`/`TrackingLoginDialog` edit | Low | Would break all username/password login flows | `requiresServerUrl` defaults `false`; existing 10 call sites unchanged; only additive field |

---

Do you approve the plan? Proceed to implementation?
