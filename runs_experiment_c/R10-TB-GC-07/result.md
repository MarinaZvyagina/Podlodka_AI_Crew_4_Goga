# R10-TB-GC-07

Condition: goga_native_architecture
Base tag: condition-c-r10-v1
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: True
Cost: $1.2353801999999998
Duration: 147637ms, turns: 27

## Agent's own summary

## Summary

Added a "shared media only" filter to Signal-iOS's in-conversation search, reusing the existing search bar and prev/next navigation:

- **`Signal/ConversationView/ConversationSearch.swift`** — `ConversationSearchController` now shows a bookmark button on the search bar (`Theme.iconImage(.photo16)`, tinted accent color when active) that toggles a private `isAttachmentsOnlyFilterEnabled` flag via a new `UISearchBarDelegate` conformance. The minimum-search-length gate is relaxed so the filter alone can browse all shared media with empty search text, and toggling forces a fresh search.
- **`SignalUI/Search/FullTextSearcher.swift`** — `searchWithinConversation` gained an `onlyMessagesWithAttachments` param. With search text, it runs the existing full-text/mention search then intersects matches against attachment-bearing message row IDs. With empty text and the filter on, it skips FTS entirely and browses attachment-bearing messages directly. Works identically for 1:1 and group threads since it operates on the same underlying search path both share.
- **`SignalServiceKit/Storage/MediaGallery/MediaGalleryAttachmentFinder.swift`** — added `messageRowIdsWithBodyAttachments(inThreadId:restrictedToMessageRowIds:limit:tx:)`, querying the same live `AttachmentReferences` table the media gallery already uses — so results always reflect an attachment's current association state with no separate index to keep in sync.
- Added two `OWSLocalizedString` keys for VoiceOver announcements when the filter toggles on/off.

Verified via `xcrun swiftc -parse` (clean) on all three edited files, `plutil -lint` on the strings file, and `goga lint` (`cells: 52 errors: 0`, unchanged — these files aren't under a governing CODEMANIFEST in this checkout, confirmed by checking `goga schema` first).
