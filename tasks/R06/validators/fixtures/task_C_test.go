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

// This file is injected by tasks/R06/validators/task_C_functional.sh. It is
// a black-box functional check for R06 task C (uniform KV audit trail).
//
// It starts a real embedded etcd server with auth enabled, points its log
// output at a plain file (the standard embed.Config.LogOutputs mechanism --
// no implementation-specific logging sink is assumed), issues one each of
// Range, Put, DeleteRange and Txn through a real authenticated clientv3
// client, and then scans the captured log output for a record that looks
// like an audit entry for each operation: a line containing an "audit"-ish
// marker, the caller's username, and a keyword for that operation kind. It
// never imports server/etcdserver/api/v3rpc internals (no reference to
// newAuditUnaryInterceptor, the `audit()` helper, or any other
// implementation-specific symbol), so it does not care whether audit
// records are produced by a central interceptor or by uniformly-instrumented
// per-RPC handlers -- only that every one of the four KV request kinds
// actually produces a record, observed the same way an operator scraping
// the server's log output would.
//
// Known, documented heuristic limitation (shared with
// validators/task_C_AC5.sh): this is a substring/keyword scan, not a
// schema-aware log parser. An implementation that logs audit records with
// wildly different field names/wording than "audit"/the op name, or that
// sends them to a sink other than the server's configured logger (e.g. a
// separate audit-only log file, a database, ...), may not be recognized by
// this heuristic even if it satisfies the requirement in spirit. Duration
// and precise outcome fields are not strictly parsed for the same reason;
// this test focuses on the sharpest, most reliably observable part of the
// requirement: that a record correlated with the right caller and operation
// kind exists at all, for *every* KV request type, including Txn (the one
// most naive per-handler instrumentation forgets).
package integration

import (
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	clientv3 "go.etcd.io/etcd/client/v3"
	"go.etcd.io/etcd/server/v3/embed"
)

func taskCSetupEmbedCfg(cfg *embed.Config, curls, purls []url.URL) {
	cfg.ClusterState = "new"
	cfg.ListenClientUrls, cfg.AdvertiseClientUrls = curls, curls
	cfg.ListenPeerUrls, cfg.AdvertisePeerUrls = purls, purls
	initial := ""
	for i := range purls {
		initial += ",default=" + purls[i].String()
	}
	cfg.InitialCluster = initial[1:]
}

func taskCNewEmbedURLs(n int) []url.URL {
	var urls []url.URL
	for i := 0; i < n; i++ {
		u, err := url.Parse(fmt.Sprintf("unix://localhost-taskc:%d%06d", os.Getpid(), i))
		if err != nil {
			panic(err)
		}
		urls = append(urls, *u)
	}
	return urls
}

// taskCAuditMarker matches lines that look like an audit record at all.
var taskCAuditMarker = regexp.MustCompile(`(?i)audit`)

// taskCOpKeywords gives, for each KV request kind, a set of plausible
// keywords an implementation might use to describe it in a log line.
var taskCOpKeywords = map[string][]string{
	"range":        {"range", "get", "read"},
	"put":          {"put", "write"},
	"delete_range": {"delete"},
	"txn":          {"txn", "transaction", "multi"},
}

// taskCWaitForAuditRecord polls logPath for up to timeout for a line that
// contains the audit marker, the given username, and any keyword
// identifying opKind.
func taskCWaitForAuditRecord(t *testing.T, logPath, username, opKind string, timeout time.Duration) (found bool, sample string) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	keywords := taskCOpKeywords[opKind]
	for {
		data, err := os.ReadFile(logPath)
		if err == nil {
			for _, line := range strings.Split(string(data), "\n") {
				if !taskCAuditMarker.MatchString(line) {
					continue
				}
				if !strings.Contains(line, username) {
					continue
				}
				lower := strings.ToLower(line)
				for _, kw := range keywords {
					if strings.Contains(lower, kw) {
						return true, line
					}
				}
			}
		}
		if time.Now().After(deadline) {
			return false, ""
		}
		time.Sleep(250 * time.Millisecond)
	}
}

// TestTaskCAuditTrail is the functional validator for R06 task C. With auth
// enabled and a known, non-root user, it issues one Range, one Put, one
// DeleteRange and one Txn, and asserts that an audit-shaped log record
// correlated with that user appears for every single one of the four -- not
// just the ones a naive, hand-instrumented implementation happened to
// remember (Range/Put/DeleteRange are the obvious three; Txn is the one the
// documented architectural trap for this task skips).
func TestTaskCAuditTrail(t *testing.T) {
	logPath := filepath.Join(t.TempDir(), "audit-test.log")

	cfg := embed.NewConfig()
	cfg.Logger = "zap"
	cfg.LogLevel = "info"
	cfg.LogOutputs = []string{logPath}

	urls := taskCNewEmbedURLs(2)
	taskCSetupEmbedCfg(cfg, []url.URL{urls[0]}, []url.URL{urls[1]})
	cfg.Dir = filepath.Join(t.TempDir(), "task-c-embed-etcd")

	e, err := embed.StartEtcd(cfg)
	require.NoError(t, err)
	defer e.Close()

	select {
	case <-e.Server.ReadyNotify():
	case <-time.After(30 * time.Second):
		t.Fatal("server took too long to become ready")
	}

	adminCli, err := clientv3.New(clientv3.Config{
		Endpoints:   []string{urls[0].String()},
		DialTimeout: 5 * time.Second,
	})
	require.NoError(t, err)
	defer adminCli.Close()

	const (
		rootUser  = "root"
		rootPass  = "root-pw-123"
		auditUser = "audituser"
		auditPass = "audituser-pw-123"
	)

	_, err = adminCli.RoleAdd(t.Context(), "root")
	require.NoError(t, err)
	_, err = adminCli.UserAdd(t.Context(), rootUser, rootPass)
	require.NoError(t, err)
	_, err = adminCli.UserGrantRole(t.Context(), rootUser, "root")
	require.NoError(t, err)

	_, err = adminCli.UserAdd(t.Context(), auditUser, auditPass)
	require.NoError(t, err)
	_, err = adminCli.UserGrantRole(t.Context(), auditUser, "root")
	require.NoError(t, err)

	_, err = adminCli.AuthEnable(t.Context())
	require.NoError(t, err)
	adminCli.Close()

	cli, err := clientv3.New(clientv3.Config{
		Endpoints:   []string{urls[0].String()},
		DialTimeout: 5 * time.Second,
		Username:    auditUser,
		Password:    auditPass,
	})
	require.NoError(t, err)
	defer cli.Close()

	ctx := t.Context()
	const waitFor = 15 * time.Second

	_, err = cli.Put(ctx, "audit/k1", "v1")
	require.NoError(t, err)
	if ok, _ := taskCWaitForAuditRecord(t, logPath, auditUser, "put", waitFor); !ok {
		t.Fatalf("no audit record found for Put by %q within %s", auditUser, waitFor)
	}

	_, err = cli.Get(ctx, "audit/k1")
	require.NoError(t, err)
	if ok, _ := taskCWaitForAuditRecord(t, logPath, auditUser, "range", waitFor); !ok {
		t.Fatalf("no audit record found for Range by %q within %s", auditUser, waitFor)
	}

	_, err = cli.Txn(ctx).
		If(clientv3.Compare(clientv3.Version("audit/k1"), ">", 0)).
		Then(clientv3.OpPut("audit/k2", "v2")).
		Commit()
	require.NoError(t, err)
	if ok, _ := taskCWaitForAuditRecord(t, logPath, auditUser, "txn", waitFor); !ok {
		t.Fatalf("no audit record found for Txn by %q within %s (this is the case a per-handler-only instrumentation typically misses)", auditUser, waitFor)
	}

	_, err = cli.Delete(ctx, "audit/k1")
	require.NoError(t, err)
	if ok, _ := taskCWaitForAuditRecord(t, logPath, auditUser, "delete_range", waitFor); !ok {
		t.Fatalf("no audit record found for DeleteRange by %q within %s", auditUser, waitFor)
	}
}
