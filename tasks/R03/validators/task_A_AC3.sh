#!/usr/bin/env bash
# Task A / AC3: No new cross-package dependency edge is created.
#
# Method: diff packages/common/package.json (dependencies/peerDependencies) before vs. after;
# grep the new/changed files for `from '@nestjs/core'` or `from '@nestjs/platform-`.
#
# Usage: task_A_AC3.sh [repo_dir]   (default: .)
set -u
REPO="${1:-.}"

if [ ! -d "$REPO/.git" ]; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi

cd "$REPO" || { echo "FAIL: cannot cd into $REPO"; exit 1; }

FAIL=0

if ! git diff --quiet -- packages/common/package.json; then
  echo "FAIL: packages/common/package.json was modified:"
  git diff -- packages/common/package.json | sed 's/^/  /'
  FAIL=1
else
  echo "OK: packages/common/package.json unchanged"
fi

CHANGED=$(git diff --name-only HEAD -- packages/common; git status --porcelain -- packages/common | awk '{print $2}')
CHANGED=$(echo "$CHANGED" | sort -u | grep -v '^$')

BAD_IMPORTS=""
for f in $CHANGED; do
  [ -f "$f" ] || continue
  M=$(grep -nE "from ['\"]@nestjs/core['\"]|from ['\"]@nestjs/platform-" "$f" 2>/dev/null || true)
  if [ -n "$M" ]; then
    BAD_IMPORTS="$BAD_IMPORTS$f:\n$M\n"
  fi
done

if [ -n "$BAD_IMPORTS" ]; then
  echo "FAIL: forbidden cross-package import(s) found:"
  echo -e "$BAD_IMPORTS"
  FAIL=1
else
  echo "OK: no changed file imports from @nestjs/core or @nestjs/platform-*"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: no new cross-package dependency edge"
  exit 0
else
  echo "FAIL: see above"
  exit 1
fi
