# R08-TD-BF-01

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.75
Dangerous success: False
Goga engagement signal: False
Cost: $3.8474412
Duration: 411430ms, turns: 69

## Agent's own summary

# Change Plan

## Task Classification
**Feature** — additive performance optimization (result caching) with a correctness-critical invalidation requirement. No API surface removed or altered.

## Affected Cells
| Cell | Files to Modify | What Changes |
|---|---|---|
| `search/` (undocumented) | `app/src/main/java/org/thoughtcrime/securesms/search/SearchRepository.java` | Add two bounded `LRUCache` fields, check-before-compute + populate-on-miss in `queryThreadsSync`/`queryMessagesSync`, add a package/public `invalidateCache()` method |
| `contacts/paged/` (undocumented) | `app/src/main/java/org/thoughtcrime/securesms/contacts/paged/ContactSearchViewModel.kt` | Register a `DatabaseObserver.Observer` in `init` that calls `searchRepository.invalidateCache()`, unregister it in `onCleared()` |
| `app/database` (documented) | none | Read-only consumption of already-public `DatabaseObserver.registerConversationListObserver`/`unregisterObserver`/`Observer` — no manifest change |

## Root Cause Analysis
No memoization exists between `ContactSearchViewModel.querySection()` and `SearchRepository.queryThreadsSync`/`queryMessagesSync`. The only existing cache (`ContactSearchPagedDataSource.SearchCache`) is rebuilt from scratch on every `publish()`, including retyping an identical query. See Investigation Report for full evidence chain (HIGH confidence).

## Trace Summary
`ContactSearchViewModel.querySection()` → `SearchRepository.queryThreadsSync`/`queryMessagesSync` → DB tables. All six tables that can affect search results (`MessageTable`, `ThreadTable`, `GroupTable`, `RecipientTable`, `CallTable`, `AttachmentTable`) call `DatabaseObserver.notifyConversationListListeners()` on every relevant mutation — this is the invalidation signal to hook.

## Change Strategy

**1. `SearchRepository.java`**
- Add a constant `private static final int SEARCH_CACHE_MAX_SIZE = 20;` (small — cached payloads can hold up to 500 rows each; the goal is "repeat the last few searches," not an unbounded history).
- Add two private final fields:
  - `private final LRUCache<ThreadCacheKey, ThreadSearchResult> threadSearchCache = new LRUCache<>(SEARCH_CACHE_MAX_SIZE);`
  - `private final LRUCache<MessageCacheKey, MessageSearchResult> messageSearchCache = new LRUCache<>(SEARCH_CACHE_MAX_SIZE);`
- Add two small private static key classes (`ThreadCacheKey(query, unreadOnly)`, `MessageCacheKey(query, filter)`) with `equals`/`hashCode` via `Objects.equals`/`Objects.hash` — `SearchFilter` already contributes structural equality since it's a Kotlin data class.
- In `queryThreadsSync`: build `ThreadCacheKey`, check cache under `synchronized (threadSearchCache)`; on hit return immediately (skip the DB work and the `Log.d` timing line, since nothing was recomputed); on miss, compute exactly as today, then `synchronized (threadSearchCache) { threadSearchCache.put(key, result); }` before returning.
- In `queryMessagesSync`: same pattern with `MessageCacheKey`/`messageSearchCache`.
- Add `public void invalidateCache()` that clears both maps under their respective locks.
- The callback-based `query(String, long threadId, Callback)` method and its private helpers are **not touched**.

**2. `ContactSearchViewModel.kt`**
- Add import for `org.thoughtcrime.securesms.database.DatabaseObserver` and `org.thoughtcrime.securesms.dependencies.AppDependencies` (mirrors `StoryArchiveViewModel.kt`).
- Add `private val searchDataChangedObserver = DatabaseObserver.Observer { searchRepository.invalidateCache() }`.
- In the existing `init { ... }` block, add `AppDependencies.databaseObserver.registerConversationListObserver(searchDataChangedObserver)`.
- In `override fun onCleared()`, add `AppDependencies.databaseObserver.unregisterObserver(searchDataChangedObserver)` alongside the existing `disposables.clear()`.

## Specification Impact
None. No CODEMANIFEST exists for `search/` or `contacts/paged/`; the `app/database` cell's `DatabaseObserver` contract is consumed unmodified (same public methods, same semantics, same call pattern already used by `StoryArchiveViewModel.kt`).

## Usage Impact
None. No `.usages` file references `SearchRepository`, `ContactSearchViewModel`, or the conversation-list observer.

## Compatibility Verification
**Backward compatible.** Same inputs against unchanged DB state return the same values (byte-identical objects, since a cache hit returns the exact object that would otherwise be recomputed). Same inputs against changed DB state recompute fresh results exactly as today, because the cache is cleared on any relevant mutation. No signature changes, no new checked exceptions, no removed methods. `invalidateCache()` and the constructor/lifecycle additions are net-new public surface — additive only.

## Test Strategy
- **New unit/robolectric test in `SearchRepositoryTest.kt` or a new instrumented test** (existing tests are Robolectric-based static-method tests only; `queryThreadsSync`/`queryMessagesSync` need a DB, so this likely needs `app/src/androidTest` coverage, or a Robolectric test with an in-memory `SignalDatabase` if that pattern exists elsewhere — the implementer/test-engineer should check for a precedent, e.g. other `*Table` androidTests) covering:
  1. Two consecutive identical `queryThreadsSync`/`queryMessagesSync` calls with no DB change → same result, second call does not re-hit the DB (can be asserted indirectly via a spy/counter, or simply asserted as a correctness contract: cache returns `==`-identical or `equals`-equal result).
  2. A DB mutation (e.g. insert a matching message) between two identical searches → second search reflects the new data (no staleness).
  3. Two different query strings are cached independently — searching A then B then A again does not return B's results for A.
  4. `invalidateCache()` clears both thread and message caches.
- Verify `SearchFilter.equals`/`hashCode` is exercised as a cache key (already covered by Kotlin's generated implementation — no new test needed for that specific fact, but the message-cache independence test above exercises it transitively).
- No modification needed to the existing 9 static-helper tests in `SearchRepositoryTest.kt` — they remain valid as-is.

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Cache never invalidated in some edge-case write path that bypasses all six tables' `notifyConversationListListeners()` calls | Low | High (stale results) | Broad, whole-cache invalidation on *any* conversation-list-relevant signal (not per-key) maximizes coverage; six independently-verified call sites already cover insert/update/delete/rename/group-title across all relevant tables |
| Unbounded cache growth if a user searches many distinct terms over a long session | Low | Low | Bounded `LRUCache` (size 20) per cache, evicts oldest on overflow — matches existing `LiveRecipientCache` idiom |
| `ContactSearchViewModel` is shared by non-chat-list search surfaces (contact picker, member search, forward sheet) — adding the observer affects all of them | Low | None (correctness-only change) | Same invalidation guarantee benefits all consumers equally; no behavior regression, only fresher results |
| Returning a shared cached object to multiple UI bind calls if a `Spannable` field were mutated in place downstream | Very Low | Medium | Verified via trace: `SearchUtil.getHighlightedSpan` copies via `new SpannableString(text)`, never mutates the argument in place |

Do you approve the plan? Proceed to implementation?
