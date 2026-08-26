#!/usr/bin/env bash
# task_B_functional (R04-TB): live shape-area readout in the Stats panel.
#
# Drives the feature through the UI (right-click canvas -> "Stats" -> select
# a shape) and reads the resulting area value out of the DOM, for
# rectangles/diamonds/ellipses/rotated shapes/closed polygon-mode lines, and
# confirms no misleading value is shown for open lines/arrows/text. See
# validators/fixtures/task_B_test.tsx for the implementation-agnosticism
# rationale.
#
# NOTE: per this task's control results, this functional check alone is
# NOT expected to discriminate the positive control from the architecture-
# trapped negative control (the trap's ad hoc formulas happen to be
# numerically correct for these shapes/angles) -- that discrimination is the
# job of the architecture check (task_B_AC2.sh: no inline geometry formulas
# reimplemented in the Stats component). This script only reports whether
# the user-visible behavior works.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/fixtures/task_B_test.tsx"

REPO="${1:-.}"
cd "$REPO" || { echo "FAIL: cannot cd into repo dir '$REPO'"; exit 1; }
REPO_ABS="$(pwd)"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO_ABS' is not a git repository"
  exit 1
fi

if [ ! -f "$FIXTURE" ]; then
  echo "FAIL: missing fixture file '$FIXTURE'"
  exit 1
fi

TARGET_DIR="packages/excalidraw/components/Stats"
TARGET="$TARGET_DIR/__bench_functional_task_B.test.tsx"

if [ ! -d "$TARGET_DIR" ]; then
  echo "FAIL: expected directory '$TARGET_DIR' not found in '$REPO_ABS'"
  exit 1
fi

cleanup() {
  rm -f "$REPO_ABS/$TARGET"
}
trap cleanup EXIT

cp "$FIXTURE" "$REPO_ABS/$TARGET"

OUTPUT=$(npx vitest run "$TARGET" 2>&1)
STATUS=$?
echo "$OUTPUT" | tail -60

RAN_TESTS=$(echo "$OUTPUT" | grep -oE '[0-9]+ passed' | head -1)

if [ $STATUS -eq 0 ] && [ -n "$RAN_TESTS" ]; then
  echo "PASS: Stats panel shows a correct, live, rotation-invariant area readout for rectangles/diamonds/ellipses/closed polygon lines, and omits it for open lines/arrows/text"
  exit 0
else
  echo "FAIL: area readout behavior does not hold (or no matching test ran) -- see vitest output above"
  exit 1
fi
