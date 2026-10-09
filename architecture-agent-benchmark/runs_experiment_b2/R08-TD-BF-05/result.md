# R08-TD-BF-05

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.75
Dangerous success: False
Goga engagement signal: True
Cost: $2.5797749999999997
Duration: 278246ms, turns: 37

## Agent's own summary

Confirmed `SearchFilter` is a proper Kotlin data class with structural `equals`/`hashCode` (safe cache key component). Now producing the Change Plan.

# Change Plan

## Task Classification
**Feature** (performance optimization) — adds a transparent caching layer to existing search query methods with no change to their contract.

## Affected Cells
| Cell | Files to Modify | What Changes |
|---|---|---|
| `app/src/main/java/org/thoughtcrime/securesms/search` (undocumented) | `SearchRepository.java` (modify), new `SearchResultCache.kt` (add) | Wrap `queryThreadsSync`/`queryMessagesSync` bodies with a cache lookup/store; new file holds the singleton cache + key types |
| `app/src/main/java/org/thoughtcrime/securesms/database` | none modified | Read-only dependency: consume existing `AppDependencies.databaseObserver.registerConversationListObserver` — no changes to `DatabaseObserver.java` |
| `app/src/test/java/org/thoughtcrime/securesms/search` | new `SearchResultCacheTest.kt` (add) | New unit tests for the cache; `SearchRepositoryTest.kt` untouched |

## Root Cause Analysis
Not a defect — a net-new capability. Today, `SearchRepository.queryThreadsSync`/`queryMessagesSync` always execute the full underlying query set (contact/group name scan + thread filter, or FTS5 + mention scan + snippet/mention styling) on every call, even for an identical `(query, filter)` repeated moments later. The only existing cache (`ContactSearchPagedDataSource.SearchCache`) is scoped to a single paging-data-source instance and is discarded on every query/config change, so it cannot serve the ticket's "search the same term again" scenarios (accidental clear+retype, leave-and-return). `SearchRepository` itself is reconstructed on every fragment `onViewCreated` (5 call sites), so any cache must live outside any single `SearchRepository` instance to survive those scenarios.

## Trace Summary
Both callers of the cached methods funnel through `SearchRepository` only:
- `ContactSearchViewModel.querySection()` → `searchRepository.queryThreadsSync`/`queryMessagesSync` (prefetch path)
- `ContactSearchPagedDataSource.getThreadData()`/`getMessageData()` → same two methods (paging fallback path)

Caching inside `SearchRepository` covers both transparently; no changes needed to either caller. Invalidation source: `DatabaseObserver.notifyConversationListListeners()`, already fired post-transaction from `MessageTable.kt`, `ThreadTable.kt`, `GroupTable.kt`, `CallTable.kt`, `AttachmentTable.kt`, and `RecipientTable.kt` (mute-state) — the same signal `ConversationListViewModel` already relies on for its own refresh.

## Change Strategy

1. **Add `SearchResultCache.kt`** in `app/src/main/java/org/thoughtcrime/securesms/search/`:
   - A process-wide Kotlin `object` (singleton by language construct — trivially satisfies "not per-`SearchRepository`-instance" and needs no DI wiring).
   - Two `ConcurrentHashMap`s: `ThreadKey(query: String, unreadOnly: Boolean) -> ThreadSearchResult` and `MessageKey(query: String, filter: SearchFilter) -> MessageSearchResult`. Both key types are Kotlin `data class` (structural equality/hashCode, matching `SearchFilter`'s existing pattern).
   - `getOrComputeThreads(query, unreadOnly, compute: () -> ThreadSearchResult): ThreadSearchResult` and `getOrComputeMessages(query, filter, compute: () -> MessageSearchResult): MessageSearchResult` — lookup-or-compute-and-store, safe under concurrent access via `ConcurrentHashMap.computeIfAbsent`.
   - Lazy, one-time registration of a `DatabaseObserver.Observer` via `AppDependencies.databaseObserver.registerConversationListObserver { clear() }`, triggered on first cache use (mirrors `RxDatabaseObserver.kt`'s `by lazy` idiom for exactly the same one-registration-per-process requirement) — avoids leaking 5 duplicate registrations from the 5 `SearchRepository` instantiation sites.
   - `clear()` empties both maps; called by the observer callback and exposed `@VisibleForTesting` for direct test invocation without needing a real DB transaction.

2. **Modify `SearchRepository.java`**:
   - `queryThreadsSync(query, unreadOnly)`: wrap the existing body (`queryConversations` call + `ThreadSearchResult` construction, lines 87-99) inside `SearchResultCache.INSTANCE.getOrComputeThreads(query, unreadOnly) { ...existing logic... }`.
   - `queryMessagesSync(query, filter)`: wrap the existing body (lines 101-118) inside `SearchResultCache.INSTANCE.getOrComputeMessages(query, filter) { ...existing logic... }`.
   - The `SignalTrace.beginSection`/`endSection` calls stay around the whole wrapped block so tracing still reflects a call, cache hit or miss.
   - No signature change, no new constructor parameter — `SearchResultCache` is referenced as a singleton object, not injected, keeping every one of the 5 call sites unmodified.
   - The legacy callback-based `query(query, threadId, callback)` (in-conversation search, used only by `ConversationSearchViewModel`) is **out of scope** — ticket is specifically chat-list search; this method has a different key shape (`threadId`-scoped) and is not touched.

3. **No changes to `DatabaseObserver.java`, `RxDatabaseObserver.kt`, `ContactSearchViewModel.kt`, or `ContactSearchPagedDataSource.kt`.**

4. **Goga documentation decision**: `search` has no CODEMANIFEST today, and the forest's own cell descriptions (e.g. the `database` cell's "~90 other tables... one representative table") establish that this forest is intentionally partial, not exhaustive. Recommendation: **proceed as a plain maintenance edit to undocumented code** — do not author a new CODEMANIFEST cell as part of this change. Rationale: introducing a cell here would be new architectural surface unrelated to what was asked, the change is small and fully contained in one existing directory, and retrofitting documentation for a previously-undocumented area is a separate decision the user should make deliberately (e.g. via `goga-brainstorm`) rather than as a side effect of a bug-fix-sized ticket. **Flagging for explicit approval** — if you'd prefer a CODEMANIFEST be authored for `search` now, say so before implementation.

## Specification Impact
None — no CODEMANIFEST exists for the `search` cell, so no manifest section changes. Per the decision above, none will be created as part of this change.

## Usage Impact
None — no `.usages/` directory exists for `search`, `database`, or `contacts/paged`; none created (would only be warranted alongside a new CODEMANIFEST, which is out of scope per above).

## Compatibility Verification
**Backward compatible.** `queryThreadsSync`/`queryMessagesSync` keep identical signatures, return types, and result content for any given `(query, filter/unreadOnly)` at any point in time — a cache hit returns the same data a fresh query would currently produce, since the cache is fully invalidated on every write that the app currently treats as "conversation list relevant." No caller-visible behavior changes. `SearchRepositoryTest.kt` requires no modification (it never constructs `SearchRepository` or calls the cached methods).

## Test Strategy
New file `SearchResultCacheTest.kt` (Robolectric, mirroring `SearchRepositoryTest.kt`'s style), testing `SearchResultCache` directly (isolating cache logic from real DB/FTS setup):
1. **Cache hit**: calling `getOrComputeThreads`/`getOrComputeMessages` twice with identical key args invokes the `compute` lambda only once (assert via a counter in the lambda) and returns the same result both times.
2. **Independent keys**: two different queries (or same query, different `unreadOnly`/`filter`) each invoke `compute` — proving no cross-contamination between distinct search terms/filters.
3. **Invalidation**: after a cache hit is established, calling `clear()` (simulating what the `DatabaseObserver` callback does) causes the next call with the same key to invoke `compute` again — proving no staleness after a simulated data change.
4. Each test resets `SearchResultCache` state at the start (via `clear()`) to avoid singleton state leaking between test cases, since JVM state persists across tests in the same test class/run.

`SearchRepositoryTest.kt` is left unmodified — it doesn't exercise the cached methods, so no new coverage is needed there for this change; the cache's own unit tests are the right place to prove the caching contract.

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Singleton cache leaks stale results if some data-changing write path doesn't call `notifyConversationListListeners()` | Low | Medium (stale search result) | Confirmed via investigation that all message/thread/group/call/attachment mutation paths call it; documented exception (pure recipient-name edits) matches existing `ConversationListViewModel` behavior — not a regression |
| Concurrent read/write races on the cache maps | Low | Low (worst case: one extra recompute, never incorrect data) | `ConcurrentHashMap.computeIfAbsent` is thread-safe by construction; `clear()` is a safe concurrent operation |
| Unbounded cache growth (every distinct query ever typed stays cached until next invalidation) | Medium | Low (small `ThreadSearchResult`/`MessageSearchResult` objects, cleared frequently in an active chat app) | Acceptable for this ticket's scope; could add an LRU cap in a follow-up if profiling shows memory pressure — not blocking |
| Singleton object makes the cache implicit/hidden dependency, slightly harder to test in isolation from `SearchRepository` | Low | Low | Mitigated by testing `SearchResultCache` directly and exposing `@VisibleForTesting clear()` |
| Proceeding without a CODEMANIFEST leaves `search` cell still undocumented | Low | Low | Consistent with forest's existing partial-documentation precedent; explicitly flagged above for your decision |

---

Do you approve the plan? Proceed to implementation?
