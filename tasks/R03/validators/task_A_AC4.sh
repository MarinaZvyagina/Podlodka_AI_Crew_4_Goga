#!/usr/bin/env bash
# Task A / AC4: New class is actually exported through the standard public barrel, not dead
# code or an ad hoc export path.
#
# Method: grep the new exception's export line in packages/common/exceptions/index.ts; confirm
# packages/common's root index re-exports packages/common/exceptions/index.ts.
#
# Usage: task_A_AC4.sh [repo_dir]   (default: .)
set -u
REPO="${1:-.}"

if [ ! -d "$REPO/.git" ]; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi

cd "$REPO" || { echo "FAIL: cannot cd into $REPO"; exit 1; }

BARREL="packages/common/exceptions/index.ts"
ROOT_INDEX="packages/common/index.ts"

if [ ! -f "$BARREL" ]; then
  echo "FAIL: barrel file $BARREL not found"
  exit 1
fi

# Find new export lines added to the barrel (diff-added lines starting with '+export')
ADDED_EXPORTS=$(git diff -- "$BARREL" | grep -E '^\+export \* from' || true)

if [ -z "$ADDED_EXPORTS" ]; then
  echo "FAIL: no new 'export * from ...' line was added to $BARREL"
  exit 1
fi

echo "New export line(s) added to $BARREL:"
echo "$ADDED_EXPORTS" | sed 's/^/  /'

# Confirm the root index still re-exports the exceptions barrel (should be pre-existing/unchanged)
if [ -f "$ROOT_INDEX" ] && grep -qE "export \* from '\./exceptions/index\.js'" "$ROOT_INDEX"; then
  echo "OK: $ROOT_INDEX still re-exports ./exceptions/index.js (public entry point intact)"
else
  echo "FAIL: $ROOT_INDEX does not re-export ./exceptions/index.js — barrel may have been bypassed"
  exit 1
fi

echo "PASS: new class is exported via the standard public barrel"
exit 0
