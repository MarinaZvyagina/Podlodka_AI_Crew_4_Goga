#!/usr/bin/env bash
# R09 Task C (alternative speech pipeline) — AC2
# "Engine selection is centralized, not scattered as branching logic at call sites."
# Method: no NEW branching on which pipeline to use should appear in the ViewModel/ViewController
# layer or in QuickAnswersService.swift; selection happens once, at construction time
# (DefaultQuickAnswersService.makeDefaultEngine() or an equivalent single factory).
#
# NOTE: this inspects the *diff* (added lines) against the pinned commit, not the whole file
# content — QuickAnswersViewController.swift/OptInView.swift already legitimately contain
# unrelated `if #available(iOS 26, *)` checks at the pinned commit (for other iOS-26-gated UI),
# so a whole-file grep would false-positive on the positive control too.
set -uo pipefail

REPO="${1:-.}"
REPO="$(cd "$REPO" 2>/dev/null && pwd)"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: AC2 - '$1' is not a git repo working directory"
  exit 1
fi
cd "$REPO" || exit 1

UI_DIR="BrowserKit/Sources/QuickAnswersKit/UI"
SERVICE_FILE="BrowserKit/Sources/QuickAnswersKit/Backend/QuickAnswersService.swift"

if [ ! -d "$UI_DIR" ] || [ ! -f "$SERVICE_FILE" ]; then
  echo "FAIL: AC2 - expected paths not found ($UI_DIR / $SERVICE_FILE)"
  exit 1
fi

PATTERN='engine ==|selectedEngine|experimentFlag|TranscriptionEngine|useAlternate|AlternateTranscription|pipelineFlag|if #available.*iOS 26'

# Added (+) lines only, across tracked + untracked new files in these paths.
DIFF_MATCHES=$(git diff -U0 -- "$UI_DIR" "$SERVICE_FILE" 2>/dev/null | grep -E '^\+' | grep -vE '^\+\+\+' | grep -E "$PATTERN" || true)

# Also catch the case of a brand-new (untracked) file added under UI_DIR that itself contains the
# pattern (git diff on an untracked path shows nothing unless added to the index).
UNTRACKED=$(git status --porcelain=v1 -- "$UI_DIR" 2>/dev/null | awk '/^\?\?/{print $2}')
UNTRACKED_MATCHES=""
for f in $UNTRACKED; do
  M=$(grep -nE "$PATTERN" "$f" 2>/dev/null || true)
  [ -n "$M" ] && UNTRACKED_MATCHES="$UNTRACKED_MATCHES
$f:
$M"
done

if [ -n "$DIFF_MATCHES" ] || [ -n "$UNTRACKED_MATCHES" ]; then
  echo "FAIL: AC2 - new pipeline-selection-shaped branching/reference found outside the centralized factory (in UI/ or QuickAnswersService.swift):"
  [ -n "$DIFF_MATCHES" ] && echo "$DIFF_MATCHES" | sed 's/^/  /'
  [ -n "$UNTRACKED_MATCHES" ] && echo "$UNTRACKED_MATCHES" | sed 's/^/  /'
  exit 1
else
  echo "PASS: AC2 - no new pipeline-selection branching introduced in QuickAnswersViewModel/ViewController/OptInView or QuickAnswersService.swift; selection appears centralized elsewhere (e.g. DefaultQuickAnswersService.makeDefaultEngine())"
  exit 0
fi
