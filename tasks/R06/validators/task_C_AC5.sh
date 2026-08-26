#!/usr/bin/env bash
# AC5: Coverage is genuinely uniform across all four KV RPC kinds (Range,
# Put, DeleteRange, Txn) without per-type special-casing spread across
# multiple files.
#
# Method (per metadata_C.yaml AC5): "Integration test exercising
# Range/Put/DeleteRange/Txn and confirming an audit record for each; code
# review confirming the type-switch (or equivalent) lives in one
# function/file."
#
# HEURISTIC / LIMITATIONS (read before trusting this script's verdict):
#   This script cannot know an arbitrary target implementation's exact log
#   format, field names, or sink (it could log to zap at Info/Debug, write to
#   a dedicated audit logger, emit a metric, etc.). To stay honest instead of
#   faking a verdict against an unknown format, it does the following:
#
#   1. It copies a real, runnable Go integration test (embedded below,
#      modeled on tests/integration/v3_auth_test.go's auth setup) into
#      $1/tests/integration/v3_audit_trail_check_test.go. That test starts a
#      1-member cluster with auth enabled, issues one authenticated Range,
#      Put, Txn, and DeleteRange, and then greps the member's captured zap
#      log output for a line containing "audit" plus an operation-kind marker
#      word (range/get, put, delete, txn/transaction) for EACH of the four
#      operations. This is a loose but real substring heuristic: it doesn't
#      know the implementation's exact field names, but it does distinguish
#      "an audit-looking record exists for op kind X" from "it doesn't",
#      which is exactly what's needed to catch the AC5 trap (some op kinds
#      silently uncovered).
#   2. It runs: cd "$1/tests" && go test ./integration/... -run
#      TestV3AuditTrail -v -timeout 180s
#   3. It ALWAYS removes the copied test file afterward, regardless of
#      outcome, so the repo is left clean.
#   4. If the implementation doesn't log anything containing the word
#      "audit" at all (e.g. it names its log message something else
#      entirely, or emits structured events via a completely different
#      mechanism such as a metrics counter with no log line), this test will
#      legitimately FAIL even though the implementation might be otherwise
#      correct. That is a real limitation of black-box log-scraping: this
#      script reports MANUAL REVIEW REQUIRED (not a hard FAIL) whenever the
#      test fails AND grep of the diff shows some audit-looking code was
#      added somewhere outside key.go/v3_server.go (i.e. the structural
#      signal from AC1 is positive) — in that case a human should check the
#      actual log/field format instead of trusting this script's string
#      matching. If AC1's structural signal is ALSO absent, this script
#      reports a hard FAIL, since there is then no positive signal at all.
#   5. Per the task instructions, if a fully generic log-format-agnostic
#      check isn't feasible, the fallback is: AC1's structural signal (one
#      shared code location covering all four op kinds) combined with "the
#      server didn't error running all four request types" against a
#      pragmatic functional smoke run. This script performs both the
#      stronger log-based check (primary) and documents the fallback
#      (secondary, used only to decide FAIL vs MANUAL REVIEW REQUIRED).

set -uo pipefail

REPO="${1:-.}"
BASE="23a4e406a2e70a807486b4c40a9e24da493886bf"
TEST_REL="tests/integration/v3_audit_trail_check_test.go"
TEST_FILE="$REPO/$TEST_REL"

if [ ! -d "$REPO/tests/integration" ]; then
  echo "FAIL: $REPO/tests/integration not found — cannot run the integration test"
  exit 1
fi

cleanup() {
  rm -f "$TEST_FILE"
}
trap cleanup EXIT

if [ -e "$TEST_FILE" ]; then
  echo "FAIL: $TEST_REL already exists in the target repo; refusing to overwrite. Remove it and re-run."
  exit 1
fi

cat > "$TEST_FILE" <<'EOF_TEST'
// Copyright 2026 The etcd Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package integration

import (
	"context"
	"strings"
	"testing"
	"time"

	clientv3 "go.etcd.io/etcd/client/v3"
	"go.etcd.io/etcd/tests/v3/framework/integration"
)

// TestV3AuditTrail is the functional check for task R06-TC (uniform audit trail for
// every Range/Put/DeleteRange/Txn request). See task_C_AC5.sh for the heuristic and
// its limitations. It starts a 1-member cluster with auth enabled and a known root
// user, issues one Range, one Put, one DeleteRange, and one Txn request as that user,
// and checks the member's captured log output for an audit-looking record per
// operation kind.
func TestV3AuditTrail(t *testing.T) {
	integration.BeforeTest(t)
	clus := integration.NewCluster(t, &integration.ClusterConfig{Size: 1})
	defer clus.Terminate(t)

	api := integration.ToGRPC(clus.Client(0))
	authSetupRoot(t, api.Auth)

	rootCli, err := clus.ClusterClient(t, integration.WithAuth("root", "123"))
	if err != nil {
		t.Fatalf("failed to create authenticated client: %v", err)
	}

	ctx, cancel := context.WithTimeout(t.Context(), 30*time.Second)
	defer cancel()

	if _, err := rootCli.Put(ctx, "audit-key", "v1"); err != nil {
		t.Fatalf("put failed: %v", err)
	}
	if _, err := rootCli.Get(ctx, "audit-key"); err != nil {
		t.Fatalf("range failed: %v", err)
	}
	if _, err := rootCli.Txn(ctx).Then(clientv3.OpPut("audit-key2", "v2")).Commit(); err != nil {
		t.Fatalf("txn failed: %v", err)
	}
	if _, err := rootCli.Delete(ctx, "audit-key"); err != nil {
		t.Fatalf("delete failed: %v", err)
	}

	m := clus.Members[0]
	expectAuditRecord(t, m, 10*time.Second, "put", []string{"put"})
	expectAuditRecord(t, m, 10*time.Second, "range", []string{"range", "get"})
	expectAuditRecord(t, m, 10*time.Second, "txn", []string{"txn", "transaction"})
	expectAuditRecord(t, m, 10*time.Second, "delete_range", []string{"delete"})
}

func expectAuditRecord(t *testing.T, m *integration.Member, timeout time.Duration, label string, markers []string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(t.Context(), timeout)
	defer cancel()

	lines, err := m.LogObserver.ExpectFunc(ctx, func(log string) bool {
		lower := strings.ToLower(log)
		if !strings.Contains(lower, "audit") {
			return false
		}
		for _, marker := range markers {
			if strings.Contains(lower, marker) {
				return true
			}
		}
		return false
	}, 1)
	if err != nil {
		t.Fatalf("no audit record observed for op kind %q (markers %v) within %s: %v", label, markers, timeout, err)
	}
	for _, l := range lines {
		t.Logf("[audit record for %s]: %s", label, l)
	}
}
EOF_TEST

pushd "$REPO/tests" > /dev/null || { echo "FAIL: could not cd into $REPO/tests"; exit 1; }
test_output="$(go test ./integration/... -run TestV3AuditTrail -v -timeout 180s 2>&1)"
test_exit=$?
popd > /dev/null

if [ $test_exit -eq 0 ]; then
  echo "PASS: TestV3AuditTrail passed — audit-looking log records observed for all four op kinds (range/put/delete_range/txn)"
  exit 0
fi

# Test failed (or errored). Use AC1's structural signal to decide FAIL vs
# MANUAL REVIEW REQUIRED, per this script's documented fallback.
grpc_diff="$(git -C "$REPO" diff "$BASE" -- server/etcdserver/api/v3rpc/grpc.go 2>/dev/null)"
interceptor_diff="$(git -C "$REPO" diff "$BASE" -- server/etcdserver/api/v3rpc/interceptor.go 2>/dev/null)"
structural_signal=0
if echo "$grpc_diff" | grep -qE '^\+.*[A-Za-z_][A-Za-z0-9_]*\(s\),?\s*$'; then
  structural_signal=1
fi
if echo "$interceptor_diff" | grep -E '^\+[^+]' | grep -qiE 'AuthInfoFromCtx|audit'; then
  structural_signal=1
fi

txn_record_status="txn audit record WAS observed (failure is unrelated to txn coverage)"
if ! echo "$test_output" | grep -qi 'audit record for txn'; then
  txn_record_status="txn audit record was NOT observed before the test failed (consistent with Txn being uncovered, or the test erroring out earlier)"
fi

if [ "$structural_signal" -eq 1 ]; then
  echo "MANUAL REVIEW REQUIRED: TestV3AuditTrail failed (exit $test_exit), but grpc.go/interceptor.go show a structural signal consistent with a centralized audit mechanism using a different log format/wording than this script's markers. Inspect actual log output below and verify manually whether all four op kinds are covered. ${txn_record_status}"
  echo "--- test output (tail) ---"
  echo "$test_output" | tail -60
  exit 2
fi

echo "FAIL: TestV3AuditTrail failed (exit $test_exit) and no structural signal of a centralized audit mechanism was found in grpc.go/interceptor.go — likely missing coverage for at least one KV RPC kind. ${txn_record_status}"
echo "--- test output (tail) ---"
echo "$test_output" | tail -60
exit 1
