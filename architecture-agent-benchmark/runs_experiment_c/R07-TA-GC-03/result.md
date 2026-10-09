# R07-TA-GC-03

Condition: goga_native_architecture
Base tag: condition-c-r07-v1
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: False
Cost: $1.8407381999999999
Duration: 60278ms, turns: 6

## Agent's own summary

Done. Repository URLs are now validated before any network call:

- **`domain/.../AddExtensionStore.kt`** — the create-repo use case now checks the URL with OkHttp's `toHttpUrlOrNull()` (the same parser already used for the actual network fetch) before calling into the repository/network layer. Anything that isn't a well-formed `http://`/`https://` URL — blank, missing scheme, malformed, or a different scheme — short-circuits with a new `InvalidExtensionStoreUrlException`, no network request made.
- **`ExtensionStoresViewModel.kt`** — catches that specific exception and surfaces a friendly, localized message instead of the raw exception text; other failures (e.g. actual network/parse errors from a reachable-but-bad URL) still show their original message as before.
- **`i18n/.../strings.xml`** — added `extensionStoresScreen.addStore.invalidUrl` = "Enter a valid http:// or https:// repository URL", matching the existing string-key conventions.

Both entry points (the manual "Add store" dialog and the deeplink confirm dialog) route through the same `createRepo()` call, so both get the new check. Refreshing and removing existing repos are untouched. Verified `:domain:compileDebugKotlin`, `:app:compileDebugKotlin`, and spotless all pass clean.
