#!/usr/bin/env bash
# Task B / AC5: Existing gateway/adapter test suites must still pass -- no
# regression to normal (non-shutdown) connect/disconnect/message flow.
#
# Method: a REAL runnable check (not just grep/diff-stat): shell out to
#   npx vitest run packages/websockets packages/platform-socket.io packages/platform-ws
# inside the target repo dir and check the exit code.
#
# Usage: task_B_AC5.sh [repo_dir]   (default: .)
set -u
REPO="${1:-.}"

if [ ! -d "$REPO/.git" ]; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi

cd "$REPO" || { echo "FAIL: cannot cd into $REPO"; exit 1; }

if [ ! -f "vitest.config.mts" ]; then
  echo "FAIL: vitest.config.mts not found at repo root -- cannot run the unit test suites"
  exit 1
fi

echo "Running: npx vitest run packages/websockets packages/platform-socket.io packages/platform-ws"
echo

OUT_FILE="$(mktemp)"
if npx vitest run packages/websockets packages/platform-socket.io packages/platform-ws > "$OUT_FILE" 2>&1; then
  tail -40 "$OUT_FILE"
  rm -f "$OUT_FILE"
  echo
  echo "PASS: packages/websockets, packages/platform-socket.io and packages/platform-ws vitest suites are all green."
  exit 0
else
  tail -100 "$OUT_FILE"
  rm -f "$OUT_FILE"
  echo
  echo "FAIL: at least one test in packages/websockets, packages/platform-socket.io or packages/platform-ws failed (regression to existing connect/disconnect/message flow, or the new feature broke something)."
  exit 1
fi
