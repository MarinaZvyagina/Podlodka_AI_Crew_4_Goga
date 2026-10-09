# R07-TA-BF-03

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $1.9269507
Duration: 326223ms, turns: 58

## Agent's own summary

Done. Summary of the fix:

**Where the problem lived:** `AddExtensionStore` (`domain/.../extension/interactor/AddExtensionStore.kt`) forwarded any string straight to `ExtensionStoreRepository.insert()`, which immediately made a network call — the single choke point both the "Add repository" dialog and the deeplink-confirm dialog go through (`ExtensionStoresViewModel.createRepo`).

**What changed:**
- `AddExtensionStore` now validates the URL with `java.net.URI` before touching the repository — accepts only `http`/`https` schemes with a non-empty host, rejecting blank input, missing/other schemes, and malformed text via `URISyntaxException`. Invalid input short-circuits with `Result.failure(InvalidExtensionRepoUrlException())`, no network call made.
- Added `InvalidExtensionRepoUrlException` in the domain model package as a typed marker.
- `ExtensionStoresViewModel` now maps that specific exception to a new localized string (`extensionStoresScreen.addStore.invalidUrl`, added to `strings.xml`) instead of showing the exception's raw/technical message; other failures still fall back to `throwable.message` as before.
- Added `AddExtensionStoreTest` (mockk/kotest, matching existing domain test conventions) covering valid URL insertion, rejection of garbage/blank/non-http(s) input, and that the repository is never contacted on invalid input.

Note: `goga schema` showed this `extension` code isn't part of any documented CODEMANIFEST cell (coverage there is partial, not a signal of importance per `ARCHITECTURE_CONTRACTS.md`), so this was implemented as a normal contained fix rather than routed through `goga-brainstorm`/`goga-apply`. `goga lint` still reports 0 errors, and `:domain:compileDebugKotlin`, `:app:compileDebugKotlin`, `:domain:testDebugUnitTest`, and `spotlessCheck` all pass.
