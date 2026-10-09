# R08-TA-BF-07

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: True
ACR: 1.0
Dangerous success: False
Goga engagement signal: True
Cost: $1.0139486999999998
Duration: 227349ms, turns: 38

## Agent's own summary

The code change is complete. Summary:

**Fix**: `app/src/main/java/org/thoughtcrime/securesms/blocked/BlockedUsersRepository.java` — `getBlocked()` now sorts the resolved `Recipient` list by display name (case-insensitive, locale-aware) before delivering it.

**Approach**:
- Reused the existing `GroupMemberOrder.displayNameComparator` utility (already used outside the groups feature, e.g. in `MessageDetails.java`) rather than inventing a new comparator — matches "the same way most other contact lists in the app already behave."
- Sorted at the `Recipient` level (where `getDisplayName(context)` is resolvable), not in `RecipientTable.getBlocked()` at the DB layer, since that method is also called by `PrivacySettingsRepository` (only needs `.size()`) and `MultiDeviceBlockedUpdateJob` (a sync job where order is irrelevant) — sorting there would be unnecessary churn on shared code with no benefit to those callers.
- Since `BlockedUsersViewModel.block()`/`unblock()` already call `loadRecipients()` → `repository.getBlocked()` again on every mutation, and the fragment feeds results through a `ListAdapter` + `DiffUtil`, the list re-sorts correctly in place (not appended) whenever a contact is blocked/unblocked while the screen is open — satisfying that acceptance criterion for free.
- `goga lint` passes (this package isn't part of a documented Goga cell, so no CODEMANIFEST needed updating); the change also doesn't touch the `database` or `groups/ui` cell contracts.

I kicked off a background Gradle compile (`compileGithubProdReleaseJavaWithJavac`) to double-check the Java/Kotlin interop syntax (`GroupMemberOrder.<Recipient>displayNameComparator(...)`) actually compiles — I'll confirm once it finishes.
