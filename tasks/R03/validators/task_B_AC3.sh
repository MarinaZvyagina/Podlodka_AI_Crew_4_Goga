#!/usr/bin/env bash
# Task B / AC3: Per-transport wire-protocol behavior must stay behind the
# adapter abstraction (WebSocketAdapter / AbstractWsAdapter) and be
# implemented symmetrically for both platforms.
#
# Method:
#   1. git diff --stat: confirm both
#      packages/platform-socket.io/adapters/io-adapter.ts and
#      packages/platform-ws/adapters/ws-adapter.ts are touched (or, in a
#      template-method style, the shared base class
#      packages/websockets/adapters/ws-adapter.ts is touched and both
#      concrete adapters still each carry some of the new logic).
#   2. grep packages/core and packages/websockets (excluding tests) for
#      socket.io-specific calls (`.emit(`, `.disconnectSockets(`) or
#      ws-specific calls (raw `.send(`, `.close(<code>, <reason>)`,
#      `.terminate(`) -- there must be ZERO such calls outside the
#      platform-socket.io / platform-ws packages.
#
# Usage: task_B_AC3.sh [repo_dir]   (default: .)
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

echo "Changed files (git diff --stat against HEAD):"
git diff --stat HEAD | sed 's/^/  /'
echo

IO_ADAPTER="packages/platform-socket.io/adapters/io-adapter.ts"
WS_ADAPTER="packages/platform-ws/adapters/ws-adapter.ts"
BASE_ADAPTER="packages/websockets/adapters/ws-adapter.ts"

TOUCHED_IO=0
TOUCHED_WS=0
TOUCHED_BASE=0
echo "$CHANGED" | grep -qxF "$IO_ADAPTER" && TOUCHED_IO=1
echo "$CHANGED" | grep -qxF "$WS_ADAPTER" && TOUCHED_WS=1
echo "$CHANGED" | grep -qxF "$BASE_ADAPTER" && TOUCHED_BASE=1

echo "IoAdapter (platform-socket.io) touched: $TOUCHED_IO"
echo "WsAdapter (platform-ws) touched:        $TOUCHED_WS"
echo "AbstractWsAdapter (websockets) touched: $TOUCHED_BASE"
echo

if [ "$TOUCHED_IO" -eq 0 ] || [ "$TOUCHED_WS" -eq 0 ]; then
  echo "FAIL: expected both $IO_ADAPTER and $WS_ADAPTER to be touched with symmetric per-transport logic (optionally alongside the shared base class $BASE_ADAPTER). Behavior is not implemented symmetrically for both platforms."
  exit 1
fi

# Scan packages/core and packages/websockets (excluding tests, and excluding
# the platform-* packages themselves) for transport-specific wire-protocol
# calls that should only live inside platform-socket.io / platform-ws.
VIOLATIONS=""
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
  MATCH=$(grep -nE '\.emit\(|\.disconnectSockets\(|\.terminate\(|\.send\(|\.close\([^)]*,[^)]*\)' "$f" 2>/dev/null | sed "s#^#$f:#")
  [ -n "$MATCH" ] && VIOLATIONS="${VIOLATIONS}${MATCH}"$'\n'
done <<< "$CHANGED"
VIOLATIONS=$(echo "$VIOLATIONS" | grep -v '^$' || true)

if [ -n "$VIOLATIONS" ]; then
  echo "FAIL: found transport-specific wire-protocol call(s) in packages/core or packages/websockets (outside the platform-* adapter packages) -- this hardcodes one transport's protocol instead of going through the adapter abstraction:"
  echo "$VIOLATIONS" | sed 's/^/  /'
  exit 1
fi

echo "No socket.io-specific (.emit(/.disconnectSockets() or raw ws-specific (.send(/.terminate(/.close(code, reason)) calls found in changed packages/core or packages/websockets files."
echo "PASS: per-transport behavior is implemented symmetrically in both platform-socket.io and platform-ws adapters, behind the shared adapter abstraction."
exit 0
