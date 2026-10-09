#!/usr/bin/env bash
# R09 Task A (TabDataStore backup-cleanup fix) — AC3
# "No new dependency edges added to the TabDataStore target's Package.swift manifest."
# Method: the TabDataStore *target* (not the .library product) dependencies entry
# ( dependencies: ["Common"] ) must be unchanged.
set -uo pipefail

REPO="${1:-.}"
REPO="$(cd "$REPO" 2>/dev/null && pwd)"
FILE="$REPO/BrowserKit/Package.swift"

if [ ! -f "$FILE" ]; then
  echo "FAIL: AC3 - $FILE not found"
  exit 1
fi

# The TabDataStore *target* declaration looks like:
#   .target(
#       name: "TabDataStore",
#       dependencies: ["Common"],
#       ...
# There is also an earlier `.library(name: "TabDataStore", targets: ["TabDataStore"])` product
# declaration which has no `dependencies:` line immediately after it — grep for the occurrence
# that IS followed by a dependencies: line.
DEP_LINE=$(awk '
  /name: "TabDataStore",/ { getline nextline; if (nextline ~ /dependencies:/) { print nextline; found=1 } }
  END { if (!found) exit 1 }
' "$FILE")
STATUS=$?

if [ "$STATUS" -ne 0 ] || [ -z "$DEP_LINE" ]; then
  echo "FAIL: AC3 - could not locate TabDataStore target's dependencies: line in Package.swift (target may have been restructured)"
  exit 1
fi

TRIMMED=$(echo "$DEP_LINE" | tr -d '[:space:]')

if [ "$TRIMMED" = 'dependencies:["Common"],' ]; then
  echo "PASS: AC3 - TabDataStore target dependencies unchanged: $DEP_LINE"
  exit 0
else
  echo "FAIL: AC3 - TabDataStore target dependencies changed: $DEP_LINE"
  exit 1
fi
