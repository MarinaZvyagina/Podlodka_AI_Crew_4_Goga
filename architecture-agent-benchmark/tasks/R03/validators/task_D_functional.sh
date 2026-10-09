#!/usr/bin/env bash
# Task D functional validator: R03-TD -- cross-platform correlation/request-ID
# header. Boots a minimal Nest HTTP app TWICE -- once under platform-express,
# once under platform-fastify -- and requires BOTH to genuinely return a
# well-formed request/correlation-id header (reusing an incoming one when
# supplied) for an overall PASS. This is the task's headline "Dangerous
# Success": an Express-only implementation looks perfectly correct until you
# actually run it under Fastify too.
#
# Delegates discovery + probe synthesis to fixtures/task_D_discover.mjs,
# which, independently per platform:
#   - runs the diff's OWN test file for that platform for real, if the diff
#     already contains a spec that bootstraps it and asserts on a
#     request/correlation-id header (same detection method as
#     task_D_AC4.sh), or
#   - synthesizes and runs a throwaway probe against the diff's own
#     discovered *.module.ts under that platform (same strategy as the
#     existing task_D_AC5.sh, generalized to cover Express too, not just
#     Fastify), inspecting raw response headers directly (never the
#     response body, whose shape is candidate-specific).
#
# Usage: task_D_functional.sh [repo_dir]   (default: .)
set -u
REPO="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISCOVER_SCRIPT="$SCRIPT_DIR/fixtures/task_D_discover.mjs"

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

PROBE_DIR="integration/_functional_check_D"

cleanup() {
  rm -rf "$REPO_ABS/$PROBE_DIR"
}
trap cleanup EXIT

echo "Discovering per-platform test coverage / synthesizing probes..."
PLAN_OUT="$(mktemp)"
if ! node "$DISCOVER_SCRIPT" "$REPO_ABS" "$REPO_ABS/$PROBE_DIR" >"$PLAN_OUT" 2>/tmp/task_D_plan_err.$$; then
  cat /tmp/task_D_plan_err.$$
  rm -f /tmp/task_D_plan_err.$$ "$PLAN_OUT"
  echo
  echo "FAIL: could not build an independent functional check for this diff under either platform (see discovery output above)."
  exit 1
fi
cat /tmp/task_D_plan_err.$$
rm -f /tmp/task_D_plan_err.$$
PLAN_JSON="$(tail -n1 "$PLAN_OUT")"
rm -f "$PLAN_OUT"
echo

EXPRESS_SPEC="$(node -e "const p=JSON.parse(process.argv[1]); process.stdout.write(p.express ? p.express.spec : '')" "$PLAN_JSON")"
FASTIFY_SPEC="$(node -e "const p=JSON.parse(process.argv[1]); process.stdout.write(p.fastify ? p.fastify.spec : '')" "$PLAN_JSON")"

run_platform() {
  local name="$1"
  local spec="$2"
  if [ -z "$spec" ]; then
    echo "$name: FAIL (no way to test this platform -- diff has no own test for it and no bootable module was found to synthesize a probe against)"
    return 1
  fi
  echo "$name: running $spec"
  local out
  out="$(mktemp)"
  if npx vitest run --config vitest.config.integration.mts "$spec" >"$out" 2>&1; then
    tail -n 40 "$out"
    rm -f "$out"
    echo "$name: PASS"
    return 0
  else
    tail -n 60 "$out"
    rm -f "$out"
    echo "$name: FAIL"
    return 1
  fi
}

EXPRESS_RESULT=0
run_platform "platform-express" "$EXPRESS_SPEC" || EXPRESS_RESULT=1
echo
FASTIFY_RESULT=0
run_platform "platform-fastify" "$FASTIFY_SPEC" || FASTIFY_RESULT=1
echo

if [ "$EXPRESS_RESULT" -eq 0 ] && [ "$FASTIFY_RESULT" -eq 0 ]; then
  echo "PASS: the request/correlation-id header is present, well-formed, and correctly reused/echoed under BOTH platform-express and platform-fastify."
  exit 0
else
  echo "FAIL: the request/correlation-id header does not work correctly under at least one platform (platform-express: $([ $EXPRESS_RESULT -eq 0 ] && echo PASS || echo FAIL), platform-fastify: $([ $FASTIFY_RESULT -eq 0 ] && echo PASS || echo FAIL)). A suite that only exercises one platform does NOT satisfy this task's hard cross-platform requirement -- this is precisely the 'functionally-green-on-one-platform, broken-on-the-other' Dangerous Success this check exists to catch."
  exit 1
fi
