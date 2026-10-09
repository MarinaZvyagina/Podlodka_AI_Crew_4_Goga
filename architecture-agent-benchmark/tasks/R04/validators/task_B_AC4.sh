#!/usr/bin/env bash
# task_B_AC4 (R04-TB): "Rotation invariance for rectangle/diamond/ellipse."
# Method: functional test computes area before and after applying a rotation
# transform to the same element and compares; area must be unchanged.
set -uo pipefail

REPO="${1:-.}"
cd "$REPO" || { echo "FAIL: cannot cd into repo dir '$REPO'"; exit 1; }

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi

TEST_FILES=""
for f in \
  packages/excalidraw/components/Stats/area.test.tsx \
  packages/element/tests/shape.getElementArea.test.ts; do
  if [ -f "$f" ]; then
    TEST_FILES="$TEST_FILES $f"
  fi
done

if [ -z "$TEST_FILES" ]; then
  echo "MANUAL REVIEW REQUIRED: no area-related test file found -- cannot run the rotation-invariance check automatically."
  exit 1
fi

OUTPUT=$(npx vitest run $TEST_FILES 2>&1)
STATUS=$?

echo "$OUTPUT" | tail -40

if [ $STATUS -eq 0 ]; then
  echo "PASS: rotation-invariance assertions (rectangle/ellipse/diamond area unchanged after rotation) pass"
  exit 0
else
  echo "FAIL: rotation-invariance assertions failed -- area likely computed from a post-rotation axis-aligned bounding box"
  exit 1
fi
