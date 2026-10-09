# R07-TA-BP-06

Condition: goga_full_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: False
Cost: $2.2058800499999998
Duration: 282076ms, turns: 40

## Agent's own summary

## Summary

The custom extension repository URL entry now rejects obviously invalid URLs before any network call, with a friendly message instead of a raw error.

**Domain layer** (`domain/.../mihon/domain/extension/model/`):
- New `ExtensionStoreUrlValidator.isValid()` — accepts only well-formed `http://`/`https://` URLs with a host, using `java.net.URI` (no new dependencies).
- New `InvalidExtensionStoreUrlException`.
- `AddExtensionStore` use case now validates the URL first and short-circuits with `Result.failure(InvalidExtensionStoreUrlException())` before ever calling the repository (which is what triggers the network fetch) — this covers both the manual "Add extension store" flow and the deeplink-confirm flow, since both go through the same use case.

**UI layer**:
- `ExtensionStoresViewModel` maps that specific exception to a typed `invalidUrl` flag on the dialog state (instead of dumping the raw exception message), and also pre-checks deeplink URLs immediately via the validator.
- `ExtensionStoreCreateDialog` gets instant client-side feedback: as the user types, an invalid URL disables the "Add" button and shows the new friendly message — no round trip needed.
- `ExtensionStoreConfirmDialog` (deeplink path) shows the same message and disables confirmation if the deeplinked URL is invalid.
- Added string resource `extensionStoresScreen.addStore.invalidUrl` = "Enter a valid http:// or https:// URL".

Existing add/refresh/remove behavior for valid repos, and the existing "already exists" duplicate check, are untouched. Verified both the `domain` and `app` modules compile cleanly (`:domain:compileDebugKotlin`, `:app:compileDebugKotlin`).

No automated tests existed for this flow previously, and none were added — let me know if you'd like a unit test for `AddExtensionStore`/`ExtensionStoreUrlValidator` following this repo's MockK/Kotest conventions.
