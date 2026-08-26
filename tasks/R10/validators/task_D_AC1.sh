#!/usr/bin/env bash
# Task D / AC1: Deletion is routed through InteractionDeleteManager rather than raw model deletion.
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
    echo "FAIL: $f adds a direct .anyRemove(transaction:) call outside InteractionDeleteManager.swift:"
    echo "$bad"
    FAIL=1
  fi
done

USES_MANAGER="$(echo "$DIFF_ALL" | grep -E '^\+.*interactionDeleteManager\.delete\(' || true)"
if [ -z "$USES_MANAGER" ]; then
  echo "FAIL: no new call to interactionDeleteManager.delete(...) found in the diff"
  FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi

echo "PASS: no new direct .anyRemove(transaction:) call sites outside InteractionDeleteManager.swift; a new interactionDeleteManager.delete(...) call was found."
echo "$USES_MANAGER"
exit 0
