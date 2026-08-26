/*
 * Copyright 2026 Signal Messenger, LLC
 * SPDX-License-Identifier: AGPL-3.0-only
 */

package org.thoughtcrime.securesms.search

import android.app.Application
import android.database.Cursor
import assertk.assertThat
import assertk.assertions.isEmpty
import assertk.assertions.isNotEmpty
import io.mockk.Runs
import io.mockk.every
import io.mockk.just
import io.mockk.mockk
import io.mockk.mockkObject
import io.mockk.mockkStatic
import io.mockk.slot
import io.mockk.unmockkAll
import io.mockk.verify
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.thoughtcrime.securesms.database.DatabaseObserver
import org.thoughtcrime.securesms.database.GroupTable
import org.thoughtcrime.securesms.database.MentionTable
import org.thoughtcrime.securesms.database.MessageTable
import org.thoughtcrime.securesms.database.RecipientTable
import org.thoughtcrime.securesms.database.SignalDatabase
import org.thoughtcrime.securesms.database.ThreadTable
import org.thoughtcrime.securesms.database.model.MessageId
import org.thoughtcrime.securesms.dependencies.AppDependencies

/**
 * FUNCTIONAL VALIDATOR FIXTURE for R08-TD ("Repeated searches are slower than they need to be" --
 * `architecture_trap` category).
 *
 * Black-box, implementation-agnostic: it drives the one class `required_existing_abstractions`
 * guarantees stays put -- `SearchRepository` -- through its real public API
 * (`queryThreadsSync`), with `SignalDatabase`'s table accessors and `AppDependencies.databaseObserver`
 * mocked out. It does not assume *how* SearchRepository caches internally, only that:
 *
 *   1. Repeating an identical query does not re-invoke the underlying table query a second time
 *      (cache hit).
 *   2. Different queries are cached independently.
 *   3. After a relevant data change is announced through the app's real invalidation mechanism
 *      (DatabaseObserver), a repeated identical query reflects the change rather than returning a
 *      stale cached result.
 *
 * For point 3, this test does not hardcode which single DatabaseObserver registration method the
 * candidate used (metadata explicitly allows `registerConversationListObserver`,
 * `registerMessageUpdateObserver`, or "an equivalent already-existing hook"): it captures every
 * observer registered via either of the two most plausible entry points and fires all of them
 * that were actually registered, so any reasonable choice among the allowed hooks is credited.
 *
 * This intentionally does NOT touch `ContactSearchViewModel` or `ConversationListFragment` --
 * the documented trap shape puts the cache there instead of behind `SearchRepository`. Since this
 * fixture is scoped to `SearchRepository`'s own public API, a trap implementation that never
 * modifies `SearchRepository` at all will correctly show *no* caching behavior here (the
 * underlying query is invoked on every call) -- i.e. this functional check is expected to FAIL
 * outright against that trap, not just on the staleness assertion. See CONTROL_RESULTS.md Task D
 * and FUNCTIONAL_VALIDATORS.md for the full discussion of why that is the correct, stronger
 * signal for this specific architecture_trap task.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, application = Application::class)
class SearchRepositoryCachingFunctionalTest {

  private lateinit var searchTable: org.thoughtcrime.securesms.database.SearchTable
  private lateinit var recipientTable: RecipientTable
  private lateinit var threadTable: ThreadTable
  private lateinit var mentionTable: MentionTable
  private lateinit var messageTable: MessageTable
  private lateinit var groupTable: GroupTable
  private lateinit var databaseObserver: DatabaseObserver

  private val conversationListObserverSlot = slot<DatabaseObserver.Observer>()
  private val messageUpdateObserverSlot = slot<DatabaseObserver.MessageObserver>()
  private var threadRowCount = 0

  private fun setUpDatabaseMocks() {
    searchTable = mockk(relaxed = true)
    threadTable = mockk(relaxed = true)
    recipientTable = mockk(relaxed = true)
    mentionTable = mockk(relaxed = true)
    messageTable = mockk(relaxed = true)
    groupTable = mockk(relaxed = true)
    databaseObserver = mockk(relaxed = true)

    mockkObject(SignalDatabase.Companion)
    every { SignalDatabase.instance } returns mockk {
      every { searchTable } returns this@SearchRepositoryCachingFunctionalTest.searchTable
      every { threadTable } returns this@SearchRepositoryCachingFunctionalTest.threadTable
      every { recipientTable } returns this@SearchRepositoryCachingFunctionalTest.recipientTable
      every { mentionTable } returns this@SearchRepositoryCachingFunctionalTest.mentionTable
      every { messageTable } returns this@SearchRepositoryCachingFunctionalTest.messageTable
      every { groupTable } returns this@SearchRepositoryCachingFunctionalTest.groupTable
    }

    mockkStatic(AppDependencies::class)
    every { AppDependencies.application } returns mockk(relaxed = true)
    every { AppDependencies.databaseObserver } returns databaseObserver
    every { databaseObserver.registerConversationListObserver(capture(conversationListObserverSlot)) } just Runs
    every { databaseObserver.registerMessageUpdateObserver(capture(messageUpdateObserverSlot)) } just Runs

    // No contacts and no groups match -> thread results come solely from the controlled cursor below.
    every { recipientTable.queryAllContacts(any(), any()) } returns null
    val emptyGroupReader = mockk<GroupTable.Reader>(relaxed = true)
    every { emptyGroupReader.getNext() } returns null
    every { groupTable.queryGroupsByTitle(any(), any(), any(), any()) } returns emptyGroupReader

    every { threadTable.getFilteredConversationList(any(), any()) } answers { makeThreadCursor(threadRowCount) }
  }

  private fun makeThreadCursor(rows: Int): Cursor {
    val cursor = mockk<Cursor>(relaxed = true)
    var pos = -1
    every { cursor.count } returns rows
    every { cursor.moveToNext() } answers { pos++; pos < rows }
    return cursor
  }

  /** Fires every DatabaseObserver hook the repository actually registered, simulating a real write. */
  private fun announceDataChanged() {
    if (conversationListObserverSlot.isCaptured) {
      conversationListObserverSlot.captured.onChanged()
    }
    if (messageUpdateObserverSlot.isCaptured) {
      messageUpdateObserverSlot.captured.onMessageChanged(MessageId(1L))
    }
  }

  @After
  fun tearDown() {
    unmockkAll()
  }

  @Test
  fun repeatedIdenticalThreadQueryIsServedFromCache() {
    setUpDatabaseMocks()
    threadRowCount = 0
    val repository = SearchRepository("Note to Self")

    repository.queryThreadsSync("hello", false)
    repository.queryThreadsSync("hello", false)

    // The underlying table query ran only on the first call; the second was served from cache.
    verify(exactly = 1) { recipientTable.queryAllContacts("hello", any()) }
  }

  @Test
  fun differentQueriesAreCachedIndependently() {
    setUpDatabaseMocks()
    threadRowCount = 0
    val repository = SearchRepository("Note to Self")

    repository.queryThreadsSync("alpha", false)
    repository.queryThreadsSync("beta", false)
    repository.queryThreadsSync("alpha", false)
    repository.queryThreadsSync("beta", false)

    verify(exactly = 1) { recipientTable.queryAllContacts("alpha", any()) }
    verify(exactly = 1) { recipientTable.queryAllContacts("beta", any()) }
  }

  @Test
  fun threadQueryReflectsMutationAfterDatabaseChangeNotification() {
    setUpDatabaseMocks()
    threadRowCount = 0
    val repository = SearchRepository("Note to Self")

    val first = repository.queryThreadsSync("hello", false)
    assertThat(first.results).isEmpty()

    // A message/thread matching the query is written through a normal write path (not this cached
    // call). Real writes announce themselves via DatabaseObserver; fire whichever hook(s) the
    // repository actually registered to simulate that.
    threadRowCount = 1
    announceDataChanged()

    val second = repository.queryThreadsSync("hello", false)

    // Correct caching: the cache was invalidated by the DB change notification, so the re-query
    // reflects the mutation rather than returning the stale, pre-mutation cached (empty) result.
    // This is the "Dangerous Success" discriminator for this task: a TTL/lifecycle-based cache
    // (the documented trap) would still return the stale empty result here.
    assertThat(second.results).isNotEmpty()
  }
}
