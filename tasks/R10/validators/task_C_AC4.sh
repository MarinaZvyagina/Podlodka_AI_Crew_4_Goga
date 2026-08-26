#!/usr/bin/env bash
# Task C / AC4: Large deletions are batched using the existing time-gated batching utility (TimeGatedBatch.processAll)
# rather than one unbounded transaction / unbatched loop.
set -uo pipefail
REPO="${1:-.}"
cd "$REPO" || { echo "FAIL: cannot cd to repo '$REPO'"; exit 1; }

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git working tree"
  exit 1
fi

safe_diff() {
  git diff -- "$@"
  git ls-files --others --exclude-standard -- "$@" 2>/dev/null | while IFS= read -r f; do
    [ -f "$f" ] || continue
    printf '+++ b/%s (untracked new file)\n' "$f"
    sed 's/^/+/' "$f"
  done
}

DIFF_JOBS="$(safe_diff SignalServiceKit/Jobs/)"

if [ -z "$DIFF_JOBS" ]; then
  echo "FAIL: no changes under SignalServiceKit/Jobs/ (nothing to check for batching)"
  exit 1
fi

TIME_GATED="$(echo "$DIFF_JOBS" | grep -E '^\+.*TimeGatedBatch\.processAll' || true)"

if [ -z "$TIME_GATED" ]; then
  echo "FAIL: no call to TimeGatedBatch.processAll found in the new job runner diff"
  exit 1
fi

UNBOUNDED_WRITE="$(echo "$DIFF_JOBS" | grep -E '^\+.*(awaitableWrite|\.write\s*\{)' || true)"
if [ -n "$UNBOUNDED_WRITE" ] && [ -z "$TIME_GATED" ]; then
  echo "FAIL: diff performs a write transaction without any batching utility nearby:"
  echo "$UNBOUNDED_WRITE"
  exit 1
fi

echo "PASS: TimeGatedBatch.processAll found in new job runner diff — deletion work is batched."
exit 0
