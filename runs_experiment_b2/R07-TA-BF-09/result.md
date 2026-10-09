# R07-TA-BF-09

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $2.0505119999999994
Duration: 173500ms, turns: 35

## Agent's own summary

This looks complete. Both `app` and `domain` modules compile cleanly, and `goga lint` still passes.

## Summary

Custom extension-repository ("extension store") URLs are now rejected upfront, before any network call:

- **`domain/.../mihon/domain/extension/model/InvalidExtensionStoreUrlException.kt`** (new) — typed domain exception, following the existing `NoChaptersException` convention.
- **`domain/.../AddExtensionStore.kt`** — validates the URL with OkHttp's `toHttpUrlOrNull()` (which accepts only well-formed `http://`/`https://` URLs) before delegating to `repository.insert()`, so no network request happens for invalid input. This is the single choke point used by both the manual "Create" dialog and the deep-link "Confirm" dialog.
- **`app/.../ExtensionStoresViewModel.kt`** — catches `InvalidExtensionStoreUrlException` and maps it to a new localized, friendly string instead of the raw exception message.
- **`i18n/.../strings.xml`** — added `extensionStoresScreen.addStore.invalidUrl`, matching the existing naming convention.

Adding, refreshing, and removing valid repositories is untouched — the check only short-circuits invalid input.
