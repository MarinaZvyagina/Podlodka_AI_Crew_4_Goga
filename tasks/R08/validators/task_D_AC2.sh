#!/usr/bin/env bash
# R08 Task D (search result caching) — AC2
# "Cache invalidation is wired to real data-change notifications, not a fixed timer/TTL or
# an Activity/Fragment lifecycle guess."
#
# Method: grep -Rn 'DatabaseObserver|registerConversationListObserver|
# registerMessageUpdateObserver|registerMessageInsertObserver' across the diff; separately
# grep for 'TTL|postDelayed|Handler().postDelayed|onResume|onPause' near the new cache
# code as red flags.
#
# Usage: task_D_AC2.sh [repo_dir] [base_ref]
set -uo pipefail

REPO_DIR="${1:-.}"
BASE_REF="${2:-441ba42c3f3175476a1f54eba8e72d8d6d304db7}"

cd "$REPO_DIR" || { echo "FAIL: cannot cd into repo dir '$REPO_DIR'"; exit 1; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "FAIL: '$REPO_DIR' is not a git repository"
  exit 1
fi
if ! git cat-file -e "${BASE_REF}^{commit}" 2>/dev/null; then
  echo "MANUAL REVIEW REQUIRED: base ref '$BASE_REF' not present in this checkout."
  exit 1
fi

CHANGED_FILES=$(git diff --name-only "$BASE_REF" --)

OBSERVER_HITS=""
RED_FLAG_HITS=""
for f in $CHANGED_FILES; do
  [ -f "$f" ] || continue
  ADDED=$(git diff "$BASE_REF" -- "$f" | grep -E '^\+' | grep -vE '^\+\+\+')
  OHIT=$(echo "$ADDED" | grep -E 'DatabaseObserver|registerConversationListObserver|registerMessageUpdateObserver|registerMessageInsertObserver')
  if [ -n "$OHIT" ]; then
    OBSERVER_HITS="$OBSERVER_HITS\n--- $f ---\n$OHIT"
  fi
  RHIT=$(echo "$ADDED" | grep -E 'TTL|postDelayed|onResume|onPause')
  if [ -n "$RHIT" ]; then
    RED_FLAG_HITS="$RED_FLAG_HITS\n--- $f ---\n$RHIT"
  fi
done

echo "DatabaseObserver-based invalidation wiring found:"
echo -e "${OBSERVER_HITS:-  none}"
echo ""
echo "Red-flag TTL/postDelayed/onResume/onPause references found:"
echo -e "${RED_FLAG_HITS:-  none}"

if [ -n "$RED_FLAG_HITS" ] && [ -z "$OBSERVER_HITS" ]; then
  echo "FAIL: AC2 — cache invalidation appears driven by a timer/TTL or Fragment lifecycle callback, not real data-change notifications."
  exit 1
fi

if [ -z "$OBSERVER_HITS" ]; then
  echo "FAIL: AC2 — no DatabaseObserver-based invalidation wiring found; the cache has no real invalidation mechanism."
  exit 1
fi

if [ -n "$RED_FLAG_HITS" ]; then
  echo "MANUAL REVIEW REQUIRED: both DatabaseObserver wiring AND TTL/lifecycle-like tokens were found. Confirm the TTL/onResume/onPause references are unrelated (e.g. pre-existing code near the diff) and not the actual invalidation mechanism."
  exit 0
fi

echo "PASS: AC2 — cache invalidation is wired to DatabaseObserver with no timer/TTL/lifecycle red flags."
exit 0
