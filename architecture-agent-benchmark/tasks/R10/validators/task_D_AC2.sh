#!/usr/bin/env bash
# Task D / AC2: Deletion requests a delete-for-me sync message so linked devices also delete the messages.
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

DIFF_ALL="$(safe_diff .)"

if [ -z "$DIFF_ALL" ]; then
  echo "FAIL: no working-tree changes found (nothing to check)"
  exit 1
fi

SYNC_MESSAGE_SENT="$(echo "$DIFF_ALL" | grep -E '^\+.*sendSyncMessage\(interactionsThread:' || true)"
DELETE_CALL="$(echo "$DIFF_ALL" | grep -E '^\+.*interactionDeleteManager\.delete\(' || true)"
BARE_DEFAULT_OR_DONOTSEND="$(echo "$DIFF_ALL" | grep -E '^\+.*sideEffects:\s*\.default\(\)' || true)"
EXPLICIT_DONOTSEND="$(echo "$DIFF_ALL" | grep -E '^\+.*deleteForMeSyncMessage:\s*\.doNotSend' || true)"

if [ -z "$SYNC_MESSAGE_SENT" ]; then
  echo "FAIL: no '.sendSyncMessage(interactionsThread:' found in the diff — deletion does not appear to request a delete-for-me sync message, so linked devices would not be updated"
  exit 1
fi

if [ -n "$BARE_DEFAULT_OR_DONOTSEND" ] || [ -n "$EXPLICIT_DONOTSEND" ]; then
  echo "FAIL: diff passes sideEffects: .default() or explicit .doNotSend for deleteForMeSyncMessage — this suppresses linked-device sync (default is .doNotSend per SideEffects.custom's default parameter)"
  exit 1
fi

if [ -z "$DELETE_CALL" ]; then
  echo "FAIL: no interactionDeleteManager.delete(...) call found alongside the sync-message side effect"
  exit 1
fi

echo "PASS: diff explicitly passes .sendSyncMessage(interactionsThread:) as the deleteForMeSyncMessage side effect on a new interactionDeleteManager.delete(...) call."
echo "$SYNC_MESSAGE_SENT"
exit 0
