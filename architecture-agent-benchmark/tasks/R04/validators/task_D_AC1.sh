#!/usr/bin/env bash
# task_D_AC1 (R04-TD): "Undo reverts the snap in a single step."
# Method: functional test triggers the command, then undoes once, and
# compares each previously-snapped shape's x/y/width/height to its pre-snap
# values.
set -uo pipefail

REPO="${1:-.}"
cd "$REPO" || { echo "FAIL: cannot cd into repo dir '$REPO'"; exit 1; }

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi

TEST_FILE=""
for f in \
  packages/excalidraw/actions/actionSnapSelectionToGrid.architecture.test.tsx \
  packages/excalidraw/actions/actionSnapSelectionToGrid.test.tsx; do
  if [ -f "$f" ]; then
    TEST_FILE="$f"
    break
  fi
done

if [ -z "$TEST_FILE" ]; then
  echo "MANUAL REVIEW REQUIRED: no dedicated test file found for the snap-to-grid command's undo behavior (expected packages/excalidraw/actions/actionSnapSelectionToGrid.architecture.test.tsx or actionSnapSelectionToGrid.test.tsx with an undo test case) -- cannot automatically confirm undo behavior."
  exit 1
fi

# run only the undo-specific test case
OUTPUT=$(npx vitest run "$TEST_FILE" -t "undo" 2>&1)
STATUS=$?
echo "$OUTPUT" | tail -40

RAN_TESTS=$(echo "$OUTPUT" | grep -oE '[0-9]+ passed' | head -1)

if [ $STATUS -eq 0 ] && [ -n "$RAN_TESTS" ]; then
  echo "PASS: a single undo fully reverts every snapped shape's x/y/width/height to its pre-snap values"
  exit 0
else
  echo "FAIL: undo did not revert the snap in a single step (or no matching test ran)"
  exit 1
fi
