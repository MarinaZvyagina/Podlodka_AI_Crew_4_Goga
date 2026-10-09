#!/usr/bin/env bash
# task_C_functional (R04-TC): hide-captions toggle.
#
# Drives the feature purely through the visible main-menu UI (finds a menu
# item whose label contains "caption", case-insensitive) and confirms: it is
# reachable with nothing selected, toggling is reversible, toggling never
# mutates/deletes the underlying shape or its bound caption text, and it
# does not clobber unrelated display toggles (e.g. grid mode). See
# validators/fixtures/task_C_test.tsx for the implementation-agnosticism
# rationale (no hardcoded appState field name or keyboard shortcut).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/fixtures/task_C_test.tsx"

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
TARGET="$TARGET_DIR/__bench_functional_task_C.test.tsx"

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
  echo "PASS: a menu-reachable, reversible captions toggle exists that never mutates element/caption data and doesn't interfere with other display toggles"
  exit 0
else
  echo "FAIL: hide-captions toggle behavior does not hold (or no matching test ran) -- see vitest output above"
  exit 1
fi
