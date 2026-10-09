# R07-TA-B-09

Condition: baseline
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Cost: $1.0720964999999998
Duration: 193220ms, turns: 38

## Agent's own summary

All 6 tests pass, 0 failures.

## Summary

Fixed in `domain/src/main/java/mihon/domain/extension/interactor/AddExtensionStore.kt`: `AddExtensionStore` now validates the URL with OkHttp's `toHttpUrlOrNull()` (which only accepts `http`/`https` schemes) before delegating to the repository. Invalid input — blank, missing scheme, non-http(s) scheme, or malformed text — is rejected immediately with a clear `IllegalArgumentException("This is not a valid repository URL")` and never reaches the network, while valid URLs flow through unchanged to `repository.insert()`. This single choke point covers both entry paths (the manual "Create" dialog and the deeplink "Confirm" dialog), since both call `ExtensionStoresViewModel.createRepo` → `AddExtensionStore`, and the existing `errorMessage` UI plumbing already surfaces the exception message to the user.

Added `domain/src/test/java/mihon/domain/extension/interactor/AddExtensionStoreTest.kt` covering rejection of invalid URLs (empty, no scheme, wrong scheme, malformed) with zero repository calls, and confirming valid URLs still delegate normally. Compiled `:domain` and ran the new tests — all pass.
