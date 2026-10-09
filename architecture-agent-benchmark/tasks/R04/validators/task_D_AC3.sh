#!/usr/bin/env bash
# task_D_AC3 (R04-TD): "version / versionNonce / updated are bumped on every
# snapped element."
# Method: functional/unit check capturing element.version before and after
# triggering the command for each snapped element.
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
  echo "MANUAL REVIEW REQUIRED: no dedicated test file found -- cannot automatically confirm version/versionNonce bumping."
  exit 1
fi

OUTPUT=$(npx vitest run "$TEST_FILE" -t "version" 2>&1)
STATUS=$?
echo "$OUTPUT" | tail -40

RAN_TESTS=$(echo "$OUTPUT" | grep -oE '[0-9]+ passed' | head -1)

if [ $STATUS -eq 0 ] && [ -n "$RAN_TESTS" ]; then
  echo "PASS: version/versionNonce are bumped on every snapped element"
  exit 0
else
  echo "FAIL: version/versionNonce were not bumped as expected (or no matching test ran) -- element was likely mutated in place without going through mutateElement"
  exit 1
fi
