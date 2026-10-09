# R07-TA-B-06

Condition: baseline
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Cost: $1.8723667499999999
Duration: 226662ms, turns: 32

## Agent's own summary

The diff is clean and minimal. Summary of changes:

- **`domain/.../interactor/AddExtensionStore.kt`**: validates the URL with OkHttp's `toHttpUrlOrNull()` (only accepts well-formed `http`/`https` URLs) before ever calling `repository.insert()`, so no network request happens for empty, malformed, or non-http(s) input. Returns `Result.failure(InvalidExtensionStoreUrlException())` instead.
- **`domain/.../model/InvalidExtensionStoreUrlException.kt`** (new): marker exception, following the codebase's existing convention (`NoChaptersException`, `SourceNotInstalledException`, etc.).
- **`app/.../ExtensionStoresViewModel.kt`**: injects `Context` (same pattern used by other `@Inject` ViewModels like `MangaViewModel`), special-cases `InvalidExtensionStoreUrlException` in `createRepo()`'s failure handler to show a localized friendly message instead of the raw exception message; all other error paths are untouched.
- **`i18n/.../strings.xml`**: adds `extensionStoresScreen.addStore.invalidUrl` = "Enter a valid http:// or https:// URL".
- **`domain/src/test/.../AddExtensionStoreTest.kt`** (new): unit tests (JUnit5 + MockK + Kotest, matching this repo's existing test style) covering valid URL, blank, no scheme, non-http scheme, and malformed text — verifying the repository is never called for invalid input.

Both the manual "Add extension store" dialog and the deep-link confirm dialog flow through the same `createRepo()`/`AddExtensionStore`, so both get the fix. Add/refresh/remove behavior for valid repositories is untouched. Verified: `:domain:testDebugUnitTest` (all pass), `:app:compileDebugKotlin` (compiles, confirming DI wiring for the new `Context` param), and `spotlessKotlinCheck` for both modules all succeed.
