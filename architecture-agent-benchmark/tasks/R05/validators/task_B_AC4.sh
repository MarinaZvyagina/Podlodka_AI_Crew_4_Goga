#!/usr/bin/env bash
# AC4: No leakage into ingestion/storage layers.
#
# Method (per metadata_B.yaml AC4): git diff --stat against the pinned commit; confirm no
# changes under app/vminsert/, app/vmselect/, lib/storage/.
#
# Usage: task_B_AC4.sh [REPO_PATH]
set -u

REPO="${1:-.}"

if [ ! -d "$REPO" ]; then
  echo "FAIL: $REPO is not a directory"
  exit 1
fi

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: $REPO is not a git working tree; cannot diff against baseline HEAD"
  exit 1
fi

CHANGED="$(git -C "$REPO" diff --name-only -- app/vminsert app/vmselect lib/storage 2>/dev/null)"

if [ -n "$CHANGED" ]; then
  echo "FAIL: changes found under app/vminsert/, app/vmselect/, or lib/storage/ (forbidden_dependencies per metadata_B.yaml): $(echo "$CHANGED" | tr '\n' ' ')"
  exit 1
fi

echo "PASS: no changes under app/vminsert/, app/vmselect/, or lib/storage/"
exit 0
