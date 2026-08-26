#!/usr/bin/env bash
# task_D_AC4 (R04-TD): "The action returns a captureUpdate of IMMEDIATELY (or
# equivalent history-capturing return), not a bare re-render trigger."
# Method: grep the new action/handler's return value / call site for
# `captureUpdate: CaptureUpdateAction.IMMEDIATELY` versus a `setState`/
# `forceUpdate` call with no `elements`/`captureUpdate` involved.
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
  echo "FAIL: no changed/new production files under $ACTIONS_DIR -- no snap-to-grid action found"
  exit 1
fi

FOUND_IMMEDIATELY=""
FOUND_BARE_RERENDER=""
for f in $NEW_ACTION_FILES; do
  [ -f "$f" ] || continue
  if grep -q 'CaptureUpdateAction\.IMMEDIATELY' "$f" 2>/dev/null; then
    FOUND_IMMEDIATELY="$FOUND_IMMEDIATELY $f"
  fi
  if grep -qE '\.setState\(\{\}\)|forceUpdate\(' "$f" 2>/dev/null; then
    FOUND_BARE_RERENDER="$FOUND_BARE_RERENDER $f"
  fi
done

if [ -n "$FOUND_BARE_RERENDER" ]; then
  echo "FAIL: found a bare re-render trigger (setState({})/forceUpdate) instead of a captureUpdate-carrying ActionResult:$FOUND_BARE_RERENDER"
  exit 1
fi

if [ -n "$FOUND_IMMEDIATELY" ]; then
  echo "PASS: found CaptureUpdateAction.IMMEDIATELY returned from:$FOUND_IMMEDIATELY"
  exit 0
fi

echo "FAIL: no file under $ACTIONS_DIR returns captureUpdate: CaptureUpdateAction.IMMEDIATELY for the snap-to-grid command"
exit 1
