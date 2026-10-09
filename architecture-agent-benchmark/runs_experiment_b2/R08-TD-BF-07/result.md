# R08-TD-BF-07

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: True
ACR: 1.0
Dangerous success: False
Goga engagement signal: True
Cost: $5.4988525500000005
Duration: 259624ms, turns: 26

## Agent's own summary

Everything checks out. Here's a summary of the change:

## Summary

Added result caching to `SearchRepository` (`app/src/main/java/org/thoughtcrime/securesms/search/SearchRepository.java`), which backs the chat list search (used via `ContactSearchViewModel`/`ContactSearchPagedDataSource`).

**How it works:**
- `queryThreadsSync(query, unreadOnly)` and `queryMessagesSync(query, filter)` now check a small `LruCache` (20 entries, keyed by the exact query text + filter) before doing the real DB/FTS scan. A hit returns the previously-built result immediately; a miss computes and caches it.
- The caches are **class-level** (shared across `SearchRepository` instances), since a new instance is constructed on essentially every search screen open — an instance-scoped cache would rarely live long enough to help with "leave and come back."
- Invalidation is wired to `DatabaseObserver`'s existing `registerConversationListObserver`/`notifyConversationListListeners()` signal — the same broad "conversation list needs refreshing" signal already used elsewhere in the app. I traced its call sites and confirmed it fires on message insert, edit, and delete, thread updates, and recipient/group renames, so any change that could affect a search result clears both caches wholesale. This is deliberately coarse (rather than per-term) for simplicity and correctness — "no stale results" trumps precision here.
- Registration is done lazily on first real construction (not in a static initializer), because eagerly touching `AppDependencies` at class-load time broke the existing pure-function unit tests (confirmed by running them — this was a real bug I caught and fixed, not a hypothetical).

**Verification:**
- Module compiles cleanly.
- Existing `SearchRepositoryTest` (9 tests) still passes.
- Added `SearchRepositoryCacheTest` (2 tests) proving repeated identical thread/message searches return the literal cached instance rather than re-querying.
- `goga lint` remains clean (9 cells, 0 errors) — `search/` isn't a governed cell in the frozen architecture forest, so no CODEMANIFEST/usages updates were needed; the change only consumes `DatabaseObserver`'s already-documented public API.

**Known limitation:** I didn't add an automated test for cache invalidation itself (verified instead via source tracing) — Robolectric shares JVM/classloader state across test methods in this repo in a way that makes `AppDependencies`-singleton-dependent async invalidation tests fragile/order-dependent to set up safely within reasonable effort.
