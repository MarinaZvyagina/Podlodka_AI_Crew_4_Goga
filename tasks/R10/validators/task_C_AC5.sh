#!/usr/bin/env bash
# Task C / AC5: Message removal goes through InteractionDeleteManager, not raw model deletion (anyRemove).
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
  echo "FAIL: no changes under SignalServiceKit/Jobs/ (nothing to check for deletion routing)"
  exit 1
fi

USES_MANAGER="$(echo "$DIFF_JOBS" | grep -E '^\+.*interactionDeleteManager\.delete\(' || true)"
# Exclude `jobRecord.anyRemove(transaction:` (or similarly named job-record variables): that's the standard,
# expected way a job cleans up its own persisted JobRecord row once finished (see
# BulkDeleteInteractionJobQueue.swift, which does exactly this) — it is not a TSInteraction/TSMessage deletion
# and does not bypass InteractionDeleteManager.
DIRECT_ANYREMOVE="$(echo "$DIFF_JOBS" | grep -E '^\+.*\.anyRemove\(transaction:' | grep -viE '\bjobrecord\.anyremove' || true)"

if [ -n "$DIRECT_ANYREMOVE" ]; then
  echo "FAIL: new job runner diff calls .anyRemove(transaction:) directly instead of going through InteractionDeleteManager:"
  echo "$DIRECT_ANYREMOVE"
  exit 1
fi

if [ -z "$USES_MANAGER" ]; then
  echo "FAIL: new job runner diff does not call interactionDeleteManager.delete(...) anywhere"
  exit 1
fi

echo "PASS: new job runner routes deletion through interactionDeleteManager.delete(...); no direct anyRemove(transaction:) call found."
echo "$USES_MANAGER"
exit 0
