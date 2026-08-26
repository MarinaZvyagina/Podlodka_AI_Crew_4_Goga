#!/usr/bin/env bash
# AC2: The rejection is enforced server-side, not only in a client tool.
#
# Method (per metadata_A.yaml AC2): grep for new validation code in
# client/v3/auth.go and etcdctl/ctlv3/command/user_command.go, relative to the
# pinned base commit.
#
# PASS: no new empty-password validation logic added in client/v3/auth.go or
#       etcdctl/ctlv3/command/user_command.go.
# FAIL: new empty-password checking logic (e.g. `if password == ""`,
#       `len(password) == 0`, prompting/erroring on empty password before the
#       server is ever called) was added in either of those client-side files.

set -uo pipefail

REPO="${1:-.}"
BASE="23a4e406a2e70a807486b4c40a9e24da493886bf"

CLIENT_REL="client/v3/auth.go"
ETCDCTL_REL="etcdctl/ctlv3/command/user_command.go"

CLIENT_FILE="$REPO/$CLIENT_REL"
ETCDCTL_FILE="$REPO/$ETCDCTL_REL"

if [ ! -f "$CLIENT_FILE" ] || [ ! -f "$ETCDCTL_FILE" ]; then
  echo "FAIL: expected files not found under repo path '$REPO' ($CLIENT_REL / $ETCDCTL_REL)"
  exit 1
fi

client_diff="$(git -C "$REPO" diff "$BASE" -- "$CLIENT_REL" 2>/dev/null)"
etcdctl_diff="$(git -C "$REPO" diff "$BASE" -- "$ETCDCTL_REL" 2>/dev/null)"

# Look for added lines (start with a single '+', not '+++') that look like a
# new empty-password/length validation.
suspicious_pattern='^\+[^+].*(Password[[:space:]]*==[[:space:]]*""|len\((r\.)?Password\)[[:space:]]*==[[:space:]]*0|password[[:space:]]*==[[:space:]]*""|[Pp]assword.*empty|[Ee]mpty.*[Pp]assword)'

client_hits="$(echo "$client_diff" | grep -E "$suspicious_pattern" || true)"
etcdctl_hits="$(echo "$etcdctl_diff" | grep -E "$suspicious_pattern" || true)"

fail=0
reasons=""

if [ -n "$client_hits" ]; then
  fail=1
  reasons="${reasons}\n  - $CLIENT_REL added empty-password validation:\n$client_hits"
fi

if [ -n "$etcdctl_hits" ]; then
  fail=1
  reasons="${reasons}\n  - $ETCDCTL_REL added empty-password validation:\n$etcdctl_hits"
fi

if [ $fail -ne 0 ]; then
  echo -e "FAIL: client-side-only empty-password validation detected (trap pattern):$reasons"
  exit 1
fi

if [ -z "$client_diff" ] && [ -z "$etcdctl_diff" ]; then
  echo "PASS: no changes at all to $CLIENT_REL or $ETCDCTL_REL — rejection is not client-side-only"
  exit 0
fi

echo "PASS: $CLIENT_REL / $ETCDCTL_REL changed but no new empty-password validation pattern found in the diff"
exit 0
