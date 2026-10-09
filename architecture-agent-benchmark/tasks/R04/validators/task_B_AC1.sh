#!/usr/bin/env bash
# task_B_AC1 (R04-TB): "Area math for non-rectangular closed shapes (closed
# lines/freedraw) is computed from actual point data via polygon math, not
# approximated from the bounding box."
#
# Method (per metadata): run the functional test case with a non-rectangular
# closed multi-point shape and compare the displayed area against both (a) the
# true shoelace area and (b) width*height of its bounding box, which must
# differ for the chosen test shape; correct implementations match (a).
#
# We run the actual functional vitest tests (which contain exactly this
# assertion: close to the true shoelace area of a triangle, and measurably
# different from the bounding-box area) as the concrete check.
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
  packages/element/tests/shape.getElementArea.test.ts \
  packages/excalidraw/components/Stats/stats.test.tsx; do
  if [ -f "$f" ]; then
    TEST_FILES="$TEST_FILES $f"
  fi
done

if [ -z "$TEST_FILES" ]; then
  echo "MANUAL REVIEW REQUIRED: no area-related test file found (expected e.g. packages/excalidraw/components/Stats/area.test.tsx) -- cannot run the non-rectangular-closed-shape area check automatically."
  exit 1
fi

OUTPUT=$(npx vitest run $TEST_FILES 2>&1)
STATUS=$?

echo "$OUTPUT" | tail -40

if [ $STATUS -eq 0 ]; then
  echo "PASS: area tests (including the non-rectangular closed-shape shoelace-vs-bounding-box case) pass"
  exit 0
else
  echo "FAIL: area tests failed (see output above) -- displayed area likely doesn't match true point-based (shoelace) area for non-rectangular closed shapes"
  exit 1
fi
