## Let users temporarily hide a series from the Updates feed

Users have asked for a way to temporarily hide a specific series from their "Updates" feed
(the list of new chapters for series in their library) without removing it from their library or
turning off notifications for it entirely. The idea is similar to "remind me later" / snoozing an
email: from the updates list, or from the series' own details page, the user should be able to
pick "remind me later" and choose how long to hide it for (e.g. a fixed set of options like
tomorrow / next week, or a custom date).

While a series is snoozed, new chapters for it should not show up in the updates feed, but they
should still download and behave normally in the background — nothing else about the series
changes. Once the snooze period has passed, the series should automatically start showing up in
the updates feed again the next time it has new content, with no further action needed from the
user. Users should also be able to clear an active snooze manually before it expires.

The feature needs to work correctly together with the updates feed's existing filters (e.g.
filtering by read/unread, by category, by bookmarked chapters) — snoozing one series must not
affect any other series, and the existing filters must keep working as before.
