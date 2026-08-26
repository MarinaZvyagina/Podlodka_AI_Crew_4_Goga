#!/usr/bin/env bash
# task_A_AC1 (R04-TA): "Change stays within the packages/excalidraw library boundary."
# Method: git diff --name-only against the pinned commit (HEAD); every changed
# production file path must start with packages/excalidraw/.
set -uo pipefail

REPO="${1:-.}"
cd "$REPO" || { echo "FAIL: cannot cd into repo dir '$REPO'"; exit 1; }

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi

CHANGED=$(git diff --name-only HEAD -- . 2>/dev/null)
UNTRACKED=$(git status --porcelain 2>/dev/null | awk '/^\?\?/ {print $2}')
ALL_FILES=$(printf '%s\n%s\n' "$CHANGED" "$UNTRACKED" | sed '/^$/d' | sort -u)

if [ -z "$ALL_FILES" ]; then
  echo "FAIL: no changes detected relative to HEAD (nothing to check)"
  exit 1
fi

BAD_FILES=$(echo "$ALL_FILES" | grep -v '^packages/excalidraw/' || true)

if [ -n "$BAD_FILES" ]; then
  echo "FAIL: changes touch files outside packages/excalidraw/:"
  echo "$BAD_FILES"
  exit 1
fi

echo "PASS: all changed/new files are under packages/excalidraw/:"
echo "$ALL_FILES"
exit 0
