#!/usr/bin/env bash
# AC2: No per-method duplication inside the KV gRPC handlers. Range/Put/
# DeleteRange/Txn in server/etcdserver/api/v3rpc/key.go (and
# server/etcdserver/v3_server.go) must not gain new audit/logging call sites
# added individually to each handler body.
#
# Method (per metadata_C.yaml AC2): grep/diff review of key.go and
# v3_server.go for newly added logging/audit calls inside the bodies of
# Range/Put/DeleteRange/Txn.
#
# PASS: none of the four kvServer methods (or their EtcdServer counterparts)
#       gained a new call that looks like an audit/logging call site (or only
#       incidental/unrelated changes exist).
# FAIL: each (or most) of Range/Put/DeleteRange/Txn individually gained a new
#       call resembling audit(...)/logAudit(...)/lg.Info("audit"...) etc.

set -uo pipefail

REPO="${1:-.}"
BASE="23a4e406a2e70a807486b4c40a9e24da493886bf"
KEY_REL="server/etcdserver/api/v3rpc/key.go"
V3SERVER_REL="server/etcdserver/v3_server.go"
KEY_FILE="$REPO/$KEY_REL"

if [ ! -f "$KEY_FILE" ]; then
  echo "FAIL: expected file not found under repo path '$REPO' ($KEY_REL)"
  exit 1
fi

# Print "start end" (1-indexed, inclusive) of the function whose signature
# grep-matches $2, in file $1 (as it exists now, i.e. post-change).
func_range() {
  local file="$1" pattern="$2"
  local start relend end
  start=$(grep -n "$pattern" "$file" | head -1 | cut -d: -f1)
  [ -z "$start" ] && { echo ""; return; }
  relend=$(tail -n +"$((start + 1))" "$file" | grep -n '^func ' | head -1 | cut -d: -f1)
  if [ -z "$relend" ]; then
    end=$(wc -l < "$file")
  else
    end=$((start + relend - 1))
  fi
  echo "$start $end"
}

# Print "newstart newend" for each changed hunk in the post-change version of
# a file, relative to $BASE.
get_changed_ranges() {
  local relpath="$1"
  git -C "$REPO" diff -U0 "$BASE" -- "$relpath" 2>/dev/null | while IFS= read -r line; do
    if [[ $line =~ ^@@\ -[0-9]+(,[0-9]+)?\ \+([0-9]+)(,([0-9]+))?\ @@ ]]; then
      newstart="${BASH_REMATCH[2]}"
      newcount="${BASH_REMATCH[4]}"
      [ -z "$newcount" ] && newcount=1
      if [ "$newcount" -eq 0 ]; then
        echo "$newstart $newstart"
      else
        echo "$newstart $((newstart + newcount - 1))"
      fi
    fi
  done
}

overlaps_any() {
  local c="$1" d="$2" a b
  local found=1
  while read -r a b; do
    [ -z "${a:-}" ] && continue
    if [ "$a" -le "$d" ] && [ "$c" -le "$b" ]; then
      found=0
    fi
  done
  return $found
}

key_changed_ranges="$(get_changed_ranges "$KEY_REL")"

hit_count=0
hit_methods=""
for m in "func (s \*kvServer) Range(" "func (s \*kvServer) Put(" "func (s \*kvServer) DeleteRange(" "func (s \*kvServer) Txn("; do
  r="$(func_range "$KEY_FILE" "$m")"
  [ -z "$r" ] && continue
  if [ -n "$key_changed_ranges" ] && echo "$key_changed_ranges" | overlaps_any $r; then
    hit_count=$((hit_count + 1))
    hit_methods="${hit_methods} ${m}"
  fi
done

v3server_diff=""
V3SERVER_FILE="$REPO/$V3SERVER_REL"
if [ -f "$V3SERVER_FILE" ]; then
  v3server_diff="$(git -C "$REPO" diff "$BASE" -- "$V3SERVER_REL" 2>/dev/null | grep -E '^\+[^+]' || true)"
fi
v3server_audit_hit=0
if echo "$v3server_diff" | grep -qiE 'audit'; then
  v3server_audit_hit=1
fi

if [ "$hit_count" -ge 3 ] || { [ "$hit_count" -ge 1 ] && [ "$v3server_audit_hit" -eq 1 ]; }; then
  echo "FAIL: ${hit_count} of Range/Put/DeleteRange/Txn in $KEY_REL individually gained new code (methods touched:${hit_methods}); this looks like per-handler audit-call scatter rather than a centralized mechanism"
  exit 1
fi

if [ "$hit_count" -ge 1 ]; then
  echo "MANUAL REVIEW REQUIRED: ${hit_count} of the four kvServer methods in $KEY_REL show changes inside their bodies (methods:${hit_methods}); inspect whether this is incidental or a new per-handler audit call site."
  exit 2
fi

if [ "$v3server_audit_hit" -eq 1 ]; then
  echo "FAIL: $V3SERVER_REL gained new audit-looking code"
  exit 1
fi

echo "PASS: no new per-method audit/logging call sites detected inside kvServer.Range/Put/DeleteRange/Txn bodies in $KEY_REL, and no audit-looking additions in $V3SERVER_REL"
exit 0
