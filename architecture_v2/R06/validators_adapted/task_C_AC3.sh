#!/usr/bin/env bash
# AC3: No second, parallel per-RPC wrapper mechanism introduced solely to add
# audit logging (e.g. a new `auditKVServer` struct embedding pb.KVServer,
# mirroring quotaKVServer in server/etcdserver/api/v3rpc/quota.go).
#
# Method (per metadata_C.yaml AC3): grep for new struct types embedding
# pb.KVServer / pb.LeaseServer registered via a new pb.Register*Server call in
# grpc.go.
#
# PASS: no new such wrapper type exists; pb.RegisterKVServer(grpcServer,
#       NewQuotaKVServer(s)) (or equivalent) in grpc.go is unchanged apart
#       from what quota.go already does at baseline.
# FAIL: a new struct embedding pb.KVServer/pb.LeaseServer (or similar) is
#       added and registered via a new pb.Register*Server call.

set -uo pipefail

REPO="${1:-.}"
BASE="abe967acfac35ba278795c42e0a8968637594cef"
V3RPC_DIR="server/etcdserver/api/v3rpc"
GRPC_REL="$V3RPC_DIR/grpc.go"

if [ ! -d "$REPO/$V3RPC_DIR" ]; then
  echo "FAIL: $V3RPC_DIR not found under repo path '$REPO'"
  exit 1
fi

# --- 1) full diff of the v3rpc package: any newly added struct type that
#        embeds pb.KVServer / pb.LeaseServer (the quotaKVServer pattern)? ----

full_diff="$(git -C "$REPO" diff "$BASE" -- "$V3RPC_DIR" 2>/dev/null)"

# Collect files changed in the v3rpc dir, and for each newly added struct
# definition, check whether pb.KVServer/pb.LeaseServer/pb.WatchServer is
# embedded within a small window below it (mirrors quotaKVServer's shape:
#   type quotaKVServer struct {
#       pb.KVServer
#       ...
#   }
new_wrapper_hit=0
new_wrapper_detail=""

changed_files="$(echo "$full_diff" | grep -E '^\+\+\+ b/' | sed 's#^+++ b/##' || true)"
for relf in $changed_files; do
  f="$REPO/$relf"
  [ -f "$f" ] || continue
  # find line numbers of newly added "type X struct {" lines
  added_type_lines="$(git -C "$REPO" diff -U0 "$BASE" -- "$relf" 2>/dev/null | grep -E '^\+type [A-Za-z_][A-Za-z0-9_]* struct' | sed -E 's/^\+//' || true)"
  [ -z "$added_type_lines" ] && continue
  while IFS= read -r typeline; do
    [ -z "$typeline" ] && continue
    typename="$(echo "$typeline" | sed -E 's/^type ([A-Za-z_][A-Za-z0-9_]*) struct.*/\1/')"
    # skip the pre-existing quotaKVServer/quotaLeaseServer names themselves
    case "$typename" in
      quotaKVServer|quotaLeaseServer) continue ;;
    esac
    # look at the current (post-change) file for this type's body and check
    # for an embedded pb.KVServer/pb.LeaseServer/pb.WatchServer field
    startline=$(grep -n -F "$typeline" "$f" | head -1 | cut -d: -f1)
    [ -z "$startline" ] && continue
    body="$(sed -n "${startline},$((startline+10))p" "$f")"
    if echo "$body" | grep -qE 'pb\.(KVServer|LeaseServer|WatchServer|UnsafeKVServer|UnsafeLeaseServer)'; then
      new_wrapper_hit=1
      new_wrapper_detail="${new_wrapper_detail}\n  - new type '${typename}' in $relf embeds a pb.*Server interface"
    fi
  done <<< "$added_type_lines"
done

# --- 2) grpc.go: any new pb.Register*Server(...) call added? ----------------

grpc_diff="$(git -C "$REPO" diff "$BASE" -- "$GRPC_REL" 2>/dev/null)"
new_register_calls="$(echo "$grpc_diff" | grep -E '^\+' | grep -E 'pb\.Register[A-Za-z]*Server\(' || true)"

if [ "$new_wrapper_hit" -eq 1 ]; then
  echo -e "FAIL: new struct type(s) embedding a pb.*Server interface detected in $V3RPC_DIR (quotaKVServer-like decorator pattern):$new_wrapper_detail"
  exit 1
fi

if [ -n "$new_register_calls" ]; then
  echo "MANUAL REVIEW REQUIRED: $GRPC_REL diff adds new pb.Register*Server(...) call(s); inspect whether this registers a new audit-only decorator wrapper:"
  echo "$new_register_calls"
  exit 2
fi

echo "PASS: no new struct type embedding pb.KVServer/pb.LeaseServer/pb.WatchServer found in $V3RPC_DIR, and no new pb.Register*Server(...) call added in $GRPC_REL"
exit 0
