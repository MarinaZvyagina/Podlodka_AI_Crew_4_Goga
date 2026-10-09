# R07-TA-BP-08

Condition: goga_full_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: False
Cost: $2.05902555
Duration: 228494ms, turns: 34

## Agent's own summary

The diff is small and focused. Summary of the fix:

**Domain layer (`AddExtensionStore.kt`)** — the single choke point both the manual "Add store" dialog and the deep-link "Confirm" dialog funnel through before any network call. It now rejects any URL that `OkHttp`'s `toHttpUrlOrNull()` can't parse as `http://`/`https://` (covers empty input, missing scheme, non-http(s) schemes, and malformed text) and returns a friendly `InvalidExtensionStoreUrlException` instead of letting the request reach `ExtensionStoreService.fetch()`.

**UI layer (`ExtensionStoresDialogs.kt`)** — the manual-entry dialog now validates as the user types, disabling "Add" and showing an inline "Enter a valid URL starting with http:// or https://" message immediately, mirroring the existing "already exists" check pattern — so invalid input never even gets submitted.

Added the corresponding string resource. Existing add/refresh/remove behavior for valid URLs is untouched; both `:domain:compileDebugKotlin` and `:app:compileDebugKotlin` build clean.
