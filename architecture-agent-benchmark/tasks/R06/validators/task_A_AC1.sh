#!/usr/bin/env bash
# AC1: New validation logic lives in the auth domain layer (server/auth/store.go),
# not the gRPC passthrough layer (server/etcdserver/api/v3rpc/auth.go).
#
# Method (per metadata_A.yaml AC1): diff review of server/auth/store.go vs
# server/etcdserver/api/v3rpc/auth.go against the pinned base commit.
#
# PASS: server/auth/store.go's UserAdd/UserChangePassword functions gained new
#       code, AND server/etcdserver/api/v3rpc/auth.go's UserAdd/UserChangePassword
#       functions gained no new business-logic lines.
# FAIL: no new code in store.go's UserAdd/UserChangePassword, OR new conditional
#       logic was added inside v3rpc/auth.go's UserAdd/UserChangePassword.

set -uo pipefail

REPO="${1:-.}"
BASE="23a4e406a2e70a807486b4c40a9e24da493886bf"
STORE_REL="server/auth/store.go"
VRPC_REL="server/etcdserver/api/v3rpc/auth.go"
STORE_FILE="$REPO/$STORE_REL"
VRPC_FILE="$REPO/$VRPC_REL"

if [ ! -f "$STORE_FILE" ] || [ ! -f "$VRPC_FILE" ]; then
  echo "FAIL: expected files not found under repo path '$REPO' ($STORE_REL / $VRPC_REL)"
  exit 1
fi

# --- helpers -----------------------------------------------------------

# Print "newstart newend" (1-indexed, inclusive) for each changed hunk in the
# post-change (working tree) version of a file, relative to $BASE.
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

# Return 0 (true) if range "$1 $2" overlaps any range read from stdin.
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

# --- store.go: UserAdd / UserChangePassword must have new code ---------

store_changed_ranges="$(get_changed_ranges "$STORE_REL")"

store_useradd_range="$(func_range "$STORE_FILE" 'func (as \*authStore) UserAdd(')"
store_changepw_range="$(func_range "$STORE_FILE" 'func (as \*authStore) UserChangePassword(')"

store_hit=1
if [ -n "$store_useradd_range" ]; then
  if echo "$store_changed_ranges" | overlaps_any $store_useradd_range; then
    store_hit=0
  fi
fi
if [ -n "$store_changepw_range" ]; then
  if echo "$store_changed_ranges" | overlaps_any $store_changepw_range; then
    store_hit=0
  fi
fi

# --- v3rpc/auth.go: UserAdd / UserChangePassword must NOT gain new logic

vrpc_useradd_range="$(func_range "$VRPC_FILE" 'func (as \*AuthServer) UserAdd(')"
vrpc_changepw_range="$(func_range "$VRPC_FILE" 'func (as \*AuthServer) UserChangePassword(')"
vrpc_changed_ranges="$(get_changed_ranges "$VRPC_REL")"

vrpc_hit=1
if [ -n "$vrpc_useradd_range" ]; then
  if echo "$vrpc_changed_ranges" | overlaps_any $vrpc_useradd_range; then
    vrpc_hit=0
  fi
fi
if [ -n "$vrpc_changepw_range" ]; then
  if echo "$vrpc_changed_ranges" | overlaps_any $vrpc_changepw_range; then
    vrpc_hit=0
  fi
fi

if [ $store_hit -ne 0 ]; then
  echo "FAIL: no new code detected inside authStore.UserAdd / authStore.UserChangePassword in $STORE_REL (diff vs $BASE)"
  exit 1
fi

if [ $vrpc_hit -eq 0 ]; then
  echo "FAIL: new code detected inside AuthServer.UserAdd / UserChangePassword in $VRPC_REL — business logic was added to the gRPC passthrough layer (trap pattern)"
  exit 1
fi

echo "PASS: new code found inside authStore.UserAdd/UserChangePassword in $STORE_REL; $VRPC_REL's UserAdd/UserChangePassword bodies unchanged"
exit 0
