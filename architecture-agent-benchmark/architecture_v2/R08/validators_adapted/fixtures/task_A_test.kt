/*
 * Copyright 2026 Signal Messenger, LLC
 * SPDX-License-Identifier: AGPL-3.0-only
 */

package org.thoughtcrime.securesms.blocked

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.thoughtcrime.securesms.database.SignalDatabase
import org.thoughtcrime.securesms.recipients.Recipient
import org.thoughtcrime.securesms.testutil.RecipientTestRule
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * FUNCTIONAL VALIDATOR FIXTURE for R08-TA ("Blocked contacts list is not sorted").
 *
 * This is a black-box, implementation-agnostic test: it drives the feature through the
 * one entry point the task's `required_existing_abstractions` guarantees will still exist
 * and still be the sole data-access point for this screen ("BlockedUsersRepository ...
 * expected to remain the sole data-access point for this screen") — its package-visible
 * getBlocked() callback API. It does NOT depend on where inside/behind that call the
 * sorting is actually implemented (repository vs. underlying RecipientTable query), so any
 * architecturally-correct candidate solution passes regardless of which of those two
 * allowed layers it chooses.
 *
 * It intentionally does NOT call any UI-layer (Fragment/Adapter) sort helper — a candidate
 * that sorts only in the UI layer (the documented trap) is expected to FAIL this test, even
 * though it would satisfy a naive "is the on-screen list alphabetical" check. That is a
 * deliberate, documented property of this functional check (see CONTROL_RESULTS.md Task A).
 *
 * Injected at: app/src/test/java/org/thoughtcrime/securesms/blocked/BlockedUsersRepositoryTest.kt
 * Run via:     ./gradlew :Signal-Android:testPlayProdDebugUnitTest --tests "org.thoughtcrime.securesms.blocked.BlockedUsersRepositoryTest"
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, application = Application::class)
class BlockedUsersRepositoryTest {

  @get:Rule
  val recipientTestRule = RecipientTestRule()

  private lateinit var repository: BlockedUsersRepository

  @Test
  fun givenRecipientsBlockedInNonAlphabeticalOrder_whenIGetBlocked_thenIExpectAlphabeticalOrder() {
    repository = BlockedUsersRepository(ApplicationProvider.getApplicationContext())

    // Insert and block in a deliberately non-alphabetical order.
    val zoe = recipientTestRule.createRecipient("Zoe")
    val amy = recipientTestRule.createRecipient("Amy")
    val mike = recipientTestRule.createRecipient("Mike")

    SignalDatabase.recipients.setBlocked(zoe, true, System.currentTimeMillis())
    SignalDatabase.recipients.setBlocked(amy, true, System.currentTimeMillis())
    SignalDatabase.recipients.setBlocked(mike, true, System.currentTimeMillis())

    val result = getBlockedSync()

    assertEquals(3, result.size)
    assertEquals(listOf("Amy", "Mike", "Zoe"), result.map { it.getDisplayName(ApplicationProvider.getApplicationContext()) })
  }

  @Test
  fun givenMixedCaseDisplayNames_whenIGetBlocked_thenSortIsCaseInsensitive() {
    repository = BlockedUsersRepository(ApplicationProvider.getApplicationContext())

    val lower = recipientTestRule.createRecipient("bob")
    val upper = recipientTestRule.createRecipient("Alice")

    SignalDatabase.recipients.setBlocked(lower, true, System.currentTimeMillis())
    SignalDatabase.recipients.setBlocked(upper, true, System.currentTimeMillis())

    val result = getBlockedSync()

    assertEquals(listOf("Alice", "bob"), result.map { it.getDisplayName(ApplicationProvider.getApplicationContext()) })
  }

  /** Drives the repository's async callback-based API synchronously for test purposes. */
  private fun getBlockedSync(): List<Recipient> {
    val latch = CountDownLatch(1)
    var out: List<Recipient> = emptyList()

    repository.getBlocked { recipients ->
      out = recipients
      latch.countDown()
    }

    assertTrue("Timed out waiting for BlockedUsersRepository#getBlocked", latch.await(5, TimeUnit.SECONDS))
    return out
  }
}
