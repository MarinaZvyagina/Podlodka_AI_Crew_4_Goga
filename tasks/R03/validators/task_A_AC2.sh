#!/usr/bin/env bash
# Task A / AC2: New class extends the existing HttpException base class rather than
# reimplementing exception behavior.
#
# Method: grep -n 'extends HttpException' on the new exception file.
#
# Usage: task_A_AC2.sh [repo_dir]   (default: .)
set -u
REPO="${1:-.}"

if [ ! -d "$REPO/.git" ]; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi

cd "$REPO" || { echo "FAIL: cannot cd into $REPO"; exit 1; }

NEW_FILES=$(git status --porcelain -- packages/common/exceptions | awk '$1 == "??" || $1 == "A" {print $2}')
# Also consider modified-but-tracked new-ish files is unlikely for a "new class" task; fall back
# to any exception file (other than the barrel and the base class) that is added or modified.
CANDIDATES=$( (git diff --name-only -- packages/common/exceptions; echo "$NEW_FILES") | sort -u | grep -v '^$' | grep -Ev '(^|/)index\.ts$|(^|/)http\.exception\.ts$' )

if [ -z "$CANDIDATES" ]; then
  echo "FAIL: no new/modified exception file found under packages/common/exceptions (excluding index.ts and http.exception.ts)"
  exit 1
fi

echo "Candidate new exception file(s):"
echo "$CANDIDATES" | sed 's/^/  /'

FOUND=0
for f in $CANDIDATES; do
  if [ -f "$f" ] && grep -n 'extends HttpException' "$f" > /tmp/task_A_AC2_grep.$$ 2>/dev/null; then
    if [ -s /tmp/task_A_AC2_grep.$$ ]; then
      echo "Match in $f:"
      cat /tmp/task_A_AC2_grep.$$ | sed 's/^/  /'
      FOUND=1
    fi
  fi
  rm -f /tmp/task_A_AC2_grep.$$
done

if [ "$FOUND" -eq 1 ]; then
  echo "PASS: new exception class extends HttpException"
  exit 0
else
  echo "FAIL: no candidate file contains 'extends HttpException' — class may reimplement behavior, extend Error directly, or status handling may have been special-cased elsewhere"
  exit 1
fi
