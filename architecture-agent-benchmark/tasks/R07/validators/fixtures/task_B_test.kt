package tachiyomi.domain.updates.interactor

import io.kotest.matchers.shouldBe
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Test
import tachiyomi.domain.manga.model.MangaCover
import tachiyomi.domain.updates.model.UpdatesWithRelations
import tachiyomi.domain.updates.repository.UpdatesRepository

/**
 * Functional validator fixture for R07-TB ("let users temporarily hide a series from the
 * Updates feed"). Black-box against the real public entry point mandated by this task's
 * required_existing_abstractions: tachiyomi.domain.updates.interactor.GetUpdates backed by a
 * fake tachiyomi.domain.updates.repository.UpdatesRepository (an interface implementation, not
 * an internal helper of one candidate).
 *
 * Verifies that GetUpdates correctly threads "current time" through to the repository so that a
 * manga which is still snoozed ("remind me later") is excluded from the updates feed, one whose
 * snooze has expired is included again, an un-snoozed manga is unaffected, and snoozing one
 * manga does not affect another - mirroring the WHERE-clause filter expected in
 * updatesView.sq (`snoozedUntil = 0 OR snoozedUntil <= :currentTime`).
 *
 * This intentionally only compiles/runs against implementations that route the snooze filter
 * through GetUpdates/UpdatesRepository's `currentTime` parameter, per this task's architectural
 * constraints. See FUNCTIONAL_VALIDATORS.md for what happens (and why) against an implementation
 * that instead filters client-side outside this pipeline.
 */
class GetUpdatesSnoozeTest {

    private val now = 10_000L
    private val future = now + 100_000L // still snoozed
    private val past = now - 100_000L // snooze has expired

    private fun update(mangaId: Long) = UpdatesWithRelations(
        mangaId = mangaId,
        mangaTitle = "Manga $mangaId",
        chapterId = mangaId * 10,
        chapterName = "Chapter 1",
        scanlator = null,
        chapterUrl = "url",
        read = false,
        bookmark = false,
        lastPageRead = 0,
        sourceId = 1L,
        dateFetch = now,
        coverData = MangaCover(
            mangaId = mangaId,
            sourceId = 1L,
            isMangaFavorite = true,
            url = null,
            lastModified = 0L,
        ),
    )

    /**
     * Mirrors the `snoozedUntil = 0 OR snoozedUntil <= :currentTime` filter expected in
     * data/src/main/sqldelight/tachiyomi/view/updatesView.sq's queries.
     */
    private class FakeUpdatesRepository(
        private val entries: List<Pair<UpdatesWithRelations, Long>>,
    ) : UpdatesRepository {

        private fun filtered(currentTime: Long): List<UpdatesWithRelations> {
            return entries
                .filter { (_, snoozedUntil) -> snoozedUntil == 0L || snoozedUntil <= currentTime }
                .map { it.first }
        }

        override suspend fun awaitWithRead(
            read: Boolean,
            after: Long,
            limit: Long,
            currentTime: Long,
        ): List<UpdatesWithRelations> = filtered(currentTime)

        override fun subscribeAll(
            after: Long,
            limit: Long,
            unread: Boolean?,
            started: Boolean?,
            bookmarked: Boolean?,
            hideExcludedScanlators: Boolean,
            includedCategories: List<Long>,
            excludedCategories: List<Long>,
            currentTime: Long,
        ): Flow<List<UpdatesWithRelations>> = flowOf(filtered(currentTime))

        override fun subscribeWithRead(
            read: Boolean,
            after: Long,
            limit: Long,
            currentTime: Long,
        ): Flow<List<UpdatesWithRelations>> = flowOf(filtered(currentTime))
    }

    @Test
    fun `manga snoozed until a future time is excluded from updates`() {
        runBlocking {
            val snoozedManga = update(mangaId = 1L)
            val repository = FakeUpdatesRepository(listOf(snoozedManga to future))
            val getUpdates = GetUpdates(repository)

            getUpdates.await(read = false, after = 0L, currentTime = now) shouldBe emptyList()
        }
    }

    @Test
    fun `manga whose snooze has passed is included in updates`() {
        runBlocking {
            val unsnoozedManga = update(mangaId = 2L)
            val repository = FakeUpdatesRepository(listOf(unsnoozedManga to past))
            val getUpdates = GetUpdates(repository)

            getUpdates.await(read = false, after = 0L, currentTime = now) shouldBe listOf(unsnoozedManga)
        }
    }

    @Test
    fun `manga that was never snoozed is always included`() {
        runBlocking {
            val neverSnoozed = update(mangaId = 3L)
            val repository = FakeUpdatesRepository(listOf(neverSnoozed to 0L))
            val getUpdates = GetUpdates(repository)

            getUpdates.await(read = false, after = 0L, currentTime = now) shouldBe listOf(neverSnoozed)
        }
    }

    @Test
    fun `snoozing one manga does not affect another manga's visibility`() {
        runBlocking {
            val snoozed = update(mangaId = 4L)
            val visible = update(mangaId = 5L)
            val repository = FakeUpdatesRepository(listOf(snoozed to future, visible to past))
            val getUpdates = GetUpdates(repository)

            val result = getUpdates.subscribe(read = false, after = 0L, currentTime = now).first()
            result shouldBe listOf(visible)
        }
    }
}
