#!/usr/bin/env bash
# AC3 (task B / R06-TB): the limit is configurable through the standard
# config path, not hardcoded or read from an ad hoc global/env var.
#
# Method (per metadata_B.yaml AC3): grep server/etcdmain/config.go and
# server/embed/config.go for a new flag/field, and trace it into LessorConfig
# construction.
#
# PASS: a new CLI flag/field related to a per-lease key limit is defined in
#       server/embed/config.go (etcd's real flag-registration site;
#       server/etcdmain/config.go wires flags generically via
#       embed.Config.AddFlags and rarely contains a per-flag body of its own
#       - see MaxTxnOps/MaxRequestBytes for precedent) or, alternatively,
#       directly in server/etcdmain/config.go, AND that same concept is
#       threaded into a LessorConfig{...} construction (server/lease/lessor.go
#       or server/etcdserver/server.go).
# FAIL: no new lease-limit-shaped flag/field in either file, OR the limit is
#       hardcoded / read from a bespoke global/env var never reaching
#       LessorConfig.

set -uo pipefail

REPO="${1:-.}"
BASE="abe967acfac35ba278795c42e0a8968637594cef"
ETCDMAIN_REL="server/etcdmain/config.go"
EMBED_REL="server/embed/config.go"
LESSOR_REL="server/lease/lessor.go"
SERVER_REL="server/etcdserver/server.go"

for rel in "$ETCDMAIN_REL" "$EMBED_REL" "$LESSOR_REL" "$SERVER_REL"; do
  if [ ! -f "$REPO/$rel" ]; then
    echo "FAIL: expected file not found under repo path '$REPO': $rel"
    exit 1
  fi
done

# Loosely match "lease + limit/max/keys/attach" flavored identifiers, case
# insensitive, e.g. MaxAttachedKeys, MaxLeaseKeys, LeaseKeyLimit,
# max-attached-keys-per-lease, experimental-max-lease-keys, etc.
PATTERN='[Ll]ease.{0,20}([Mm]ax|[Ll]imit).{0,20}[Kk]ey|[Kk]ey.{0,20}([Mm]ax|[Ll]imit).{0,20}[Ll]ease|[Mm]ax.{0,20}[Aa]ttach|[Aa]ttach.{0,20}[Ll]imit|[Aa]ttach(ed)?.{0,20}[Kk]ey|[Tt]oo[Mm]any.{0,20}[Kk]ey|[Kk]ey.{0,20}[Ll]imit'

etcdmain_diff="$(git -C "$REPO" diff "$BASE" -- "$ETCDMAIN_REL" 2>/dev/null | grep -E '^\+' | grep -Ev '^\+\+\+')"
embed_diff="$(git -C "$REPO" diff "$BASE" -- "$EMBED_REL" 2>/dev/null | grep -E '^\+' | grep -Ev '^\+\+\+')"

flag_hit=0
flag_location=""
if echo "$embed_diff" | grep -qE "$PATTERN"; then
  flag_hit=1
  flag_location="$EMBED_REL"
fi
if echo "$etcdmain_diff" | grep -qE "$PATTERN"; then
  flag_hit=1
  if [ -n "$flag_location" ]; then
    flag_location="$flag_location and $ETCDMAIN_REL"
  else
    flag_location="$ETCDMAIN_REL"
  fi
fi

if [ "$flag_hit" -eq 0 ]; then
  echo "FAIL: no new lease-key-limit-shaped flag/field found in the diff of $EMBED_REL or $ETCDMAIN_REL (vs $BASE) - the limit does not appear to be configurable through the standard CLI/embed config path."
  exit 1
fi

# --- confirm it's threaded into a LessorConfig{...} construction -------

lessor_diff="$(git -C "$REPO" diff "$BASE" -- "$LESSOR_REL" 2>/dev/null | grep -E '^\+' | grep -Ev '^\+\+\+')"
server_diff="$(git -C "$REPO" diff "$BASE" -- "$SERVER_REL" 2>/dev/null | grep -E '^\+' | grep -Ev '^\+\+\+')"

# LessorConfig struct itself must have gained a new lease-limit-shaped field...
lessorconfig_field_hit=0
if echo "$lessor_diff" | grep -qE "$PATTERN"; then
  lessorconfig_field_hit=1
fi

# ...and something constructing lease.LessorConfig{...} (in server.go, the
# real construction site, or lessor.go itself) must reference it.
threaded_hit=0
if echo "$server_diff" | grep -qE "$PATTERN"; then
  threaded_hit=1
fi
if grep -n 'LessorConfig{' "$REPO/$SERVER_REL" >/dev/null 2>&1; then
  construction_ctx="$(grep -n -A15 'LessorConfig{' "$REPO/$SERVER_REL")"
  if echo "$construction_ctx" | grep -qE "$PATTERN"; then
    threaded_hit=1
  fi
fi

if [ "$lessorconfig_field_hit" -eq 0 ]; then
  echo "FAIL: found a new config flag/field ($flag_location), but server/lease/lessor.go's LessorConfig struct does not appear to have gained a matching new field."
  exit 1
fi

if [ "$threaded_hit" -eq 0 ]; then
  echo "FAIL: found a new config flag/field ($flag_location) and a new LessorConfig field, but could not confirm the flag/field is actually threaded into a LessorConfig{...} construction in $SERVER_REL - the limit may be defined but not wired end-to-end."
  exit 1
fi

echo "PASS: found a new lease-key-limit-shaped flag/field in $flag_location, a matching new field in server/lease/lessor.go's LessorConfig, and evidence it is threaded into a LessorConfig{...} construction in $SERVER_REL."
exit 0
