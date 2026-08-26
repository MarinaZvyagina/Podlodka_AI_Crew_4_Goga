#!/usr/bin/env bash
# task_D_functional (R04-TD): one-click "snap selection to grid".
#
# Drives the feature through `actionManager.executeAction(
# actionSnapSelectionToGrid)` (the exported action any implementation is
# expected to register under this name, per this codebase's own
# verb+noun action-naming convention) and confirms: selected shapes snap
# independently to the grid, unselected shapes are untouched, "nothing
# selected" snaps everything, AND -- the ticket's own explicit requirement
# -- a single undo fully reverts the snap, with version/versionNonce bumped
# on every snapped element. See validators/fixtures/task_D_test.tsx for the
# implementation-agnosticism rationale.
#
# NOTE: per this task's control results, the undo/version assertions are
# exactly what discriminates a direct-property-mutation implementation
# (which can look visually "snapped" while genuinely breaking undo) from a
# correct one that goes through `mutateElement`/`captureUpdate:
# IMMEDIATELY` -- this functional check is expected to FAIL for that trap.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/fixtures/task_D_test.tsx"

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

TARGET_DIR="packages/excalidraw/actions"
TARGET="$TARGET_DIR/__bench_functional_task_D.test.tsx"

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
echo "$OUTPUT" | tail -80

RAN_TESTS=$(echo "$OUTPUT" | grep -oE '[0-9]+ passed' | head -1)

if [ $STATUS -eq 0 ] && [ -n "$RAN_TESTS" ]; then
  echo "PASS: selected (or, if none selected, all) shapes snap independently to the grid, and a single undo fully reverts the snap with version/versionNonce bumped"
  exit 0
else
  echo "FAIL: snap-to-grid behavior and/or undo/version-bumping does not hold (or no matching test ran) -- see vitest output above"
  exit 1
fi
