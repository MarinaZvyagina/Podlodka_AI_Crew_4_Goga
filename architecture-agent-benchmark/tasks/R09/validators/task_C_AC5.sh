#!/usr/bin/env bash
# R09 Task C (alternative speech pipeline) — AC5
# "Tests exist exercising both pipelines through the same public entry points."
# Method (runnable, best-effort): (1) build & run the QuickAnswersKitTests suite end to end
# (this fails loudly if the new engine doesn't compile or if any existing test regressed);
# (2) grep the tests directory for evidence that more than one concrete
# TranscriptionEngine-conforming type (beyond the pre-existing Mock/SFSpeechRecognizerEngine/
# SpeechAnalyzerEngine trio) is referenced from a *_Tests.swift file, as a heuristic proxy for
# "both pipelines are exercised through DefaultQuickAnswersService's public entry points".
# This is necessarily heuristic (it cannot know the new engine's chosen name in advance); a human
# should still skim the test diff to confirm record()/stopRecording() — not new bespoke methods —
# are what's being exercised.
set -uo pipefail

REPO="${1:-.}"
REPO="$(cd "$REPO" 2>/dev/null && pwd)"
BK="$REPO/BrowserKit"
TESTS_DIR="$BK/Tests/QuickAnswersKitTests"

if [ ! -d "$TESTS_DIR" ]; then
  echo "FAIL: AC5 - $TESTS_DIR not found"
  exit 1
fi

# NOTE: plain `swift test` does not work in this environment (the `Common` target unconditionally
# imports UIKit, and bare `swift build`/`swift test` default to the host macOS SDK). The
# per-library `QuickAnswersKit` scheme that Xcode auto-generates for this SwiftPM package also
# turns out not to have a Test action wired to a test bundle in this environment ("There are no
# test bundles available to test"). The `BrowserKit-Package` aggregate scheme (which bundles every
# target, including all test targets) does work with `-only-testing:` to scope it down to just
# QuickAnswersKitTests, so we use that instead — this actually builds and runs the real
# QuickAnswersKitTests test target on an iOS Simulator destination.
SIM_NAME=$(xcrun simctl list devices available 2>/dev/null | grep -m1 'iPhone' | sed -E 's/^[[:space:]]*([A-Za-z0-9 ]+) \(.*/\1/')
SIM_NAME="${SIM_NAME:-iPhone 17}"

pushd "$BK" >/dev/null || exit 1
OUTPUT=$(xcodebuild test \
  -scheme BrowserKit-Package \
  -destination "platform=iOS Simulator,name=$SIM_NAME" \
  -only-testing:QuickAnswersKitTests \
  2>&1)
STATUS=$?
popd >/dev/null

echo "$OUTPUT" | tail -80

if [ "$STATUS" -ne 0 ] || ! echo "$OUTPUT" | grep -q '\*\* TEST SUCCEEDED \*\*'; then
  echo "FAIL: AC5 - QuickAnswersKitTests suite did not build/pass; cannot confirm dual-pipeline coverage"
  exit 1
fi

# Heuristic: look for a TranscriptionEngine-conforming type name referenced in the tests that
# is not one of the three known baseline names.
KNOWN='MockTranscriptionEngine|SFSpeechRecognizerEngine|SpeechAnalyzerEngine'
CANDIDATES=$(grep -rhoE '[A-Za-z0-9_]*(Engine|Pipeline)[A-Za-z0-9_]*' "$TESTS_DIR" 2>/dev/null \
  | grep -Ev "^($KNOWN)$" \
  | grep -Ev '^(TranscriptionEngine|AudioEngine|AudioEngineProvider|MockAudioEngine|Engine)$' \
  | sort -u)

if [ -z "$CANDIDATES" ]; then
  echo "FAIL: AC5 - QuickAnswersKitTests passed, but no reference to a new engine/pipeline type was found in the tests directory; dual-pipeline coverage could not be confirmed"
  exit 1
else
  echo "PASS: AC5 - QuickAnswersKitTests suite passes, and the following candidate new-pipeline identifier(s) are referenced from tests (manually confirm these exercise record()/stopRecording(), not bespoke test-only methods):"
  echo "$CANDIDATES" | sed 's/^/  /'
  exit 0
fi
