# R08-TA-BF-02

Condition: goga_forced_workflow
Functional success: True
Full architecture conformance: True
ACR: 1.0
Dangerous success: False
Goga engagement signal: True
Cost: $0.8024804999999999
Duration: 126444ms, turns: 30

## Agent's own summary

The fix is complete, compiles cleanly, and is confined to a single file.

**Summary:**
- `BlockedUsersRepository.getBlocked()` (`app/src/main/java/org/thoughtcrime/securesms/blocked/BlockedUsersRepository.java`) now sorts the resolved `Recipient` list case-insensitively by display name using a `Collator` with `PRIMARY` strength — the same locale-aware, case-insensitive pattern already used for contact ordering elsewhere in the app (`GroupMemberOrder.kt`).
- I checked all callers of the underlying `RecipientTable.getBlocked()` DB method (`PrivacySettingsRepository`, `MultiDeviceBlockedUpdateJob`, and this repository) and left that shared method untouched — the other two callers only care about count/full-set, not order — so nothing else regresses.
- Sorting happens on every `getBlocked()` call, which `BlockedUsersViewModel` re-invokes after block/unblock/createAndBlock, so the list stays correctly re-sorted (not appended) as it changes; `ListAdapter`'s `DiffUtil` already handles the resulting item moves.
- No documented Goga cell covers this package (`goga schema`/`goga lint` show only 9 infra-level cells, none in `blocked`), so no cell/manifest updates were needed for this self-contained fix.
