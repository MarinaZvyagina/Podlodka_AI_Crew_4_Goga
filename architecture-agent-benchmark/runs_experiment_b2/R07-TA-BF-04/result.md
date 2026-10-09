# R07-TA-BF-04

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: True
Cost: $1.2698072999999999
Duration: 151895ms, turns: 45

## Agent's own summary

Summary of the fix:

- `AddExtensionStore.invoke()` (`domain/src/main/java/mihon/domain/extension/interactor/AddExtensionStore.kt`) now validates the URL with OkHttp's `toHttpUrlOrNull()` *before* calling `repository.insert()`, which is what triggers the network fetch. Anything without a proper `http://`/`https://` scheme — empty input, plain text, other schemes, malformed URLs — is rejected immediately with a friendly `InvalidExtensionStoreUrlException("Enter a valid http:// or https:// URL")`, surfaced through the existing `Result.failure` → `throwable.message` path already wired into the create/confirm dialogs.
- This single choke point covers both entry points (`createRepo` typed input and `addFromDeeplink` confirm flow), so valid-repository add/refresh/remove behavior is untouched.
- Added `domain/src/test/java/mihon/domain/extension/interactor/AddExtensionStoreTest.kt` covering invalid inputs (empty, garbage text, missing scheme, non-http scheme, `javascript:`) and a valid-URL success case; all 6 pass.

Checked against the repo's Goga architecture contracts first — `goga schema` shows the extension-store feature isn't part of the documented cell forest (only track/manga/chapter/source cells are), so no CODEMANIFEST governs these files. `goga lint` still passes clean (12 cells, 0 errors) after the change.
