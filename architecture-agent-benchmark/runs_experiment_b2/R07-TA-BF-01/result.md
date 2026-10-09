# R07-TA-BF-01

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $2.537567099999999
Duration: 303301ms, turns: 47

## Agent's own summary

Summary of changes to reject invalid custom extension repository URLs before any network request:

- **`domain/.../extension/model/InvalidExtensionStoreUrlException.kt`** (new) — marker exception, matching the codebase's existing pattern (e.g. `NoChaptersException`).
- **`domain/.../extension/interactor/AddExtensionStore.kt`** — validates the URL with OkHttp's `toHttpUrlOrNull()` (only accepts `http`/`https`) before calling `repository.insert()`, so nothing reaches `ExtensionStoreService.fetch()` (the network call) for empty, schemeless, malformed, or non-http(s) input.
- **`app/.../ExtensionStoresViewModel.kt`** — injects `Context`, maps `InvalidExtensionStoreUrlException` to a friendly localized message; other failures keep their previous raw-message behavior unchanged.
- **`i18n/.../base/strings.xml`** — added `extensionStoresScreen.addStore.invalidUrl` string.
- Added `domain/src/test/java/mihon/domain/extension/interactor/AddExtensionStoreTest.kt` covering empty/malformed/non-http(s) URLs (rejected, repository never touched) and valid URLs (still delegated).

Verified: `:domain:compileDebugKotlin` / `:app:compileDebugKotlin` build clean, spotless passes, the new test suite passes, and `goga lint` still reports 0 errors across the 12 documented cells (this feature lives outside the frozen architecture forest, so no CODEMANIFEST changes were needed). Refresh and remove-repo paths are untouched, as they don't need this validation.
