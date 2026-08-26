#!/usr/bin/env bash
# Task C / AC2: Per-handler marking is done via reflective metadata, not a
# string-keyed path registry.
#
# Method: grep -n "SetMetadata\|Reflector" in the diff; separately grep for
# suspicious patterns like a Set<string>/array of literal URL path strings
# checked against request.url or request.path.
#
# Correct: a SetMetadata-based custom decorator marks handlers/classes, and
# the guard reads it back via Reflector.get/getAllAndOverride.
# Trap: a hardcoded list of path strings checked against the incoming HTTP
# request URL (cannot express "this WS message handler is protected").
#
# Usage: task_C_AC2.sh [repo_dir]   (default: .)
set -u
REPO="${1:-.}"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi

cd "$REPO" || { echo "FAIL: cannot cd into $REPO"; exit 1; }

CHANGED=$(git diff --name-only HEAD; git status --porcelain -uall | awk '{print $2}')
CHANGED=$(echo "$CHANGED" | sort -u | grep -v '^$' | grep -E '\.(ts|js)$')

if [ -z "$CHANGED" ]; then
  echo "FAIL: no changed .ts/.js files detected against HEAD (nothing to validate)"
  exit 1
fi

echo "Changed source files:"
echo "$CHANGED" | sed 's/^/  /'
echo

META_MATCHES=""
for f in $CHANGED; do
  [ -f "$f" ] || continue
  M=$(grep -nE 'SetMetadata|Reflector' "$f" 2>/dev/null)
  if [ -n "$M" ]; then
    META_MATCHES="${META_MATCHES}${f}:
${M}
"
  fi
done

if [ -z "$META_MATCHES" ]; then
  echo "FAIL: no 'SetMetadata' or 'Reflector' usage found in the diff."
  echo "Per-handler marking does not appear to be implemented via reflective"
  echo "metadata."
  exit 1
fi

echo "Found reflective-metadata usage (SetMetadata / Reflector):"
echo "$META_MATCHES"

# Now look for a suspicious literal-path-registry pattern. Two independent
# signals, either of which is a strong red flag for the trap:
#   (a) code reading request.url / request.path / req.url / req.path /
#       .originalUrl directly -- a reflective-metadata guard has no reason
#       to inspect the raw request URL at all (it works off
#       context.getHandler()/getClass()).
#   (b) a Set<string>/array literal whose elements are URL-path-shaped
#       string literals (start with '/'), e.g. a hardcoded route registry.
SUSPICIOUS=""
for f in $CHANGED; do
  [ -f "$f" ] || continue
  M=$(grep -nE "(req|request)\.(url|path|originalUrl)\b" "$f" 2>/dev/null)
  if [ -n "$M" ]; then
    SUSPICIOUS="${SUSPICIOUS}${f} [reads request URL/path directly]:
${M}
"
  fi
  M2=$(grep -nE "(new Set<string>\s*\(\s*\[|:\s*string\[\]\s*=\s*\[)\s*['\"]\/" "$f" 2>/dev/null)
  if [ -n "$M2" ]; then
    SUSPICIOUS="${SUSPICIOUS}${f} [literal URL-path array/Set]:
${M2}
"
  fi
done

if [ -n "$SUSPICIOUS" ]; then
  echo
  echo "FAIL: found suspicious literal-path-registry pattern(s) alongside (or"
  echo "instead of) reflective metadata usage -- this looks like a"
  echo "string-keyed path registry checked against the raw request URL/path,"
  echo "which cannot express protection for a WS message handler:"
  echo "$SUSPICIOUS"
  exit 1
fi

echo
echo "PASS: reflective metadata (SetMetadata/Reflector) is used to mark/read handler protection, and no literal URL-path-registry pattern was found."
exit 0
