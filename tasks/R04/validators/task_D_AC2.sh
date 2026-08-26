#!/usr/bin/env bash
# task_D_AC2 (R04-TD): "No direct in-place property assignment on element
# objects."
# Method: grep the diff for `.x =`, `.y =`, `.width =`, `.height =`
# assignments on variables typed as ExcalidrawElement (or array elements from
# `elements`/`selectedElements`) outside of mutateElement.ts.
set -uo pipefail

REPO="${1:-.}"
cd "$REPO" || { echo "FAIL: cannot cd into repo dir '$REPO'"; exit 1; }

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi

CHANGED=$(git diff --name-only HEAD -- . 2>/dev/null)
UNTRACKED=$(git status --porcelain 2>/dev/null | awk '/^\?\?/ {print $2}')
ALL_FILES=$(printf '%s\n%s\n' "$CHANGED" "$UNTRACKED" | sed '/^$/d' | sort -u | grep -E '\.tsx?$' | grep -vE '\.(test|spec)\.tsx?$' | grep -v 'packages/element/src/mutateElement.ts' | grep -v 'packages/element/src/Scene.ts' || true)

if [ -z "$ALL_FILES" ]; then
  echo "PASS: no changed/new production files to inspect (outside mutateElement.ts/Scene.ts)"
  exit 0
fi

BAD=""
for f in $ALL_FILES; do
  [ -f "$f" ] || continue
  ADDED_LINES=$(git diff HEAD -- "$f" 2>/dev/null | grep -E '^\+' || true)
  if [ -z "$ADDED_LINES" ]; then
    ADDED_LINES=$(sed 's/^/+/' "$f")
  fi
  # direct assignment like `element.x = ...`, `el.width = ...`,
  # `selectedElements[i].height = ...`, or Object.assign(element, {...})
  MATCHES=$(echo "$ADDED_LINES" | grep -E '\.(x|y|width|height)\s*=[^=]' | grep -vE '(===|!==|<=|>=)' || true)
  OBJASSIGN=$(echo "$ADDED_LINES" | grep -E 'Object\.assign\(\s*(element|el)\b' || true)
  if [ -n "$MATCHES" ] || [ -n "$OBJASSIGN" ]; then
    BAD="$BAD\n$f:\n$MATCHES$OBJASSIGN"
  fi
done

if [ -n "$BAD" ]; then
  echo "FAIL: direct property assignment on element-like objects found outside mutateElement.ts/Scene.ts:"
  echo -e "$BAD"
  exit 1
fi

echo "PASS: no direct .x=/.y=/.width=/.height= assignments or Object.assign(element, ...) found in the diff outside mutateElement.ts/Scene.ts"
exit 0
