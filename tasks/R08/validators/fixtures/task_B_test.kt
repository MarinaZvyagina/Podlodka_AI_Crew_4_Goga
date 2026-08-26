/*
 * Copyright 2026 Signal Messenger, LLC
 * SPDX-License-Identifier: AGPL-3.0-only
 */

package org.thoughtcrime.securesms.mediasend.v3

import android.app.Application
import android.content.ContentValues
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.BeforeClass
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.signal.core.models.database.AttachmentId
import org.signal.core.util.logging.Log
import org.signal.mediasend.preupload.PreUploadRepository
import org.thoughtcrime.securesms.database.AttachmentTable
import org.thoughtcrime.securesms.database.SignalDatabase
import org.thoughtcrime.securesms.database.TestSms
import org.thoughtcrime.securesms.testutil.MockAppDependenciesRule
import org.thoughtcrime.securesms.testutil.SignalDatabaseRule
import org.thoughtcrime.securesms.testutil.SystemOutLogger
import java.lang.reflect.Method

/**
 * FUNCTIONAL VALIDATOR FIXTURE for R08-TB ("full quality override in media-send batch").
 *
 * This is black-box and implementation-agnostic with respect to the *name* of the new
 * capability: `metadata_B.yaml` fixes the CLASS names a correct solution must use
 * (`PreUploadRepository` interface, app-side impl `MediaSendV3PreUploadRepository` --
 * see `required_existing_abstractions`) but does not fix the *method name* the candidate
 * adds to that interface. So instead of calling a hardcoded method name, this test:
 *
 *   1. Reflects on the fixed `PreUploadRepository` interface and finds whichever method is
 *      NOT part of the six methods that already existed at the pinned commit (BASELINE_METHODS
 *      below) -- i.e. whatever new capability the candidate added.
 *   2. Looks up the same-named/same-shaped method on the fixed app-side singleton
 *      `org.thoughtcrime.securesms.mediasend.v3.MediaSendV3PreUploadRepository` (a Kotlin
 *      `object`, invoked via its generated `INSTANCE` field).
 *   3. Invokes it with synthesized arguments (matched positionally by parameter type: a
 *      Context, the id of a real attachment row inserted for the test, and `true` for a
 *      Boolean/boolean parameter) against a real Robolectric-backed SQLite `SignalDatabase`.
 *   4. Asserts the *observable, architecturally-fixed* outcome required by the ticket: the
 *      marked attachment's persisted `transformProperties.skipTransform` becomes `true`,
 *      a sibling attachment is unaffected, and the value survives being re-read from a fresh
 *      DB query (the closest JVM-level proxy available for "survives process death", since no
 *      emulator/instrumentation is available in this environment -- see metadata's own
 *      functional_check_command note and CONTROL_RESULTS.md Task B).
 *
 * If no qualifying new method can be found/invoked this way (e.g. a trap implementation that
 * never extends `PreUploadRepository` at all, such as the documented negative control's bespoke
 * `FullQualityCompressionOverride` object), the test fails loudly with a diagnostic rather than
 * silently passing -- which is the correct, intended outcome: that trap does not implement the
 * required interface-level capability at all.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, application = Application::class)
class MediaSendV3PreUploadRepositoryFullQualityTest {

  @get:Rule
  val signalDatabaseRule = SignalDatabaseRule()

  @get:Rule
  val appDependencies = MockAppDependenciesRule()

  companion object {
    @BeforeClass
    @JvmStatic
    fun setUpClass() {
      Log.initialize(SystemOutLogger())
    }

    /** Methods already present on PreUploadRepository at the pinned commit (441ba42c...). */
    private val BASELINE_METHODS = setOf(
      "preUpload",
      "cancelJobs",
      "deleteAttachment",
      "updateAttachmentCaption",
      "updateDisplayOrder",
      "deleteAbandonedPreuploadedAttachments"
    )

    private const val IMPL_CLASS = "org.thoughtcrime.securesms.mediasend.v3.MediaSendV3PreUploadRepository"

    /** Finds the single new interface method a correct solution is expected to have added. */
    private fun findNewCapabilityMethod(): Method {
      // Kotlin mangles JVM method names with a "-<hash>" suffix when a parameter is a value
      // class (e.g. preUpload(..., recipientId: MediaRecipientId, ...) -> "preUpload-49-Suxc"
      // at the pinned commit). Compare on the unmangled prefix so that doesn't look like a
      // "new" method.
      val candidates = PreUploadRepository::class.java.declaredMethods
        .filter { !it.isBridge && !it.isSynthetic }
        .filter { it.name.substringBefore('-') !in BASELINE_METHODS }

      if (candidates.isEmpty()) {
        fail(
          "No new method was added to PreUploadRepository (feature/media-send/src/main/java/org/signal/mediasend/preupload/PreUploadRepository.kt) " +
            "beyond the ${BASELINE_METHODS.size} that already existed at the pinned commit. A correct solution must expose the per-attachment " +
            "full-quality override through this interface (see required_existing_abstractions in metadata_B.yaml)."
        )
      }

      // Prefer a candidate that takes a boolean flag (matches "fullQuality: Boolean" in every
      // plausible naming of this capability); fall back to the first candidate otherwise.
      return candidates.firstOrNull { m -> m.parameterTypes.any { it == Boolean::class.java || it == java.lang.Boolean.TYPE } }
        ?: candidates.first()
    }

    private fun buildArgs(method: Method, context: Application, attachmentRowId: Long): Array<Any?> {
      return method.parameterTypes.map { type ->
        when {
          type.isAssignableFrom(Application::class.java) || type.name == "android.content.Context" -> context
          type == Long::class.java || type == java.lang.Long.TYPE -> attachmentRowId
          type == Boolean::class.java || type == java.lang.Boolean.TYPE -> true
          type.name == "org.signal.core.models.database.AttachmentId" -> {
            type.getConstructor(java.lang.Long.TYPE).newInstance(attachmentRowId)
          }
          type == String::class.java -> null
          else -> null
        }
      }.toTypedArray()
    }
  }

  @Test
  fun givenMultiItemBatch_whenOneMarkedFullQuality_thenOnlyThatAttachmentSkipsTransform() {
    val context = ApplicationProvider.getApplicationContext<Application>()
    val messageId = TestSms.insert(signalDatabaseRule.writeableDatabase)
    val markedId = AttachmentId(insertAttachment(messageId))
    val siblingId = AttachmentId(insertAttachment(messageId))

    val method = findNewCapabilityMethod()
    val implClass = Class.forName(IMPL_CLASS)
    val instance = implClass.getField("INSTANCE").get(null)
    val implMethod = implClass.getMethod(method.name, *method.parameterTypes)
    implMethod.isAccessible = true

    val args = buildArgs(method, context, markedId.id)
    implMethod.invoke(instance, *args)

    val marked = SignalDatabase.attachments.getAttachment(markedId)
    val sibling = SignalDatabase.attachments.getAttachment(siblingId)

    assertNotNull("Marked attachment should still exist after invoking ${method.name}", marked)
    assertNotNull("Marked attachment's transformProperties should not be null", marked!!.transformProperties)
    assertTrue(
      "Expected transformProperties.skipTransform == true on the marked attachment after invoking PreUploadRepository#${method.name}",
      marked.transformProperties!!.skipTransform
    )
    assertFalse(
      "Sibling attachment (never marked) must remain compressed as usual (skipTransform == false)",
      sibling!!.transformProperties?.skipTransform ?: false
    )
  }

  @Test
  fun givenFullQualityMarked_whenReReadFromDatabase_thenChoiceSurvivesProcessRecreation() {
    val context = ApplicationProvider.getApplicationContext<Application>()
    val messageId = TestSms.insert(signalDatabaseRule.writeableDatabase)
    val markedId = AttachmentId(insertAttachment(messageId))

    val method = findNewCapabilityMethod()
    val implClass = Class.forName(IMPL_CLASS)
    val instance = implClass.getField("INSTANCE").get(null)
    val implMethod = implClass.getMethod(method.name, *method.parameterTypes)
    implMethod.isAccessible = true
    implMethod.invoke(instance, *buildArgs(method, context, markedId.id))

    // Simulate process recreation: re-read straight from the persisted row rather than any
    // surviving in-memory ViewModel/UI/cache state (this is a fresh DB query, same as a newly
    // constructed AppDependencies/ViewModel would perform after the app process is relaunched).
    val persisted = SignalDatabase.attachments.getTransformProperties(markedId)

    assertNotNull(persisted)
    assertTrue(
      "The full-quality choice must be persisted on the attachment row, not just transient UI state, " +
        "so it survives the app process being killed and relaunched mid-send.",
      persisted!!.skipTransform
    )
  }

  private fun insertAttachment(messageId: Long): Long {
    return SignalDatabase.writableDatabase.insert(
      AttachmentTable.TABLE_NAME,
      null,
      ContentValues().apply {
        put(AttachmentTable.MESSAGE_ID, messageId)
        put(AttachmentTable.TRANSFER_STATE, AttachmentTable.TRANSFER_PROGRESS_DONE)
        put(AttachmentTable.CONTENT_TYPE, "image/jpeg")
      }
    )
  }
}
