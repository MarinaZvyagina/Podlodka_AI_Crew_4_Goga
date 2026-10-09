#!/usr/bin/env bash
# AC4: Passwordless (NoPassword=true) accounts are unaffected.
#
# Method (per metadata_A.yaml AC4): go test with a subtest creating/updating a
# NoPassword=true user with an empty password and asserting success.
#
# PASS: `go test ./auth/... -run 'TestUserAdd|TestUserChangePassword' -v`
#       exits 0 AND the test output shows a passing test that exercises
#       NoPassword=true with an empty password.
# FAIL: go test itself fails/exits non-zero.
# MANUAL REVIEW REQUIRED (exit 2): go test passes but no subtest name/output
#       clearly exercises the NoPassword=true + empty-password case.

set -uo pipefail

REPO="${1:-.}"
SERVER_DIR="$REPO/server"

if [ ! -d "$SERVER_DIR" ]; then
  echo "FAIL: server/ directory not found under repo path '$REPO'"
  exit 1
fi

pushd "$SERVER_DIR" > /dev/null || { echo "FAIL: could not cd into $SERVER_DIR"; exit 1; }

test_output="$(go test ./auth/... -run 'TestUserAdd|TestUserChangePassword' -v -timeout 120s 2>&1)"
test_exit=$?

popd > /dev/null

if [ $test_exit -ne 0 ]; then
  echo "FAIL: 'go test ./auth/... -run TestUserAdd|TestUserChangePassword -v' exited $test_exit"
  echo "$test_output" | tail -60
  exit 1
fi

# Find PASS'd test names that look like they exercise NoPassword=true with an
# empty password.
nopass_pass_lines="$(echo "$test_output" | grep -E '^--- PASS: Test[A-Za-z0-9_]*' | grep -iE 'nopass|no_password')"

if [ -z "$nopass_pass_lines" ]; then
  echo "MANUAL REVIEW REQUIRED: go test passed (exit 0), but no passing subtest name clearly exercises the NoPassword=true + empty-password case. Inspect test output manually to confirm a NoPassword=true UserAdd/UserChangePassword with an empty password succeeds."
  echo "$test_output" | grep -E '^(--- PASS|--- FAIL|=== RUN)'
  exit 2
fi

echo "PASS: go test exited 0, and the following passing subtest(s) exercise NoPassword=true with an empty password:"
echo "$nopass_pass_lines"
exit 0
