#!/usr/bin/env bash
# Task D / AC4: Functional test coverage actually includes both platforms,
# not just the default.
#
# Method: inspect the diff's new/changed test files for references to both
# ExpressAdapter/platform-express AND FastifyAdapter/platform-fastify
# bootstrapping.
#
# Usage: task_D_AC4.sh [repo_dir]   (default: .)
set -u
REPO="${1:-.}"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi

cd "$REPO" || { echo "FAIL: cannot cd into $REPO"; exit 1; }

CHANGED=$( { git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u | grep -v '^$')

if [ -z "$CHANGED" ]; then
  echo "FAIL: no changes detected against HEAD (nothing to validate)"
  exit 1
fi

TEST_FILES=$(echo "$CHANGED" | grep -E '\.spec\.ts$|/e2e/' || true)

if [ -z "$TEST_FILES" ]; then
  echo "FAIL: no new/changed test files (*.spec.ts or under an e2e/ dir) found in the diff"
  exit 1
fi

echo "Changed test files:"
echo "$TEST_FILES" | sed 's/^/  /'
echo

HAS_FASTIFY=0
HAS_EXPRESS_OR_DEFAULT=0
FASTIFY_FILES=""
EXPRESS_FILES=""

while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue

  if grep -qE "FastifyAdapter|platform-fastify" "$f" 2>/dev/null; then
    HAS_FASTIFY=1
    FASTIFY_FILES="${FASTIFY_FILES}${f}"$'\n'
  fi

  # "Default" bootstrap (Test.createTestingModule(...).compile() then
  # createNestApplication() with no adapter arg) is Express by default in
  # Nest, so we count either an explicit ExpressAdapter/platform-express
  # reference OR a bootstrap with no adapter argument as express coverage.
  if grep -qE "ExpressAdapter|platform-express" "$f" 2>/dev/null; then
    HAS_EXPRESS_OR_DEFAULT=1
    EXPRESS_FILES="${EXPRESS_FILES}${f}"$'\n'
  elif grep -qE "createNestApplication\(\)" "$f" 2>/dev/null; then
    HAS_EXPRESS_OR_DEFAULT=1
    EXPRESS_FILES="${EXPRESS_FILES}${f} (default/no-adapter bootstrap == express)"$'\n'
  fi
done <<< "$TEST_FILES"

echo "Express/default coverage found in:"
echo "${EXPRESS_FILES:-  (none)}" | sed 's/^/  /'
echo "Fastify coverage found in:"
echo "${FASTIFY_FILES:-  (none)}" | sed 's/^/  /'
echo

if [ "$HAS_FASTIFY" -eq 1 ] && [ "$HAS_EXPRESS_OR_DEFAULT" -eq 1 ]; then
  echo "PASS: diff's test files bootstrap and exercise BOTH platform-express (or default) AND platform-fastify"
  exit 0
fi

echo "FAIL: diff's test files do not cover both platforms (fastify_coverage=$HAS_FASTIFY express_or_default_coverage=$HAS_EXPRESS_OR_DEFAULT) -- a suite that only exercises the default/Express adapter does NOT satisfy the functional check"
exit 1
