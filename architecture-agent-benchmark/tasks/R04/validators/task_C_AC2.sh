#!/usr/bin/env bash
# task_C_AC2 (R04-TC): "No parallel keyboard-handling path was introduced."
# Method: grep packages/excalidraw/components/App.tsx (and any new files)
# diff for `addEventListener("keydown"` or a new top-level `onKeyDown` handler
# unrelated to ActionManager.handleKeyDown.
set -uo pipefail

REPO="${1:-.}"
cd "$REPO" || { echo "FAIL: cannot cd into repo dir '$REPO'"; exit 1; }

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi

CHANGED=$(git diff --name-only HEAD -- . 2>/dev/null)
UNTRACKED=$(git status --porcelain 2>/dev/null | awk '/^\?\?/ {print $2}')
ALL_FILES=$(printf '%s\n%s\n' "$CHANGED" "$UNTRACKED" | sed '/^$/d' | sort -u | grep -E '\.tsx?$' | grep -vE '\.(test|spec)\.tsx?$' || true)

if [ -z "$ALL_FILES" ]; then
  echo "PASS: no changed/new production .ts(x) files to inspect"
  exit 0
fi

BAD=""
for f in $ALL_FILES; do
  [ -f "$f" ] || continue
  # only consider ADDED lines so we don't flag pre-existing code the diff happens to touch
  ADDED_LINES=$(git diff HEAD -- "$f" 2>/dev/null | grep -E '^\+' || true)
  # for untracked (new) files, treat every line as "added"
  if [ -z "$ADDED_LINES" ] && [ -f "$f" ]; then
    ADDED_LINES=$(sed 's/^/+/' "$f")
  fi
  if echo "$ADDED_LINES" | grep -E 'addEventListener\(\s*["'"'"']key(down|up|press)["'"'"']' >/dev/null 2>&1; then
    BAD="$BAD\n$f: new addEventListener(\"keydown\"/...) found"
  fi
  # a new top-level onKeyDown handler unrelated to ActionManager -- heuristic:
  # a new React onKeyDown={...} prop added outside of components/App.tsx's own
  # ActionManager.handleKeyDown wiring (App.tsx itself is allowed to keep its
  # single existing top-level handler; flag *new* ones added elsewhere).
  if [ "$f" != "packages/excalidraw/components/App.tsx" ]; then
    if echo "$ADDED_LINES" | grep -E 'onKeyDown=\{' >/dev/null 2>&1; then
      BAD="$BAD\n$f: new onKeyDown={...} handler found outside components/App.tsx"
    fi
  fi
done

if [ -n "$BAD" ]; then
  echo "FAIL: possible parallel keyboard-handling path introduced:"
  echo -e "$BAD"
  exit 1
fi

echo "PASS: no new addEventListener(\"keydown\"/...) or stray onKeyDown handlers found outside the existing ActionManager path"
exit 0
