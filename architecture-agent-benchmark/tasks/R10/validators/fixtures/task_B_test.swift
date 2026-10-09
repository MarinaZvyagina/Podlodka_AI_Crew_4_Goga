// === TASK_B_FUNCTIONAL_VALIDATOR_FIXTURE ===
// Injected temporarily by validators/task_B_functional.sh into
// Signal/test/util/FTS/GRDBFullTextSearcherTest.swift (an existing, already-project-referenced XCTest case
// for exactly this API), and stripped back out afterward. Not part of the permanent test suite.
//
// ASPIRATIONAL / for a full-build environment: this exercises the ARCHITECTURALLY-PRESCRIBED real public
// entry point named in metadata_B.yaml's required_existing_abstractions — `FullTextSearcher
// .searchWithinConversation`, extended with an `attachmentsOnly` parameter (per public_api_constraints, this
// should be addable as a new parameter with a default value so this call site and all others keep compiling).
//
// IMPORTANT — documented limitation: because "attachmentsOnly" filtering could legally be implemented at a
// different layer (e.g. entirely inside ConversationSearchController, as the negative/trap control does), a
// candidate that puts the filtering elsewhere will make this exact call fail to *compile* (no such parameter),
// not merely fail an assertion. That is precisely why validators/task_B_functional.sh does NOT treat this
// fixture's compilation as the sole source of truth for the functional verdict: the script's primary,
// implementation-agnostic automated signal is a static/behavioral scan (does *some* reachable code path filter
// search results using attachment-presence information, regardless of which file it lives in), with this
// fixture kept only as the best real dynamic test for the case where the architecturally-correct location was
// used, to be run when a full workspace build is actually feasible (see FUNCTIONAL_VALIDATORS.md).
extension GRDBFullTextSearcherTest {

    func test_taskB_attachmentsOnlyFilterNarrowsResultsAndDoesNotThrow() {
        // Minimal, self-contained scenario: a single 1:1 thread with one text-only message. We don't stand up
        // a real v2 attachment fixture here (that requires the full AttachmentManager pipeline), so this
        // smoke test only proves the new parameter exists, is callable through the real orchestration layer,
        // and does not throw / does not regress the unfiltered (attachmentsOnly: false) result for plain text.
        // A message actually carrying an attachment should also appear when attachmentsOnly is true and
        // disappear when it's false is absent here only because SignalBaseTest for the given commit; treat as
        // MANUAL REVIEW to extend with a real attachment insert in a full-build environment.
        self.write { transaction in
            let thread = TSContactThread.getOrCreateThread(withContactAddress: self.aliceRecipient.address, transaction: transaction)
            let message = TSOutgoingMessageBuilder(thread: thread, messageBody: "plain text, no attachment").build(transaction: transaction)
            message.anyInsert(transaction: transaction)

            do {
                let unfiltered = try self.searcher.searchWithinConversation(
                    threadUniqueId: thread.uniqueId,
                    isGroupThread: false,
                    searchText: "plain",
                    attachmentsOnly: false,
                    transaction: transaction,
                )
                let filtered = try self.searcher.searchWithinConversation(
                    threadUniqueId: thread.uniqueId,
                    isGroupThread: false,
                    searchText: "plain",
                    attachmentsOnly: true,
                    transaction: transaction,
                )
                XCTAssertGreaterThanOrEqual(unfiltered.messages.count, filtered.messages.count)
                XCTAssertEqual(filtered.messages.count, 0, "a text-only message with no attachment must not appear in attachments-only results")
            } catch {
                XCTFail("searchWithinConversation(attachmentsOnly:) threw unexpectedly: \(error)")
            }
        }
    }
}
// === END TASK_B_FUNCTIONAL_VALIDATOR_FIXTURE ===
