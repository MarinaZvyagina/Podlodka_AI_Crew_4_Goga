#!/usr/bin/env bash
# task_B_AC2 (R04-TB): "Geometry computation lives in / is reused from the
# element or math layer, not duplicated inline in the Stats UI component."
# Method: grep packages/excalidraw/components/Stats/*.tsx diff for a
# shoelace-style accumulation loop (e.g. `sum +=` over point pairs) or
# hardcoded `Math.PI *` ellipse-area formulas written directly in the
# component.
set -uo pipefail

REPO="${1:-.}"
cd "$REPO" || { echo "FAIL: cannot cd into repo dir '$REPO'"; exit 1; }

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi

STATS_DIR="packages/excalidraw/components/Stats"
if [ ! -d "$STATS_DIR" ]; then
  echo "MANUAL REVIEW REQUIRED: $STATS_DIR not found"
  exit 1
fi

CHANGED=$(git diff --name-only HEAD -- "$STATS_DIR" 2>/dev/null)
UNTRACKED=$(git status --porcelain 2>/dev/null | awk -v d="$STATS_DIR" '/^\?\?/ && index($2, d) == 1 {print $2}')
STATS_FILES=$(printf '%s\n%s\n' "$CHANGED" "$UNTRACKED" | sed '/^$/d' | sort -u | grep '\.tsx\?$' | grep -vE '\.(test|spec)\.tsx?$' || true)

if [ -z "$STATS_FILES" ]; then
  echo "PASS: no changed/new production files under $STATS_DIR (nothing to inline geometry into)"
  exit 0
fi

FOUND_ISSUES=""
for f in $STATS_FILES; do
  [ -f "$f" ] || continue
  # shoelace-style accumulation over point pairs, e.g. `sum += a[i][0] * ...`
  if grep -nE '(sum|area)\s*\+=' "$f" >/dev/null 2>&1; then
    FOUND_ISSUES="$FOUND_ISSUES\n$f: shoelace-style accumulation loop (\"sum +=\"/\"area +=\") found"
  fi
  # hardcoded ellipse-area style formula written directly in the component
  if grep -nE 'Math\.PI\s*\*' "$f" >/dev/null 2>&1; then
    FOUND_ISSUES="$FOUND_ISSUES\n$f: hardcoded 'Math.PI *' ellipse-area formula found"
  fi
  # hardcoded rectangle/diamond area formulas written directly (width * height, or /2 diamond variant)
  if grep -nE '\.width\s*\*\s*[A-Za-z_.]*\.height|\.height\s*\*\s*[A-Za-z_.]*\.width' "$f" >/dev/null 2>&1; then
    FOUND_ISSUES="$FOUND_ISSUES\n$f: hardcoded width*height-style area formula found"
  fi
done

if [ -n "$FOUND_ISSUES" ]; then
  echo "FAIL: inline geometry/area formulas found directly in the Stats component:"
  echo -e "$FOUND_ISSUES"
  exit 1
fi

echo "PASS: no inline shoelace loops or hardcoded per-type area formulas found in changed/new Stats component files:"
echo "$STATS_FILES"
exit 0
