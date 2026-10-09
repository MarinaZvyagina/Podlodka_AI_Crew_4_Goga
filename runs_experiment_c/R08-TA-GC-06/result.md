# R08-TA-GC-06

Condition: goga_native_architecture
Base tag: condition-c-r08-v1
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: False
Cost: $1.2703814999999998
Duration: 157411ms, turns: 38

## Agent's own summary

## Summary

Fixed the unordered "Blocked contacts" list by sorting at the query level in `RecipientTable.getBlocked()` (`app/src/main/java/org/thoughtcrime/securesms/database/RecipientTable.kt:729`).

**What changed:** added an `ORDER BY` clause using the same case-insensitive name-priority expression (`nickname → system contact name → profile name → username`, wrapped in `LOWER()`) that the rest of the codebase already uses for other contact lists (`SORT_NAME`), with `E164` as a tiebreaker. This is the same convention used by `getSignalContacts`, `queryContacts`, etc.

**Why this satisfies the ticket:**
- Initial load is sorted, since `BlockedUsersRepository.getBlocked()` → `BlockedUsersViewModel` just passes the query result straight through.
- Block/unblock actions call `loadRecipients()` which re-runs the same query and re-emits the full list via `adapter.submitList(...)`, so the list stays correctly sorted after mutations rather than appending at the end — no extra logic needed in the ViewModel/Adapter.
- Checked other callers of `getBlocked()`: `PrivacySettingsRepository` only uses `.size`, and `MultiDeviceBlockedUpdateJob` just maps the list into a sync payload — neither depends on ordering, so they're unaffected.

Verified the change compiles cleanly via `./gradlew :app:compileProdReleaseKotlin --offline` (exit 0). No existing tests cover blocked-list ordering specifically.
