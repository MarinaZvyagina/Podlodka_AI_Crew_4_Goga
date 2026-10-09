#!/usr/bin/env bash
# R09 Task C (alternative speech pipeline) — AC1
# "New pipeline is implemented as a TranscriptionEngine conformer, not a parallel bespoke class."
# Baseline (pinned commit) has exactly 2 conformer declarations: SFSpeechRecognizerEngine,
# SpeechAnalyzerEngine. A correct solution adds a third file/type declaring
# `<Name>: TranscriptionEngine`.
set -uo pipefail

REPO="${1:-.}"
REPO="$(cd "$REPO" 2>/dev/null && pwd)"
DIR="$REPO/BrowserKit/Sources/QuickAnswersKit/Backend/SpeechService"

if [ ! -d "$DIR" ]; then
  echo "FAIL: AC1 - $DIR not found"
  exit 1
fi

MATCHES=$(grep -n ': TranscriptionEngine' "$DIR"/*.swift 2>/dev/null || true)
COUNT=$(echo "$MATCHES" | grep -c ': TranscriptionEngine' || true)

echo "$MATCHES" | sed 's/^/  /'

if [ "$COUNT" -ge 3 ]; then
  echo "PASS: AC1 - found $COUNT TranscriptionEngine conformers (baseline is 2: SFSpeechRecognizerEngine, SpeechAnalyzerEngine); a new conformer was added"
  exit 0
else
  echo "FAIL: AC1 - found only $COUNT TranscriptionEngine conformer(s); expected >= 3 (a new conformer beyond the existing SFSpeechRecognizerEngine/SpeechAnalyzerEngine)"
  exit 1
fi
