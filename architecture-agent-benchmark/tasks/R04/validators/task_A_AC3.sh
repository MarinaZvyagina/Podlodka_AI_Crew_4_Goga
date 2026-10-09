#!/usr/bin/env bash
# task_A_AC3 (R04-TA): "No new external dependency added for this bounded,
# single-component task."
# Method: diff packages/excalidraw/package.json "dependencies" before/after (HEAD vs
# working tree).
set -uo pipefail

REPO="${1:-.}"
cd "$REPO" || { echo "FAIL: cannot cd into repo dir '$REPO'"; exit 1; }

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi

PKG=packages/excalidraw/package.json
if [ ! -f "$PKG" ]; then
  echo "FAIL: $PKG not found"
  exit 1
fi

OLD=$(git show "HEAD:$PKG" 2>/dev/null)
NEW=$(cat "$PKG")

if [ -z "$OLD" ]; then
  echo "MANUAL REVIEW REQUIRED: could not read $PKG from HEAD"
  exit 1
fi

ADDED=$(node -e '
const old = JSON.parse(process.argv[1]);
const neu = JSON.parse(process.argv[2]);
const oldDeps = Object.keys(old.dependencies || {});
const newDeps = Object.keys(neu.dependencies || {});
const added = newDeps.filter((d) => !oldDeps.includes(d));
console.log(JSON.stringify(added));
' "$OLD" "$NEW" 2>/dev/null)

if [ -z "$ADDED" ]; then
  echo "MANUAL REVIEW REQUIRED: could not parse $PKG as JSON"
  exit 1
fi

COUNT=$(node -e "console.log(JSON.parse(process.argv[1]).length)" "$ADDED")

if [ "$COUNT" -eq 0 ]; then
  echo "PASS: no new entries added under packages/excalidraw/package.json dependencies"
  exit 0
else
  echo "FAIL: new dependency entries added: $ADDED"
  exit 1
fi
