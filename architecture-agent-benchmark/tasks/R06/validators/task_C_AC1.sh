#!/usr/bin/env bash
# AC1: Audit mechanism is registered once, centrally, in the existing interceptor
# chain (chainUnaryInterceptors in server/etcdserver/api/v3rpc/grpc.go), or by
# extending newLogUnaryInterceptor / logUnaryRequestStats in
# server/etcdserver/api/v3rpc/interceptor.go in place.
#
# Method (per metadata_C.yaml AC1): diff review of grpc.go's Server()
# function / chainUnaryInterceptors slice vs the pinned base commit; if that's
# unchanged, look for interceptor.go being extended in place with new
# audit-relevant code.
#
# PASS: grpc.go's diff shows a new entry added to the chainUnaryInterceptors
#       slice literal, OR interceptor.go's diff shows newLogUnaryInterceptor /
#       logUnaryRequestStats (or a new sibling function near them) extended
#       with new audit-looking code (new AuthInfoFromCtx call, or a new
#       "audit"-named identifier).
# FAIL: grpc.go is unchanged AND interceptor.go shows no meaningful extension,
#       while key.go and/or v3_server.go changed instead (audit logic pushed
#       into the handlers rather than the chain).

set -uo pipefail

REPO="${1:-.}"
BASE="23a4e406a2e70a807486b4c40a9e24da493886bf"
GRPC_REL="server/etcdserver/api/v3rpc/grpc.go"
INTERCEPTOR_REL="server/etcdserver/api/v3rpc/interceptor.go"
KEY_REL="server/etcdserver/api/v3rpc/key.go"
V3SERVER_REL="server/etcdserver/v3_server.go"

if [ ! -d "$REPO/server" ]; then
  echo "FAIL: server/ directory not found under repo path '$REPO'"
  exit 1
fi

grpc_diff="$(git -C "$REPO" diff "$BASE" -- "$GRPC_REL" 2>/dev/null)"
interceptor_diff="$(git -C "$REPO" diff "$BASE" -- "$INTERCEPTOR_REL" 2>/dev/null)"
key_diff="$(git -C "$REPO" diff "$BASE" -- "$KEY_REL" 2>/dev/null)"
v3server_diff="$(git -C "$REPO" diff "$BASE" -- "$V3SERVER_REL" 2>/dev/null)"

# --- 1) grpc.go: was a new entry added to the chainUnaryInterceptors slice? ---

grpc_chain_hit=0
if [ -n "$grpc_diff" ]; then
  # Look for an added (+) non-comment line inside the chainUnaryInterceptors
  # literal that introduces a new interceptor constructor call, distinct from
  # the three that already exist at baseline.
  new_entries="$(echo "$grpc_diff" | grep -E '^\+' | grep -E '^\+\s*[A-Za-z_][A-Za-z0-9_]*\(s\),?\s*$' | \
    grep -vE 'newLogUnaryInterceptor\(s\)|newUnaryInterceptor\(s\)' || true)"
  if [ -n "$new_entries" ]; then
    grpc_chain_hit=1
  fi
fi

# --- 2) interceptor.go: was newLogUnaryInterceptor/logUnaryRequestStats
#        extended in place, or a new sibling audit function added? ------------

interceptor_hit=0
if [ -n "$interceptor_diff" ]; then
  added_lines="$(echo "$interceptor_diff" | grep -E '^\+[^+]')"
  if echo "$added_lines" | grep -qiE 'AuthInfoFromCtx|audit'; then
    interceptor_hit=1
  fi
fi

# --- 3) key.go / v3_server.go: did audit-like logic land there instead? ------

handlers_changed=0
if [ -n "$key_diff" ] || [ -n "$v3server_diff" ]; then
  if echo "$key_diff$v3server_diff" | grep -E '^\+[^+]' | grep -qiE 'audit|caller|identity'; then
    handlers_changed=1
  fi
fi

if [ "$grpc_chain_hit" -eq 1 ] || [ "$interceptor_hit" -eq 1 ]; then
  if [ "$handlers_changed" -eq 1 ]; then
    echo "MANUAL REVIEW REQUIRED: both the interceptor chain (grpc.go/interceptor.go) AND key.go/v3_server.go changed in ways that look audit-related; inspect whether the handlers gained real per-method audit calls in addition to the centralized mechanism."
    exit 2
  fi
  echo "PASS: audit mechanism appears registered centrally (grpc.go chainUnaryInterceptors changed: $grpc_chain_hit, interceptor.go extended with AuthInfoFromCtx/audit code: $interceptor_hit); key.go/v3_server.go show no audit-looking additions"
  exit 0
fi

if [ "$handlers_changed" -eq 1 ]; then
  echo "FAIL: grpc.go's chainUnaryInterceptors is unchanged and interceptor.go shows no audit-relevant extension, while key.go/v3_server.go gained audit-looking additions instead (per-handler scatter, trap pattern)"
  exit 1
fi

echo "FAIL: no evidence of a new interceptor-chain entry or an in-place extension of newLogUnaryInterceptor/logUnaryRequestStats in $GRPC_REL / $INTERCEPTOR_REL"
exit 1
