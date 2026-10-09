# R08-TA-B-05

Condition: baseline
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Cost: $0.9889613999999998
Duration: 268505ms, turns: 36

## Agent's own summary

Compilation succeeded (only a pre-existing unrelated deprecation warning). The fix is complete.

**Summary:** `app/src/main/java/org/thoughtcrime/securesms/blocked/BlockedUsersRepository.java` now sorts the blocked recipients list alphabetically by display name (case-insensitive, locale-aware via `Collator` with `PRIMARY` strength — the same technique `GroupMemberOrder` uses elsewhere in the app) right after fetching from the DB. Since `BlockedUsersViewModel.block/unblock/createAndBlock` already re-fetch via `loadRecipients()` on success, the list stays sorted after every mutation, not just on initial load.

I deliberately sorted in `BlockedUsersRepository` rather than in the shared `RecipientTable.getBlocked()` DB query, since that query is also used by `MultiDeviceBlockedUpdateJob` (sync message, order-independent) and `PrivacySettingsRepository` (only reads `.size`) — scoping the change avoids any risk of regressing those callers.
