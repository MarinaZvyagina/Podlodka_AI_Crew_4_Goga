#!/usr/bin/env bash
# Task C / AC3: The same mechanism is genuinely exercised for both HTTP and
# WebSocket gateways, and no HTTP-adapter-specific code was added.
#
# Method: inspect added/changed files for both an HTTP controller case
# (@Controller / @Get / @Post / etc.) AND a WS gateway case
# (@WebSocketGateway / @SubscribeMessage), and check that the same guard
# class (the one found `implements CanActivate`) is referenced by both
# (directly, or indirectly via APP_GUARD registration shared by the whole
# application). Also grep packages/platform-express and
# packages/platform-fastify for any new maintenance-mode-related code
# (expected: none -- the correct mechanism is transport-agnostic and lives
# above the adapter layer).
#
# Usage: task_C_AC3.sh [repo_dir]   (default: .)
set -u
REPO="${1:-.}"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
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

# --- Step 1: forbidden platform-adapter code ---------------------------------
PLATFORM_HITS=$(echo "$CHANGED" | grep -E '^packages/platform-express/|^packages/platform-fastify/' || true)
if [ -n "$PLATFORM_HITS" ]; then
  echo "FAIL: new/changed code found inside packages/platform-express or"
  echo "packages/platform-fastify -- the correct mechanism must operate above"
  echo "the concrete HTTP adapter layer:"
  echo "$PLATFORM_HITS" | sed 's/^/  /'
  exit 1
fi
echo "OK: no changes under packages/platform-express or packages/platform-fastify."
echo

# --- Step 2: locate the guard class (same detection as AC1) ------------------
GUARD_CLASS=""
for f in $CHANGED_SRC; do
  [ -f "$f" ] || continue
  M=$(grep -oE 'class [A-Za-z0-9_]+ implements CanActivate' "$f" 2>/dev/null | head -1 | awk '{print $2}')
  if [ -n "$M" ]; then
    GUARD_CLASS="$M"
    break
  fi
done

if [ -z "$GUARD_CLASS" ]; then
  echo "FAIL: no class 'implements CanActivate' was found anywhere in the"
  echo "diff (see AC1) -- there is no shared guard mechanism for AC3 to"
  echo "confirm is exercised by both an HTTP case and a WS gateway case."
  echo "Whatever cross-transport protection exists (if any) is not built on"
  echo "the framework's CanActivate contract."
  exit 1
fi

echo "Guard class under test: $GUARD_CLASS"
echo

# --- Step 3: find HTTP evidence ----------------------------------------------
HTTP_FILES=""
for f in $CHANGED_SRC; do
  [ -f "$f" ] || continue
  if grep -qE '@Controller\(|@Get\(|@Post\(|@Put\(|@Delete\(|@Patch\(' "$f" 2>/dev/null; then
    HTTP_FILES="${HTTP_FILES}${f}
"
  fi
done

# --- Step 4: find WS evidence -------------------------------------------------
WS_FILES=""
for f in $CHANGED_SRC; do
  [ -f "$f" ] || continue
  if grep -qE '@WebSocketGateway\(|@SubscribeMessage\(' "$f" 2>/dev/null; then
    WS_FILES="${WS_FILES}${f}
"
  fi
done

if [ -z "$HTTP_FILES" ] || [ -z "$WS_FILES" ]; then
  echo "FAIL: diff does not contain both an HTTP case (@Controller/@Get/...)"
  echo "and a WS gateway case (@WebSocketGateway/@SubscribeMessage)."
  echo "HTTP files found:"
  echo "${HTTP_FILES:-  (none)}" | sed 's/^/  /'
  echo "WS files found:"
  echo "${WS_FILES:-  (none)}" | sed 's/^/  /'
  exit 1
fi

echo "HTTP evidence found in:"
echo "$HTTP_FILES" | sed 's/^/  /'
echo "WS evidence found in:"
echo "$WS_FILES" | sed 's/^/  /'
echo

# --- Step 5: does the guard class (or its registration) reach both sides? ---
# Direct reference: the guard class name appears in an HTTP file and a WS file
# (e.g. via @UseGuards(GuardClass) or an import), OR it is registered once via
# APP_GUARD in a module file that is shared by both the HTTP controller and
# the WS gateway (global registration covers every handler transport-wide).
GUARD_REF_IN_HTTP=$(echo "$HTTP_FILES" | while read -r f; do [ -n "$f" ] && grep -l "$GUARD_CLASS" "$f" 2>/dev/null; done)
GUARD_REF_IN_WS=$(echo "$WS_FILES" | while read -r f; do [ -n "$f" ] && grep -l "$GUARD_CLASS" "$f" 2>/dev/null; done)

APP_GUARD_MODULE=$(for f in $CHANGED_SRC; do [ -f "$f" ] && grep -l "APP_GUARD" "$f" 2>/dev/null; done)

if [ -n "$GUARD_REF_IN_HTTP" ] && [ -n "$GUARD_REF_IN_WS" ]; then
  echo "PASS: guard class '$GUARD_CLASS' is directly referenced in both an HTTP file and a WS gateway file."
  exit 0
fi

if [ -n "$APP_GUARD_MODULE" ]; then
  echo "Guard is registered globally via APP_GUARD in:"
  echo "$APP_GUARD_MODULE" | sed 's/^/  /'
  echo "PASS: guard is registered globally (APP_GUARD), and both an HTTP"
  echo "controller case and a WS gateway case are present in the diff, so"
  echo "the same guard mechanism applies to both transports."
  exit 0
fi

echo "MANUAL REVIEW REQUIRED: found separate HTTP and WS test/example files"
echo "and a CanActivate guard class ($GUARD_CLASS), but could not automatically"
echo "confirm that the SAME guard instance protects both -- neither a direct"
echo "reference to '$GUARD_CLASS' in both HTTP and WS files, nor a shared"
echo "APP_GUARD registration, was found. Please manually confirm both paths"
echo "are protected by the same guard class."
exit 1
