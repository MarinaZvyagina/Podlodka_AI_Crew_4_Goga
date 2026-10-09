#!/usr/bin/env bash
# R09 Task D (Copy Address toast, architecture trap) — AC4
# "showToastType(toast:) in BrowserViewController handles the new case (explicitly or via its
#  `default:` branch) rather than a second, parallel presentation path being added."
set -uo pipefail

REPO="${1:-.}"
REPO="$(cd "$REPO" 2>/dev/null && pwd)"
FILE="$REPO/firefox-ios/Client/Frontend/Browser/BrowserViewController/Views/BrowserViewController.swift"

if [ ! -f "$FILE" ]; then
  echo "FAIL: AC4 - $FILE not found"
  exit 1
fi

BLOCK=$(grep -n 'func showToastType' -A 25 "$FILE")
echo "$BLOCK"

if [ -z "$BLOCK" ]; then
  echo "FAIL: AC4 - could not find 'func showToastType' in $FILE"
  exit 1
fi

# Trap signature: a brand new, parallel presentation method added and called directly from an
# action handler (bypassing showToastType). Common plausible names for this trap.
PARALLEL_METHOD=$(grep -nE 'func showCopyAddress|func showCopyURLConfirmation|func presentCopyAddressToast' "$FILE" || true)

if [ -n "$PARALLEL_METHOD" ]; then
  echo "FAIL: AC4 - found a new, parallel toast-presentation method that bypasses showToastType(toast:):"
  echo "$PARALLEL_METHOD"
  exit 1
fi

# Positive signal: showToastType still has a single switch over `toast` (no second switch/function
# added elsewhere handling ToastType).
SWITCH_COUNT=$(grep -c 'switch toast {' "$FILE" || true)

if [ "$SWITCH_COUNT" -gt 1 ]; then
  echo "FAIL: AC4 - found $SWITCH_COUNT occurrences of 'switch toast {' in BrowserViewController.swift; expected exactly 1 (a second toast-presentation switch may have been introduced)"
  exit 1
fi

echo "PASS: AC4 - showToastType(toast:) remains the single presentation path for ToastType (switch toast { } occurs once); no parallel presentation method detected"
exit 0
