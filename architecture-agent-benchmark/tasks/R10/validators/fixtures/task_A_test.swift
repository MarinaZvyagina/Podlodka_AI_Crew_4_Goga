// === TASK_A_FUNCTIONAL_VALIDATOR_FIXTURE ===
// Injected temporarily by validators/task_A_functional.sh into
// SignalServiceKit/tests/Attachments/AutoDownloadPolicyTest.swift (an existing, already-project-referenced
// test file), and stripped back out afterward. Not part of the permanent test suite.
//
// Black-box, implementation-agnostic test of the REAL public entry point named in metadata_A.yaml's
// required_existing_abstractions: `AutoDownloadPolicy.build` and `MediaBandwidthPreferences.MediaType`.
// Deliberately does NOT assume the new MediaType case's name (any candidate is free to name it anything, per
// public_api_constraints — only the raw string must be new/stable). It only asserts on externally observable
// behavior:
//   1. A 5th MediaType case now exists (independently configurable, alongside photo/video/audio/document).
//   2. A large (> alwaysLimit) voice-message audio attachment resolves to *some* `.preference(mediaType:)`
//      that is NOT `.audio` and NOT `.always` -- i.e. routed to a distinct preference, not silently folded
//      into the existing general audio setting (this is the task's explicit "must be a real behavior change,
//      not just a new settings row" requirement).
//   3. A small (< alwaysLimit) voice-message audio attachment still resolves to `.always` (existing fast path
//      preserved).
//   4. A non-voice-message audio attachment of the same large size still resolves to `.preference(mediaType:
//      .audio)` (existing behavior for regular audio attachments is unchanged).
//
// Reuses Testing (Swift Testing framework) + @testable import SignalServiceKit exactly like the sibling
// AutoDownloadPolicyTest.swift in the same file, and deliberately avoids relying on that file's
// `extension AutoDownloadPolicy: @retroactive Equatable` (via switch/case matching instead), so this fixture
// is self-contained even if a candidate diff altered or removed that extension.

enum TaskAFunctionalValidatorFixture {

    @Test
    static func voiceMessagePreferenceExistsAndIsIndependentlyConfigurable() {
        #expect(
            MediaBandwidthPreferences.MediaType.allCases.count >= 5,
            "expected a 5th (or more) MediaType case for voice messages in addition to photo/video/audio/document",
        )
    }

    @Test
    static func largeVoiceMessageIsRoutedAwayFromGeneralAudioPreference() {
        let policy = AutoDownloadPolicy.build(
            context: .body,
            mimeType: "audio/aac",
            renderingFlag: .voiceMessage,
            plaintextSize: 5_000_000, // well above alwaysLimit (100KB)
        )
        switch policy {
        case .preference(let mediaType):
            #expect(mediaType != .audio, "large voice messages must not share the general .audio preference")
        case .always, .never:
            Issue.record("expected large voice message to resolve to a distinct .preference(mediaType:), got \(policy)")
        }
    }

    @Test
    static func smallVoiceMessageFastPathIsPreserved() {
        let policy = AutoDownloadPolicy.build(
            context: .body,
            mimeType: "audio/aac",
            renderingFlag: .voiceMessage,
            plaintextSize: 50_000, // well below alwaysLimit (100KB)
        )
        switch policy {
        case .always:
            break
        default:
            Issue.record("expected small voice message to keep resolving to .always, got \(policy)")
        }
    }

    @Test
    static func nonVoiceAudioAttachmentsAreUnaffected() {
        let policy = AutoDownloadPolicy.build(
            context: .body,
            mimeType: "audio/aac",
            renderingFlag: .default,
            plaintextSize: 5_000_000,
        )
        switch policy {
        case .preference(let mediaType) where mediaType == .audio:
            break
        default:
            Issue.record("expected non-voice-message audio attachment to keep resolving to .preference(mediaType: .audio), got \(policy)")
        }
    }
}
// === END TASK_A_FUNCTIONAL_VALIDATOR_FIXTURE ===
