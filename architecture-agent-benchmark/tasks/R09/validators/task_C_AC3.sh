#!/usr/bin/env bash
# R09 Task C (alternative speech pipeline) — AC3
# "New engine reuses AudioManagerProtocol/AuthorizeProvider rather than talking to
#  AVFoundation/Speech APIs directly."
# Method: identify any *.swift file under Backend/SpeechService/ beyond the known baseline set,
# and grep it for direct AVAudioEngine/AVAudioSession/SFSpeechRecognizer construction and for
# use of AudioManagerProtocol/AuthorizeProvider in its initializer.
set -uo pipefail

REPO="${1:-.}"
REPO="$(cd "$REPO" 2>/dev/null && pwd)"
DIR="$REPO/BrowserKit/Sources/QuickAnswersKit/Backend/SpeechService"

if [ ! -d "$DIR" ]; then
  echo "FAIL: AC3 - $DIR not found"
  exit 1
fi

BASELINE="Abstractions.swift AudioManager.swift AuthorizationHandler.swift SFSpeechRecognizerEngine.swift SpeechAnalyzerEngine.swift SpeechError.swift TranscriptionEngine.swift"

NEW_FILES=()
for f in "$DIR"/*.swift; do
  base=$(basename "$f")
  is_baseline=0
  for b in $BASELINE; do
    [ "$base" = "$b" ] && is_baseline=1
  done
  [ "$is_baseline" -eq 0 ] && NEW_FILES+=("$f")
done

if [ ${#NEW_FILES[@]} -eq 0 ]; then
  echo "FAIL: AC3 - no new file found under $DIR beyond the baseline set ($BASELINE); cannot locate the new engine to review"
  exit 1
fi

BAD=0
FOUND_ABSTRACTION_USAGE=0
for f in "${NEW_FILES[@]}"; do
  echo "Reviewing new file: $f"
  DIRECT=$(grep -nE 'AVAudioEngine\(|AVAudioSession\(|AVAudioSession\.sharedInstance|SFSpeechRecognizer\(|SFSpeechAudioBufferRecognitionRequest\(|requestRecordPermission\(|SFSpeechRecognizer\.requestAuthorization' "$f" || true)
  if [ -n "$DIRECT" ]; then
    echo "  FAIL-worthy: direct AVFoundation/Speech API usage found:"
    echo "$DIRECT" | sed 's/^/    /'
    BAD=1
  fi
  ABSTRACTION=$(grep -nE 'AudioManagerProtocol|AuthorizeProvider' "$f" || true)
  if [ -n "$ABSTRACTION" ]; then
    FOUND_ABSTRACTION_USAGE=1
    echo "  OK: reuses existing abstraction(s):"
    echo "$ABSTRACTION" | sed 's/^/    /'
  fi
done

if [ "$BAD" -eq 1 ]; then
  echo "FAIL: AC3 - new engine talks to AVFoundation/Speech APIs directly instead of going through AudioManagerProtocol/AuthorizeProvider"
  exit 1
fi

if [ "$FOUND_ABSTRACTION_USAGE" -eq 0 ]; then
  echo "FAIL: AC3 - new engine file(s) do not reference AudioManagerProtocol or AuthorizeProvider at all; cannot confirm it reuses the existing plumbing"
  exit 1
fi

echo "PASS: AC3 - new engine has no direct AVFoundation/Speech API usage and references AudioManagerProtocol/AuthorizeProvider"
exit 0
