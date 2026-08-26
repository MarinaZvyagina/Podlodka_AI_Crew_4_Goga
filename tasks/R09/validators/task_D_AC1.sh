#!/usr/bin/env bash
# R09 Task D (Copy Address toast, architecture trap) — AC1
# "A new ToastType case exists for the copy-address confirmation."
set -uo pipefail

REPO="${1:-.}"
REPO="$(cd "$REPO" 2>/dev/null && pwd)"
FILE="$REPO/firefox-ios/Client/Frontend/Browser/ToastType.swift"

if [ ! -f "$FILE" ]; then
  echo "FAIL: AC1 - $FILE not found"
  exit 1
fi

BLOCK_NUMBERED=$(grep -n 'enum ToastType' -A 12 "$FILE")
echo "$BLOCK_NUMBERED"

# Strip the "NN:" / "NN-" line-number prefix `grep -n` adds, so the `^\s*case` regexes below
# (which assume lines start with optional whitespace) actually match.
BLOCK=$(echo "$BLOCK_NUMBERED" | sed -E 's/^[0-9]+[:-]//')

# Baseline (pinned commit) cases.
BASELINE='addBookmark|addToReadingList|clearCookies|openNewTab|removeFromReadingList|removeShortcut|retryTranslatingPage|shakeToSummarizeNotAvailable'

NEW_CASE=$(echo "$BLOCK" | grep -E '^\s*case [a-zA-Z]+' | grep -vE "case ($BASELINE)" || true)

if [ -z "$NEW_CASE" ]; then
  echo "FAIL: AC1 - no new ToastType case found beyond the pinned-commit baseline ($BASELINE)"
  exit 1
fi

echo "New case(s):"
echo "$NEW_CASE" | sed 's/^/  /'

NEW_CASE_NAME=$(echo "$NEW_CASE" | head -1 | sed -E 's/^[[:space:]]*case[[:space:]]+\(?([a-zA-Z]+).*/\1/')

TITLE_HANDLED=$(grep -A 20 'var title: String' "$FILE" | grep -c "case \.$NEW_CASE_NAME")

if [ "$TITLE_HANDLED" -lt 1 ]; then
  echo "FAIL: AC1 - new case '.$NEW_CASE_NAME' found but 'var title' does not handle it"
  exit 1
fi

echo "PASS: AC1 - new ToastType case '.$NEW_CASE_NAME' added with a title handled in the existing switch"
exit 0
