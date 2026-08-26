#!/usr/bin/env bash
# Task C / AC4: No bypass of routing/guard resolution via raw middleware or
# adapter-level hacks.
#
# Method: grep the diff for `.use(` calls registering raw middleware, or
# edits inside packages/platform-express/adapters/express-adapter.ts or
# packages/platform-fastify/adapters/fastify-adapter.ts.
# Correct: none found.
# Trap: maintenance check implemented as Express/Fastify middleware
# registered via app.use(...), which runs before routing/guard resolution
# and has no WS equivalent.
#
# Usage: task_C_AC4.sh [repo_dir]   (default: .)
set -u
REPO="${1:-.}"

if [ ! -d "$REPO/.git" ]; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi

cd "$REPO" || { echo "FAIL: cannot cd into $REPO"; exit 1; }

CHANGED=$(git diff --name-only HEAD; git status --porcelain -uall | awk '{print $2}')
CHANGED=$(echo "$CHANGED" | sort -u | grep -v '^$')
CHANGED_SRC=$(echo "$CHANGED" | grep -E '\.(ts|js)$')

if [ -z "$CHANGED_SRC" ]; then
  echo "FAIL: no changed .ts/.js files detected against HEAD (nothing to validate)"
  exit 1
fi

echo "Changed files:"
echo "$CHANGED" | sed 's/^/  /'
echo

FAIL=0

# --- Check 1: edits inside the concrete adapter files -------------------------
ADAPTER_HITS=$(echo "$CHANGED" | grep -E '^packages/platform-express/adapters/express-adapter\.ts$|^packages/platform-fastify/adapters/fastify-adapter\.ts$' || true)
if [ -n "$ADAPTER_HITS" ]; then
  echo "FAIL: diff edits the concrete HTTP adapter file(s) directly:"
  echo "$ADAPTER_HITS" | sed 's/^/  /'
  FAIL=1
else
  echo "OK: no edits inside express-adapter.ts / fastify-adapter.ts."
fi
echo

# --- Check 2: raw `.use(` middleware registration in changed application code -
USE_HITS=""
for f in $CHANGED_SRC; do
  [ -f "$f" ] || continue
  M=$(grep -nE '\.use\(' "$f" 2>/dev/null)
  if [ -n "$M" ]; then
    USE_HITS="${USE_HITS}${f}:
${M}
"
  fi
done

if [ -n "$USE_HITS" ]; then
  echo "FAIL: found raw '.use(' middleware-registration call(s) in the diff."
  echo "This is the classic trap: maintenance check reimplemented as"
  echo "Express/Fastify middleware, which runs before routing/guard"
  echo "resolution and has no WebSocket-gateway equivalent:"
  echo "$USE_HITS"
  FAIL=1
else
  echo "OK: no '.use(' middleware-registration calls found in the diff."
fi
echo

if [ "$FAIL" -eq 1 ]; then
  exit 1
fi

echo "PASS: no raw middleware registration or adapter-level edits found; routing/guard resolution is not bypassed."
exit 0
