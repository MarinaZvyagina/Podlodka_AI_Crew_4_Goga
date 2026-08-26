#!/usr/bin/env bash
# R09 Task C (alternative speech-to-text pipeline, QuickAnswersKit) — FUNCTIONAL validator
#
# Ticket: "A/B test an alternative speech-to-text pipeline for voice search." A correct submission
# adds a second TranscriptionEngine conformer alongside SFSpeechRecognizerEngine/SpeechAnalyzerEngine
# and makes it selectable via a flag, while record()/stopRecording()/search(text:) keep behaving
# identically regardless of which pipeline backs the service.
#
# This script performs two complementary, real checks:
#   1. Injects a standalone, implementation-agnostic Swift Testing fixture
#      (validators/fixtures/task_C_test.swift) into BrowserKit/Tests/QuickAnswersKitTests/ and runs
#      the *entire* QuickAnswersKitTests test target for real via `xcodebuild test`. This both (a)
#      exercises the fixture's own black-box assertions about record()/stopRecording()/search(text:)
#      behaving identically regardless of which TranscriptionEngine is injected, via the pre-existing
#      `engine:` init parameter, and (b) runs whatever tests the candidate itself added for their new
#      pipeline (satisfying the ticket's own "add tests covering that both pipelines can be selected"
#      requirement) and confirms nothing pre-existing regressed.
#   2. Because the fixture cannot know the candidate's new engine type's name in advance (the flag
#      and the new engine class name are implementation details, not part of the public API contract
#      per the task's own public_api_constraints), it additionally does a structural check: grep
#      BrowserKit/Sources/QuickAnswersKit/Backend/SpeechService/*.swift for `: TranscriptionEngine`
#      conformers and require strictly more than the two that exist at the pinned commit
#      (SFSpeechRecognizerEngine, SpeechAnalyzerEngine). This directly checks functional requirement
#      "a second, alternative speech transcription implementation is added".
#
# Why `xcodebuild test` and not plain `swift test`: confirmed by direct reproduction that plain
# `swift build`/`swift test` fail in this environment ("no such module 'UIKit'" from the Common
# target resolving against the host macOS SDK). `xcodebuild test` against the aggregate
# `BrowserKit-Package` scheme (the per-target `QuickAnswersKit` scheme has no Test action wired to a
# bundle in this environment) scoped down with `-only-testing:QuickAnswersKitTests`, targeting an
# iOS Simulator destination, is the actually-working equivalent used throughout Phase 5 (see
# ../CONTROL_RESULTS.md).
#
# Usage: task_C_functional.sh [path-to-repo-root]  (default: .)
# Exit codes: 0 = PASS, 1 = FAIL.

set -uo pipefail

REPO="${1:-.}"
REPO="$(cd "$REPO" 2>/dev/null && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$REPO" ] || [ ! -d "$REPO" ]; then
  echo "FAIL: could not resolve repo path '$1'"
  exit 1
fi

BK="$REPO/BrowserKit"
TESTS_DIR="$BK/Tests/QuickAnswersKitTests"
SPEECH_SERVICE_DIR="$BK/Sources/QuickAnswersKit/Backend/SpeechService"

if [ ! -d "$TESTS_DIR" ]; then
  echo "FAIL: $TESTS_DIR not found"
  exit 1
fi
if [ ! -d "$SPEECH_SERVICE_DIR" ]; then
  echo "FAIL: $SPEECH_SERVICE_DIR not found"
  exit 1
fi

FIXTURE_SRC="$SCRIPT_DIR/fixtures/task_C_test.swift"
if [ ! -f "$FIXTURE_SRC" ]; then
  echo "FAIL: fixture not found at $FIXTURE_SRC"
  exit 1
fi

TEST_FILE="$TESTS_DIR/R09TaskCFunctionalTests.swift"
if [ -f "$TEST_FILE" ]; then
  echo "FAIL: $TEST_FILE already exists in the target repo; refusing to overwrite. Remove it and re-run."
  exit 1
fi

cleanup() { rm -f "$TEST_FILE"; }
trap cleanup EXIT

cp "$FIXTURE_SRC" "$TEST_FILE"

SIM_NAME=$(xcrun simctl list devices available 2>/dev/null | grep -m1 'iPhone' | sed -E 's/^[[:space:]]*([A-Za-z0-9 ]+) \(.*/\1/')
SIM_NAME="${SIM_NAME:-iPhone 17}"

pushd "$BK" >/dev/null || { echo "FAIL: could not cd into $BK"; exit 1; }
OUTPUT=$(xcodebuild test \
  -scheme BrowserKit-Package \
  -destination "platform=iOS Simulator,name=$SIM_NAME" \
  -only-testing:QuickAnswersKitTests \
  2>&1)
STATUS=$?
popd >/dev/null

echo "$OUTPUT" | tail -100

SUITE_OK=0
if [ "$STATUS" -eq 0 ] && echo "$OUTPUT" | grep -q '\*\* TEST SUCCEEDED \*\*'; then
  SUITE_OK=1
fi

# Structural check: count TranscriptionEngine conformers in Sources (baseline at the pinned commit
# is 2: SFSpeechRecognizerEngine, SpeechAnalyzerEngine). A correct submission adds a new one.
CONFORMER_COUNT=$(grep -rhoE '^\s*(final\s+)?class\s+[A-Za-z0-9_]+\s*:\s*[A-Za-z0-9_,\s]*TranscriptionEngine' \
  "$SPEECH_SERVICE_DIR" 2>/dev/null | wc -l | tr -d ' ')
CONFORMERS=$(grep -rnoE '^\s*(final\s+)?class\s+[A-Za-z0-9_]+\s*:\s*[A-Za-z0-9_,\s]*TranscriptionEngine' \
  "$SPEECH_SERVICE_DIR" 2>/dev/null)

echo
echo "TranscriptionEngine conformers found in $SPEECH_SERVICE_DIR:"
echo "$CONFORMERS" | sed 's/^/  /'
echo "Count: $CONFORMER_COUNT (baseline at the pinned commit is 2: SFSpeechRecognizerEngine, SpeechAnalyzerEngine)"

SECOND_ENGINE_OK=0
if [ "$CONFORMER_COUNT" -ge 3 ]; then
  SECOND_ENGINE_OK=1
fi

if [ "$SUITE_OK" -eq 1 ] && [ "$SECOND_ENGINE_OK" -eq 1 ]; then
  echo
  echo "PASS: Task C functional check — QuickAnswersKitTests suite (pre-existing + injected black-box fixture + any candidate-added tests) passes on iOS Simulator '$SIM_NAME', record()/stopRecording()/search(text:) behave identically regardless of which TranscriptionEngine is injected, and a new TranscriptionEngine conformer beyond the two pre-existing engines was found in Sources/QuickAnswersKit/Backend/SpeechService/."
  exit 0
elif [ "$SUITE_OK" -eq 0 ]; then
  echo
  echo "FAIL: Task C functional check — QuickAnswersKitTests did not build or pass (see xcodebuild output above)."
  exit 1
else
  echo
  echo "FAIL: Task C functional check — QuickAnswersKitTests passed, but no second TranscriptionEngine conformer was found in Sources/QuickAnswersKit/Backend/SpeechService/ beyond the two pre-existing engines. The ticket's core functional requirement (\"a second, alternative speech transcription implementation is added\") is not met — an alternate pipeline built as a duplicated bespoke recording path instead of a TranscriptionEngine conformer would produce exactly this result."
  exit 1
fi
