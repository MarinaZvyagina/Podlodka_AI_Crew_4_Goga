#!/usr/bin/env bash
# Functional validator for R06 task B (cap max attached keys per lease).
#
# Injects a black-box test (fixtures/task_B_test.go) that configures the
# limit purely through go.etcd.io/etcd/server/v3/embed.Config (discovering
# the actual field name via reflection with a permissive, concept-based
# pattern, so it isn't tied to one reference implementation's exact
# identifier), starts a real embedded server, and exercises the limit only
# via real clientv3 Put/Grant/Get RPCs. See the fixture's header comment for
# full rationale.
#
# Deliberately NOT papered over: if the limit is enforced by making
# lease.Lessor.Attach() itself return a new error (the documented
# architectural trap for this task), server/storage/mvcc/kvstore_txn.go
# panics on any non-ErrLeaseNotFound error from Attach, crashing the
# in-process embedded server - and since the test runs in the same process,
# that crashes this test binary too (go test exits non-zero). That is a
# real, reproducible functional failure for this task, not an artifact of
# the validator, and this script reports it as FAIL rather than trying to
# recover/ignore it.
#
# Usage: task_B_functional.sh [REPO_PATH]   (REPO_PATH defaults to ".")
# Prints PASS:/FAIL: and exits 0/1.

set -uo pipefail

REPO="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/fixtures/task_B_test.go"
TEST_NAME="TestTaskBMaxAttachedKeysPerLease"
DEST_REL="tests/integration/zz_task_b_functional_test.go"
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
  echo "PASS: $TEST_NAME succeeded - the configured max-attached-keys-per-lease limit is enforced end to end with a clean client-facing error, re-attaching an existing key is never rejected, and the server remains healthy afterward."
  exit 0
fi

if echo "$OUTPUT" | grep -qi "panic:"; then
  echo "FAIL: $TEST_NAME crashed the (embedded, in-process) etcd server - a real panic was observed instead of a clean client-facing error. Output:"
  echo "$OUTPUT" | grep -i -A 20 "panic:" | head -60
  exit 1
fi

echo "FAIL: $TEST_NAME did not pass (exit status $STATUS). Output:"
echo "$OUTPUT" | tail -60
exit 1
