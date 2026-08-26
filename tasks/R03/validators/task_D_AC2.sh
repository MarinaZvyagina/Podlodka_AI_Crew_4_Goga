#!/usr/bin/env bash
# Task D / AC2: Feature is implemented symmetrically for both platforms (or
# entirely above the adapter layer via the existing abstract methods).
#
# Method: git diff --stat; check whether
# packages/platform-express/adapters/express-adapter.ts and
# packages/platform-fastify/adapters/fastify-adapter.ts received equivalent
# changes, OR whether NEITHER was touched because the feature is expressed
# purely via code in packages/core (or an app-level provider) calling the
# existing abstract setHeader/appendHeader methods.
#
# Trap: only platform-express touched (or Express-specific code appears
# anywhere) with no equivalent fastify change.
#
# Usage: task_D_AC2.sh [repo_dir]   (default: .)
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

echo "git diff --stat:"
git diff --stat HEAD 2>/dev/null | sed 's/^/  /'
echo "New (untracked) files:"
git status --porcelain | awk '$1 == "??" {print $2}' | sed 's/^/  /'
echo

EXPRESS_ADAPTER="packages/platform-express/adapters/express-adapter.ts"
FASTIFY_ADAPTER="packages/platform-fastify/adapters/fastify-adapter.ts"

express_touched=0
fastify_touched=0
echo "$CHANGED" | grep -qxF "$EXPRESS_ADAPTER" && express_touched=1
echo "$CHANGED" | grep -qxF "$FASTIFY_ADAPTER" && fastify_touched=1

if [ "$express_touched" -ne "$fastify_touched" ]; then
  echo "FAIL: asymmetric platform-adapter changes -- express_touched=$express_touched fastify_touched=$fastify_touched"
  exit 1
fi

if [ "$express_touched" -eq 1 ] && [ "$fastify_touched" -eq 1 ]; then
  echo "OK: both platform adapter files were touched (symmetric low-level change) -- inspecting diff sizes as a sanity check"
  EXP_LINES=$(git diff HEAD -- "$EXPRESS_ADAPTER" | grep -cE '^[+-][^+-]')
  FAS_LINES=$(git diff HEAD -- "$FASTIFY_ADAPTER" | grep -cE '^[+-][^+-]')
  echo "  express-adapter.ts changed lines: $EXP_LINES"
  echo "  fastify-adapter.ts changed lines: $FAS_LINES"
fi

# Even when neither canonical adapter file was touched, scan the WHOLE diff
# (application/shared code) for Express-specific escape hatches that would
# make the feature secretly Express-only despite claiming to be
# platform-neutral.
EXPRESS_SIGNS_REGEX='\bexpress\(\)|from ['"'"'"]express['"'"'"]|require\(['"'"'"]express['"'"'"]\)|\bExpressAdapter\b|getHttpAdapter\(\)\s*\.\s*getInstance\(\)|\bexpressApp\b|\bexpressInstance\b'

SUSPICIOUS=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  case "$f" in
    *.ts) ;;
    *) continue ;;
  esac
  # Adapter implementation files are allowed to reference express/fastify by
  # name -- that's their job. Test/spec files are allowed to reference
  # ExpressAdapter/express explicitly too (that's covered by AC4, not AC2).
  case "$f" in
    packages/platform-express/*|packages/platform-fastify/*) continue ;;
    *.spec.ts|*/e2e/*|*/test/*) continue ;;
  esac
  MATCHES=$(grep -nE "$EXPRESS_SIGNS_REGEX" "$f" 2>/dev/null || true)
  if [ -n "$MATCHES" ]; then
    SUSPICIOUS="${SUSPICIOUS}${f}:"$'\n'"${MATCHES}"$'\n'
  fi
done <<< "$CHANGED"

if [ -n "$SUSPICIOUS" ]; then
  echo "FAIL: Express-specific code found in application/shared source with no fastify equivalent (feature is not platform-neutral):"
  echo "$SUSPICIOUS" | sed 's/^/  /'
  exit 1
fi

echo "PASS: platform adapters touched symmetrically (or neither touched), and no Express-only escape hatch found in application/shared source"
exit 0
