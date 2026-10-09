#!/usr/bin/env bash
# AC5: Deletes and compaction correctly invalidate cached data (not just
# plain writes).
#
# Method: embed and copy the same integration test used by task_D_AC3.sh
# into $1/tests/integration/ (cache a range, DeleteRange or Compact
# affecting it, then Range again) and run only the "DeleteRange" and
# "Compact" subtests -- confirming a deleted key is never served from a
# stale cache, and a compacted revision is reported as compacted rather
# than silently served from a stale cache entry.
#
# The copied test file is always removed afterward, regardless of outcome.
set -u

REPO="${1:-.}"
TEST_DIR="$REPO/tests/integration"
TEST_FILE="$TEST_DIR/v3_range_caching_check_test.go"
RUN_PATTERN='TestV3RangeCachingConsistency/(DeleteRange|Compact)'

if [ ! -d "$TEST_DIR" ]; then
  echo "MANUAL REVIEW REQUIRED: $TEST_DIR not found in $REPO; cannot run integration test"
  exit 2
fi

PRE_EXISTING=0
if [ -e "$TEST_FILE" ]; then
  PRE_EXISTING=1
fi

cleanup() {
  if [ "$PRE_EXISTING" -eq 0 ]; then
    rm -f "$TEST_FILE"
  fi
}
trap cleanup EXIT

if [ "$PRE_EXISTING" -eq 1 ]; then
  echo "MANUAL REVIEW REQUIRED: $TEST_FILE already exists in the target repo; refusing to overwrite. Remove it or inspect manually."
  exit 2
fi

cat > "$TEST_FILE" <<'GOTEST_EOF'
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
	"testing"

	"github.com/stretchr/testify/require"

	pb "go.etcd.io/etcd/api/v3/etcdserverpb"
	"go.etcd.io/etcd/api/v3/mvccpb"
	"go.etcd.io/etcd/tests/v3/framework/integration"
)

// TestV3RangeCachingConsistency exercises the requirement from task R06-TD:
// repeated, identical Range requests may be served from a cache, but a
// client must never observe data staler than what an equivalent uncached
// read would have returned at the time of the request. It covers Put,
// DeleteRange, and Compact invalidation, each with both Serializable=false
// (linearizable) and Serializable=true (serializable) Range requests.
func TestV3RangeCachingConsistency(t *testing.T) {
	t.Run("Put", testV3RangeCachingConsistencyPut)
	t.Run("DeleteRange", testV3RangeCachingConsistencyDeleteRange)
	t.Run("Compact", testV3RangeCachingConsistencyCompact)
}

// rangeValue issues a Range for key against kvc with the given Serializable
// flag and returns the single value found (or nil if the key is absent).
func rangeValue(t *testing.T, kvc pb.KVClient, key string, serializable bool) []byte {
	t.Helper()
	resp, err := kvc.Range(t.Context(), &pb.RangeRequest{
		Key:          []byte(key),
		Serializable: serializable,
	})
	require.NoError(t, err)
	if len(resp.Kvs) == 0 {
		return nil
	}
	return resp.Kvs[0].Value
}

func testV3RangeCachingConsistencyPut(t *testing.T) {
	integration.BeforeTest(t)
	clus := integration.NewCluster(t, &integration.ClusterConfig{Size: 3})
	defer clus.Terminate(t)

	kvc := integration.ToGRPC(clus.Client(0)).KV
	key := "caching/put-key"

	for _, serializable := range []bool{false, true} {
		// (1) Range once to (potentially) warm any cache.
		_, err := kvc.Range(t.Context(), &pb.RangeRequest{Key: []byte(key), Serializable: serializable})
		require.NoError(t, err)

		// (2) Put a new value through the normal client path.
		newVal := []byte("new-value")
		_, err = kvc.Put(t.Context(), &pb.PutRequest{Key: []byte(key), Value: newVal})
		require.NoError(t, err)

		// (3) Immediately Range again: must observe the new value, not a
		// cached pre-Put result, for both linearizable and serializable
		// requests.
		got := rangeValue(t, kvc, key, serializable)
		require.Equalf(t, newVal, got, "serializable=%v: stale value returned after Put: got %q, want %q", serializable, got, newVal)
	}
}

func testV3RangeCachingConsistencyDeleteRange(t *testing.T) {
	integration.BeforeTest(t)
	clus := integration.NewCluster(t, &integration.ClusterConfig{Size: 3})
	defer clus.Terminate(t)

	kvc := integration.ToGRPC(clus.Client(0)).KV

	for _, serializable := range []bool{false, true} {
		key := "caching/delete-key"
		_, err := kvc.Put(t.Context(), &pb.PutRequest{Key: []byte(key), Value: []byte("v1")})
		require.NoError(t, err)

		// Cache a range that sees the key present.
		got := rangeValue(t, kvc, key, serializable)
		require.Equal(t, []byte("v1"), got)

		// Delete it.
		_, err = kvc.DeleteRange(t.Context(), &pb.DeleteRangeRequest{Key: []byte(key)})
		require.NoError(t, err)

		// A subsequent Range must reflect the deletion, not serve the
		// cached (pre-delete) value.
		resp, err := kvc.Range(t.Context(), &pb.RangeRequest{Key: []byte(key), Serializable: serializable})
		require.NoError(t, err)
		require.Emptyf(t, resp.Kvs, "serializable=%v: deleted key still served (stale cache), got value %q", serializable, valueOrNil(resp.Kvs))
	}
}

func testV3RangeCachingConsistencyCompact(t *testing.T) {
	integration.BeforeTest(t)
	clus := integration.NewCluster(t, &integration.ClusterConfig{Size: 3})
	defer clus.Terminate(t)

	kvc := integration.ToGRPC(clus.Client(0)).KV

	for i, serializable := range []bool{false, true} {
		key := "caching/compact-key"
		_, err := kvc.Put(t.Context(), &pb.PutRequest{Key: []byte(key), Value: []byte("v1")})
		require.NoError(t, err)
		putResp, err := kvc.Put(t.Context(), &pb.PutRequest{Key: []byte(key), Value: []byte("v2")})
		require.NoError(t, err)
		compactRev := putResp.Header.Revision

		// Cache a Range pinned at an old (pre-compaction) revision: this
		// must succeed right now...
		oldRevReq := &pb.RangeRequest{Key: []byte(key), Revision: compactRev - 1, Serializable: serializable}
		_, err = kvc.Range(t.Context(), oldRevReq)
		require.NoErrorf(t, err, "iteration %d: range at revision %d should succeed before compaction", i, compactRev-1)

		// Compact away that old revision.
		_, err = kvc.Compact(t.Context(), &pb.CompactionRequest{Revision: compactRev})
		require.NoError(t, err)

		// The identical Range request, repeated, must now report the
		// revision as compacted -- not silently return the cached
		// pre-compaction result.
		_, err = kvc.Range(t.Context(), oldRevReq)
		require.ErrorContainsf(t, err, "mvcc: required revision has been compacted", "iteration %d: compacted revision was served from a stale cache instead of returning ErrCompacted", i)

		// A live (uncompacted) Range for the same key must still return
		// the latest value.
		got := rangeValue(t, kvc, key, serializable)
		require.Equal(t, []byte("v2"), got)
	}
}

func valueOrNil(kvs []*mvccpb.KeyValue) []byte {
	if len(kvs) == 0 {
		return nil
	}
	return kvs[0].Value
}
GOTEST_EOF

cd "$REPO/tests" || { echo "MANUAL REVIEW REQUIRED: could not cd into $REPO/tests"; exit 2; }

OUT=$(go test ./integration/... -run "$RUN_PATTERN" -v -timeout 180s 2>&1)
RC=$?

echo "$OUT"

if [ "$RC" -eq 0 ] && echo "$OUT" | grep -q '^--- PASS: TestV3RangeCachingConsistency'; then
  echo "PASS: $RUN_PATTERN succeeded -- deleted/compacted data was never served from a stale cache"
  exit 0
fi

echo "FAIL: $RUN_PATTERN did not pass (see output above) -- a Range after a DeleteRange/Compact returned stale (already-deleted or already-compacted) data, or the test failed to run"
exit 1
