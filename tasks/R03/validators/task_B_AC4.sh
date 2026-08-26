#!/usr/bin/env bash
# Task B / AC4: No new static dependency edge from packages/core or
# packages/websockets onto a specific platform package
# (@nestjs/platform-socket.io / @nestjs/platform-ws). Any dynamic/optional
# loading must follow the existing pattern in
# packages/core/helpers/load-adapter.ts, not a hardcoded static import. Also,
# no new dependency/peerDependency entries pointing at those packages should
# appear in packages/core/package.json or packages/websockets/package.json.
#
# Method:
#   1. Diff packages/core/package.json and packages/websockets/package.json
#      dependencies/peerDependencies against HEAD; fail if a new entry for
#      @nestjs/platform-socket.io or @nestjs/platform-ws appears.
#   2. Grep changed *.ts files (excluding tests) in packages/core and
#      packages/websockets for a static `from '@nestjs/platform-socket.io'`
#      / `from '@nestjs/platform-ws'` import specifier.
#
# Usage: task_B_AC4.sh [repo_dir]   (default: .)
set -u
REPO="${1:-.}"

if [ ! -d "$REPO/.git" ]; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi

cd "$REPO" || { echo "FAIL: cannot cd into $REPO"; exit 1; }

CHANGED=$( { git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u | grep -v '^$')

if [ -z "$CHANGED" ]; then
  echo "FAIL: no changes detected against HEAD (nothing to validate)"
  exit 1
fi

FAILED=0

for pkgjson in packages/core/package.json packages/websockets/package.json; do
  if [ ! -f "$pkgjson" ]; then
    continue
  fi
  DIFF_OUT=$(git diff HEAD -- "$pkgjson" 2>/dev/null || true)
  if [ -z "$DIFF_OUT" ]; then
    echo "OK: $pkgjson unchanged."
    continue
  fi
  NEW_PLATFORM_DEP=$(echo "$DIFF_OUT" | grep -E '^[+]' | grep -v '^[+][+][+]' | grep -E '"@nestjs/platform-socket\.io"|"@nestjs/platform-ws"')
  if [ -n "$NEW_PLATFORM_DEP" ]; then
    echo "FAIL: $pkgjson gained a new dependency entry pointing at a platform package:"
    echo "$NEW_PLATFORM_DEP" | sed 's/^/  /'
    FAILED=1
  else
    echo "OK: $pkgjson changed, but no new @nestjs/platform-socket.io / @nestjs/platform-ws dependency entry found."
  fi
done
echo

STATIC_IMPORT_VIOLATIONS=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  case "$f" in
    packages/core/*|packages/websockets/*) ;;
    *) continue ;;
  esac
  case "$f" in
    *.ts) ;;
    *) continue ;;
  esac
  case "$f" in
    *test*|*.spec.ts) continue ;;
  esac
  MATCH=$(grep -nE "from ['\"]@nestjs/platform-socket\.io['\"]|from ['\"]@nestjs/platform-ws['\"]|require\(['\"]@nestjs/platform-socket\.io['\"]\)|require\(['\"]@nestjs/platform-ws['\"]\)" "$f" 2>/dev/null | sed "s#^#$f:#")
  [ -n "$MATCH" ] && STATIC_IMPORT_VIOLATIONS="${STATIC_IMPORT_VIOLATIONS}${MATCH}"$'\n'
done <<< "$CHANGED"
STATIC_IMPORT_VIOLATIONS=$(echo "$STATIC_IMPORT_VIOLATIONS" | grep -v '^$' || true)

if [ -n "$STATIC_IMPORT_VIOLATIONS" ]; then
  echo "FAIL: found a static import/require of a platform package from packages/core or packages/websockets source (excluding tests) -- must use the existing dynamic loadAdapter() pattern instead:"
  echo "$STATIC_IMPORT_VIOLATIONS" | sed 's/^/  /'
  FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi

echo "PASS: no new @nestjs/platform-socket.io / @nestjs/platform-ws dependency entries in packages/core or packages/websockets package.json, and no new static import of either package from their non-test source files."
exit 0
