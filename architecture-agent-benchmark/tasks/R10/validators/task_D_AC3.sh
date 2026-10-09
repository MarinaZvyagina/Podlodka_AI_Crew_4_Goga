#!/usr/bin/env bash
# Task D / AC3: Associated call records stay consistent (no orphaned CallRecord entries). This is inherited for
# free by going through InteractionDeleteManager; a raw anyRemove-based path would skip it. We automate the
# greppable proxy (this feature's deletion goes through InteractionDeleteManager, same as AC1) and flag manual
# review for the deeper claim (that CallRecord cleanup is not silently skipped/documented away).
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
safe_changed_files() {
  git diff --name-only -- "$@"
  git ls-files --others --exclude-standard -- "$@" 2>/dev/null
}

MANAGER_FILE="SignalServiceKit/Messages/Interactions/InteractionDeleteManager.swift"

DIFF_ALL="$(safe_diff .)"

if [ -z "$DIFF_ALL" ]; then
  echo "FAIL: no working-tree changes found (nothing to check)"
  exit 1
fi

CHANGED_FILES="$(safe_changed_files . || true)"
FAIL=0
for f in $CHANGED_FILES; do
  if [ "$f" = "$MANAGER_FILE" ]; then
    continue
  fi
  d="$(safe_diff "$f" 2>/dev/null || true)"
  bad="$(echo "$d" | grep -E '^\+.*\.anyRemove\(transaction:' || true)"
  if [ -n "$bad" ]; then
    echo "FAIL: $f deletes interactions directly via anyRemove outside InteractionDeleteManager — CallRecord cleanup (callRecordDeleteManager/callRecordStore) will not run for this path:"
    echo "$bad"
    FAIL=1
  fi
done

USES_MANAGER="$(echo "$DIFF_ALL" | grep -E '^\+.*interactionDeleteManager\.delete\(' || true)"
if [ -z "$USES_MANAGER" ] && [ "$FAIL" -eq 0 ]; then
  echo "FAIL: no interactionDeleteManager.delete(...) call found, and no direct anyRemove detected either — cannot confirm deletion path exists at all"
  FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi

echo "PASS: deletion path goes through InteractionDeleteManager (which owns CallRecord cleanup); no direct anyRemove-based deletion bypassing it was found."
echo "MANUAL REVIEW REQUIRED: confirm no call-containing messages are deliberately filtered out of the deletion set in a way that's undocumented (acceptable) vs silently mishandled (not acceptable)."
exit 0
