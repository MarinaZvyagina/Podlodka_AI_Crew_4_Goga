#!/usr/bin/env bash
# task_B_AC3 (R04-TB): "Dependency direction is preserved: math/element packages
# do not import from excalidraw."
# Method: grep packages/math/src/**/*.ts and packages/element/src/**/*.ts diffs
# for any `from "@excalidraw/excalidraw"` or `from "../../excalidraw"`-style
# import; also check package.json dependency lists. NOTE: packages/element
# already has one pre-existing type-only import from
# "@excalidraw/excalidraw/types" (in shape.ts, for AppState/
# EmbedsValidationStatus, unrelated to this feature) -- this check only flags
# NEW such imports introduced by the diff, not that pre-existing one.
set -uo pipefail

REPO="${1:-.}"
cd "$REPO" || { echo "FAIL: cannot cd into repo dir '$REPO'"; exit 1; }

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi

FAIL=0
REASONS=""

for pkg in math element; do
  DIR="packages/$pkg/src"
  [ -d "$DIR" ] || continue
  DIFF=$(git diff HEAD -- "$DIR" 2>/dev/null)
  # only look at ADDED lines (new imports introduced by this change)
  NEW_BAD_IMPORTS=$(echo "$DIFF" | grep -E '^\+' | grep -E 'from ["'"'"'](@excalidraw/excalidraw|\.\./excalidraw|\.\./\.\./excalidraw)' || true)
  if [ -n "$NEW_BAD_IMPORTS" ]; then
    FAIL=1
    REASONS="$REASONS\npackages/$pkg: new import from excalidraw introduced:\n$NEW_BAD_IMPORTS"
  fi

  PKG_JSON="packages/$pkg/package.json"
  if [ -f "$PKG_JSON" ]; then
    OLD=$(git show "HEAD:$PKG_JSON" 2>/dev/null)
    NEW=$(cat "$PKG_JSON")
    if [ -n "$OLD" ]; then
      ADDED_DEP=$(node -e '
        const old = JSON.parse(process.argv[1]);
        const neu = JSON.parse(process.argv[2]);
        const oldDeps = Object.keys(old.dependencies || {});
        const newDeps = Object.keys(neu.dependencies || {});
        const added = newDeps.filter((d) => !oldDeps.includes(d) && d.includes("excalidraw"));
        console.log(JSON.stringify(added));
      ' "$OLD" "$NEW" 2>/dev/null)
      if [ -n "$ADDED_DEP" ] && [ "$ADDED_DEP" != "[]" ]; then
        FAIL=1
        REASONS="$REASONS\n$PKG_JSON: new excalidraw-related dependency added: $ADDED_DEP"
      fi
    fi
  fi
done

if [ "$FAIL" -eq 1 ]; then
  echo "FAIL: dependency direction violated (math/element -> excalidraw):"
  echo -e "$REASONS"
  exit 1
fi

echo "PASS: no new imports/dependencies from packages/math or packages/element onto packages/excalidraw were introduced"
exit 0
