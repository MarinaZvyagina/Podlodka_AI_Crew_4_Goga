#!/usr/bin/env bash
# AC5: No new dependency edge introduced between server/auth and
# server/etcdserver/api/v3rpc beyond what already exists.
#
# Method (per metadata_A.yaml AC5): go list -deps (or manual import review) on
# server/auth and server/etcdserver/api/v3rpc packages before/after the change.
#
# PASS: go.etcd.io/etcd/server/v3/auth's dependency graph does not gain
#       go.etcd.io/etcd/server/v3/etcdserver/api/v3rpc (or any of its
#       v3rpc-specific types), and no new import lines were added to
#       server/auth/store.go or server/etcdserver/api/v3rpc/auth.go pulling in
#       the other side.
# FAIL: server/auth newly imports something from
#       server/etcdserver/api/v3rpc (or vice versa in an unnatural way).

set -uo pipefail

REPO="${1:-.}"
BASE="23a4e406a2e70a807486b4c40a9e24da493886bf"
STORE_REL="server/auth/store.go"
VRPC_REL="server/etcdserver/api/v3rpc/auth.go"
SERVER_DIR="$REPO/server"

if [ ! -d "$SERVER_DIR" ]; then
  echo "FAIL: server/ directory not found under repo path '$REPO'"
  exit 1
fi

fail=0
reasons=""

# --- 1) go list -deps: server/auth must not depend on v3rpc -----------

pushd "$SERVER_DIR" > /dev/null || { echo "FAIL: could not cd into $SERVER_DIR"; exit 1; }
auth_deps="$(go list -deps go.etcd.io/etcd/server/v3/auth 2>&1)"
auth_deps_exit=$?
popd > /dev/null

if [ $auth_deps_exit -ne 0 ]; then
  echo "FAIL: 'go list -deps go.etcd.io/etcd/server/v3/auth' failed (build error?):"
  echo "$auth_deps" | tail -30
  exit 1
fi

vrpc_edge="$(echo "$auth_deps" | grep -E 'go\.etcd\.io/etcd/server/v3/etcdserver/api/v3rpc' || true)"
if [ -n "$vrpc_edge" ]; then
  fail=1
  reasons="${reasons}\n  - go.etcd.io/etcd/server/v3/auth now depends on: $vrpc_edge"
fi

# --- 2) import-block diff: no new cross-boundary imports added --------

store_import_diff="$(git -C "$REPO" diff "$BASE" -- "$STORE_REL" 2>/dev/null | grep -E '^\+[^+]' | grep -E 'etcdserver/api/v3rpc' || true)"
vrpc_import_diff="$(git -C "$REPO" diff "$BASE" -- "$VRPC_REL" 2>/dev/null | grep -E '^\+[^+]' | grep -E '"go\.etcd\.io/etcd/server/v3/auth"|/rpctypes"' || true)"

if [ -n "$store_import_diff" ]; then
  fail=1
  reasons="${reasons}\n  - $STORE_REL diff adds a v3rpc import:\n$store_import_diff"
fi

if [ -n "$vrpc_import_diff" ]; then
  # server/etcdserver/api/v3rpc/auth.go already imports server/v3/auth today,
  # so a *new* line duplicating/re-adding this import (or adding an rpctypes
  # import not previously present) is worth flagging for manual review rather
  # than an automatic FAIL, since it could be an incidental gofmt reordering.
  echo "MANUAL REVIEW REQUIRED: $VRPC_REL diff touches its auth/rpctypes-related imports; inspect whether this reflects new business logic added to the passthrough layer:"
  echo -e "$vrpc_import_diff"
  exit 2
fi

if [ $fail -ne 0 ]; then
  echo -e "FAIL: new dependency edge detected:$reasons"
  exit 1
fi

echo "PASS: go.etcd.io/etcd/server/v3/auth's dependency graph does not include server/etcdserver/api/v3rpc; no new cross-boundary imports added"
exit 0
