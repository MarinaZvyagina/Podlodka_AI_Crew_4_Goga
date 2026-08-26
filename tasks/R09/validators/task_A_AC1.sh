#!/usr/bin/env bash
# R09 Task A (TabDataStore backup-cleanup fix) — AC1
# "Fix is scoped to the TabDataStore target only (single-component, no cross-module edits)."
# Method: assert every path changed vs. the pinned commit starts with
#   BrowserKit/Sources/TabDataStore/ or BrowserKit/Tests/TabDataStoreTests/
set -uo pipefail

REPO="${1:-.}"
REPO="$(cd "$REPO" 2>/dev/null && pwd)"
if [ -z "$REPO" ] || [ ! -d "$REPO/.git" ]; then
  echo "FAIL: AC1 - '$1' is not a git repo working directory"
  exit 1
fi
cd "$REPO" || exit 1

# All changed paths: staged + unstaged + untracked, relative to repo root.
CHANGED=$(git status --porcelain=v1 2>/dev/null | sed -E 's/^...//' | sed -E 's/.* -> //' | sort -u)

if [ -z "$CHANGED" ]; then
  echo "FAIL: AC1 - no changes detected against the pinned commit; nothing to check"
  exit 1
fi

BAD=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    BrowserKit/Sources/TabDataStore/*|BrowserKit/Tests/TabDataStoreTests/*)
      ;;
    *)
      echo "  out-of-scope: $f"
      BAD=1
      ;;
  esac
done <<< "$CHANGED"

if [ "$BAD" -eq 1 ]; then
  echo "FAIL: AC1 - changes touch files outside BrowserKit/Sources/TabDataStore/ and BrowserKit/Tests/TabDataStoreTests/"
  exit 1
else
  echo "PASS: AC1 - all changed files are scoped to the TabDataStore target:"
  echo "$CHANGED" | sed 's/^/  /'
  exit 0
fi
