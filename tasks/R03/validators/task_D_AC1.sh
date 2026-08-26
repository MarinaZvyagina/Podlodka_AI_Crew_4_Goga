#!/usr/bin/env bash
# Task D / AC1: The response header must be set through the abstract adapter's
# setHeader/appendHeader (dispatched via HttpAdapterHost/AbstractHttpAdapter),
# never via a raw call directly on the platform response object from shared
# or application code.
#
# Method: grep -n '\.setHeader(\|\.appendHeader(' across all files changed by
# the diff (the task spec scopes this to packages/core/**/*.ts, excluding
# packages/core/adapters/http-adapter.ts itself, and packages/common/**/*.ts
# touched by the diff -- but we also scan any other changed application-level
# file, since the architectural trap for this task is expected to live in
# app/interceptor code rather than inside packages/core or packages/common).
# For every match, the receiver (the identifier right before the method call)
# must look like a reference to the abstract adapter (e.g. httpAdapter,
# adapterHost.httpAdapter, applicationRef, adapter) and NOT a raw
# response/request object (response, res, reply, rawRes, httpRes...).
#
# The two canonical platform adapter implementation files
# (packages/platform-express/adapters/express-adapter.ts and
# packages/platform-fastify/adapters/fastify-adapter.ts) are exempt: they are
# *allowed* (and expected) to call the raw platform response object, since
# that's precisely where AbstractHttpAdapter#setHeader/#appendHeader are
# realized per-platform.
#
# Usage: task_D_AC1.sh [repo_dir]   (default: .)
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

EXEMPT_FILES="packages/platform-express/adapters/express-adapter.ts
packages/platform-fastify/adapters/fastify-adapter.ts
packages/core/adapters/http-adapter.ts"

echo "Changed files:"
echo "$CHANGED" | sed 's/^/  /'
echo

SUSPICIOUS=""
CHECKED_ANY=0

while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  case "$f" in
    *.ts) ;;
    *) continue ;;
  esac
  if echo "$EXEMPT_FILES" | grep -qxF "$f"; then
    continue
  fi

  MATCHES=$(grep -nE '\.setHeader\(|\.appendHeader\(' "$f" 2>/dev/null || true)
  [ -z "$MATCHES" ] && continue
  CHECKED_ANY=1

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    # Skip comment lines (JSDoc/line comments) -- we only care about
    # actual executable code, not prose describing what NOT to do.
    CODE_PART="${line#*:}"
    TRIMMED=$(echo "$CODE_PART" | sed -E 's/^[[:space:]]*//')
    case "$TRIMMED" in
      '*'*|'//'*) continue ;;
    esac
    # Extract the receiver: the identifier chain immediately before
    # ".setHeader(" or ".appendHeader(".
    RECEIVER=$(echo "$line" | grep -oE '[A-Za-z0-9_.]+\.(setHeader|appendHeader)\(' | sed -E 's/\.(setHeader|appendHeader)\($//')
    if echo "$RECEIVER" | grep -qiE '(^|\.)(response|res|reply|rawres|rawresponse|httpres|expressresponse|fastifyreply)$'; then
      SUSPICIOUS="${SUSPICIOUS}${f}: ${line}  [receiver='${RECEIVER}']"$'\n'
    fi
  done <<< "$MATCHES"
done <<< "$CHANGED"

if [ -n "$SUSPICIOUS" ]; then
  echo "FAIL: found direct call(s) on a raw response/request object instead of going through the abstract adapter:"
  echo "$SUSPICIOUS" | sed 's/^/  /'
  exit 1
fi

if [ "$CHECKED_ANY" -eq 0 ]; then
  echo "PASS: no .setHeader(/.appendHeader( calls found in changed files outside the platform adapter implementations (feature likely dispatches purely through the abstract adapter, or sets no headers directly in shared/app code)"
  exit 0
fi

echo "PASS: all .setHeader(/.appendHeader( calls found in changed files are dispatched through an adapter-like receiver (e.g. httpAdapter/applicationRef), not a raw response object"
exit 0
