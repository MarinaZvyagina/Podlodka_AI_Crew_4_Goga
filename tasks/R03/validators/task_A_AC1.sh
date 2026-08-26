#!/usr/bin/env bash
# Task A / AC1: Change is scoped to packages/common/exceptions (+ its barrel + its tests),
# not spread into other packages.
#
# Method: git diff --name-only against the pinned commit; inspect path prefixes of every
# changed/added file. Allowed roots:
#   - packages/common/exceptions/
#   - packages/common/test/exceptions/
#   - packages/common/utils/http-error-by-code.util.ts (optional, reasonable extra)
#
# Usage: task_A_AC1.sh [repo_dir]   (default: .)
set -u
REPO="${1:-.}"

if [ ! -d "$REPO/.git" ]; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi

cd "$REPO" || { echo "FAIL: cannot cd into $REPO"; exit 1; }

CHANGED=$(git diff --name-only HEAD; git diff --name-only --cached HEAD 2>/dev/null; git status --porcelain | awk '{print $2}')
CHANGED=$(echo "$CHANGED" | sort -u | grep -v '^$')

if [ -z "$CHANGED" ]; then
  echo "FAIL: no changes detected against HEAD (nothing to validate)"
  exit 1
fi

echo "Changed files:"
echo "$CHANGED" | sed 's/^/  /'

BAD=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    packages/common/exceptions/*) ;;
    packages/common/test/exceptions/*) ;;
    packages/common/utils/http-error-by-code.util.ts) ;;
    *) BAD="$BAD$f"$'\n' ;;
  esac
done <<< "$CHANGED"

if [ -n "$BAD" ]; then
  echo "FAIL: changes found outside the allowed scope:"
  echo "$BAD" | sed 's/^/  /'
  exit 1
fi

echo "PASS: all changed files are rooted at packages/common/exceptions/, packages/common/test/exceptions/, or the optional http-error-by-code.util.ts"
exit 0
