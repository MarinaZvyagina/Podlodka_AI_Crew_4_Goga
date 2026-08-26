#!/usr/bin/env bash
# R09 Task D (Copy Address toast, architecture trap) — AC2 [CENTRAL CHECK FOR THIS TASK]
# "The toast is triggered via store.dispatch(...) with GeneralBrowserActionType.showToast, not via
#  a direct UI call from the copyAddressAction handler."
# Method (runnable): locate the copyAddressAction closure in BrowserViewController.swift by
# brace/paren-depth extraction, then inspect its body for (a) a store.dispatch(...) call carrying
# actionType: GeneralBrowserActionType.showToast, and (b) the ABSENCE of a direct
# show(toast:/showPlainToast(/PlainToast(/ButtonToast( call. Several pre-existing legacy direct
# calls are known to exist elsewhere in this 5000+ line file (not introduced by this task) — this
# script only inspects the copyAddressAction closure specifically, not the whole file.
set -uo pipefail

REPO="${1:-.}"
REPO="$(cd "$REPO" 2>/dev/null && pwd)"
FILE="$REPO/firefox-ios/Client/Frontend/Browser/BrowserViewController/Views/BrowserViewController.swift"

if [ ! -f "$FILE" ]; then
  echo "FAIL: AC2 - $FILE not found"
  exit 1
fi

if ! grep -q 'copyAddressAction = AccessibleAction' "$FILE"; then
  echo "FAIL: AC2 - could not find 'copyAddressAction = AccessibleAction(...)' in $FILE (has it been renamed/moved?)"
  echo "MANUAL REVIEW REQUIRED: locate wherever the 'Copy Address' action now lives and inspect it by hand."
  exit 1
fi

BLOCK=$(awk '
  /copyAddressAction = AccessibleAction\(name:/ { start=1 }
  start {
    print
    n = gsub(/[{(]/, "&", $0)
    m = gsub(/[})]/, "&", $0)
    depth += n - m
    if (started && depth <= 0) { exit }
    started = 1
  }
' "$FILE")

echo "Extracted copyAddressAction closure body:"
echo "$BLOCK" | sed 's/^/  /'
echo

DISPATCH_OK=$(echo "$BLOCK" | grep -c 'store\.dispatch' || true)
SHOWTOAST_ACTIONTYPE_OK=$(echo "$BLOCK" | grep -c 'GeneralBrowserActionType\.showToast\|actionType: \.showToast' || true)
DIRECT_TOAST_CALLS=$(echo "$BLOCK" | grep -nE 'show\(toast:|showPlainToast\(|showBookmarkToast\(|PlainToast\(|ButtonToast\(' || true)

BAD=0
if [ "$DISPATCH_OK" -lt 1 ]; then
  echo "-> no store.dispatch(...) call found inside the copyAddressAction closure"
  BAD=1
fi
if [ "$SHOWTOAST_ACTIONTYPE_OK" -lt 1 ]; then
  echo "-> no GeneralBrowserActionType.showToast (or 'actionType: .showToast') found inside the closure"
  BAD=1
fi
if [ -n "$DIRECT_TOAST_CALLS" ]; then
  echo "-> found DIRECT toast-presentation call(s) inside the copyAddressAction closure (bypasses Redux):"
  echo "$DIRECT_TOAST_CALLS" | sed 's/^/     /'
  BAD=1
fi

if [ "$BAD" -eq 1 ]; then
  echo "FAIL: AC2 - copyAddressAction does not dispatch GeneralBrowserActionType.showToast through store.dispatch(...) without a direct toast call"
  exit 1
else
  echo "PASS: AC2 - copyAddressAction dispatches store.dispatch(... actionType: GeneralBrowserActionType.showToast ...) with no direct toast-presentation call in its body"
  exit 0
fi
