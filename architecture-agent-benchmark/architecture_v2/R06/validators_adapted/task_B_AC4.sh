#!/usr/bin/env bash
# AC4 (task B / R06-TB): the new client-facing error goes through the
# existing rpctypes/error-translation mechanism.
#
# Method (per metadata_B.yaml AC4): grep api/v3rpc/rpctypes/error.go and
# server/etcdserver/api/v3rpc/util.go's toGRPCErrorMap for a new lease-limit
# entry.
#
# PASS: a new sentinel error is added to both the rpctypes catalogue
#       (api/v3rpc/rpctypes/error.go) and toGRPCErrorMap
#       (server/etcdserver/api/v3rpc/util.go), following the existing
#       ErrLeaseTTLTooLarge-style pattern.
# FAIL: a raw status.Error(codes...) or an untranslated Go error crosses the
#       gRPC boundary directly from a handler for the new condition, bypassing
#       the shared error catalogue (or no new error was added at all).

set -uo pipefail

REPO="${1:-.}"
BASE="abe967acfac35ba278795c42e0a8968637594cef"
RPCTYPES_REL="api/v3rpc/rpctypes/error.go"
UTIL_REL="server/etcdserver/api/v3rpc/util.go"
TXN_REL="server/etcdserver/txn/put.go"

for rel in "$RPCTYPES_REL" "$UTIL_REL"; do
  if [ ! -f "$REPO/$rel" ]; then
    echo "FAIL: expected file not found under repo path '$REPO': $rel"
    exit 1
  fi
done

PATTERN='[Ll]ease.{0,20}([Mm]ax|[Ll]imit|[Tt]oo[Mm]any).{0,20}[Kk]ey|[Kk]ey.{0,20}([Mm]ax|[Ll]imit|[Tt]oo[Mm]any).{0,20}[Ll]ease|[Mm]ax.{0,20}[Aa]ttach|[Aa]ttach.{0,20}[Ll]imit|[Aa]ttach(ed)?.{0,20}[Kk]ey|[Tt]oo[Mm]any.{0,20}[Kk]ey|[Kk]ey.{0,20}[Ll]imit'

rpctypes_diff="$(git -C "$REPO" diff "$BASE" -- "$RPCTYPES_REL" 2>/dev/null | grep -E '^\+' | grep -Ev '^\+\+\+')"
util_diff="$(git -C "$REPO" diff "$BASE" -- "$UTIL_REL" 2>/dev/null | grep -E '^\+' | grep -Ev '^\+\+\+')"

# --- 1. new sentinel(s) added to the rpctypes catalogue -----------------

if ! echo "$rpctypes_diff" | grep -qE "^\+\s*ErrGRPC.*status\.Error\("; then
  echo "FAIL: no new 'ErrGRPCxxx = status.Error(...)' entry found in the diff of $RPCTYPES_REL - no new sentinel was added to the rpctypes catalogue."
  exit 1
fi

if ! echo "$rpctypes_diff" | grep -qE "$PATTERN"; then
  echo "FAIL: $RPCTYPES_REL gained new error variable(s), but none look lease-key-limit-shaped (expected something like ErrGRPCTooManyAttachedKeys / ErrTooManyAttachedKeys)."
  exit 1
fi

# --- 2. same error mapped in toGRPCErrorMap ------------------------------

if ! grep -n 'toGRPCErrorMap' "$REPO/$UTIL_REL" >/dev/null 2>&1; then
  echo "FAIL: toGRPCErrorMap not found in $UTIL_REL (unexpected - required_existing_abstraction missing)."
  exit 1
fi

if ! echo "$util_diff" | grep -qE "$PATTERN"; then
  echo "FAIL: no new lease-key-limit-shaped entry found in the diff of $UTIL_REL - the new domain error does not appear to be mapped in toGRPCErrorMap."
  exit 1
fi

if ! echo "$util_diff" | grep -qE '^\+.*rpctypes\.ErrGRPC'; then
  echo "FAIL: $UTIL_REL's diff does not add a line mapping a domain error to an rpctypes.ErrGRPCxxx value - toGRPCErrorMap does not appear to have gained a new entry in the expected shape."
  exit 1
fi

# --- 3. negative signal: no raw status.Error(codes...) added in the handler path ---

if [ -f "$REPO/$TXN_REL" ]; then
  txn_diff="$(git -C "$REPO" diff "$BASE" -- "$TXN_REL" 2>/dev/null | grep -E '^\+' | grep -Ev '^\+\+\+')"
  if echo "$txn_diff" | grep -qE 'status\.Error\(codes\.'; then
    echo "FAIL: $TXN_REL's diff contains a raw status.Error(codes...., ...) call - the new error appears to bypass the rpctypes catalogue and cross the gRPC boundary directly from a handler/pre-apply check."
    exit 1
  fi
fi

echo "PASS: a new lease-key-limit sentinel was added to the rpctypes catalogue ($RPCTYPES_REL) and mapped in toGRPCErrorMap ($UTIL_REL), following the ErrLeaseTTLTooLarge-style pattern; no raw status.Error(codes...) call was introduced in the request-validation path."
exit 0
