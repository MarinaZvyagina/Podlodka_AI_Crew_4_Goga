// Auto-generated fixture for validators/task_C_functional.sh — not part of any submitted solution.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/
//
// Black-box functional regression test for R09 Task C ("A/B test an alternative speech-to-text
// pipeline for voice search"). This test is deliberately implementation-agnostic about *how* the
// candidate wires up their new pipeline/flag (the metadata explicitly allows the new init parameter
// to have any name), so it does not attempt to guess or call a candidate-specific flag. Instead it
// exercises the one relevant capability that is guaranteed to exist regardless of implementation:
// DefaultQuickAnswersService's public initializer already accepts an injected `engine:
// TranscriptionEngine?` (this predates this task and must remain unchanged per the task's own
// public_api_constraints), so this test injects an arbitrary TranscriptionEngine conformer — the
// pre-existing MockTranscriptionEngine test double, standing in for "whichever pipeline is active"
// — and asserts that record()/stopRecording()/search(text:) behave identically through the public
// entry points no matter which concrete engine backs the service. This is exactly functional
// requirement (b) from the ticket: "record()/stopRecording() behave identically (same call sequence
// into whichever engine is active) regardless of which pipeline is selected."
//
// This test alone CANNOT verify functional requirement (a) ("a second, alternative speech
// transcription implementation is added") because that requires knowing the candidate's new
// engine's type name, which isn't fixed by the API contract. The validator script that injects this
// fixture additionally greps BrowserKit/Sources/QuickAnswersKit/Backend/SpeechService/ for a new
// TranscriptionEngine conformer beyond the two pre-existing ones (SFSpeechRecognizerEngine,
// SpeechAnalyzerEngine) to cover that requirement structurally.

import Shared
import Testing
import TestKit

@testable import QuickAnswersKit

@MainActor
final class R09TaskCFunctionalTests {
    let testHelper = SwiftTestingHelper()

    /// Functional requirement (unchanged public surface): DefaultQuickAnswersService can still be
    /// constructed and used through record()/stopRecording()/search(text:) exactly as before, with
    /// no changes required at call sites (existing default-argument call sites keep working).
    @Test
    func test_record_stopRecording_search_workThroughPublicEntryPoints_withInjectedEngine() async throws {
        let engine = MockTranscriptionEngine()
        engine.resultsToYield = [
            SpeechResult(text: "What is the weather", isFinal: false),
            SpeechResult(text: "today?", isFinal: true)
        ]
        let resultsServiceFactory = MockResultsServiceFactory()

        let subject = try DefaultQuickAnswersService(
            engine: engine,
            configFetcher: MockQuickAnswersConfigFetcher(),
            resultsServiceFactory: resultsServiceFactory,
            prefs: MockProfilePrefs()
        )
        testHelper.trackForMemoryLeaks(subject)

        let stream = try await subject.record()
        var received: [SpeechResult] = []
        for try await value in stream { received.append(value) }
        #expect(received.count == engine.resultsToYield.count)
        #expect(engine.prepareCallCount == 1)
        #expect(engine.startCallCount == 1)

        try await subject.stopRecording()
        #expect(engine.stopCallCount == 1)

        let result = await subject.search(text: "hello")
        switch result {
        case .success(let searchResult):
            #expect(searchResult == SearchResult.empty())
        case .failure(let error):
            Issue.record("Expected success(.empty()), got failure: \(error)")
        }
    }

    /// Functional requirement: "Enrolled vs. non-enrolled users should be able to run side by side
    /// without interfering with each other (e.g. no shared mutable state that would leak between
    /// them)." Two independently-constructed service instances, each with their own injected
    /// engine, must not share recording state.
    @Test
    func test_twoConcurrentServiceInstances_withDifferentEngines_doNotShareState() async throws {
        let engineA = MockTranscriptionEngine()
        engineA.resultsToYield = [SpeechResult(text: "A", isFinal: true)]
        let engineB = MockTranscriptionEngine()
        engineB.resultsToYield = [SpeechResult(text: "B", isFinal: true)]

        let subjectA = try DefaultQuickAnswersService(
            engine: engineA,
            configFetcher: MockQuickAnswersConfigFetcher(),
            resultsServiceFactory: MockResultsServiceFactory(),
            prefs: MockProfilePrefs()
        )
        let subjectB = try DefaultQuickAnswersService(
            engine: engineB,
            configFetcher: MockQuickAnswersConfigFetcher(),
            resultsServiceFactory: MockResultsServiceFactory(),
            prefs: MockProfilePrefs()
        )
        testHelper.trackForMemoryLeaks(subjectA)
        testHelper.trackForMemoryLeaks(subjectB)

        let streamA = try await subjectA.record()
        let streamB = try await subjectB.record()

        var receivedA: [SpeechResult] = []
        for try await value in streamA { receivedA.append(value) }
        var receivedB: [SpeechResult] = []
        for try await value in streamB { receivedB.append(value) }

        #expect(receivedA == engineA.resultsToYield)
        #expect(receivedB == engineB.resultsToYield)
        // Each instance's engine was driven independently — no cross-talk between the two cohorts.
        #expect(engineA.startCallCount == 1)
        #expect(engineB.startCallCount == 1)
    }
}
