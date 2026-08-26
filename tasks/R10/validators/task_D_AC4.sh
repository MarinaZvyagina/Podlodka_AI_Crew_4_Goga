#!/usr/bin/env bash
# Task D / AC4: Conversation state (preview, unread count, message list) updates immediately without relaunch.
# This is inherited for free by going through InteractionDeleteManager's cache/thread-update side effects; a raw
# anyRemove loop would skip InteractionReadCache invalidation. We automate the greppable proxy and flag the rest.
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

FAIL=0
CHANGED_FILES="$(safe_changed_files . || true)"
for f in $CHANGED_FILES; do
  if [ "$f" = "$MANAGER_FILE" ]; then
    continue
  fi
  d="$(safe_diff "$f" 2>/dev/null || true)"
  bad="$(echo "$d" | grep -E '^\+.*\.anyRemove\(transaction:' || true)"
  if [ -n "$bad" ]; then
    echo "FAIL: $f deletes interactions directly via anyRemove outside InteractionDeleteManager — InteractionReadCache invalidation and thread 'last message'/unread-count updates will not run for this path, risking stale UI until relaunch:"
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

echo "PASS: deletion path goes through InteractionDeleteManager, which owns thread/preview/unread-count and InteractionReadCache updates; no bypassing anyRemove path found."
exit 0
