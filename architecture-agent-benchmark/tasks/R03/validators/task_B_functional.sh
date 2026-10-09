#!/usr/bin/env bash
# Task B functional validator: R03-TB -- WebSocket graceful-shutdown
# notification, required equivalently for packages/platform-socket.io and
# packages/platform-ws.
#
# This is a fully self-contained fixture (no discovery needed): it boots a
# real Nest app with a trivial gateway, once under the default (socket.io)
# adapter and once under WsAdapter, connects a real client in each case, and
# calls the framework's real public `app.close()` (the same call
# `enableShutdownHooks()` triggers) -- then asserts, purely from the
# client's point of view, that *some* message/event arrived on the
# still-open connection before it was closed. See fixtures/task_B_test.spec.ts
# for the full black-box rationale.
#
# Both platform runs must pass for an overall PASS -- per
# metadata_B.yaml this is a hard "equivalent behavior for both transports"
# requirement, and CONTROL_RESULTS.md records this as the specific place
# where the negative/trap control (socket.io-only, no ws support at all)
# is expected to fail.
#
# Usage: task_B_functional.sh [repo_dir]   (default: .)
set -u
REPO="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_SRC="$SCRIPT_DIR/fixtures/task_B_test.spec.ts"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi
if [ ! -f "$FIXTURE_SRC" ]; then
  echo "FAIL: fixture not found at $FIXTURE_SRC"
  exit 1
fi

cd "$REPO" || { echo "FAIL: cannot cd into $REPO"; exit 1; }
REPO_ABS="$(pwd)"

if [ ! -f "vitest.config.integration.mts" ]; then
  echo "FAIL: vitest.config.integration.mts not found at repo root"
  exit 1
fi

PROBE_DIR="integration/_functional_check_B"
PROBE_SPEC="$PROBE_DIR/e2e/shutdown-notify.spec.ts"
mkdir -p "$PROBE_DIR/e2e"

cleanup() {
  rm -rf "$REPO_ABS/$PROBE_DIR"
}
trap cleanup EXIT

cp "$FIXTURE_SRC" "$PROBE_SPEC"

echo "Injected functional-check fixture at: $PROBE_SPEC"
echo "Running: npx vitest run --config vitest.config.integration.mts $PROBE_SPEC"
echo

OUT="$(mktemp)"
if npx vitest run --config vitest.config.integration.mts "$PROBE_SPEC" >"$OUT" 2>&1; then
  tail -n 80 "$OUT"
  rm -f "$OUT"
  echo
  echo "PASS: connected WebSocket clients receive a notification before disconnect on graceful shutdown, equivalently under both platform-socket.io and platform-ws."
  exit 0
else
  tail -n 120 "$OUT"
  IO_OK=1
  WS_OK=1
  grep -q "socket.io:.*✓\|socket.io:.*passed" "$OUT" 2>/dev/null || IO_OK=0
  grep -q "platform-ws:.*✓\|platform-ws:.*passed" "$OUT" 2>/dev/null || WS_OK=0
  rm -f "$OUT"
  echo
  echo "FAIL: at least one transport did not deliver a shutdown notification to a connected client before closing its connection (see vitest output above for which of socket.io / platform-ws failed). This is the exact 'notifies socket.io but silently does nothing for ws' Dangerous-Success pattern this check is designed to catch."
  exit 1
fi
