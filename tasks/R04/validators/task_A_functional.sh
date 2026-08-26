#!/usr/bin/env bash
# task_A_functional (R04-TA): filename sanitization.
#
# Drives the pre-existing, registered `actionChangeProjectName` action
# (packages/excalidraw/actions/actionExport.tsx) exactly the way committing
# a new drawing name works, and asserts the committed name
# (`h.state.name`) is always a safe, non-empty file name on Windows/macOS/
# Linux -- regardless of where/how the candidate implementation centralizes
# its sanitization logic. See validators/fixtures/task_A_test.tsx for the
# implementation-agnosticism rationale.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/fixtures/task_A_test.tsx"

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
TARGET="$TARGET_DIR/__bench_functional_task_A.test.tsx"

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
  echo "PASS: committed drawing names are always sanitized to a safe, non-empty file name (no reserved chars, no leading/trailing dot or whitespace)"
  exit 0
else
  echo "FAIL: filename sanitization behavior does not hold (or no matching test ran) -- see vitest output above"
  exit 1
fi
