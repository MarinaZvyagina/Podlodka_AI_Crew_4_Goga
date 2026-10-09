#!/usr/bin/env bash
# Functional validator for R06 task C (uniform KV audit trail).
#
# Injects a black-box test (fixtures/task_C_test.go) that starts a real
# embedded etcd server with auth enabled and its log output pointed at a
# plain file (the standard embed.Config.LogOutputs mechanism - no
# implementation-specific logging sink assumed), issues one each of
# Range/Put/DeleteRange/Txn through a real authenticated clientv3 client,
# and scans the captured log for an audit-shaped record (an "audit" marker +
# the caller's username + an op-kind keyword) for every one of the four
# request kinds - including Txn, the one a naive per-handler-only
# instrumentation typically forgets. See the fixture's header comment for
# the documented heuristic limitations (shared with validators/task_C_AC5.sh).
#
# Usage: task_C_functional.sh [REPO_PATH]   (REPO_PATH defaults to ".")
# Prints PASS:/FAIL: and exits 0/1.

set -uo pipefail

REPO="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/fixtures/task_C_test.go"
TEST_NAME="TestTaskCAuditTrail"
DEST_REL="tests/integration/zz_task_c_functional_test.go"
DEST="$REPO/$DEST_REL"

if [ ! -d "$REPO" ]; then
  echo "FAIL: repo path '$REPO' does not exist"
  exit 1
fi
if [ ! -f "$FIXTURE" ]; then
  echo "FAIL: fixture not found at $FIXTURE"
  exit 1
fi
if [ ! -d "$REPO/tests/integration" ]; then
  echo "FAIL: expected directory not found under repo path '$REPO': tests/integration"
  exit 1
fi

cleanup() {
  rm -f "$DEST"
}
trap cleanup EXIT

cp "$FIXTURE" "$DEST"

pushd "$REPO/tests" > /dev/null || { echo "FAIL: could not cd into $REPO/tests"; exit 1; }
OUTPUT="$(go test ./integration/... -run "$TEST_NAME" -v -timeout 120s 2>&1)"
STATUS=$?
popd > /dev/null

if [ $STATUS -eq 0 ] && echo "$OUTPUT" | grep -q "^--- PASS: $TEST_NAME"; then
  echo "PASS: $TEST_NAME succeeded - an audit-shaped log record correlated with the calling user was observed for Range, Put, DeleteRange, and Txn."
  exit 0
fi

echo "FAIL: $TEST_NAME did not pass (exit status $STATUS). Output:"
echo "$OUTPUT" | tail -60
exit 1
