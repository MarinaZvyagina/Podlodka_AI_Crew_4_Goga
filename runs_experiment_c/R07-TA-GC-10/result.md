# R07-TA-GC-10

Condition: goga_native_architecture
Base tag: condition-c-r07-v1
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: False
Cost: $1.7989729499999996
Duration: 214718ms, turns: 28

## Agent's own summary

## Summary

Custom extension repository URLs are now validated before any network call:

- **`domain/.../model/InvalidExtensionStoreUrlException.kt`** (new) — marker exception, following the same pattern as `NoChaptersException`.
- **`domain/.../interactor/AddExtensionStore.kt`** — before delegating to `repository.insert()` (which triggers the network fetch), parses the URL with `java.net.URI` and rejects it unless the scheme is `http`/`https` and a host is present. Covers empty input, missing scheme, wrong scheme, and malformed text.
- **`ExtensionStoresViewModel.kt`** — catches `InvalidExtensionStoreUrlException` specifically and shows a friendly, localized message instead of the raw exception text; all other failure paths (network errors, parse errors) are unchanged.
- **`strings.xml`** — added `extensionStoresScreen.addStore.invalidUrl`: "This isn't a valid repository URL. Enter a link that starts with http:// or https://".

This applies to both the manual "add repo" dialog and the deep-link add flow, since both go through `AddExtensionStore`. Adding, refreshing, and removing valid repos is untouched. Verified `:domain:compileDebugKotlin` and `:app:compileDebugKotlin` both build cleanly with these changes.
