#!/usr/bin/env bash
# R09 Task C (alternative speech pipeline) — AC4
# "QuickAnswersService public surface and existing call sites are unmodified."
# Method: diff QuickAnswersService.swift against the pinned commit; it must be byte-identical.
set -uo pipefail

REPO="${1:-.}"
REPO="$(cd "$REPO" 2>/dev/null && pwd)"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: AC4 - '$1' is not a git repo working directory"
  exit 1
fi
cd "$REPO" || exit 1

FILE="BrowserKit/Sources/QuickAnswersKit/Backend/QuickAnswersService.swift"

if [ ! -f "$FILE" ]; then
  echo "FAIL: AC4 - $FILE not found"
  exit 1
fi

DIFF=$(git diff -- "$FILE" 2>&1)

if [ -z "$DIFF" ]; then
  echo "PASS: AC4 - $FILE is unchanged vs. the pinned commit (QuickAnswersService public surface untouched)"
  exit 0
else
  echo "FAIL: AC4 - $FILE was modified; the public QuickAnswersService surface should not need to change for this task:"
  echo "$DIFF"
  exit 1
fi
