#!/usr/bin/env bash
# task_C_AC4 (R04-TC): "Toggling does not mutate element data (only
# rendering/appState)."
# Method: functional test asserts element array reference/content is
# unchanged after toggling; also grep diff for any `mutateElement`/direct
# element property writes inside the new toggle's perform function.
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

STATIC_FAIL=0
STATIC_REASON=""
for f in $NEW_ACTION_FILES; do
  [ -f "$f" ] || continue
  if grep -qE 'mutateElement|newElementWith|\.isDeleted\s*=|elements\.splice|elements\.push' "$f" 2>/dev/null; then
    STATIC_FAIL=1
    STATIC_REASON="$STATIC_REASON\n$f: appears to mutate/replace element data from within the toggle action"
  fi
done

if [ "$STATIC_FAIL" -eq 1 ]; then
  echo "FAIL: toggle action appears to touch element data directly:"
  echo -e "$STATIC_REASON"
  exit 1
fi

# run the functional test, which asserts elements are byte-identical
# before/after toggling
TEST_FILE=""
for f in packages/excalidraw/actions/actionToggleCaptionsVisibility.test.tsx; do
  if [ -f "$f" ]; then
    TEST_FILE="$f"
  fi
done

if [ -z "$TEST_FILE" ]; then
  echo "MANUAL REVIEW REQUIRED: no dedicated functional test file found for the captions-visibility toggle -- cannot automatically confirm elements are untouched. Static scan found no obvious element mutation in the action file(s), though."
  exit 1
fi

OUTPUT=$(npx vitest run "$TEST_FILE" 2>&1)
STATUS=$?
echo "$OUTPUT" | tail -30

if [ $STATUS -eq 0 ]; then
  echo "PASS: functional test confirms toggling does not mutate element data, and static scan found no mutateElement/element-array writes in the toggle action"
  exit 0
else
  echo "FAIL: functional test failed -- toggling likely mutated element data"
  exit 1
fi
