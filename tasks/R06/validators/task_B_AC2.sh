#!/usr/bin/env bash
# AC2 (task B / R06-TB): end-to-end behavior at the limit boundary - clean
# error, no crash.
#
# Method (per metadata_B.yaml AC2): integration test issuing real Put RPCs up
# to and past the configured limit against a running (embedded) etcd
# instance, then checking the server is still responsive.
#
# PASS: over-limit Put returns a clean, typed gRPC error; server stays up and
#       serves subsequent requests.
# FAIL: server process exits/panics on the over-limit Put, or the over-limit
#       Put silently succeeds (no limit enforced end-to-end), or the limit
#       cannot be configured/exercised at all.
#
# Strategy:
#  1. If the repo already has its own tests/integration/*_test.go defining
#     TestV3LeaseAttachedKeysLimit (as instructed by functional_check_command),
#     run that test as-is - it is inherently generic since the implementation
#     wrote it against its own config field names.
#  2. Otherwise, fall back to a bundled reference test (modeled on
#     tests/integration/v3_lease_test.go) that drives the scenario via
#     integration.ClusterConfig{MaxAttachedKeysPerLease: N} - the field name
#     used by this benchmark's own positive-control implementation. If that
#     doesn't even compile against the target repo, the limit is not wired
#     through a discoverable standard config path we can exercise, and this
#     is reported as FAIL (not skipped).
# Any copied file is always removed afterward, regardless of outcome.

set -uo pipefail

REPO="${1:-.}"
TESTS_DIR="$REPO/tests"
INTEG_DIR="$TESTS_DIR/integration"

if [ ! -d "$INTEG_DIR" ]; then
  echo "FAIL: $INTEG_DIR not found; cannot run the integration-level functional check"
  exit 1
fi

COPIED_FILE=""
cleanup() {
  if [ -n "$COPIED_FILE" ] && [ -f "$COPIED_FILE" ]; then
    rm -f "$COPIED_FILE"
  fi
}
trap cleanup EXIT

run_and_judge() {
  # Runs TestV3LeaseAttachedKeysLimit in $TESTS_DIR/integration and prints a
  # verdict. Returns 0 for PASS, 1 for FAIL (also echoes PASS:/FAIL: itself).
  local out rc
  out="$(cd "$TESTS_DIR" && go test ./integration/... -run '^TestV3LeaseAttachedKeysLimit$' -v -timeout 180s 2>&1)"
  rc=$?

  if echo "$out" | grep -qE 'panic:|SIGSEGV|SIGABRT|fatal error:'; then
    echo "FAIL: the integration test run shows a server/test-process panic or fatal error - the over-limit Put appears to crash the node rather than returning a clean gRPC error. Relevant output:"
    echo "$out" | grep -E 'panic:|SIGSEGV|SIGABRT|fatal error:' | head -20
    return 1
  fi

  if [ "$rc" -ne 0 ]; then
    echo "FAIL: TestV3LeaseAttachedKeysLimit did not pass (exit code $rc). Tail of output:"
    echo "$out" | tail -40
    return 1
  fi

  if ! echo "$out" | grep -q -- '--- PASS: TestV3LeaseAttachedKeysLimit'; then
    echo "FAIL: TestV3LeaseAttachedKeysLimit did not report PASS (it may not have run at all). Tail of output:"
    echo "$out" | tail -40
    return 1
  fi

  echo "PASS: TestV3LeaseAttachedKeysLimit passed end-to-end (clean gRPC error at the limit boundary, server remained responsive afterward), with no panic/fatal error observed in the test output."
  return 0
}

# --- Strategy 1: use the implementation's own test, if present ---------

if ls "$INTEG_DIR"/*.go >/dev/null 2>&1 && grep -lq 'func TestV3LeaseAttachedKeysLimit(' "$INTEG_DIR"/*.go 2>/dev/null; then
  if run_and_judge; then
    exit 0
  fi
  exit 1
fi

# --- Strategy 2: fall back to a bundled reference test -----------------

echo "NOTE: no tests/integration/*.go in the target repo defines TestV3LeaseAttachedKeysLimit; falling back to a bundled reference test driven via integration.ClusterConfig{MaxAttachedKeysPerLease: N}." >&2

COPIED_FILE="$INTEG_DIR/zz_validator_v3_lease_attached_keys_limit_test.go"
cat > "$COPIED_FILE" <<'EOF'
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
	"fmt"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	clientv3 "go.etcd.io/etcd/client/v3"
	"go.etcd.io/etcd/tests/v3/framework/integration"
)

func TestV3LeaseAttachedKeysLimit(t *testing.T) {
	integration.BeforeTest(t)

	const limit = 3
	clus := integration.NewCluster(t, &integration.ClusterConfig{
		Size:                    1,
		MaxAttachedKeysPerLease: limit,
	})
	defer clus.Terminate(t)

	cli := clus.Client(0)
	ctx := t.Context()

	lresp, err := cli.Grant(ctx, 100)
	require.NoError(t, err)
	leaseID := lresp.ID

	for i := 0; i < limit; i++ {
		key := fmt.Sprintf("key-%d", i)
		_, err := cli.Put(ctx, key, "v", clientv3.WithLease(leaseID))
		require.NoErrorf(t, err, "put %d (under limit) should succeed", i)
	}

	_, err = cli.Put(ctx, "key-0", "v2", clientv3.WithLease(leaseID))
	require.NoError(t, err, "re-attaching an already-attached key must not be rejected")

	_, err = cli.Put(ctx, "key-new", "v", clientv3.WithLease(leaseID))
	require.Error(t, err, "put of a new key past the limit must fail")

	getResp, getErr := cli.Get(ctx, "key-new")
	require.NoError(t, getErr, "server must still be responsive after the rejection")
	require.Empty(t, getResp.Kvs, "rejected put must not have been (partially) applied")

	putCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	_, err = cli.Put(putCtx, "unrelated-key", "unrelated-value")
	require.NoError(t, err, "server must remain healthy and serve unrelated Puts after the rejection")

	getResp, err = cli.Get(ctx, "unrelated-key")
	require.NoError(t, err)
	require.Len(t, getResp.Kvs, 1)
}
EOF

# NOTE: `go build` deliberately does not compile _test.go files, so it would
# not catch an unknown struct field referenced only from a test - use `go
# vet`, which does type-check test files, to actually validate the bundled
# reference test compiles against this repo's ClusterConfig.
if ! (cd "$TESTS_DIR" && go vet ./integration/... 2>build_err.log); then
  echo "FAIL: the target repo has no discoverable way to configure the max-attached-keys-per-lease limit (the bundled reference test, which sets integration.ClusterConfig.MaxAttachedKeysPerLease, fails to compile against this repo) - the limit is not wired through a standard config path we can exercise end-to-end."
  echo "--- vet error ---"
  cat "$TESTS_DIR/build_err.log" 2>/dev/null | head -30
  rm -f "$TESTS_DIR/build_err.log"
  exit 1
fi
rm -f "$TESTS_DIR/build_err.log"

if run_and_judge; then
  exit 0
fi
exit 1
