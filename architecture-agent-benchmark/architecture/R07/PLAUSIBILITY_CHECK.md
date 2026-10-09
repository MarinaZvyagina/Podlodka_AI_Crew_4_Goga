# PLAUSIBILITY_CHECK.md — R07 (mihonapp/mihon)

## When this check was performed

`tasks/R07/task_A.md` through `task_D.md` were read for the first time **after** `SCOPE.md` was
written and frozen, and after all 12 CODEMANIFEST files were authored, materialized, linted, and
drift-checked — per the assignment's explicit ordering requirement. No content in the
architecture forest was revised in response to reading the tasks (see "Outcome" below).

## The four task prompts (quoted)

- **Task A** ("Reject invalid custom extension repository URLs early"): validate a user-entered
  extension-repository URL client-side (must be `http://`/`https://`, reject empty/malformed/
  wrong-scheme input) before any network request, with a clear error message, "before making any
  network request."
- **Task B** ("Let users temporarily hide a series from the Updates feed"): a per-series
  "snooze"/"remind me later" toggle with a configurable duration that hides a manga from the
  Updates feed without affecting downloads, notifications, or library membership, auto-clearing
  when the snooze period passes, and composing correctly with the feed's existing
  read/unread/category/bookmark filters.
- **Task C** ("Sync reading progress with a self-hosted library server"): add login (any
  credential scheme), logout, and ongoing reading-progress sync for a self-hosted manga/comic
  server, "in the same general spirit as a few similar setups the app already talks to," visible
  per-library-entry, "sit[ting] naturally alongside whatever similar syncing options the app
  already offers."
- **Task D** ("Cache repeated source searches"): cache popular/latest/search results per
  query+filters for a short, expiring window, with a way to force a fresh fetch, correct across
  paginated scrolling.

## Term-level check: no task-specific vocabulary appears in the forest

Grepped all 12 CODEMANIFEST files for the task-specific terms each prompt turns on: none of
"repository url", "extension repository", "scheme", "malformed", "snooze", "remind me later",
"updates feed", "hide from updates", "self-hosted", "self hosted", "kavita", "komga", "suwayomi",
"cache", "caching", "ttl", "expire" appear anywhere in the forest (a repo-wide `grep -i` across
all 12 files returned zero matches for every term). The forest never says anything shaped like
"add caching here" or "add a snooze field" — every annotation describes what a real,
already-existing class/method does today, in the codebase's own vocabulary (e.g. `Tracker`,
`BaseTracker`, `TrackerManager`, `SourceManager`, `MangaRepository`, `Source.getSearchManga`),
consistent with `TREATMENT_DESIGN.md` §4's required phrasing style.

## Where genuine overlap exists, and why it's expected rather than leakage

One of the four tasks (C) touches functionality that lives squarely inside a cell this forest
documents — anticipated during scoping (the task instructions explicitly flagged this as the
pattern to check for, by analogy with R01's `IProtection`/Task C overlap) and confirmed here
after reading the actual prompt:

- **Task C ↔ `app/.../data/track` (the `Tracker`/`BaseTracker`/`TrackerManager` extension
  point)**: this is the closest overlap, structurally identical to R01's. Task C's "login/logout/
  ongoing sync with a self-hosted server, in the same spirit as similar setups the app already
  talks to" is a near-textbook new `Tracker` (the forest's `extension_point` practice says
  exactly: "implementing `Tracker` (typically by extending `BaseTracker`...)... registering one
  instance of it in `TrackerManager`'s `trackers` list with a stable, never-reused id"; the
  cell's own Annotations note that eleven trackers already exist, several of them
  literally self-hosted-server integrations — Kavita, Komga, Suwayomi — though those names are
  never mentioned in the forest itself). This is Task C's category by design (an Existing
  Extension Point task: the prompt does not name `Tracker` and the agent must discover or fail to
  discover it). The forest describes the *mechanism* (what `Tracker`/`BaseTracker`/
  `TrackerManager` are, how a concrete tracker plugs in, and that `EnhancedTracker`/
  `DeletableTracker` are optional add-on capabilities) using only real, pre-existing names; it
  never mentions self-hosted servers, sync, or login flows as a *feature to build*. An agent
  still has to recognize that Task C's request *is* a tracker integration and map "login" /
  "logout" / "ongoing progress sync" onto `Tracker.login`/`logout`/`update`/`refresh` and
  `BaseTracker`'s credential-storage plumbing — the forest doesn't perform that mapping for it.
  Judgment call: kept as-is, since documenting this real extension point generically is precisely
  the mechanism the Goga condition is meant to test (per `PROTOCOL.md` RQ7/RQ9 — does the
  treatment change existing-extension-point usage rate, and does the effect vary by task type),
  not an accidental giveaway of the answer.
- **Task A ↔ (no cell)**: no overlap. Nothing in this forest touches extension-repository
  management, URL validation, or app configuration/settings; that subsystem
  (`domain/.../release`, extension-repository handling in `app/.../extension`) was not in scope
  and is not referenced anywhere in the forest.
- **Task B ↔ (no cell)**: no overlap. The forest documents `Manga`'s `chapterFlags`-derived
  filters (unread/bookmarked/sort) as part of the manga aggregate, but nothing about the Updates
  feed, snoozing, or scheduling is mentioned; `domain/.../updates` was scoped out entirely (see
  `SCOPE.md`).
- **Task D ↔ `source-api/.../source`**: weak, favorable overlap only. The forest documents
  `Source.getPopularManga`/`getLatestUpdates`/`getSearchManga` as plain suspend methods returning
  a `MangasPage`, with no caching behavior mentioned anywhere in their annotations ("One page of
  the source's 'popular' manga listing" — nothing about freshness, TTL, or repeated calls). This
  is the same "no hint" outcome R01 found for its Task D (price-cache) against `freqtrade/exchange`.

## Outcome

No revision was made to the architecture forest as a result of this check. The one genuine
close-overlap case (Task C / `app/.../data/track`) was judged to be the expected, in-scope
operation of documenting a real, load-bearing extension point — not task-specific hint content —
and is disclosed here explicitly rather than papered over, per `TREATMENT_DESIGN.md` §4's
"independent plausibility check" requirement and consistent with how the R01 validation run
treated the analogous `IProtection`/Task C overlap for freqtrade. As with R01, no retroactive
rephrasing toward more-abstract `Usages` wording was performed here, to avoid the appearance of
hand-tuning the artifact after seeing the task list — which would itself be a worse violation of
the freeze discipline than leaving an honestly-disclosed, architecturally-justified overlap in
place.
