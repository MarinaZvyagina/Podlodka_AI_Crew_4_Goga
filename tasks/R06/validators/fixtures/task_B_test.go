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

// This file is injected by tasks/R06/validators/task_B_functional.sh. It is
// a black-box functional check for R06 task B (cap max attached keys per
// lease).
//
// It never imports server/lease, server/etcdserver/txn or any other
// server-internal package: the limit is configured purely through
// go.etcd.io/etcd/server/v3/embed.Config (the standard, documented way to
// start an embedded etcd server, and the exact path the task's own
// architectural_constraints require the new setting to be threaded through:
// CLI flag -> embed.Config -> server config -> LessorConfig), and it is
// exercised purely through real clientv3 RPCs against a real, running
// server process.
//
// Because different implementations may reasonably name the new knob
// differently (MaxAttachedKeysPerLease, MaxLeaseAttachedKeys,
// LeaseKeyLimit, ...), the exact field is *discovered* on embed.Config via
// reflection using a permissive, concept-based pattern (mirroring the same
// loose matching approach used by validators/task_B_AC3.sh), rather than
// hardcoded to one reference implementation's identifier. If no such field
// can be found at all, that is itself a legitimate functional failure: the
// task requires the limit to be configurable via the standard server config
// path, and if this black-box probe can't find any candidate field there,
// an operator starting a real server would not be able to configure it
// either.
package integration

import (
	"context"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	clientv3 "go.etcd.io/etcd/client/v3"
	"go.etcd.io/etcd/server/v3/embed"
)

const taskBAttachedKeyLimit = 3

// taskBFieldPattern matches embed.Config field names that plausibly
// represent "max distinct keys attachable to a lease", independent of exact
// naming. It intentionally mirrors the loose regex used by the
// architecture-check validator for this same task (task_B_AC3.sh).
var taskBFieldPattern = regexp.MustCompile(`(?i)(lease.{0,20}(max|limit).{0,20}key|key.{0,20}(max|limit).{0,20}lease|max.{0,20}attach|attach.{0,20}limit|attach(ed)?.{0,20}key|toomany.{0,20}key|key.{0,20}limit)`)

// taskBFindLimitField searches the exported, integer-kinded fields of
// *embed.Config for one whose name matches taskBFieldPattern.
func taskBFindLimitField(cfg *embed.Config) (reflect.Value, string, bool) {
	v := reflect.ValueOf(cfg).Elem()
	t := v.Type()
	for i := 0; i < t.NumField(); i++ {
		f := t.Field(i)
		if f.PkgPath != "" { // unexported field
			continue
		}
		if !taskBFieldPattern.MatchString(f.Name) {
			continue
		}
		fv := v.Field(i)
		switch fv.Kind() {
		case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64,
			reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64:
			if fv.CanSet() {
				return fv, f.Name, true
			}
		}
	}
	return reflect.Value{}, "", false
}

func taskBSetupEmbedCfg(cfg *embed.Config, curls, purls []url.URL) {
	cfg.Logger = "zap"
	cfg.LogOutputs = []string{"/dev/null"}
	cfg.ClusterState = "new"
	cfg.ListenClientUrls, cfg.AdvertiseClientUrls = curls, curls
	cfg.ListenPeerUrls, cfg.AdvertisePeerUrls = purls, purls
	initial := ""
	for i := range purls {
		initial += ",default=" + purls[i].String()
	}
	cfg.InitialCluster = initial[1:]
}

func taskBNewEmbedURLs(n int) []url.URL {
	var urls []url.URL
	for i := 0; i < n; i++ {
		u, err := url.Parse(fmt.Sprintf("unix://localhost-taskb:%d%06d", os.Getpid(), i))
		if err != nil {
			panic(err)
		}
		urls = append(urls, *u)
	}
	return urls
}

// TestTaskBMaxAttachedKeysPerLease is the functional validator for R06 task
// B. It starts one real embedded etcd server with the discovered
// max-attached-keys-per-lease knob set to a small limit, then, purely via
// real clientv3 RPCs:
//  1. Attaches `limit` distinct new keys to one lease: all must succeed.
//  2. Re-attaches an already-attached key while at the limit: must succeed
//     (re-attaching never increases the distinct key count).
//  3. Attaches one more brand-new key past the limit: must fail with a
//     clean, client-visible error -- not a stream/connection failure caused
//     by the server crashing.
//  4. Confirms the server is still healthy afterward by issuing and reading
//     back an unrelated Put/Get.
//
// If the limit is enforced by returning a new error type from
// lease.Lessor.Attach() itself (the documented architectural trap for this
// task), server/storage/mvcc/kvstore_txn.go's storeTxnWrite.put() treats any
// non-ErrLeaseNotFound error from Attach as an unrecoverable invariant
// violation and panics, crashing the whole (embedded, in-process) server --
// which, since the test runs in the same process, crashes this test binary
// too. That crash is the real signal this test is designed to reproduce and
// preserve, not paper over: go test will exit non-zero.
func TestTaskBMaxAttachedKeysPerLease(t *testing.T) {
	cfg := embed.NewConfig()
	fv, fieldName, ok := taskBFindLimitField(cfg)
	if !ok {
		t.Fatalf("could not find a configurable max-attached-keys-per-lease field on embed.Config (expected an exported integer field whose name relates to lease/key/attach/limit concepts) - the limit does not appear to be configurable through the standard embed.Config path")
	}
	t.Logf("using embed.Config field %q as the max-attached-keys-per-lease knob", fieldName)
	switch fv.Kind() {
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		fv.SetInt(int64(taskBAttachedKeyLimit))
	default:
		fv.SetUint(uint64(taskBAttachedKeyLimit))
	}

	urls := taskBNewEmbedURLs(2)
	taskBSetupEmbedCfg(cfg, []url.URL{urls[0]}, []url.URL{urls[1]})
	cfg.Dir = filepath.Join(t.TempDir(), "task-b-embed-etcd")

	e, err := embed.StartEtcd(cfg)
	require.NoError(t, err)
	defer e.Close()

	select {
	case <-e.Server.ReadyNotify():
	case <-time.After(30 * time.Second):
		t.Fatal("server took too long to become ready")
	}

	cli, err := clientv3.New(clientv3.Config{
		Endpoints:   []string{urls[0].String()},
		DialTimeout: 5 * time.Second,
	})
	require.NoError(t, err)
	defer cli.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	lresp, err := cli.Grant(ctx, 100)
	require.NoError(t, err)
	leaseID := lresp.ID

	for i := 0; i < taskBAttachedKeyLimit; i++ {
		key := fmt.Sprintf("key-%d", i)
		_, err := cli.Put(ctx, key, "v", clientv3.WithLease(leaseID))
		require.NoErrorf(t, err, "put %d (under limit) should succeed", i)
	}

	_, err = cli.Put(ctx, "key-0", "v2", clientv3.WithLease(leaseID))
	require.NoError(t, err, "re-attaching an already-attached key must not be rejected, even at the limit")

	putCtx, putCancel := context.WithTimeout(ctx, 15*time.Second)
	_, err = cli.Put(putCtx, "key-new", "v", clientv3.WithLease(leaseID))
	putCancel()
	require.Error(t, err, "a put attaching a brand-new key past the limit must fail")

	getResp, getErr := cli.Get(ctx, "key-new")
	require.NoErrorf(t, getErr, "server must remain responsive right after the rejection (got: %v)", getErr)
	require.Empty(t, getResp.Kvs, "the rejected put must not have been (partially) applied")

	unrelatedCtx, unrelatedCancel := context.WithTimeout(ctx, 10*time.Second)
	defer unrelatedCancel()
	_, err = cli.Put(unrelatedCtx, "unrelated-key", "unrelated-value")
	require.NoError(t, err, "server must remain healthy and keep serving unrelated Puts after the rejection")

	getResp, err = cli.Get(ctx, "unrelated-key")
	require.NoError(t, err)
	require.Len(t, getResp.Kvs, 1)
	require.Equal(t, "unrelated-value", string(getResp.Kvs[0].Value))
}
