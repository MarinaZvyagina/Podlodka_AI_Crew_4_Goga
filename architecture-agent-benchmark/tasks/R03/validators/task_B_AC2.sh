#!/usr/bin/env bash
# Task B / AC2: Gateway/connection discovery for the shutdown-notification
# feature must go through the existing SocketsContainer registry
# (packages/websockets/sockets-container.ts, populated via
# packages/websockets/socket-module.ts), not a new, independently
# maintained record of connected sockets/gateways.
#
# Method:
#   1. grep -n "SocketsContainer" across the diff -- must find at least one
#      hit in a non-test changed file (evidence the feature discovers
#      servers through the existing registry).
#   2. Separately scan the *added* lines of the diff for new module/class
#      -level collections (Map/Set/WeakMap/Array) whose name suggests they
#      independently track connected sockets/clients/gateways (a trap
#      signal: a parallel bookkeeping structure instead of reusing
#      SocketsContainer).
#
# Usage: task_B_AC2.sh [repo_dir]   (default: .)
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

echo "Changed files:"
echo "$CHANGED" | sed 's/^/  /'
echo

SC_HITS=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  case "$f" in
    *.ts) ;;
    *) continue ;;
  esac
  MATCH=$(grep -n "SocketsContainer" "$f" 2>/dev/null | sed "s#^#$f:#")
  [ -n "$MATCH" ] && SC_HITS="${SC_HITS}${MATCH}"$'\n'
done <<< "$CHANGED"
SC_HITS=$(echo "$SC_HITS" | grep -v '^$' || true)

echo "SocketsContainer references found in diff:"
if [ -n "$SC_HITS" ]; then
  echo "$SC_HITS" | sed 's/^/  /'
else
  echo "  (none)"
fi
echo

# Scan ADDED lines only, across non-test changed .ts files, for suspicious
# new parallel bookkeeping collections tracking sockets/clients/gateways.
SUSPICIOUS=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  case "$f" in
    *.ts) ;;
    *) continue ;;
  esac
  case "$f" in
    *test*|*.spec.ts) continue ;;
  esac
  ADDED=$(git diff -U0 -- "$f" 2>/dev/null | grep -E '^[+]' | grep -v '^[+][+][+]')
  [ -z "$ADDED" ] && continue
  # Look for "new Map(", "new Set(", "new WeakMap(", or array literal
  # assignments, on a line that also mentions socket/client/gateway/connection
  # -like naming, and is NOT the pre-existing SocketsContainer's own file.
  MATCH=$(echo "$ADDED" | grep -iE '(new (Map|Set|WeakMap|WeakSet)\(|\[\]\s*;?\s*$|:\s*(Map|Set)<)' | grep -iE 'socket|client|gateway|connection')
  if [ -n "$MATCH" ] && [ "$f" != "packages/websockets/sockets-container.ts" ]; then
    SUSPICIOUS="${SUSPICIOUS}${f}:"$'\n'"${MATCH}"$'\n'
  fi
done <<< "$CHANGED"
SUSPICIOUS=$(echo "$SUSPICIOUS" | grep -v '^$' || true)

if [ -n "$SUSPICIOUS" ]; then
  echo "FAIL: found newly-added collection(s) outside sockets-container.ts that look like an independent, parallel record of connected sockets/gateways (should reuse the existing SocketsContainer instead):"
  echo "$SUSPICIOUS" | sed 's/^/  /'
  exit 1
fi

if [ -z "$SC_HITS" ]; then
  echo "FAIL: no reference to the existing SocketsContainer registry found anywhere in the diff -- cannot confirm gateway/connection discovery goes through it."
  exit 1
fi

echo "No suspicious new parallel bookkeeping structures detected."
echo "PASS: gateway/connection discovery is wired through the existing SocketsContainer registry, and no new independently-maintained tracking structure was introduced."
exit 0
