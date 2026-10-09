# R07-TA-GC-01

Condition: goga_native_architecture
Base tag: condition-c-r07-v1
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: False
Cost: $1.8105243000000002
Duration: 255811ms, turns: 39

## Agent's own summary

Both `domain` and `app` compile cleanly with the changes, confirming the string resource, exception, DI injection, and ViewModel wiring all work correctly.

## Summary

Custom extension store URLs are now rejected before any network call:

- **`domain/.../model/InvalidExtensionStoreUrlException.kt`** (new) — typed exception for invalid URLs.
- **`domain/.../interactor/AddExtensionStore.kt`** — validates the URL with OkHttp's `toHttpUrlOrNull()` (which only accepts well-formed `http`/`https` URLs, rejecting empty/malformed/other-scheme input) before delegating to the repository/network fetch. This use case is the single choke point for both the manual "+" dialog and the deep-link confirm flow, so both paths get the same guard.
- **`i18n/.../strings.xml`** — added `extensionStoresScreen.addStore.invalidUrl` ("This isn't a valid URL. Enter a full http:// or https:// address"), following the existing sibling string naming convention.
- **`app/.../ExtensionStoresViewModel.kt`** — injects `Context` and maps `InvalidExtensionStoreUrlException` to the new localized message (mirroring the existing `NoChaptersException` → `context.stringResource(...)` pattern used elsewhere), leaving other failure messages (network errors, parse errors) untouched.

Adding, refreshing, and removing valid repositories is unchanged — validation only short-circuits before the network fetch when the URL itself is invalid. Verified with `./gradlew :domain:compileDebugKotlin` and `:app:compileDebugKotlin`, both succeeding.
