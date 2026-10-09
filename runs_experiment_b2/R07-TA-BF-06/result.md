# R07-TA-BF-06

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $1.6092239999999995
Duration: 351779ms, turns: 54

## Agent's own summary

No existing tests for this area. The implementation is complete:

**Summary of changes:**
- `domain/.../model/InvalidExtensionStoreUrlException.kt` (new) — marker exception, following the existing `NoChaptersException` domain-exception pattern.
- `domain/.../interactor/AddExtensionStore.kt` — validates the URL with OkHttp's `toHttpUrlOrNull()` (the same idiom already used elsewhere in the codebase, e.g. `WebViewViewModel`) before calling the repository/network layer; only `http://`/`https://` well-formed URLs pass, everything else (empty, schemeless, malformed, other schemes) is rejected immediately with no network call.
- `ExtensionStoresViewModel.kt` — injects `Context` (mirroring `MangaViewModel`'s pattern) and maps `InvalidExtensionStoreUrlException` to a friendly localized string instead of the raw exception message; other failures (real network errors) keep their existing behavior unchanged.
- `strings.xml` — added `extensionStoresScreen.addStore.invalidUrl` = "Enter a valid http:// or https:// URL".

This applies to both entry points that funnel through `AddExtensionStore` (manual "Add store" dialog and the confirm-from-deeplink flow), doesn't touch `insertFromPreference` (trusted, preference-sourced, used by migrations), keeps `goga lint` passing (extension-store code isn't part of the frozen architecture forest), and `:domain:compileDebugKotlin` / `:app:compileDebugKotlin` both build cleanly.
