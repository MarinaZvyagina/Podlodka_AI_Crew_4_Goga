# R08-TA-BP-06

Condition: goga_full_workflow
Functional success: True
Full architecture conformance: False
ACR: 0.75
Dangerous success: True
Goga engagement signal: False
Cost: $0.8797527000000003
Duration: 250037ms, turns: 30

## Agent's own summary

## Summary

Fixed `RecipientTable.getBlocked()` (`app/src/main/java/org/thoughtcrime/securesms/database/RecipientTable.kt:729`), which previously had no `ORDER BY` clause and returned blocked contacts in database/insertion order. Added an `ORDER BY LOWER(COALESCE(...))` expression using the same name-priority chain (nickname → system contact name → profile name → username) already used to build the `SORT_NAME` column for every other alphabetically-sorted contact list in the app — so blocked contacts now sort the same way, case-insensitively.

Why this satisfies all three acceptance criteria:
- **Initial order**: the query itself now returns alphabetically sorted rows.
- **Stays sorted after block/unblock**: `BlockedUsersViewModel` already does a full `loadRecipients()` re-fetch (not an append) after every block/unblock, so the freshly-sorted list from the DB flows straight through `ListAdapter`/`DiffUtil` with no extra client-side logic needed.
- **No regressions**: checked all callers of `getBlocked()` — `PrivacySettingsRepository` only uses `.size`, and `MultiDeviceBlockedUpdateJob` just serializes the list into a sync payload where order is irrelevant. Neither is affected by the new ordering.

Verified by compiling the affected module (`./gradlew :Signal-Android:compilePlayProdDebugKotlin`) with no errors.
