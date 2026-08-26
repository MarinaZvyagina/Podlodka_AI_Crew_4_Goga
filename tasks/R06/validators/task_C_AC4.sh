#!/usr/bin/env bash
# AC4: Caller identity for the audit trail is obtained via the existing
# AuthInfoFromCtx accessor (as used e.g. by AuthAdmin.isPermitted in
# server/etcdserver/api/v3rpc/auth.go), not by re-parsing gRPC
# metadata/tokens from scratch in new code.
#
# Method (per metadata_C.yaml AC4): grep for AuthInfoFromCtx usage in the
# new/changed code, vs. any new manual metadata/token parsing.
#
# PASS: new/changed code calls AuthInfoFromCtx(ctx) (or an equivalent
#       already-existing accessor) to get the username.
# FAIL: new/changed code re-implements token/metadata extraction
#       independently (e.g. metadata.FromIncomingContext, jwt parsing) in the
#       new audit-related code, without also calling AuthInfoFromCtx.

set -uo pipefail

REPO="${1:-.}"
BASE="23a4e406a2e70a807486b4c40a9e24da493886bf"
V3RPC_DIR="server/etcdserver/api/v3rpc"
ETCDSERVER_DIR="server/etcdserver"

if [ ! -d "$REPO/$V3RPC_DIR" ]; then
  echo "FAIL: $V3RPC_DIR not found under repo path '$REPO'"
  exit 1
fi

full_diff="$(git -C "$REPO" diff "$BASE" -- "$V3RPC_DIR" "$REPO/$ETCDSERVER_DIR" 2>/dev/null)"
# also include v3_server.go / key.go explicitly in case the above glob is odd
full_diff="$full_diff
$(git -C "$REPO" diff "$BASE" -- "$ETCDSERVER_DIR/v3_server.go" 2>/dev/null)"

added_lines="$(echo "$full_diff" | grep -E '^\+[^+]' || true)"

if [ -z "$added_lines" ]; then
  echo "FAIL: no added lines found in $V3RPC_DIR / $ETCDSERVER_DIR relative to $BASE — nothing to check identity extraction against"
  exit 1
fi

auth_info_hits="$(echo "$added_lines" | grep -E 'AuthInfoFromCtx' || true)"

# Manual/independent identity extraction red flags: new metadata parsing,
# JWT parsing, or reading auth headers directly, in the added lines. Exclude
# hits that are simply part of a larger AuthInfoFromCtx call chain or
# pre-existing helper reuse.
manual_parsing_hits="$(echo "$added_lines" | grep -E 'metadata\.FromIncomingContext|jwt\.Parse|ParseWithClaims|"authorization"|md\.Get\("authorization"|token\.Info\(' || true)"

if [ -n "$auth_info_hits" ]; then
  if [ -n "$manual_parsing_hits" ]; then
    echo "MANUAL REVIEW REQUIRED: added code calls AuthInfoFromCtx but ALSO adds what looks like independent metadata/token parsing; inspect whether the manual parsing is for identity or something unrelated:"
    echo "$manual_parsing_hits"
    exit 2
  fi
  echo "PASS: added code calls AuthInfoFromCtx to obtain caller identity; no new manual metadata/token parsing detected"
  exit 0
fi

if [ -n "$manual_parsing_hits" ]; then
  echo "FAIL: added code performs manual metadata/token parsing without using AuthInfoFromCtx:"
  echo "$manual_parsing_hits"
  exit 1
fi

echo "MANUAL REVIEW REQUIRED: no AuthInfoFromCtx call and no obvious manual metadata/token parsing found in the diff; the audit mechanism may not yet capture caller identity at all, or uses an accessor this script doesn't recognize. Inspect the diff manually."
exit 2
