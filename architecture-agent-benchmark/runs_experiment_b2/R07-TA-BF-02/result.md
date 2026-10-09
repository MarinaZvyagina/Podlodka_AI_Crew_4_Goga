# R07-TA-BF-02

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: False
Cost: $2.465819700000001
Duration: 333899ms, turns: 58

## Agent's own summary

Done. Custom extension repository URLs are now validated before any network call:

- **`domain/.../interactor/AddExtensionStore.kt`** — checks the URL with OkHttp's `toHttpUrlOrNull()` (the same idiom already used elsewhere in this codebase for URL validation); only `http://`/`https://` URLs with a valid host pass. Anything else (blank, no scheme, wrong scheme like `ftp:`/`javascript:`, malformed text) short-circuits to `Result.failure(InvalidExtensionStoreUrlException())` before `ExtensionStoreRepository.insert()` — and thus the network fetch — is ever reached.
- **`domain/.../model/InvalidExtensionStoreUrlException.kt`** — new marker exception, following the same plain-exception pattern already used for `NoChaptersException`.
- **`ExtensionStoresViewModel.kt`** — maps that exception to a friendly localized message (`context.stringResource(...)`, mirroring the pattern in `MangaViewModel`) instead of leaking the raw exception message; all other failures still fall back to `throwable.message` as before.
- **`strings.xml`** — added `extensionStoresScreen.addStore.invalidUrl` = "Enter a valid http:// or https:// URL".

Both the manual "Add store" dialog and the deeplink-confirm flow go through `AddExtensionStore`, so both are covered. Added `AddExtensionStoreTest.kt` covering blank/malformed/wrong-scheme/no-host inputs (all rejected without touching the repository) and valid http/https inputs (delegated through unchanged). Verified: `:domain:testDebugUnitTest` passes, `:domain:compileDebugKotlin` and `:app:compileDebugKotlin` build clean, and `spotlessKotlinCheck` passes on both modules. Existing add/refresh/remove behavior for valid repos is untouched.
