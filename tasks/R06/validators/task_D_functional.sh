#!/usr/bin/env bash
# Functional validator for R06 task D (cache repeated reads without
# violating consistency).
#
# Injects a black-box integration test (fixtures/task_D_test.go) that talks
# only to the raw pb.KVClient gRPC stub against a real 3-node cluster - the
# same entry point any client/tool uses - and never references any caching
# implementation detail. It asserts that a Range never returns data staler
# than an equivalent uncached read would have, for both Serializable=true
# and Serializable=false requests, across Put, DeleteRange, and Compact.
#
# Usage: task_D_functional.sh [REPO_PATH]   (REPO_PATH defaults to ".")
# Prints PASS:/FAIL: and exits 0/1.

set -uo pipefail

REPO="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/fixtures/task_D_test.go"
TEST_NAME="TestTaskDRangeCachingConsistency"
DEST_REL="tests/integration/zz_task_d_functional_test.go"
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
OUTPUT="$(go test ./integration/... -run "$TEST_NAME" -v -timeout 180s 2>&1)"
STATUS=$?
popd > /dev/null

if [ $STATUS -eq 0 ] && echo "$OUTPUT" | grep -q "^--- PASS: $TEST_NAME"; then
  echo "PASS: $TEST_NAME succeeded - repeated Range requests never returned data staler than an equivalent uncached read across Put/DeleteRange/Compact, for both linearizable and serializable reads."
  exit 0
fi

echo "FAIL: $TEST_NAME did not pass (exit status $STATUS). Output:"
echo "$OUTPUT" | tail -80
exit 1
