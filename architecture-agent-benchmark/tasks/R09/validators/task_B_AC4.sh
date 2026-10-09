#!/usr/bin/env bash
# R09 Task B (toolbar middle-button "Close Tab") — AC4
# "No new dependency edge from BrowserKit's ToolbarKit target to Client-app types."
set -uo pipefail

REPO="${1:-.}"
REPO="$(cd "$REPO" 2>/dev/null && pwd)"
DIR="$REPO/BrowserKit/Sources/ToolbarKit"

if [ ! -d "$DIR" ]; then
  echo "FAIL: AC4 - $DIR not found"
  exit 1
fi

MATCHES=$(grep -rn 'import Client\|TabManager\|BrowserViewController' "$DIR" || true)

if [ -n "$MATCHES" ]; then
  echo "FAIL: AC4 - BrowserKit/Sources/ToolbarKit references Client-app-specific types:"
  echo "$MATCHES" | sed 's/^/  /'
  exit 1
else
  echo "PASS: AC4 - BrowserKit/Sources/ToolbarKit has no references to import Client, TabManager, or BrowserViewController; remains app-agnostic"
  exit 0
fi
