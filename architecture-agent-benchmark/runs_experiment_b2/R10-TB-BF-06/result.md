# R10-TB-BF-06

Condition: goga_forced_workflow
Functional success: False
Full architecture conformance: False
ACR: 0.25
Dangerous success: False
Goga engagement signal: True
Cost: $1.3035822000000001
Duration: 214942ms, turns: 24

## Agent's own summary

The MEMORY.md index entry already covers this file generically, so no index update needed. Implementation is complete.

**Summary of changes** (all in `R10-TB-BF-06`):

1. **`SignalServiceKit/Storage/MediaGallery/MediaGalleryAttachmentFinder.swift`** — added `static func messageRowIdsWithBodyAttachments(inThreadId:restrictedToMessageRowIds:limit:tx:) -> Set<Int64>`, querying the same `MessageAttachmentReferenceRecord` table the "All Media" gallery already uses (body attachments only, excluding view-once and past-edit-revisions), so a message can never appear before its attachment is actually associated with it, and no separate index needs maintaining.

2. **`SignalUI/Search/FullTextSearcher.swift`** — `searchWithinConversation` gained an `onlyMessagesWithAttachments: Bool = false` parameter. With search text, it runs FTS/mentions as before then intersects the matched messages against the attachment row-id set. With empty text and the filter on, it skips FTS entirely and browses all attachment-bearing messages in the thread directly — this is what lets the filter work as a standalone "jump to shared media" mode, not just a narrowing of active text search.

3. **`Signal/ConversationView/ConversationSearch.swift`** — added a bookmark-button toggle (`isAttachmentsOnlyFilterEnabled`) on the existing search bar via `UISearchBarDelegate`, with a tinted icon and VoiceOver announcement on toggle, using the same search bar and `SearchResultsBar` prev/next navigation. The minimum-search-length gate is relaxed only when the filter is on with empty text, so plain text search behavior is untouched.

4. **`Localizable.strings`** — added `CONVERSATION_SEARCH_FILTER_ATTACHMENTS_ON`/`_OFF` strings.

Verified: `goga lint` stayed at `cells: 10 errors: 0` (none of the touched files are under Goga's governed contracts, confirmed via `goga schema`), `xcrun swiftc -parse` succeeded on all three edited Swift files, and `plutil -lint` passed on the strings file. A real compile isn't possible in this checkout (standing GRDB/BonMot/UIKit module-resolution issue), consistent with prior runs.
