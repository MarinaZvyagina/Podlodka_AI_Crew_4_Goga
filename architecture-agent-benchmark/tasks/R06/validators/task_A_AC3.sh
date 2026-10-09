#!/usr/bin/env bash
# AC3: Error is a proper named sentinel consistent with existing style, not an
# ad hoc string or silent success.
#
# Method (per metadata_A.yaml AC3): grep for 'errors.New(' additions near the
# top-level var block in server/auth/store.go, and for any bare fmt.Errorf or
# swallowed error (`_ = ...`) introduced in the changed functions.
#
# PASS: a new `Err...` sentinel var (errors.New(...)) was added to the var
#       block, distinct from ErrNoPasswordUser, and no inline fmt.Errorf/panic
#       or swallowed error was introduced in UserAdd/UserChangePassword.
# FAIL: no new sentinel added (i.e. empty password silently accepted), or an
#       ad hoc fmt.Errorf/panic/swallowed error was introduced instead.

set -uo pipefail

REPO="${1:-.}"
BASE="23a4e406a2e70a807486b4c40a9e24da493886bf"
STORE_REL="server/auth/store.go"
STORE_FILE="$REPO/$STORE_REL"

if [ ! -f "$STORE_FILE" ]; then
  echo "FAIL: $STORE_REL not found under repo path '$REPO'"
  exit 1
fi

diff_output="$(git -C "$REPO" diff "$BASE" -- "$STORE_REL" 2>/dev/null)"

if [ -z "$diff_output" ]; then
  echo "FAIL: no changes at all to $STORE_REL — empty password is presumably still silently accepted"
  exit 1
fi

# 1) A new named sentinel error was added: an added line matching
#    `Err<Name> = errors.New(...)`, distinct from the pre-existing
#    ErrNoPasswordUser.
new_sentinel_lines="$(echo "$diff_output" | grep -E '^\+[^+].*Err[A-Za-z0-9_]+[[:space:]]*=[[:space:]]*errors\.New\(' || true)"
new_sentinel_lines="$(echo "$new_sentinel_lines" | grep -v 'ErrNoPasswordUser' || true)"

if [ -z "$new_sentinel_lines" ]; then
  echo "FAIL: no new 'Err... = errors.New(...)' sentinel found in the diff of $STORE_REL"
  exit 1
fi

# 2) No ad hoc fmt.Errorf / panic / swallowed error introduced in the diff
#    hunks (heuristic: scan all added lines in the whole file diff, since
#    UserAdd/UserChangePassword changes are the only functional change
#    expected here).
adhoc_hits="$(echo "$diff_output" | grep -E '^\+[^+].*(fmt\.Errorf\(|panic\(|^\+[^+][[:space:]]*_[[:space:]]*=[[:space:]]*err)' || true)"

if [ -n "$adhoc_hits" ]; then
  echo "FAIL: ad hoc error handling (fmt.Errorf/panic/swallowed err) introduced in $STORE_REL diff:"
  echo "$adhoc_hits"
  exit 1
fi

echo "PASS: new sentinel error(s) added to $STORE_REL var block, no ad hoc fmt.Errorf/panic/swallowed error introduced:"
echo "$new_sentinel_lines"
exit 0
