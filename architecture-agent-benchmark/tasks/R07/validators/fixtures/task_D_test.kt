package tachiyomi.data.source

import androidx.paging.PagingSource
import eu.kanade.tachiyomi.source.Source
import eu.kanade.tachiyomi.source.model.FilterList
import eu.kanade.tachiyomi.source.model.MangasPage
import eu.kanade.tachiyomi.source.model.SManga
import io.kotest.matchers.shouldBe
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test
import tachiyomi.domain.manga.interactor.NetworkToLocalManga
import tachiyomi.domain.manga.model.Manga

/**
 * Functional validator fixture for R07-TD ("cache repeated source searches"). Exercises the
 * caching behavior through tachiyomi.data.source.SourceSearchPagingSource /
 * SourcePopularPagingSource (the paging sources tachiyomi.data.source.SourceRepositoryImpl
 * constructs for tachiyomi.domain.source.repository.SourceRepository.search()/getPopular()/
 * getLatest() - the required entry point per this task's architectural_constraints), using a
 * mocked eu.kanade.tachiyomi.source.Source with a call counter: a repeated, identical request
 * shortly afterward must not hit the underlying Source again, an expired entry (or explicit
 * invalidate) must, and pagination across multiple pages of a cached search must keep returning
 * the correct page.
 *
 * Note on genericity: this fixture is written against the specific caching shape used by this
 * benchmark's reference/positive-control implementation (a dedicated
 * `tachiyomi.data.source.SourceSearchCache` class threaded into the paging sources'
 * constructors, as named explicitly in this task's CONTROL_RESULTS.md verdict). A fully
 * implementation-agnostic version (tolerant of e.g. caching being inlined directly inside
 * SourceRepositoryImpl with a different constructor shape) would require runtime
 * reflection-based dependency construction; see FUNCTIONAL_VALIDATORS.md for why that tradeoff
 * was made and what it means for candidates that structure the cache differently.
 */
class SourceSearchCacheTest {

    private fun sManga(tag: String) = SManga.create().apply {
        url = "url-$tag"
        title = "Title $tag"
    }

    private fun page(tag: String, hasNextPage: Boolean = false) =
        MangasPage(mangas = listOf(sManga(tag)), hasNextPage = hasNextPage)

    private fun fakeSource(callCounter: IntArray, id: Long = 1L): Source {
        val source = mockk<Source>()
        every { source.id } returns id
        coEvery { source.getSearchManga(any(), any(), any()) } answers {
            callCounter[0]++
            page("search")
        }
        coEvery { source.getPopularManga(any()) } answers {
            callCounter[0]++
            page("popular")
        }
        coEvery { source.getLatestUpdates(any()) } answers {
            callCounter[0]++
            page("latest")
        }
        return source
    }

    private fun passthroughNetworkToLocalManga(): NetworkToLocalManga {
        val networkToLocalManga = mockk<NetworkToLocalManga>()
        coEvery { networkToLocalManga(any<List<Manga>>()) } answers { firstArg() }
        return networkToLocalManga
    }

    private suspend fun PagingSource<Long, Manga>.refresh() =
        load(PagingSource.LoadParams.Refresh(key = null, loadSize = 25, placeholdersEnabled = false))
            as PagingSource.LoadResult.Page<Long, Manga>

    private suspend fun PagingSource<Long, Manga>.append(key: Long) =
        load(PagingSource.LoadParams.Append(key = key, loadSize = 25, placeholdersEnabled = false))
            as PagingSource.LoadResult.Page<Long, Manga>

    @Test
    fun `repeating an identical search shortly after reuses the cached result`() = runTest {
        val callCounter = intArrayOf(0)
        val source = fakeSource(callCounter)
        val networkToLocalManga = passthroughNetworkToLocalManga()
        val cache = SourceSearchCache()

        repeat(2) {
            SourceSearchPagingSource(source, "one piece", FilterList(), networkToLocalManga, cache).refresh()
        }

        callCounter[0] shouldBe 1
    }

    @Test
    fun `repeating an identical popular listing shortly after reuses the cached result`() = runTest {
        val callCounter = intArrayOf(0)
        val source = fakeSource(callCounter)
        val networkToLocalManga = passthroughNetworkToLocalManga()
        val cache = SourceSearchCache()

        repeat(2) {
            SourcePopularPagingSource(source, networkToLocalManga, cache).refresh()
        }

        callCounter[0] shouldBe 1
    }

    @Test
    fun `a different query for the same source is not served from another entry's cache`() = runTest {
        val callCounter = intArrayOf(0)
        val source = fakeSource(callCounter)
        val networkToLocalManga = passthroughNetworkToLocalManga()
        val cache = SourceSearchCache()

        SourceSearchPagingSource(source, "one piece", FilterList(), networkToLocalManga, cache).refresh()
        SourceSearchPagingSource(source, "bleach", FilterList(), networkToLocalManga, cache).refresh()

        callCounter[0] shouldBe 2
    }

    @Test
    fun `a call after the cache expires hits the network again`() = runTest {
        val callCounter = intArrayOf(0)
        val source = fakeSource(callCounter)
        val networkToLocalManga = passthroughNetworkToLocalManga()
        val cache = SourceSearchCache()
        var now = 0L
        cache.nowProvider = { now }

        SourceSearchPagingSource(source, "one piece", FilterList(), networkToLocalManga, cache).refresh()

        // Still within the TTL window: served from cache.
        now += cache.ttlMillis - 1
        SourceSearchPagingSource(source, "one piece", FilterList(), networkToLocalManga, cache).refresh()
        callCounter[0] shouldBe 1

        // Past the TTL window: cache entry is stale, network is hit again.
        now += 2
        SourceSearchPagingSource(source, "one piece", FilterList(), networkToLocalManga, cache).refresh()
        callCounter[0] shouldBe 2
    }

    @Test
    fun `an explicit invalidate forces a fresh fetch`() = runTest {
        val callCounter = intArrayOf(0)
        val source = fakeSource(callCounter)
        val networkToLocalManga = passthroughNetworkToLocalManga()
        val cache = SourceSearchCache()

        SourceSearchPagingSource(source, "one piece", FilterList(), networkToLocalManga, cache).refresh()
        cache.invalidate(cache.key(source.id, "search", "one piece", FilterList()))
        SourceSearchPagingSource(source, "one piece", FilterList(), networkToLocalManga, cache).refresh()

        callCounter[0] shouldBe 2
    }

    @Test
    fun `paginating through a cached search still returns the correct page each time`() = runTest {
        val callCounter = intArrayOf(0)
        val source = mockk<Source>()
        every { source.id } returns 1L
        coEvery { source.getSearchManga(1, any(), any()) } answers {
            callCounter[0]++
            page("page1", hasNextPage = true)
        }
        coEvery { source.getSearchManga(2, any(), any()) } answers {
            callCounter[0]++
            page("page2", hasNextPage = false)
        }
        val networkToLocalManga = passthroughNetworkToLocalManga()
        val cache = SourceSearchCache()

        val firstSession = SourceSearchPagingSource(source, "one piece", FilterList(), networkToLocalManga, cache)
        val firstPage = firstSession.refresh()
        val secondPage = firstSession.append(firstPage.nextKey!!)

        callCounter[0] shouldBe 2
        firstPage.data.single().url shouldBe "url-page1"
        secondPage.data.single().url shouldBe "url-page2"

        // Simulate navigating away and back: a brand-new PagingSource/session for the identical
        // query, shortly after, must be served entirely from the cache, page by page, with no
        // extra network calls.
        val secondSession = SourceSearchPagingSource(source, "one piece", FilterList(), networkToLocalManga, cache)
        val firstPageAgain = secondSession.refresh()
        val secondPageAgain = secondSession.append(firstPageAgain.nextKey!!)

        callCounter[0] shouldBe 2
        firstPageAgain.data.single().url shouldBe "url-page1"
        secondPageAgain.data.single().url shouldBe "url-page2"
    }
}
