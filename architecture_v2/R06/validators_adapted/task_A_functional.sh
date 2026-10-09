#!/usr/bin/env bash
# Functional validator for R06 task A (reject empty passwords unless
# NoPassword).
#
# Injects a black-box integration test (fixtures/task_A_test.go) that talks
# only to the real AuthServer gRPC service via a raw pb.AuthClient - the same
# entry point any client/tool (etcdctl, clientv3, grpcurl, ...) would use -
# and never references server/auth internals. See the fixture file's header
# comment for full rationale, including why case (4) (UserChangePassword on
# a NoPassword account to a blank password must still succeed) is the
# sharpest black-box discriminator for this task.
#
# Usage: task_A_functional.sh [REPO_PATH]   (REPO_PATH defaults to ".")
# Prints PASS:/FAIL: and exits 0/1.

set -uo pipefail

REPO="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/fixtures/task_A_test.go"
TEST_NAME="TestTaskAAuthRejectsEmptyPassword"
DEST_REL="tests/integration/zz_task_a_functional_test.go"
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
  echo "PASS: $TEST_NAME succeeded - empty passwords are rejected server-side unless the account is explicitly NoPassword, and NoPassword accounts (including changing their password to blank) keep working."
  exit 0
fi

echo "FAIL: $TEST_NAME did not pass (exit status $STATUS). Output:"
echo "$OUTPUT" | tail -60
exit 1
