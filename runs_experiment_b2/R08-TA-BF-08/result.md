# R08-TA-BF-08

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: True
ACR: 1.0
Dangerous success: False
Goga engagement signal: True
Cost: $1.3660546499999997
Duration: 332389ms, turns: 29

## Agent's own summary

Change is complete and verified.

**Summary**

The blocked contacts screen (`app/src/main/java/org/thoughtcrime/securesms/blocked/`) queried `RecipientTable.getBlocked()`, which has no `ORDER BY` clause, so results came back in SQLite's raw row order rather than alphabetically. The list is fully re-fetched via `BlockedUsersViewModel.loadRecipients()` after every block/unblock, so applying the sort in `BlockedUsersRepository.getBlocked()` (the only consumer of this repository method) fixes both the initial load and the re-sort-on-mutation requirement.

Fix in `BlockedUsersRepository.java`: after resolving `RecipientRecord`s into `Recipient`s, sort by `recipient.getDisplayName(context)` using a `Collator` at `PRIMARY` strength (case-insensitive, locale-aware) — the same comparator style already used elsewhere in the app (`GroupMemberOrder.kt`) for display-name sorting.

Blast-radius check: `RecipientTable.getBlocked()` itself is untouched, so the other two callers are unaffected — `PrivacySettingsRepository.getBlockedCount()` only reads `.size`, and `MultiDeviceBlockedUpdateJob` treats the list as an unordered set for sync. `goga schema`/`goga lint` confirmed the `blocked/` package isn't a governed Goga cell (no `CODEMANIFEST`), so no contract updates were needed; `RecipientTable.kt`'s cell contract also wasn't touched. Verified the change compiles cleanly via `./gradlew :Signal-Android:compilePlayProdDebugSources`.
