#!/usr/bin/env bash
# Task C functional validator: R03-TC -- maintenance-mode guard (HTTP + WS).
#
# Task C's functional requirement does not fix a class/decorator/service
# name (any developer-chosen "mark this handler" mechanism is acceptable as
# long as it works for both transports), so a single static fixture cannot
# exercise an arbitrary candidate's demo app the way Task A/B's fixtures do.
# Instead this delegates to fixtures/task_C_discover.mjs, which:
#   - locates the diff's own demo module/controller/gateway/service by
#     structural convention (integration/*/src/*.module.ts, a sibling
#     *.controller.ts / *.gateway.ts, and -- via the guard's constructor if
#     one exists, else by name heuristic -- the toggle service), and
#   - generates a real vitest e2e spec that boots that module for real,
#     drives the toggle service via runtime reflection (never assuming a
#     method is called `enable()`/`isEnabled()`), and independently asserts
#     the marked HTTP route + WS message handler are rejected while
#     maintenance is on and unaffected handlers keep working -- rather than
#     trusting any call-log/spy the candidate's own diff might have added
#     (which a trap implementation could write to self-servingly pass).
#
# See fixtures/task_C_discover.mjs for the full discovery algorithm.
#
# Usage: task_C_functional.sh [repo_dir]   (default: .)
set -u
REPO="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISCOVER_SCRIPT="$SCRIPT_DIR/fixtures/task_C_discover.mjs"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi
if [ ! -f "$DISCOVER_SCRIPT" ]; then
  echo "FAIL: discovery script not found at $DISCOVER_SCRIPT"
  exit 1
fi

cd "$REPO" || { echo "FAIL: cannot cd into $REPO"; exit 1; }
REPO_ABS="$(pwd)"

if [ ! -f "vitest.config.integration.mts" ]; then
  echo "FAIL: vitest.config.integration.mts not found at repo root"
  exit 1
fi

PROBE_DIR="integration/_functional_check_C"
PROBE_SPEC="$PROBE_DIR/e2e/maintenance-mode-probe.spec.ts"

cleanup() {
  rm -rf "$REPO_ABS/$PROBE_DIR"
}
trap cleanup EXIT

echo "Discovering the candidate's maintenance-mode demo app..."
if ! node "$DISCOVER_SCRIPT" "$REPO_ABS" "$REPO_ABS/$PROBE_SPEC"; then
  echo
  echo "FAIL: could not build an independent functional check for this diff (see discovery output above)."
  exit 1
fi
echo

echo "Running: npx vitest run --config vitest.config.integration.mts $PROBE_SPEC"
echo

OUT="$(mktemp)"
if npx vitest run --config vitest.config.integration.mts "$PROBE_SPEC" >"$OUT" 2>&1; then
  tail -n 80 "$OUT"
  rm -f "$OUT"
  echo
  echo "PASS: the discovered maintenance-mode mechanism rejects the marked HTTP route and the marked WS message handler while maintenance mode is on (unmarked handlers unaffected), and normal behavior is restored once toggled off -- verified via a real, independently-driven e2e boot of the diff's own demo app."
  exit 0
else
  tail -n 120 "$OUT"
  rm -f "$OUT"
  echo
  echo "FAIL: the discovered maintenance-mode mechanism did not reject the marked HTTP route and/or the marked WS message handler while maintenance mode was on (see vitest output above for which side failed)."
  exit 1
fi
