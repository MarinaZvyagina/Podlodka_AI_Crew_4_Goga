#!/usr/bin/env bash
# R08 Task C (thumbnail cache cleanup) — AC4
# "The job is actually enqueued through the app's existing JobManager on some
# already-established recurring/periodic trigger path, not invoked ad hoc from a UI
# lifecycle callback."
#
# Method: grep -n 'jobManager\.' (or 'AppDependencies.jobManager') across the diff;
# identify where/how often the new job gets enqueued. This script automates the presence
# check and flags a red flag if enqueue only happens from an Activity/Fragment lifecycle
# callback; final judgment on "is this really periodic/automatic" needs manual review.
#
# Usage: task_C_AC4.sh [repo_dir] [base_ref]
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

ENQUEUE_HITS=""
LIFECYCLE_ENQUEUE_HITS=""
for f in $CHANGED_FILES; do
  [ -f "$f" ] || continue
  HIT=$(git diff "$BASE_REF" -- "$f" | grep -E '^\+' | grep -vE '^\+\+\+' | grep -E 'jobManager\.|AppDependencies\.jobManager')
  if [ -n "$HIT" ]; then
    ENQUEUE_HITS="$ENQUEUE_HITS\n--- $f ---\n$HIT"
    case "$f" in
      *Activity.java|*Activity.kt|*Fragment.java|*Fragment.kt)
        if echo "$HIT" | grep -qE 'onResume|onCreate|onStart'; then
          LIFECYCLE_ENQUEUE_HITS="$LIFECYCLE_ENQUEUE_HITS $f"
        fi
        ;;
    esac
  fi
done

echo "New jobManager enqueue call sites:"
echo -e "${ENQUEUE_HITS:-  none}"

if [ -z "$ENQUEUE_HITS" ]; then
  echo "FAIL: AC4 — no jobManager.* / AppDependencies.jobManager enqueue call found anywhere in the diff; the job is never scheduled."
  exit 1
fi

if [ -n "$LIFECYCLE_ENQUEUE_HITS" ]; then
  echo "Potential red flag: enqueue call(s) found inside Activity/Fragment lifecycle files:$LIFECYCLE_ENQUEUE_HITS"
  echo "MANUAL REVIEW REQUIRED to confirm whether this is the *only* enqueue path (fails AC4 — ad hoc trigger) or whether it's supplementary to a genuinely periodic/automatic path (e.g. self re-enqueue, or app-init scheduling) elsewhere in the diff."
fi

echo "PASS (heuristic): AC4 — job is enqueued via jobManager somewhere in the diff."
echo "MANUAL REVIEW REQUIRED to confirm the enqueue path is periodic/automatic (e.g. alongside other maintenance jobs at app init, or via Job self re-enqueue) rather than solely a one-off UI-triggered call."
exit 0
