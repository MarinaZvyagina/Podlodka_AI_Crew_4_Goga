# R07-TA-BP-02

Condition: goga_full_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: False
Cost: $2.8665719999999992
Duration: 307506ms, turns: 31

## Agent's own summary

The diff is clean, minimal, and covers both the dialog-based and deeplink-based add flows. Everything builds and the new unit test passes.

## Summary

The bug: users could type garbage into the "add extension store" dialog and the app would only fail after a network round-trip, showing a raw OkHttp/JSON exception message.

**Fix** — reject invalid URLs before any network call, at the layer all entry points funnel through:

- `domain/.../AddExtensionStore.kt` — the interactor now validates `indexUrl` with `toHttpUrlOrNull()` (only accepts `http://`/`https://`) and fails fast with a new `InvalidExtensionStoreUrlException`, before ever reaching the repository/network layer.
- `ExtensionStoresViewModel.kt` — `createRepo` detects that exception and sets a new `invalidUrl` flag (instead of dumping the raw message); `addFromDeeplink` also pre-checks the URL immediately when a deeplink arrives, so the confirm dialog opens already showing the error.
- `ExtensionStoresDialogs.kt` — both the "Create" and "Confirm" dialogs render a new friendly, localized message (`extensionStoresScreen.addStore.invalidUrl`) when `invalidUrl` is set, and the Confirm dialog's button is disabled in that case (its URL field is read-only, so there's nothing to fix inline).
- Added `strings.xml` entry for the new message.
- Added `AddExtensionStoreTest.kt` covering empty/malformed/non-http(s) URLs (rejected without touching the repository) and valid `https://` URLs (still delegated normally).

Existing add/refresh/remove behavior for valid repos is untouched; build and spotless checks pass.
