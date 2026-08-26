#!/usr/bin/env bash
# task_C_AC1 (R04-TC): "Feature is implemented as a registered action, not a
# bespoke mechanism."
# Method: grep the diff for a new `register({...})` call with `keyTest`,
# `checked`, and `perform` fields, defined in packages/excalidraw/actions/.
set -uo pipefail

REPO="${1:-.}"
cd "$REPO" || { echo "FAIL: cannot cd into repo dir '$REPO'"; exit 1; }

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi

ACTIONS_DIR="packages/excalidraw/actions"
CHANGED=$(git diff --name-only HEAD -- "$ACTIONS_DIR" 2>/dev/null)
UNTRACKED=$(git status --porcelain 2>/dev/null | awk -v d="$ACTIONS_DIR" '/^\?\?/ && index($2, d) == 1 {print $2}')
NEW_ACTION_FILES=$(printf '%s\n%s\n' "$CHANGED" "$UNTRACKED" | sed '/^$/d' | sort -u | grep -E '\.tsx?$' | grep -vE '\.(test|spec)\.tsx?$' || true)

if [ -z "$NEW_ACTION_FILES" ]; then
  echo "FAIL: no changed/new production files under $ACTIONS_DIR -- no registered action found"
  exit 1
fi

FOUND=""
for f in $NEW_ACTION_FILES; do
  [ -f "$f" ] || continue
  if grep -q 'register(' "$f" 2>/dev/null \
    && grep -q 'keyTest' "$f" 2>/dev/null \
    && grep -q 'checked' "$f" 2>/dev/null \
    && grep -q 'perform' "$f" 2>/dev/null; then
    FOUND="$FOUND $f"
  fi
done

if [ -n "$FOUND" ]; then
  echo "PASS: found a register({...}) action with keyTest/checked/perform in:$FOUND"
  exit 0
fi

echo "FAIL: no file under $ACTIONS_DIR defines a register({...}) call with keyTest, checked, and perform fields together (expected a new toggle action, structurally like actionToggleGridMode.tsx)"
exit 1
