package eu.kanade.tachiyomi.data.track

import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.lang.reflect.Method

/**
 * Functional validator fixture for R07-TC ("sync reading progress with a self-hosted library
 * server"). Black-box against the app's existing, generic extension point -
 * eu.kanade.tachiyomi.data.track.Tracker / BaseTracker / TrackerManager - which is the sole
 * mechanism every current tracker (MyAnimeList, AniList, Kitsu, Shikimori, Bangumi, Komga,
 * MangaUpdates, Kavita, Suwayomi, Hikka, MangaBaka) already uses. Does not reference any
 * specific new tracker's class/package name or internal helpers.
 *
 * Deliberately reflection-only, with NO instantiation of TrackerManager (or any tracker):
 * eu.kanade.tachiyomi.data.track.anilist.Anilist has an `init {}` block that eagerly touches
 * BaseTracker's Injekt/appGraph-backed preference plumbing, which throws
 * uy.kohesive.injekt.api.InjektionException outside a fully initialized Android app graph -
 * i.e. under a plain JVM unit test, `TrackerManager()` cannot be constructed at all, baseline
 * behavior or not. Instead this inspects TrackerManager's compiled shape via java.lang.reflect:
 * every existing tracker is exposed as its own public, zero-argument, no-collection property
 * getter (getMyAnimeList(), getAniList(), ..., getMangaBaka()) whose return type implements
 * Tracker - a new integration registered the same way adds one more such getter, detectable
 * without ever running tracker/DI code.
 */
class TrackerRegistrationTest {

    private val trackerInterface = Class.forName("eu.kanade.tachiyomi.data.track.Tracker")

    /**
     * Public, zero-arg getters on TrackerManager whose return type implements Tracker - i.e. one
     * hardcoded property per registered tracker, exactly the pattern every existing tracker
     * (myAnimeList, aniList, kitsu, shikimori, bangumi, komga, mangaUpdates, kavita, suwayomi,
     * hikka, mangaBaka) already follows. Excludes `trackers`/`loggedInTrackers` (return a List,
     * not a Tracker) and `get`/`getAll` (take parameters).
     */
    private fun trackerPropertyGetters(): List<Method> {
        return TrackerManager::class.java.declaredMethods.filter { method ->
            method.parameterCount == 0 &&
                method.name.startsWith("get") &&
                method.name != "getTrackers" &&
                trackerInterface.isAssignableFrom(method.returnType)
        }
    }

    @Test
    fun `a new tracker property beyond the baseline 11 is declared on TrackerManager`() {
        val getters = trackerPropertyGetters()

        assertTrue(
            getters.size > 11,
            "Expected TrackerManager to declare a new tracker property beyond the baseline 11 " +
                "(one per existing tracker: myAnimeList, aniList, kitsu, shikimori, bangumi, " +
                "komga, mangaUpdates, kavita, suwayomi, hikka, mangaBaka), but found only " +
                "${getters.size}: ${getters.map { it.name }}. A reading-progress-sync " +
                "integration implemented as a standalone class bypassing " +
                "Tracker/BaseTracker/TrackerManager (the documented architectural trap for this " +
                "task) will never show up here.",
        )
    }

    @Test
    fun `the new tracker property extends BaseTracker like every existing tracker`() {
        val baseTrackerClass = Class.forName("eu.kanade.tachiyomi.data.track.BaseTracker")
        val getters = trackerPropertyGetters()

        val nonConforming = getters.filterNot { baseTrackerClass.isAssignableFrom(it.returnType) }

        assertTrue(
            nonConforming.isEmpty(),
            "Expected every tracker property on TrackerManager (including any new one) to " +
                "extend BaseTracker, like every existing tracker does, but these do not: " +
                "${nonConforming.map { "${it.name} -> ${it.returnType.name}" }}",
        )
    }

    @Test
    fun `the trackers registry field is still a plain list (registry contract unchanged)`() {
        val trackersGetter = TrackerManager::class.java.getDeclaredMethod("getTrackers")

        assertTrue(
            java.util.List::class.java.isAssignableFrom(trackersGetter.returnType),
            "TrackerManager.trackers is expected to remain a List<Tracker>-shaped registry " +
                "(found return type ${trackersGetter.returnType.name}) - i.e. the new tracker " +
                "should be added as one more entry in the existing hardcoded list, not via a " +
                "new parallel registry/manager class.",
        )
    }
}
