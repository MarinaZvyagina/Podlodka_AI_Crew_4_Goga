# R07-TA-G-07

Condition: goga
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Cost: $1.3206316500000002
Duration: 171146ms, turns: 20

## Agent's own summary

The change is minimal and focused: `AddExtensionStore` is the single interactor both "create repo" entry points (the manual add dialog and the deep-link confirm dialog) funnel through before any network call reaches `ExtensionStoreService.fetch`. It now validates the URL is a well-formed `http://`/`https://` URL with a host, and short-circuits with a clear `IllegalArgumentException` message (matching the existing convention of plain-English exception messages surfaced via `throwable.message` in `ExtensionStoresViewModel` — the same path already used for the legacy-store validation error) — no UI or ViewModel changes were needed since that plumbing already existed. `refreshAll`/`remove` operate on already-stored URLs and are untouched, so existing behavior for valid repos is unchanged.

Summary of changes:
- `domain/src/main/java/mihon/domain/extension/interactor/AddExtensionStore.kt` — reject invalid URLs before calling `repository.insert`.
- `domain/src/test/java/mihon/domain/extension/interactor/AddExtensionStoreTest.kt` (new) — covers empty/blank input, malformed text, non-http(s) schemes, schemeless-host URLs, and confirms valid `http`/`https` URLs still delegate to the repository.

Verified: `:domain:testDebugUnitTest` passes (including the new tests), `:app:compileDebugKotlin` and `:data:compileDebugKotlin` build clean, and `:domain:spotlessKotlinCheck` passes.
