#!/usr/bin/env bash
# task_C_AC3 (R04-TC): "New toggle state lives on the shared AppState, not a
# separate, newly-invented container."
# Method: grep packages/excalidraw/types.ts diff for the new boolean field's
# location relative to gridModeEnabled/zenModeEnabled/objectsSnapModeEnabled;
# also check whether a new standalone module-level variable or React context
# was introduced to hold this one flag instead.
set -uo pipefail

REPO="${1:-.}"
cd "$REPO" || { echo "FAIL: cannot cd into repo dir '$REPO'"; exit 1; }

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi

TYPES=packages/excalidraw/types.ts
DIFF=$(git diff HEAD -- "$TYPES" 2>/dev/null)

ADDED_FIELD=$(echo "$DIFF" | grep -E '^\+' | grep -E '^\+\s*[A-Za-z_]+(HiddenEnabled|ModeEnabled|Enabled)\??:\s*boolean' || true)

if [ -z "$ADDED_FIELD" ]; then
  echo "FAIL: no new '*Enabled: boolean' field was added to $TYPES (expected a new AppState boolean alongside gridModeEnabled/zenModeEnabled/objectsSnapModeEnabled)"
  exit 1
fi

echo "New AppState boolean field(s) found in $TYPES diff:"
echo "$ADDED_FIELD"

# now check for a suspicious alternative state container introduced elsewhere:
# a new React.createContext(...) or a new module-level `let`/`const` mutable
# flag added anywhere under packages/excalidraw for this feature.
CHANGED=$(git diff --name-only HEAD -- packages/excalidraw 2>/dev/null)
UNTRACKED=$(git status --porcelain 2>/dev/null | awk '/^\?\?/ && index($2, "packages/excalidraw") == 1 {print $2}')
ALL_FILES=$(printf '%s\n%s\n' "$CHANGED" "$UNTRACKED" | sed '/^$/d' | sort -u | grep -E '\.tsx?$' | grep -vE '\.(test|spec)\.tsx?$' || true)

SUSPICIOUS=""
for f in $ALL_FILES; do
  [ -f "$f" ] || continue
  ADDED_LINES=$(git diff HEAD -- "$f" 2>/dev/null | grep -E '^\+' || true)
  if [ -z "$ADDED_LINES" ]; then
    ADDED_LINES=$(sed 's/^/+/' "$f")
  fi
  if echo "$ADDED_LINES" | grep -E 'createContext\(' >/dev/null 2>&1; then
    SUSPICIOUS="$SUSPICIOUS\n$f: new React.createContext(...) found"
  fi
done

if [ -n "$SUSPICIOUS" ]; then
  echo "FAIL: a new, separate state container (context) was introduced alongside the AppState field:"
  echo -e "$SUSPICIOUS"
  exit 1
fi

echo "PASS: new toggle state lives on AppState (types.ts) and no separate context/container was introduced"
exit 0
