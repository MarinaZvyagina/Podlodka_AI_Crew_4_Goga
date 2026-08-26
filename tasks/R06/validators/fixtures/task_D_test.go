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

// This file is injected by tasks/R06/validators/task_D_functional.sh. It is
// a black-box functional check for R06 task D (cache repeated reads without
// violating consistency).
//
// It talks only to the raw pb.KVClient gRPC stub (via
// integration.ToGRPC(...).KV) against a real 3-node cluster -- the same
// entry point any client/tool uses -- and never references any caching
// implementation detail (no rangeCache, no sync.Map, no TTL constant, no
// mvcc-package symbol). It only checks the externally observable contract:
// a Range must never return data staler than what an equivalent uncached
// read would have returned at the time of the request, for both
// Serializable=true and Serializable=false requests, across Put,
// DeleteRange and Compact.
package integration

import (
	"testing"

	"github.com/stretchr/testify/require"

	pb "go.etcd.io/etcd/api/v3/etcdserverpb"
	"go.etcd.io/etcd/api/v3/mvccpb"
	"go.etcd.io/etcd/tests/v3/framework/integration"
)

// TestTaskDRangeCachingConsistency exercises the requirement from task
// R06-TD: repeated, identical Range requests may be served from a cache,
// but a client must never observe data staler than what an equivalent
// uncached read would have returned at the time of the request. It covers
// Put, DeleteRange, and Compact invalidation, each with both
// Serializable=false (linearizable) and Serializable=true (serializable)
// Range requests.
func TestTaskDRangeCachingConsistency(t *testing.T) {
	t.Run("Put", taskDRangeCachingConsistencyPut)
	t.Run("DeleteRange", taskDRangeCachingConsistencyDeleteRange)
	t.Run("Compact", taskDRangeCachingConsistencyCompact)
}

// taskDRangeValue issues a Range for key against kvc with the given
// Serializable flag and returns the single value found (or nil if the key
// is absent).
func taskDRangeValue(t *testing.T, kvc pb.KVClient, key string, serializable bool) []byte {
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

func taskDRangeCachingConsistencyPut(t *testing.T) {
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
		got := taskDRangeValue(t, kvc, key, serializable)
		require.Equalf(t, newVal, got, "serializable=%v: stale value returned after Put: got %q, want %q", serializable, got, newVal)
	}
}

func taskDRangeCachingConsistencyDeleteRange(t *testing.T) {
	integration.BeforeTest(t)
	clus := integration.NewCluster(t, &integration.ClusterConfig{Size: 3})
	defer clus.Terminate(t)

	kvc := integration.ToGRPC(clus.Client(0)).KV

	for _, serializable := range []bool{false, true} {
		key := "caching/delete-key"
		_, err := kvc.Put(t.Context(), &pb.PutRequest{Key: []byte(key), Value: []byte("v1")})
		require.NoError(t, err)

		// Cache a range that sees the key present.
		got := taskDRangeValue(t, kvc, key, serializable)
		require.Equal(t, []byte("v1"), got)

		// Delete it.
		_, err = kvc.DeleteRange(t.Context(), &pb.DeleteRangeRequest{Key: []byte(key)})
		require.NoError(t, err)

		// A subsequent Range must reflect the deletion, not serve the
		// cached (pre-delete) value.
		resp, err := kvc.Range(t.Context(), &pb.RangeRequest{Key: []byte(key), Serializable: serializable})
		require.NoError(t, err)
		require.Emptyf(t, resp.Kvs, "serializable=%v: deleted key still served (stale cache), got value %q", serializable, taskDValueOrNil(resp.Kvs))
	}
}

func taskDRangeCachingConsistencyCompact(t *testing.T) {
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
		got := taskDRangeValue(t, kvc, key, serializable)
		require.Equal(t, []byte("v2"), got)
	}
}

func taskDValueOrNil(kvs []*mvccpb.KeyValue) []byte {
	if len(kvs) == 0 {
		return nil
	}
	return kvs[0].Value
}
